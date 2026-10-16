import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sareemart_customer/core/catalog_db/catalog_database.dart';
import 'package:sareemart_customer/core/catalog_db/db_recovery.dart';
import 'package:sareemart_customer/core/catalog_db/sync_coverage.dart';
import 'package:sareemart_customer/core/catalog_db/sync_cursor.dart';
import 'package:sareemart_customer/core/offline/local_store.dart';
import 'package:sareemart_customer/core/offline/offline_cache.dart';

const _scopeA = 'city:4';
const _scopeB = 'city:9';

ProductUpsert _product(int id, {String name = '', String blob = ''}) =>
    ProductUpsert(
      serverId: id,
      name: name.isEmpty ? 'Product $id' : name,
      storeId: 7,
      categoryId: 3,
      storeName: 'Store Seven',
      searchBlob: blob.isEmpty ? 'product $id abaya' : blob,
      priceSnapshot: '{"price": 100}',
      payload: '{"id": $id}',
      variants: [VariantUpsert(serverId: id * 10, payload: '{}')],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncCursor (correction #3)', () {
    test('start cursor emits base params without after_created_at', () {
      final p = const SyncCursor.start().toQueryParams(limit: 50);
      expect(p['sort'], 'old');
      expect(p['limit'], 50);
      expect(p['after_id'], 0);
      expect(p.containsKey('after_created_at'), isFalse);
    });

    test('advance moves forward only, in listing order', () {
      var c = const SyncCursor.start();
      c = c.advance(createdAt: '2026-01-01 10:00:00', id: 5);
      expect(
        c.toQueryParams(limit: 50)['after_created_at'],
        '2026-01-01 10:00:00',
      );
      // Older row: ignored (out-of-order advance corrupts checkpoints).
      final same = c.advance(createdAt: '2026-01-01 09:00:00', id: 99);
      expect(same, c);
      // Same timestamp, higher id: advances (tie-break rule).
      final tied = c.advance(createdAt: '2026-01-01 10:00:00', id: 6);
      expect(tied.lastId, 6);
      // Same timestamp, lower id: ignored.
      expect(tied.advance(createdAt: '2026-01-01 10:00:00', id: 6), tied);
    });

    test('compareTo orders null-start before everything', () {
      const start = SyncCursor.start();
      const mid = SyncCursor(lastCreatedAt: '2026-01-01 10:00:00', lastId: 5);
      expect(start.compareTo(mid), lessThan(0));
      expect(mid.compareTo(start), greaterThan(0));
      expect(mid.compareTo(mid), 0);
    });
  });

  group('schema lifecycle (matrix #1, #11)', () {
    test('fresh open creates schema v3', () async {
      final db = await CatalogDatabase.openMemory();
      final v = await db.customSelect('PRAGMA user_version;').getSingle();
      expect(v.data['user_version'], 3);
      // FK enforcement is active on every connection.
      final fk = await db.customSelect('PRAGMA foreign_keys;').getSingle();
      expect(fk.data['foreign_keys'], 1);
      // Reconciliation columns exist with safe defaults.
      final cols = await db
          .customSelect('PRAGMA table_info(products);')
          .get();
      final names = cols.map((r) => r.data['name']).toSet();
      expect(
        names,
        containsAll(['is_listed', 'min_price', 'in_stock', 'has_offer']),
      );
      await db.close();
    });

    test(
      'reopen of populated file retains data (interrupted-migration safe)',
      () async {
        final dir = await Directory.systemTemp.createTemp('catdb');
        final file = File('${dir.path}/c.db');
        var db = await CatalogDatabase.openFile(file);
        var dao = CatalogDao(db);
        await dao.upsertProductBatch(
          scope: _scopeA,
          rows: [_product(1)],
          now: DateTime.utc(2026, 1, 1),
        );
        await db.close();
        db = await CatalogDatabase.openFile(file);
        dao = CatalogDao(db);
        expect(await dao.productCount(_scopeA), 1);
        final v = await db.customSelect('PRAGMA user_version;').getSingle();
        expect(v.data['user_version'], 3);
        await db.close();
        await dir.delete(recursive: true);
      },
    );
  });

  group('upsert identity (matrix #2, #3)', () {
    test('repeated batch is a no-op for identity', () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      final batch = [_product(1), _product(2)];
      final now = DateTime.utc(2026, 1, 1);
      await dao.upsertProductBatch(scope: _scopeA, rows: batch, now: now);
      await dao.upsertProductBatch(scope: _scopeA, rows: batch, now: now);
      expect(await dao.productCount(_scopeA), 2);
      expect((await dao.searchProducts(_scopeA, 'abaya')).length, 2);
      await db.close();
    });

    test('same server id in two scopes coexists without leakage', () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      final now = DateTime.utc(2026, 1, 1);
      await dao.upsertProductBatch(
        scope: _scopeA,
        rows: [_product(1)],
        now: now,
      );
      await dao.upsertProductBatch(
        scope: _scopeB,
        rows: [_product(1)],
        now: now,
      );
      expect(await dao.productCount(_scopeA), 1);
      expect(await dao.productCount(_scopeB), 1);
      expect((await dao.searchProducts(_scopeA, 'abaya')).length, 1);
      // Scoped delete touches only its own scope (+ FTS row).
      await dao.deleteScopedProduct(_scopeA, 1);
      expect(await dao.productCount(_scopeA), 0);
      expect(await dao.productCount(_scopeB), 1);
      expect((await dao.searchProducts(_scopeA, 'abaya')), isEmpty);
      expect((await dao.searchProducts(_scopeB, 'abaya')).length, 1);
      await db.close();
    });
  });

  group('batch atomicity (matrix #4, #8)', () {
    test('failed transaction leaves no partial rows', () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      await dao.upsertProductBatch(
        scope: _scopeA,
        rows: [_product(1)],
        now: DateTime.utc(2026, 1, 1),
      );
      // Simulate a batch that dies mid-commit: nothing may persist.
      try {
        await db.transaction(() async {
          await db
              .into(db.products)
              .insert(
                ProductsCompanion.insert(
                  scope: _scopeA,
                  serverId: 2,
                  name: 'Partial',
                  storeId: 7,
                  searchBlob: 'partial',
                  priceSnapshot: '{}',
                  payload: '{}',
                  refreshedAt: DateTime.utc(2026, 1, 1),
                  lastSeenAt: DateTime.utc(2026, 1, 1),
                ),
              );
          throw StateError('simulated batch failure');
        });
      } catch (_) {}
      expect(await dao.productCount(_scopeA), 1);
      await db.close();
    });

    test(
      'sync-state checkpoint round-trips per scope (matrix #4, #7)',
      () async {
        final db = await CatalogDatabase.openMemory();
        final dao = CatalogDao(db);
        expect(await dao.getSyncState(_scopeA), isNull);
        await dao.saveSyncState(
          SyncStatesCompanion.insert(
            scope: _scopeA,
            phase: 'full_running',
            lastOffset: const Value(50),
            lastCreatedAt: const Value('2026-01-01 10:00:00'),
            lastId: const Value(123),
            serverTotal: const Value(200),
            storedCount: const Value(50),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        final s = await dao.getSyncState(_scopeA);
        expect(s?.lastOffset, 50);
        expect(s?.lastId, 123);
        // Kill-mid-sync resume: checkpoint readable, second scope independent.
        expect(await dao.getSyncState(_scopeB), isNull);
        await db.close();
      },
    );
  });

  group('recovery (matrix #9, #10)', () {
    test('corrupt file is quarantined and recreated', () async {
      final dir = await Directory.systemTemp.createTemp('catdb');
      final file = File('${dir.path}/c.db');
      await file.writeAsString('not-a-database{{{');
      final db = await CatalogDatabase.openFile(file);
      final dao = CatalogDao(db);
      await dao.upsertProductBatch(
        scope: _scopeA,
        rows: [_product(1)],
        now: DateTime.utc(2026, 1, 1),
      );
      expect(await dao.productCount(_scopeA), 1);
      await db.close();
      final leftovers = dir
          .listSync()
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toList();
      expect(leftovers.any((n) => n.startsWith('c.db.corrupt.')), isTrue);
      await dir.delete(recursive: true);
    });

    test('unrecoverable filesystem failure surfaces cleanly', () async {
      final dir = await Directory.systemTemp.createTemp('catdb');
      final blocker = File('${dir.path}/blocker');
      await blocker.writeAsString('x');
      // Parent is a file, not a directory: creation must fail, not hang.
      await expectLater(
        CatalogDatabase.openFile(File('${blocker.path}/c.db')),
        throwsA(isA<Exception>()),
      );
      await dir.delete(recursive: true);
    });
  });

  group('legacy preservation + rollback (matrix #10, #12)', () {
    test('DB init and writes touch no SharedPreferences key', () async {
      SharedPreferences.setMockInitialValues({
        'shop_cache': jsonEncode({'id': 1}),
        'guest_cart': jsonEncode([
          {'product_variant_id': 2, 'qty': 1},
        ]),
        'oc:pending::guest': '[]',
      });
      final prefs = await SharedPreferences.getInstance();
      final before = Map<String, Object?>.fromEntries(
        prefs.getKeys().map((k) => MapEntry(k, prefs.get(k))),
      );
      final db = await CatalogDatabase.openMemory();
      await CatalogDao(db).upsertProductBatch(
        scope: _scopeA,
        rows: [_product(1)],
        now: DateTime.utc(2026, 1, 1),
      );
      await db.close();
      for (final e in before.entries) {
        expect(prefs.get(e.key), e.value, reason: e.key);
      }
    });

    test('rollback: JSON catalog path works with DB present', () async {
      // The JSON path is independent of the catalog DB: with the DB open
      // beside it, JSON round-trips exactly as before (rollback safety).
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = OfflineCache(LocalStore(prefs));
      final db = await CatalogDatabase.openMemory();
      await CatalogDao(db).upsertProductBatch(
        scope: _scopeA,
        rows: [_product(1)],
        now: DateTime.utc(2026, 1, 1),
      );
      await db.close();
      // Rollback read path: JSON cache round-trips independently of the DB.
      await cache.writeProductPage('oc:products::k', [
        {'id': 9},
      ]);
      expect(cache.readDoc('oc:products::k'), isNotNull);
    });
  });

  group('image manifest primitives (correction #4)', () {
    test('budget accounting and oldest-first eviction', () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      final t0 = DateTime.utc(2026, 1, 1);
      await dao.putImage(url: 'u1', localPath: '/a', bytes: 100, now: t0);
      await dao.putImage(
        url: 'u2',
        localPath: '/b',
        bytes: 100,
        now: t0.add(const Duration(seconds: 1)),
      );
      await dao.putImage(
        url: 'u3',
        localPath: '/c',
        bytes: 100,
        now: t0.add(const Duration(seconds: 2)),
      );
      expect(await dao.imagesTotalBytes(), 300);
      // Touch u1: eviction order becomes u2, u3, u1.
      await dao.touchImage('u1', t0.add(const Duration(seconds: 3)));
      final victims = await dao.evictCandidates(bytesToFree: 150);
      expect(victims.map((c) => c.url), ['u2', 'u3']);
      for (final v in victims) {
        await dao.removeImage(v.url);
      }
      expect(await dao.imagesTotalBytes(), 100);
      await db.close();
    });
  });

  group('scoped reads', () {
    test('listProducts filters, paginates, and isolates scopes', () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      final now = DateTime.utc(2026, 1, 1);
      await dao.upsertProductBatch(
        scope: _scopeA,
        rows: [_product(1), _product(2), _product(3)],
        now: now,
      );
      await dao.upsertProductBatch(
        scope: _scopeB,
        rows: [_product(1)],
        now: now,
      );
      final page = await dao.listProducts(_scopeA, limit: 2);
      expect(page.map((p) => p.serverId), [1, 2]);
      final rest = await dao.listProducts(_scopeA, limit: 2, offset: 2);
      expect(rest.map((p) => p.serverId), [3]);
      await db.close();
    });
  });

  group('R1 recovery classification', () {
    SqliteException err(int code) =>
        SqliteException(extendedResultCode: code, message: 'probe');

    test('corruption signatures quarantine; everything else preserves', () {
      expect(classifyOpenFailure(err(11)), OpenFailureKind.corruption);
      expect(classifyOpenFailure(err(26)), OpenFailureKind.corruption);
      // Extended codes keep their primary meaning (mask 0xFF).
      expect(
        classifyOpenFailure(err((11 << 8) | 11)),
        OpenFailureKind.corruption,
      );
      for (final code in [1, 3, 5, 6, 7, 8, 10, 13, 14, 19, 21]) {
        expect(
          classifyOpenFailure(err(code)),
          OpenFailureKind.transient,
          reason: 'code $code',
        );
      }
      expect(
        classifyOpenFailure(StateError('not sqlite')),
        OpenFailureKind.transient,
      );
    });

    test('simulated busy/locking error preserves the original file', () async {
      final dir = await Directory.systemTemp.createTemp('catdb');
      final file = File('${dir.path}/c.db');
      final db = await CatalogDatabase.openFile(file);
      await CatalogDao(db).upsertProductBatch(
        scope: _scopeA,
        rows: [_product(1)],
        now: DateTime.utc(2026, 1, 1),
      );
      await db.close();
      final before = await file.readAsBytes();
      Future<CatalogDatabase> busy(File f) async {
        throw SqliteException(
          extendedResultCode: 5,
          message: 'database is locked',
        );
      }

      await expectLater(
        CatalogDatabase.openFile(file, openForTest: busy),
        throwsA(isA<SqliteException>()),
      );
      // File untouched, no quarantine sibling, original error surfaced.
      expect(await file.readAsBytes(), before);
      expect(
        dir.listSync().where((e) => e.path.contains('corrupt')).isEmpty,
        isTrue,
      );
      final reopened = await CatalogDatabase.openFile(file);
      expect(await CatalogDao(reopened).productCount(_scopeA), 1);
      await reopened.close();
      await dir.delete(recursive: true);
    });

    test('permission/resource failure preserves file and rethrows', () async {
      final dir = await Directory.systemTemp.createTemp('catdb');
      final file = File('${dir.path}/c.db');
      await file.writeAsBytes([1, 2, 3]);
      for (final code in [8, 13, 3]) {
        Future<CatalogDatabase> failing(File f) async {
          throw SqliteException(extendedResultCode: code, message: 'probe');
        }

        await expectLater(
          CatalogDatabase.openFile(file, openForTest: failing),
          throwsA(isA<SqliteException>()),
        );
        expect(await file.readAsBytes(), [1, 2, 3]);
      }
      expect(
        dir.listSync().where((e) => e.path.contains('corrupt')).isEmpty,
        isTrue,
      );
      await dir.delete(recursive: true);
    });

    test('recovery failure remains visible, quarantine preserved', () async {
      final dir = await Directory.systemTemp.createTemp('catdb');
      final blocker = File('${dir.path}/blocker');
      await blocker.writeAsString('x');
      // Corruption-classified open failure, but recreation is impossible:
      // the error must propagate (not a silent empty database).
      Future<CatalogDatabase> corrupt(File f) async {
        throw SqliteException(
          extendedResultCode: 26,
          message: 'file is not a database',
        );
      }

      await expectLater(
        CatalogDatabase.openFile(
          File('${blocker.path}/c.db'),
          openForTest: corrupt,
        ),
        throwsA(isA<Exception>()),
      );
      expect(await blocker.readAsString(), 'x');
      await dir.delete(recursive: true);
    });
  });

  group('R2 coverage gate', () {
    test('codec round-trips known values, rejects unknown', () {
      expect(SyncCoverageCodec.toDb(SyncCoverage.bestEffort), 'best_effort');
      expect(SyncCoverageCodec.toDb(SyncCoverage.verified), 'verified');
      expect(SyncCoverageCodec.fromDb('best_effort'), SyncCoverage.bestEffort);
      expect(SyncCoverageCodec.fromDb('verified'), SyncCoverage.verified);
      expect(() => SyncCoverageCodec.fromDb('complete'), throwsArgumentError);
      expect(() => SyncCoverageCodec.fromDb(''), throwsArgumentError);
      expect(() => SyncCoverageCodec.fromDb('VERIFIED'), throwsArgumentError);
    });

    test('saveSyncState rejects unknown coverage, writes nothing', () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      await expectLater(
        () => dao.saveSyncState(
          SyncStatesCompanion.insert(
            scope: _scopeA,
            phase: 'full_running',
            coverage: const Value('complete'),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
        throwsArgumentError,
      );
      expect(await dao.getSyncState(_scopeA), isNull);
      await db.close();
    });

    test('verified without sufficient evidence is refused', () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      SyncStatesCompanion claimed() => SyncStatesCompanion.insert(
        scope: _scopeA,
        phase: 'full_complete',
        coverage: const Value('verified'),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      await expectLater(
        () => dao.saveSyncState(claimed()),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        () => dao.saveSyncState(
          claimed(),
          evidence: const VerifiedEvidence(
            baselineComplete: true,
            cursorComplete: true,
            tombstonesReconciled: false,
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await dao.getSyncState(_scopeA), isNull);
      // A complete evidence bundle records the claim (no production path
      // constructs one in this phase; the gate, not the content, is under
      // test here).
      await dao.saveSyncState(
        claimed(),
        evidence: const VerifiedEvidence(
          baselineComplete: true,
          cursorComplete: true,
          tombstonesReconciled: true,
        ),
      );
      expect(await dao.coverageOf(_scopeA), SyncCoverage.verified);
      await db.close();
    });

    test('coverageOf reads typed values, fails loudly on unknown', () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      expect(await dao.coverageOf(_scopeA), isNull);
      await dao.saveSyncState(
        SyncStatesCompanion.insert(
          scope: _scopeA,
          phase: 'full_running',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(await dao.coverageOf(_scopeA), SyncCoverage.bestEffort);
      // Simulate a corrupt/legacy stored value bypassing the gate.
      await db.customStatement(
        "UPDATE sync_states SET coverage = 'bogus' WHERE scope = ?;",
        [_scopeA],
      );
      await expectLater(dao.coverageOf(_scopeA), throwsArgumentError);
      await db.close();
    });
  });

  group('R3 schema migration + integrity (v1→v3)', () {
    /// Fabricates a populated v1-shaped file: built with the current code,
    /// then downgraded with raw SQL (variants table without the FK, products
    /// table without the v3 reconciliation columns, §2.2 indexes dropped,
    /// version reset). This keeps every other table byte-identical to a real
    /// v1 file. Drift DateTime storage is unix seconds.
    Future<File> makeV1File(
      Directory dir, {
      bool withOrphan = false,
      bool dropVariants = false,
    }) async {
      final file = File('${dir.path}/v1.db');
      var db = await CatalogDatabase.openFile(file);
      await CatalogDao(db).upsertProductBatch(
        scope: _scopeA,
        rows: [_product(1)],
        now: DateTime.utc(2026, 1, 1),
      );
      await db.close();
      final raw = sqlite3.open(file.path);
      raw.execute(
        'CREATE TABLE product_variants_v1 (scope TEXT NOT NULL, '
        'server_id INTEGER NOT NULL, product_id INTEGER NOT NULL, '
        'payload TEXT NOT NULL, refreshed_at INTEGER NOT NULL, '
        'PRIMARY KEY (scope, server_id));',
      );
      raw.execute(
        'INSERT INTO product_variants_v1 SELECT scope, server_id, '
        'product_id, payload, refreshed_at FROM product_variants;',
      );
      raw.execute('DROP TABLE product_variants;');
      raw.execute(
        'ALTER TABLE product_variants_v1 RENAME TO product_variants;',
      );
      raw.execute(
        'CREATE TABLE products_v1 (scope TEXT NOT NULL, '
        'server_id INTEGER NOT NULL, slug TEXT, name TEXT NOT NULL, '
        'store_id INTEGER NOT NULL, category_id INTEGER, '
        'search_blob TEXT NOT NULL, price_snapshot TEXT NOT NULL, '
        'thumbnail_url TEXT, local_image_path TEXT, '
        'rating REAL NOT NULL DEFAULT 0.0, status INTEGER NOT NULL DEFAULT 1, '
        'payload TEXT NOT NULL, refreshed_at INTEGER NOT NULL, '
        'last_seen_at INTEGER NOT NULL, '
        'PRIMARY KEY (scope, server_id));',
      );
      raw.execute(
        'INSERT INTO products_v1 (scope, server_id, slug, name, store_id, '
        'category_id, search_blob, price_snapshot, thumbnail_url, '
        'local_image_path, rating, status, payload, refreshed_at, '
        'last_seen_at) SELECT scope, server_id, slug, name, store_id, '
        'category_id, search_blob, price_snapshot, thumbnail_url, '
        'local_image_path, rating, status, payload, refreshed_at, '
        'last_seen_at FROM products;',
      );
      raw.execute('DROP TABLE products;');
      raw.execute('ALTER TABLE products_v1 RENAME TO products;');
      for (final idx in [
        'idx_products_scope_category',
        'idx_products_scope_store',
        'idx_products_scope_status',
        'idx_products_scope_listed',
        'idx_variants_scope_product',
        'idx_stores_scope_status',
        'idx_categories_scope_parent',
        'idx_images_last_used',
      ]) {
        raw.execute('DROP INDEX IF EXISTS $idx;');
      }
      const secs = 1767225600; // 2026-01-01T00:00:00Z
      if (withOrphan) {
        // Raw connection has FK enforcement off: orphan insert allowed,
        // mirroring a v1 file that predates the constraint.
        raw.execute(
          "INSERT INTO product_variants VALUES ('$_scopeA', 77, 999, '{}', $secs);",
        );
      }
      if (dropVariants) {
        raw.execute('DROP TABLE product_variants;');
      }
      raw.execute('PRAGMA user_version = 1;');
      raw.close();
      return file;
    }

    test('populated v1 migrates with data, FK, cascade, indexes', () async {
      final dir = await Directory.systemTemp.createTemp('catdb');
      final file = await makeV1File(dir);
      final db = await CatalogDatabase.openFile(file);
      final dao = CatalogDao(db);
      final v = await db.customSelect('PRAGMA user_version;').getSingle();
      expect(v.data['user_version'], 3);
      // Data + scope identity preserved (DateTime round-trips seconds).
      final products = await dao.listProducts(_scopeA);
      expect(products.map((p) => p.serverId), [1]);
      expect(products.first.name, 'Product 1');
      // v3 reconciliation columns default safely: migrated rows stay listed
      // with unknown price/stock/offer (never hidden by filters).
      expect(products.first.isListed, isTrue);
      expect(products.first.minPrice, isNull);
      expect(products.first.inStock, isNull);
      expect(products.first.hasOffer, isNull);
      // Drift stores DateTime as unix seconds, read back in local time.
      expect(products.first.refreshedAt.toUtc(), DateTime.utc(2026, 1, 1));
      // FK enforced: orphan variant insert now fails.
      await expectLater(
        db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                scope: _scopeA,
                serverId: 77,
                productId: 4242,
                payload: '{}',
                refreshedAt: DateTime.utc(2026, 1, 1),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
      // Cascade: deleting the product removes its variants.
      await db.delete(db.products).go();
      final variants = await db.select(db.productVariants).get();
      expect(variants, isEmpty);
      // Raw deletes bypass explicit FTS maintenance (the DAO's job): the
      // audit correctly reports the inconsistency instead of hiding it.
      expect(await dao.orphanCounts(), {'variants': 0, 'fts': 1});
      // The DAO tombstone path restores consistency.
      await dao.deleteScopedProduct(_scopeA, 1);
      expect(await dao.orphanCounts(), {'variants': 0, 'fts': 0});
      // §2.2 indexes exist.
      final idx = await db
          .customSelect(
            "SELECT name AS n FROM sqlite_master WHERE type = 'index' AND n LIKE 'idx\\_%' ESCAPE '\\';",
          )
          .get();
      final names = idx.map((r) => r.data['n'] as String).toSet();
      expect(
        names,
        containsAll([
          'idx_products_scope_category',
          'idx_variants_scope_product',
          'idx_images_last_used',
        ]),
      );
      // No FK violations introduced by the migration.
      final violations = await db
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);
      await db.close();
      await dir.delete(recursive: true);
    });

    test(
      'migration preserves pre-existing orphans, audit reports them',
      () async {
        final dir = await Directory.systemTemp.createTemp('catdb');
        final file = await makeV1File(dir, withOrphan: true);
        // FK enforcement is OFF during onUpgrade (beforeOpen runs after), so
        // the upgrade never drops rows: orphans are preserved and reported,
        // never silently deleted.
        final db = await CatalogDatabase.openFile(file);
        final dao = CatalogDao(db);
        final v = await db.customSelect('PRAGMA user_version;').getSingle();
        expect(v.data['user_version'], 3);
        expect(await dao.productCount(_scopeA), 1);
        expect(await dao.orphanCounts(), {'variants': 1, 'fts': 0});
        final violations = await db
            .customSelect('PRAGMA foreign_key_check;')
            .get();
        expect(violations.length, 1);
        await db.close();
        await dir.delete(recursive: true);
      },
    );

    test('broken migration fails without data loss', () async {
      final dir = await Directory.systemTemp.createTemp('catdb');
      final file = await makeV1File(dir, dropVariants: true);
      // The 1→2 copy references a missing table (SQLITE_ERROR, transient).
      // The SAVEPOINT rolls the file back: version stays 1, user rows
      // intact, no partial DDL, no quarantine — a later retry is possible.
      await expectLater(
        CatalogDatabase.openFile(file),
        throwsA(isA<SqliteException>()),
      );
      final raw = sqlite3.open(file.path);
      expect(raw.userVersion, 1);
      final tables = raw
          .select("SELECT name FROM sqlite_master WHERE type = 'table';")
          .map((r) => r['name'] as String)
          .toSet();
      expect(tables.contains('product_variants_new'), isFalse);
      final products = raw.select('SELECT server_id FROM products;');
      expect(products.map((r) => r['server_id']), [1]);
      raw.close();
      expect(
        dir.listSync().where((e) => e.path.contains('corrupt')).isEmpty,
        isTrue,
      );
      // Retry is still possible and fails the same clean way.
      await expectLater(
        CatalogDatabase.openFile(file),
        throwsA(isA<SqliteException>()),
      );
      await dir.delete(recursive: true);
    });

    test('no orphans after every DAO mutation path', () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      final now = DateTime.utc(2026, 1, 1);
      await dao.upsertProductBatch(
        scope: _scopeA,
        rows: [_product(1), _product(2)],
        now: now,
      );
      expect(await dao.orphanCounts(), {'variants': 0, 'fts': 0});
      await dao.deleteScopedProduct(_scopeA, 1);
      expect(await dao.orphanCounts(), {'variants': 0, 'fts': 0});
      await dao.upsertProductBatch(
        scope: _scopeA,
        rows: [_product(3)],
        now: now,
      );
      await dao.deleteScopeCatalog(_scopeA);
      expect(await dao.orphanCounts(), {'variants': 0, 'fts': 0});
      await db.close();
    });
  });

  group('reconciliation + DB-backed browse (schema v3)', () {
    ProductUpsert rich(
      int id, {
      double? minPrice,
      bool? inStock,
      bool? hasOffer,
      double rating = 0,
      List<int> variantIds = const [],
    }) =>
        ProductUpsert(
          serverId: id,
          name: 'R $id abaya',
          storeId: 7,
          categoryId: id.isEven ? 3 : 5,
          storeName: 'Store Seven',
          searchBlob: 'r $id abaya',
          priceSnapshot: '{}',
          payload: '{"id": $id}',
          rating: rating,
          minPrice: minPrice,
          inStock: inStock,
          hasOffer: hasOffer,
          variants: [
            for (final vid in variantIds)
              VariantUpsert(serverId: vid, payload: '{}'),
          ],
        );

    test('reconcileListed unlists missing, keeps seen + other scopes',
        () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      final now = DateTime.utc(2026, 1, 1);
      await dao.upsertProductBatch(
        scope: _scopeA,
        rows: [rich(1), rich(2), rich(3)],
        now: now,
      );
      await dao.upsertProductBatch(
        scope: _scopeB,
        rows: [rich(2)],
        now: now,
      );
      await dao.reconcileListed(_scopeA, {1, 3});
      expect(await dao.productCount(_scopeA), 2);
      expect(await dao.getProductById(_scopeA, 2), isNotNull);
      // Detail lookups still resolve unlisted rows.
      expect((await dao.getProductById(_scopeA, 2))!.isListed, isFalse);
      // Other scopes untouched.
      expect(await dao.productCount(_scopeB), 1);
      // Search excludes the unlisted row.
      expect(
        (await dao.searchProducts(_scopeA, 'abaya')).map((p) => p.serverId),
        unorderedEquals([1, 3]),
      );
      await db.close();
    });

    test('reconcileListed with empty set unlists the whole scope', () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      await dao.upsertProductBatch(
        scope: _scopeA,
        rows: [rich(1)],
        now: DateTime.utc(2026, 1, 1),
      );
      await dao.reconcileListed(_scopeA, {});
      expect(await dao.productCount(_scopeA), 0);
      expect(await dao.getProductById(_scopeA, 1), isNotNull);
      await db.close();
    });

    test('variant prune removes shrunk sets, keeps others', () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      final now = DateTime.utc(2026, 1, 1);
      await dao.upsertProductBatch(
        scope: _scopeA,
        rows: [rich(1, variantIds: [11, 12]), rich(2, variantIds: [21])],
        now: now,
      );
      expect(
        (await dao.variantsForProduct(_scopeA, 1)).map((v) => v.serverId),
        unorderedEquals([11, 12]),
      );
      // Re-upsert product 1 with a shrunk variant set.
      await dao.upsertProductBatch(
        scope: _scopeA,
        rows: [rich(1, variantIds: [11])],
        now: now,
      );
      expect(
        (await dao.variantsForProduct(_scopeA, 1)).map((v) => v.serverId),
        [11],
      );
      // Product 2 (absent from this batch) keeps its variants.
      expect(
        (await dao.variantsForProduct(_scopeA, 2)).map((v) => v.serverId),
        [21],
      );
      expect(await dao.orphanCounts(), {'variants': 0, 'fts': 0});
      await db.close();
    });

    test('deleteMissingStores keeps seen ids only', () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      final now = DateTime.now();
      await dao.upsertStores(
        scope: _scopeA,
        rows: [
          StoresCompanion.insert(
            scope: _scopeA,
            serverId: 1,
            name: 'S1',
            payload: '{}',
            refreshedAt: now,
            lastSeenAt: now,
          ),
          StoresCompanion.insert(
            scope: _scopeA,
            serverId: 2,
            name: 'S2',
            payload: '{}',
            refreshedAt: now,
            lastSeenAt: now,
          ),
        ],
      );
      await dao.deleteMissingStores(_scopeA, {2});
      expect(
        (await dao.listStores(_scopeA, limit: 10)).map((s) => s.serverId),
        [2],
      );
      await db.close();
    });

    test('queryProducts filters/sorts/pages in SQL over the full set',
        () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      final now = DateTime.utc(2026, 1, 1);
      await dao.upsertProductBatch(
        scope: _scopeA,
        rows: [
          rich(1, minPrice: 100, inStock: true, hasOffer: true, rating: 4.5),
          rich(2, minPrice: 200, inStock: false, hasOffer: false, rating: 3.0),
          rich(3, minPrice: null, inStock: null, hasOffer: null, rating: 0),
          rich(4, minPrice: 50, inStock: true, hasOffer: null, rating: 5.0),
        ],
        now: now,
      );
      // Unknown (NULL) values never filter rows out.
      expect(
        (await dao.queryProducts(_scopeA, priceMin: 150))
            .map((p) => p.serverId),
        unorderedEquals([2, 3]),
      );
      expect(
        (await dao.queryProducts(_scopeA, inStockOnly: true))
            .map((p) => p.serverId),
        unorderedEquals([1, 3, 4]),
      );
      expect(
        (await dao.queryProducts(_scopeA, offersOnly: true))
            .map((p) => p.serverId),
        unorderedEquals([1, 3, 4]),
      );
      expect(
        (await dao.queryProducts(_scopeA, minRating: 4))
            .map((p) => p.serverId),
        unorderedEquals([1, 3, 4]),
      );
      // Global sort: cheapest first, unknowns last — over the FULL set.
      expect(
        (await dao.queryProducts(_scopeA, sort: 'low'))
            .map((p) => p.serverId),
        [4, 1, 2, 3],
      );
      expect(
        (await dao.queryProducts(_scopeA, sort: 'high'))
            .map((p) => p.serverId),
        [2, 1, 4, 3],
      );
      // Pagination slices the sorted set; counts match filters, not windows.
      final page = await dao.queryProducts(
        _scopeA,
        sort: 'low',
        limit: 2,
        offset: 2,
      );
      expect(page.map((p) => p.serverId), [2, 3]);
      expect(await dao.countProducts(_scopeA, priceMin: 150), 2);
      expect(await dao.countProducts(_scopeA), 4);
      // Combined search + category filter in one query.
      expect(
        (await dao.queryProducts(_scopeA, search: 'abaya', categoryId: 3))
            .map((p) => p.serverId),
        unorderedEquals([2, 4]),
      );
      await db.close();
    });
  });
}
