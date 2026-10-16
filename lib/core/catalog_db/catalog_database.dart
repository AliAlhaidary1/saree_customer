import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';

import 'catalog_config.dart';
import 'db_recovery.dart';
import 'sync_coverage.dart';
import 'tables.dart';

part 'catalog_database.g.dart';

/// Drift database for the offline catalog.
///
/// Read paths consult it when `CatalogDbConfig.enabledForUse` is true and
/// always fall back to JSON/network when it is unavailable. Account data
/// (favorites, cart, orders, outbox, sessions, tokens, addresses) is
/// intentionally absent from this schema.
@DriftDatabase(
  tables: [
    Cities,
    Categories,
    Stores,
    Products,
    ProductVariants,
    CachedImages,
    SyncStates,
    CartItems,
  ],
)
class CatalogDatabase extends _$CatalogDatabase {
  CatalogDatabase(super.e);

  @override
  int get schemaVersion => CatalogDbConfig.schemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createFts();
      await _createIndexes();
    },
    beforeOpen: (details) async {
      // Foreign-key enforcement is per-connection in SQLite and OFF by
      // default; without this, the composite FK on product_variants is
      // documentation only. Every connection (file, memory, future
      // isolates) passes through here.
      await customStatement('PRAGMA foreign_keys = ON;');
    },
    // v1 → v2: rebuild product_variants with the composite FK (SQLite
    // cannot ALTER a table to add a constraint) and add the §2.2 index
    // set. Data is copied verbatim; FTS rows are untouched (separate
    // virtual table, keyed by scope+server_id which do not change).
    // v1 → v2: rebuild product_variants with the composite FK (SQLite
    // cannot ALTER a table to add a constraint) and add the §2.2 index
    // set. Data is copied verbatim; FTS rows are untouched (separate
    // virtual table, keyed by scope+server_id which do not change).
    // The whole step runs inside a SAVEPOINT so a failure rolls the
    // file back to its pre-migration state (retryable, no partial DDL).
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await customStatement('SAVEPOINT drift_v1_to_v2;');
        try {
          await customStatement(
            'CREATE TABLE product_variants_new ('
            'scope TEXT NOT NULL, '
            'server_id INTEGER NOT NULL, '
            'product_id INTEGER NOT NULL, '
            'payload TEXT NOT NULL, '
            'refreshed_at INTEGER NOT NULL, '
            'PRIMARY KEY (scope, server_id), '
            'FOREIGN KEY (scope, product_id) '
            'REFERENCES products (scope, server_id) '
            'ON DELETE CASCADE);',
          );
          await customStatement(
            'INSERT INTO product_variants_new '
            '(scope, server_id, product_id, payload, refreshed_at) '
            'SELECT scope, server_id, product_id, payload, refreshed_at '
            'FROM product_variants;',
          );
          await customStatement('DROP TABLE product_variants;');
          await customStatement(
            'ALTER TABLE product_variants_new RENAME TO product_variants;',
          );
          await _createIndexes();
          await customStatement('RELEASE drift_v1_to_v2;');
        } catch (e) {
          try {
            await customStatement('ROLLBACK TO drift_v1_to_v2;');
            await customStatement('RELEASE drift_v1_to_v2;');
          } catch (_) {}
          rethrow;
        }
      }
      // v2 → v3: reconciliation columns on products (pure ADD COLUMN with
      // safe defaults — no data rewrite, no row loss). Existing rows keep
      // is_listed=1 (they were listed when synced); min_price/in_stock/
      // has_offer default to NULL (unknown: never hidden by filters) and are
      // recomputed on the next upsert. Runs inside a SAVEPOINT like v1→v2.
      if (from < 3) {
        await customStatement('SAVEPOINT drift_v2_to_v3;');
        try {
          await customStatement(
            'ALTER TABLE products ADD COLUMN is_listed INTEGER NOT NULL DEFAULT 1;',
          );
          await customStatement(
            'ALTER TABLE products ADD COLUMN min_price REAL;',
          );
          await customStatement(
            'ALTER TABLE products ADD COLUMN in_stock INTEGER;',
          );
          await customStatement(
            'ALTER TABLE products ADD COLUMN has_offer INTEGER;',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_products_scope_listed '
            'ON products (scope, is_listed);',
          );
          await customStatement('RELEASE drift_v2_to_v3;');
        } catch (e) {
          try {
            await customStatement('ROLLBACK TO drift_v2_to_v3;');
            await customStatement('RELEASE drift_v2_to_v3;');
          } catch (_) {}
          rethrow;
        }
      }
    },
  );

  Future<void> _createFts() => customStatement(
    'CREATE VIRTUAL TABLE IF NOT EXISTS products_fts USING '
    'fts5(scope, server_id UNINDEXED, name, search_blob, store_name, '
    'tokenize="unicode61");',
  );

  /// Plan §2.2 index set. Idempotent (`IF NOT EXISTS`) so it runs on both
  /// fresh creates and the v1 → v2 upgrade.
  Future<void> _createIndexes() async {
    for (final stmt in const [
      'CREATE INDEX IF NOT EXISTS idx_products_scope_category '
          'ON products (scope, category_id);',
      'CREATE INDEX IF NOT EXISTS idx_products_scope_store '
          'ON products (scope, store_id);',
      'CREATE INDEX IF NOT EXISTS idx_products_scope_status '
          'ON products (scope, status);',
      'CREATE INDEX IF NOT EXISTS idx_variants_scope_product '
          'ON product_variants (scope, product_id);',
      'CREATE INDEX IF NOT EXISTS idx_stores_scope_status '
          'ON stores (scope, status);',
      'CREATE INDEX IF NOT EXISTS idx_categories_scope_parent '
          'ON categories (scope, parent_id, row_order);',
      'CREATE INDEX IF NOT EXISTS idx_images_last_used '
          'ON cached_images (last_used_at);',
    ]) {
      await customStatement(stmt);
    }
  }

  /// Opens (creating if needed) the file database.
  ///
  /// Recovery contract (R1): the file is quarantined + recreated ONLY on
  /// confirmed corruption ([OpenFailureKind.corruption] per
  /// [classifyOpenFailure]: `SQLITE_CORRUPT`/`SQLITE_NOTADB`). Transient and
  /// operational failures (busy/locked/readonly/perm/io/full/nomem/cantopen,
  /// migration-time resource failures, unknown errors) close any handle,
  /// preserve the file untouched, and rethrow the original error — no
  /// replacement database is silently created.
  ///
  /// If recreation itself fails, that error propagates with the quarantine
  /// file preserved on disk for forensics.
  static Future<CatalogDatabase> openFile(
    File file, {
    @visibleForTesting Future<CatalogDatabase> Function(File file)? openForTest,
    @visibleForTesting OpenFailureKind Function(Object)? classifyForTest,
  }) async {
    final open = openForTest ?? _openAndProbe;
    final classify = classifyForTest ?? classifyOpenFailure;
    try {
      return await open(file);
    } catch (e) {
      if (classify(e) != OpenFailureKind.corruption) rethrow;
      try {
        if (await file.exists()) {
          await file.rename(
            '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}',
          );
        }
      } catch (_) {}
      // Always a real open: a test double must never stand in for recovery.
      return _openAndProbe(file);
    }
  }

  /// Opens + probes (migrations run). Closes its own handle on failure so
  /// callers (and Windows file locking) never inherit a broken connection.
  static Future<CatalogDatabase> _openAndProbe(File file) async {
    final db = CatalogDatabase(NativeDatabase(file));
    try {
      await db.customSelect('SELECT 1;').getSingle();
      return db;
    } catch (e) {
      try {
        await db.close();
      } catch (_) {}
      rethrow;
    }
  }

  /// In-memory database for tests.
  static Future<CatalogDatabase> openMemory() async {
    final db = CatalogDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1;').getSingle();
    return db;
  }
}

/// One product row prepared by the sync engine (Phase 2). Payloads are the
/// raw backend JSON maps; the DAO stores them verbatim plus indexed columns.
class ProductUpsert {
  ProductUpsert({
    required this.serverId,
    this.slug,
    required this.name,
    required this.storeId,
    this.categoryId,
    this.storeName = '',
    this.searchBlob = '',
    this.priceSnapshot = '{}',
    this.thumbnailUrl,
    this.rating = 0,
    this.status = 1,
    this.payload = '{}',
    this.variants = const [],
    this.minPrice,
    this.inStock,
    this.hasOffer,
  });

  final int serverId;
  final String? slug;
  final String name;
  final int storeId;
  final int? categoryId;
  final String storeName;
  final String searchBlob;
  final String priceSnapshot;
  final String? thumbnailUrl;
  final double rating;
  final int status;
  final String payload;
  final List<VariantUpsert> variants;

  /// Minimum effective variant price, null when the payload carries none.
  final double? minPrice;

  /// Any variant in stock (or unlimited flag), null = unknown (never hidden).
  final bool? inStock;

  /// Any offer signal, null = unknown (never hidden).
  final bool? hasOffer;
}

class VariantUpsert {
  VariantUpsert({required this.serverId, this.payload = '{}'});

  final int serverId;
  final String payload;
}

/// Data-access layer for the catalog. All batch writes run in a single
/// transaction; checkpoints are persisted by the caller only after these
/// futures complete (plan §4.1), so a failed batch leaves no partial rows.
class CatalogDao {
  CatalogDao(this._db);

  final CatalogDatabase _db;

  /// Escapes user text for an FTS5 prefix query. Empty input matches nothing
  /// (callers return [] early instead of MATCH '').
  static String ftsPhrase(String query) {
    final q = query.replaceAll('"', '""').trim();
    return '"$q"*';
  }

  /// Upserts one committed batch: products + variants + FTS rows, atomically.
  /// Repeating a batch is a no-op for identity (composite keys) — resume-safe.
  /// Every upserted product is marked listed (it came from the live listing).
  /// Variants are pruned per touched product: variant rows absent from the new
  /// payload are deleted, so shrunk variant sets cannot leave ghost rows. Only
  /// products present in this batch are pruned — partial walks never touch
  /// other products' variants.
  Future<void> upsertProductBatch({
    required String scope,
    required List<ProductUpsert> rows,
    required DateTime now,
  }) {
    return _db.transaction(() async {
      for (final r in rows) {
        await _db
            .into(_db.products)
            .insertOnConflictUpdate(
              ProductsCompanion(
                scope: Value(scope),
                serverId: Value(r.serverId),
                slug: Value(r.slug),
                name: Value(r.name),
                storeId: Value(r.storeId),
                categoryId: Value(r.categoryId),
                searchBlob: Value(r.searchBlob),
                priceSnapshot: Value(r.priceSnapshot),
                thumbnailUrl: Value(r.thumbnailUrl),
                rating: Value(r.rating),
                status: Value(r.status),
                isListed: const Value(true),
                minPrice: Value(r.minPrice),
                inStock: Value(r.inStock),
                hasOffer: Value(r.hasOffer),
                payload: Value(r.payload),
                refreshedAt: Value(now),
                lastSeenAt: Value(now),
              ),
            );
        final freshVariantIds = <int>{};
        for (final v in r.variants) {
          freshVariantIds.add(v.serverId);
          await _db
              .into(_db.productVariants)
              .insertOnConflictUpdate(
                ProductVariantsCompanion(
                  scope: Value(scope),
                  serverId: Value(v.serverId),
                  productId: Value(r.serverId),
                  payload: Value(v.payload),
                  refreshedAt: Value(now),
                ),
              );
        }
        // Prune only on positive evidence: an empty variant set in the payload
        // cannot be distinguished from "variants omitted", so it prunes
        // nothing (and avoids `NOT IN ()` edge semantics).
        if (freshVariantIds.isNotEmpty) {
          await (_db.delete(_db.productVariants)
                ..where(
                  (v) =>
                      v.scope.equals(scope) &
                      v.productId.equals(r.serverId) &
                      v.serverId.isNotIn(freshVariantIds),
                ))
              .go();
        }
        await _db.customStatement(
          'DELETE FROM products_fts WHERE scope = ? AND server_id = ?;',
          [scope, r.serverId],
        );
        await _db.customStatement(
          'INSERT INTO products_fts (scope, server_id, name, search_blob, '
          'store_name) VALUES (?, ?, ?, ?, ?);',
          [scope, r.serverId, r.name, r.searchBlob, r.storeName],
        );
      }
    });
  }

  /// Removes one scoped product, its variants, and its FTS row (tombstones).
  Future<void> deleteScopedProduct(String scope, int serverId) {
    return _db.transaction(() async {
      await (_db.delete(
            _db.productVariants,
          )..where((v) => v.scope.equals(scope) & v.productId.equals(serverId)))
          .go();
      await (_db.delete(_db.products)
            ..where((p) => p.scope.equals(scope) & p.serverId.equals(serverId)))
          .go();
      await _db.customStatement(
        'DELETE FROM products_fts WHERE scope = ? AND server_id = ?;',
        [scope, serverId],
      );
    });
  }

  Future<void> upsertStores({
    required String scope,
    required List<StoresCompanion> rows,
  }) {
    return _db.transaction(() async {
      for (final r in rows) {
        await _db.into(_db.stores).insertOnConflictUpdate(r);
      }
    });
  }

  Future<void> upsertCategories({
    required String scope,
    required List<CategoriesCompanion> rows,
  }) {
    return _db.transaction(() async {
      for (final r in rows) {
        await _db.into(_db.categories).insertOnConflictUpdate(r);
      }
    });
  }

  /// Scoped product listing (primary read path from Phase 3; unused before).
  /// Unlisted rows (absent from the last clean reconciliation) are hidden by
  /// default; detail lookups below still resolve them.
  Future<List<Product>> listProducts(
    String scope, {
    int? categoryId,
    int? storeId,
    int? status,
    bool listedOnly = true,
    int limit = 50,
    int offset = 0,
  }) {
    final q = _db.select(_db.products)
      ..where((p) {
        var expr = p.scope.equals(scope);
        if (listedOnly) expr = expr & p.isListed.equals(true);
        if (categoryId != null) expr = expr & p.categoryId.equals(categoryId);
        if (storeId != null) expr = expr & p.storeId.equals(storeId);
        if (status != null) expr = expr & p.status.equals(status);
        return expr;
      })
      ..orderBy([(p) => OrderingTerm.asc(p.serverId)])
      ..limit(limit, offset: offset);
    return q.get();
  }

  /// Scoped full-text search over listed rows only (never the live API).
  Future<List<Product>> searchProducts(
    String scope,
    String query, {
    int limit = 50,
    int offset = 0,
  }) {
    if (query.trim().isEmpty) return Future.value(const []);
    return _db
        .customSelect(
          'SELECT p.* FROM products_fts AS f '
          'JOIN products AS p ON p.scope = f.scope AND p.server_id = f.server_id '
          'WHERE f.scope = ? AND p.is_listed = 1 AND products_fts MATCH ? '
          'ORDER BY rank LIMIT ? OFFSET ?;',
          variables: [
            Variable.withString(scope),
            Variable.withString(ftsPhrase(query)),
            Variable.withInt(limit),
            Variable.withInt(offset),
          ],
          readsFrom: {_db.products},
        )
        .map((row) => _db.products.map(row.data))
        .get();
  }

  /// Direct lookups for offline product-detail pages (covers products that
  /// were synchronized but never opened — no visit-scoped JSON needed).
  Future<Product?> getProductById(String scope, int serverId) {
    return (_db.select(_db.products)
          ..where((p) => p.scope.equals(scope) & p.serverId.equals(serverId)))
        .getSingleOrNull();
  }

  Future<Product?> getProductBySlug(String scope, String slug) {
    return (_db.select(_db.products)
          ..where((p) => p.scope.equals(scope) & p.slug.equals(slug)))
        .getSingleOrNull();
  }

  Future<List<ProductVariant>> variantsForProduct(String scope, int productId) {
    return (_db.select(_db.productVariants)
          ..where((v) => v.scope.equals(scope) & v.productId.equals(productId)))
        .get();
  }

  /// Scoped store listing + direct lookups for offline store pages.
  Future<List<Store>> listStores(
    String scope, {
    int limit = 50,
    int offset = 0,
  }) {
    return (_db.select(_db.stores)
          ..where((s) => s.scope.equals(scope))
          ..orderBy([(s) => OrderingTerm.asc(s.serverId)])
          ..limit(limit, offset: offset))
        .get();
  }

  Future<Store?> getStoreById(String scope, int serverId) {
    return (_db.select(_db.stores)
          ..where((s) => s.scope.equals(scope) & s.serverId.equals(serverId)))
        .getSingleOrNull();
  }

  Future<Store?> getStoreBySlug(String scope, String slug) {
    return (_db.select(_db.stores)
          ..where((s) => s.scope.equals(scope) & s.slug.equals(slug)))
        .getSingleOrNull();
  }

  /// Scoped categories ordered for display.
  Future<List<Category>> listCategories(String scope) {
    return (_db.select(_db.categories)
          ..where((c) => c.scope.equals(scope))
          ..orderBy([
            (c) => OrderingTerm.asc(c.rowOrder),
            (c) => OrderingTerm.asc(c.serverId),
          ]))
        .get();
  }

  Future<int> productCount(String scope, {bool listedOnly = true}) async {
    final expr = _db.products.serverId.count();
    final q = _db.selectOnly(_db.products)
      ..addColumns([expr])
      ..where(
        listedOnly
            ? _db.products.scope.equals(scope) &
                  _db.products.isListed.equals(true)
            : _db.products.scope.equals(scope),
      );
    final row = await q.getSingle();
    return row.read(expr) ?? 0;
  }

  /// Database-backed browse query: filtering, sorting AND pagination all
  /// happen in SQL over the full scoped set, so matches beyond the first
  /// window can never be hidden (the old fetch-window-then-filter path could
  /// miss them). Unknown column values (NULL) never filter a row out and
  /// sort last. `sort` mirrors the backend keys; `nearest` needs live
  /// coordinates and falls back to rating, like the screens.
  Future<List<Product>> queryProducts(
    String scope, {
    int? categoryId,
    int? storeId,
    String search = '',
    String sort = '',
    double? priceMin,
    double? priceMax,
    double? minRating,
    bool inStockOnly = false,
    bool offersOnly = false,
    int limit = 50,
    int offset = 0,
  }) {
    final where = StringBuffer('p.scope = ? AND p.is_listed = 1');
    final vars = <Variable>[Variable.withString(scope)];
    if (search.trim().isNotEmpty) {
      where.write(' AND products_fts MATCH ?');
      vars.add(Variable.withString(ftsPhrase(search)));
    }
    if (categoryId != null) {
      where.write(' AND p.category_id = ?');
      vars.add(Variable.withInt(categoryId));
    }
    if (storeId != null) {
      where.write(' AND p.store_id = ?');
      vars.add(Variable.withInt(storeId));
    }
    if (priceMin != null) {
      where.write(' AND (p.min_price IS NULL OR p.min_price >= ?)');
      vars.add(Variable.withReal(priceMin));
    }
    if (priceMax != null) {
      where.write(' AND (p.min_price IS NULL OR p.min_price <= ?)');
      vars.add(Variable.withReal(priceMax));
    }
    if (minRating != null && minRating > 0) {
      where.write(' AND (p.rating <= 0 OR p.rating >= ?)');
      vars.add(Variable.withReal(minRating));
    }
    if (inStockOnly) {
      where.write(' AND (p.in_stock IS NULL OR p.in_stock = 1)');
    }
    if (offersOnly) {
      where.write(' AND (p.has_offer IS NULL OR p.has_offer = 1)');
    }
    final order = switch (sort) {
      'low' => 'p.min_price ASC NULLS LAST, p.server_id ASC',
      'high' => 'p.min_price DESC NULLS LAST, p.server_id ASC',
      'rating' || 'nearest' => 'p.rating DESC, p.server_id ASC',
      'new' => 'p.server_id DESC',
      _ => 'p.server_id ASC',
    };
    final from = search.trim().isNotEmpty
        ? 'products_fts AS f JOIN products AS p '
            'ON p.scope = f.scope AND p.server_id = f.server_id '
        : 'products AS p ';
    vars.add(Variable.withInt(limit));
    vars.add(Variable.withInt(offset));
    return _db
        .customSelect(
          'SELECT p.* FROM ${from}WHERE $where ORDER BY $order '
          'LIMIT ? OFFSET ?;',
          variables: vars,
          readsFrom: {_db.products},
        )
        .map((row) => _db.products.map(row.data))
        .get();
  }

  /// Count sections or haraj rows for the given scope.
  Future<int> sectionHarajCount(String scope, String type) async {
    final expr = _db.categories.serverId.count();
    final q = _db.selectOnly(_db.categories)..addColumns([expr])
      ..where(
        _db.categories.scope.equals(scope) &
            _db.categories.type.equals(type),
      );
    final row = await q.getSingle();
    return row.read(expr) ?? 0;
  }

  /// Count matching [queryProducts] without paging (same WHERE clause).
  Future<int> countProducts(
    String scope, {
    int? categoryId,
    int? storeId,
    String search = '',
    double? priceMin,
    double? priceMax,
    double? minRating,
    bool inStockOnly = false,
    bool offersOnly = false,
  }) async {
    final where = StringBuffer('p.scope = ? AND p.is_listed = 1');
    final vars = <Variable>[Variable.withString(scope)];
    if (search.trim().isNotEmpty) {
      where.write(' AND products_fts MATCH ?');
      vars.add(Variable.withString(ftsPhrase(search)));
    }
    if (categoryId != null) {
      where.write(' AND p.category_id = ?');
      vars.add(Variable.withInt(categoryId));
    }
    if (storeId != null) {
      where.write(' AND p.store_id = ?');
      vars.add(Variable.withInt(storeId));
    }
    if (priceMin != null) {
      where.write(' AND (p.min_price IS NULL OR p.min_price >= ?)');
      vars.add(Variable.withReal(priceMin));
    }
    if (priceMax != null) {
      where.write(' AND (p.min_price IS NULL OR p.min_price <= ?)');
      vars.add(Variable.withReal(priceMax));
    }
    if (minRating != null && minRating > 0) {
      where.write(' AND (p.rating <= 0 OR p.rating >= ?)');
      vars.add(Variable.withReal(minRating));
    }
    if (inStockOnly) {
      where.write(' AND (p.in_stock IS NULL OR p.in_stock = 1)');
    }
    if (offersOnly) {
      where.write(' AND (p.has_offer IS NULL OR p.has_offer = 1)');
    }
    final from = search.trim().isNotEmpty
        ? 'products_fts AS f JOIN products AS p '
            'ON p.scope = f.scope AND p.server_id = f.server_id '
        : 'products AS p ';
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM $from WHERE $where;',
          variables: vars,
          readsFrom: {_db.products},
        )
        .getSingle();
    return (row.data['c'] as int?) ?? 0;
  }

  /// Reconciliation: mark scoped rows absent from a COMPLETED full walk as
  /// unlisted. Callers must only invoke this after a clean, uncapped,
  /// uncancelled walk that started at offset 0 — never after a partial walk,
  /// or live rows would be wrongly unlisted. Chunked for the 999-variable
  /// SQLite limit. Detail lookups still resolve unlisted rows.
  Future<void> reconcileListed(
    String scope,
    Set<int> serverIds, {
    int chunkSize = 500,
  }) {
    final ids = serverIds.toList();
    return _db.transaction(() async {
      // Upserts already set is_listed=1 for every seen row; here only the
      // unseen rows are unlisted. With an empty server set this unlists the
      // whole scope — correct only because the caller proved the walk
      // complete (genuinely empty catalog).
      if (ids.isEmpty) {
        await _db.customStatement(
          'UPDATE products SET is_listed = 0 WHERE scope = ?;',
          [scope],
        );
        return;
      }
      var offset = 0;
      while (offset < ids.length) {
        final end =
            offset + chunkSize > ids.length ? ids.length : offset + chunkSize;
        final chunk = ids.sublist(offset, end);
        final ph = List.filled(chunk.length, '?').join(', ');
        await _db.customStatement(
          'UPDATE products SET is_listed = 0 WHERE scope = ? '
          'AND server_id NOT IN ($ph);',
          [scope, ...chunk],
        );
        offset = end;
      }
    });
  }

  /// Deletes scoped stores absent from a completed full walk (small table,
  /// always fully walked; store pages fall back to network/snapshots).
  /// Same clean-walk-only contract as [reconcileListed].
  Future<void> deleteMissingStores(String scope, Set<int> serverIds) {
    return _deleteMissingIds('stores', scope, serverIds);
  }

  /// Deletes scoped categories absent from a completed full walk.
  /// Same clean-walk-only contract as [reconcileListed].
  Future<void> deleteMissingCategories(String scope, Set<int> serverIds) {
    return _deleteMissingIds('categories', scope, serverIds);
  }

  Future<void> _deleteMissingIds(
    String table,
    String scope,
    Set<int> serverIds, {
    int chunkSize = 500,
  }) {
    assert(table == 'stores' || table == 'categories');
    final ids = serverIds.toList();
    return _db.transaction(() async {
      if (ids.isEmpty) {
        await _db.customStatement('DELETE FROM $table WHERE scope = ?;', [
          scope,
        ]);
        return;
      }
      var offset = 0;
      while (offset < ids.length) {
        final end =
            offset + chunkSize > ids.length ? ids.length : offset + chunkSize;
        final chunk = ids.sublist(offset, end);
        final ph = List.filled(chunk.length, '?').join(', ');
        await _db.customStatement(
          'DELETE FROM $table WHERE scope = ? AND server_id NOT IN ($ph);',
          [scope, ...chunk],
        );
        offset = end;
      }
    });
  }

  Future<SyncState?> getSyncState(String scope) {
    return (_db.select(
      _db.syncStates,
    )..where((s) => s.scope.equals(scope))).getSingleOrNull();
  }

  /// Typed coverage read: unknown stored values throw instead of mapping
  /// silently (fail loudly on data errors).
  Future<SyncCoverage?> coverageOf(String scope) async {
    final row = await getSyncState(scope);
    if (row == null) return null;
    return SyncCoverageCodec.fromDb(row.coverage);
  }

  /// Persists a checkpoint. Coverage contract (R2):
  /// * explicitly-passed unknown coverage strings are rejected;
  /// * `verified` requires sufficient [VerifiedEvidence] — without it (or
  ///   with partial evidence) a [StateError] is thrown and nothing is
  ///   written. No production path in this phase can construct sufficient
  ///   evidence, so the only writable state here is `best_effort`.
  Future<void> saveSyncState(
    SyncStatesCompanion state, {
    VerifiedEvidence? evidence,
  }) {
    final cov = state.coverage.present ? state.coverage.value : null;
    if (cov != null) {
      final parsed = SyncCoverageCodec.fromDb(cov);
      if (parsed == SyncCoverage.verified &&
          !(evidence?.isSufficient ?? false)) {
        throw StateError(
          'verified coverage requires complete evidence '
          '(baseline + cursor + tombstones); refusing to write.',
        );
      }
    }
    return _db.into(_db.syncStates).insertOnConflictUpdate(state);
  }

  /// Removes scoped catalog rows (sweep/trim). Sync-state row is kept;
  /// image manifest is managed separately (Phase 4).
  Future<void> deleteScopeCatalog(String scope) {
    return _db.transaction(() async {
      await (_db.delete(
        _db.productVariants,
      )..where((v) => v.scope.equals(scope))).go();
      await (_db.delete(
        _db.products,
      )..where((p) => p.scope.equals(scope))).go();
      await (_db.delete(_db.stores)..where((s) => s.scope.equals(scope))).go();
      await (_db.delete(
        _db.categories,
      )..where((c) => c.scope.equals(scope))).go();
      await _db.customStatement('DELETE FROM products_fts WHERE scope = ?;', [
        scope,
      ]);
    });
  }

  // ---- Image manifest (budget enforcement primitives; pipeline in Phase 4) ----

  Future<void> putImage({
    required String url,
    required String localPath,
    required int bytes,
    required DateTime now,
  }) {
    return _db
        .into(_db.cachedImages)
        .insertOnConflictUpdate(
          CachedImagesCompanion(
            url: Value(url),
            localPath: Value(localPath),
            bytes: Value(bytes),
            lastUsedAt: Value(now),
          ),
        );
  }

  Future<void> touchImage(String url, DateTime now) async {
    await (_db.update(_db.cachedImages)..where((i) => i.url.equals(url))).write(
      CachedImagesCompanion(lastUsedAt: Value(now)),
    );
  }

  /// Manifest lookup by URL (null when untracked). Used by the prefetch
  /// cache-hit path to adopt orphan files instead of ignoring them.
  Future<CachedImage?> getImage(String url) {
    return (_db.select(
      _db.cachedImages,
    )..where((i) => i.url.equals(url))).getSingleOrNull();
  }

  Future<int> imagesTotalBytes() async {
    final expr = _db.cachedImages.bytes.sum();
    final q = _db.selectOnly(_db.cachedImages)..addColumns([expr]);
    final row = await q.getSingle();
    return row.read(expr) ?? 0;
  }

  /// Oldest-first candidates whose bytes sum to at least [bytesToFree].
  /// The caller (Phase 4 pipeline) deletes files only for returned rows,
  /// then removes the manifest rows — manifest-first ordering (§6).
  Future<List<CachedImage>> evictCandidates({required int bytesToFree}) {
    return (_db.select(
      _db.cachedImages,
    )..orderBy([(i) => OrderingTerm.asc(i.lastUsedAt)])).get().then((all) {
      final out = <CachedImage>[];
      var freed = 0;
      for (final row in all) {
        if (freed >= bytesToFree) break;
        out.add(row);
        freed += row.bytes;
      }
      return out;
    });
  }

  Future<void> removeImage(String url) {
    return (_db.delete(_db.cachedImages)..where((i) => i.url.equals(url))).go();
  }

  /// Orphan audit for relationship integrity (R3): variant and FTS rows
  /// without a matching scoped product. Every DAO mutation path must leave
  /// these at zero (asserted in tests after each path, including migration).
  Future<Map<String, int>> orphanCounts() async {
    Future<int> count(String sql) async {
      final row = await _db.customSelect(sql).getSingle();
      return (row.data['c'] as int?) ?? 0;
    }

    return {
      'variants': await count(
        'SELECT COUNT(*) AS c FROM product_variants AS v '
        'LEFT JOIN products AS p ON p.scope = v.scope '
        'AND p.server_id = v.product_id '
        'WHERE p.server_id IS NULL;',
      ),
      'fts': await count(
        'SELECT COUNT(*) AS c FROM products_fts AS f '
        'LEFT JOIN products AS p ON p.scope = f.scope '
        'AND p.server_id = f.server_id '
        'WHERE p.server_id IS NULL;',
      ),
    };
  }
}
