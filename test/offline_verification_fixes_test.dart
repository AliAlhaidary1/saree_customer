import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/catalog_db/catalog_database.dart';
import 'package:sareemart_customer/core/catalog_store.dart';
import 'package:sareemart_customer/core/image_prefetch.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/offline/local_store.dart';
import 'package:sareemart_customer/core/offline/offline_cache.dart';

Map<String, dynamic> _productRow(int id) => {
      'id': id,
      'name': 'product $id',
      'seller_id': 7,
      'store_name': 'store seven',
      'category_id': 3,
      'price': '${100 + id}',
      'rating': 4.5,
      'status': 1,
    };

Map<String, dynamic> _storeRow(int id) => {'id': id, 'name': 'store $id'};

Map<String, dynamic> _categoryRow(int id) => {'id': id, 'name': 'cat $id'};

CatalogPageFetch _pager(List<Map<String, dynamic>> all, {int? total}) {
  return ({required int limit, required int offset}) async => CatalogPage(
        rows: all.skip(offset).take(limit).toList(),
        total: total ?? all.length,
      );
}

CatalogPageFetch _failing(String error) {
  return ({required int limit, required int offset}) async =>
      CatalogPage(rows: const [], ok: false, error: error);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('verification fixes: sync completeness honesty', () {
    test('stores failure keeps products but reports incomplete', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final products =
          List.generate(3, (i) => _productRow(i + 1));
      final result = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: _pager(products),
        fetchStores: _failing('stores_boom'),
        fetchCategories: _pager([_categoryRow(1)]),
        delay: (_) async {},
      );
      expect(result.complete, isFalse);
      expect(result.error, isNotEmpty);
      expect(result.products, 3);
      // Committed products survive the stores failure.
      expect(await CatalogDao(db).productCount('city:1'), 3);
    });

    test('categories failure keeps products+stores but reports incomplete',
        () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final result = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: _pager([_productRow(1)]),
        fetchStores: _pager([_storeRow(1)]),
        fetchCategories: _failing('cats_boom'),
        delay: (_) async {},
      );
      expect(result.complete, isFalse);
      expect(result.error, 'cats_boom');
      expect(result.products, 1);
      expect(result.stores, 1);
    });

    test('maxPages truncation is reported, not done', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final products =
          List.generate(10, (i) => _productRow(i + 1));
      final result = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: _pager(products),
        fetchStores: _pager(const []),
        fetchCategories: _pager(const []),
        pageSize: 2,
        maxPages: 2,
        delay: (_) async {},
      );
      expect(result.complete, isFalse);
      expect(result.error, 'truncated_max_pages');
    });

    test('short page below server cap continues while total says more',
        () async {
      // Mirrors the verified backend: cap 48 rows, total reported on page 1
      // only. Requesting 50 must still walk the whole dataset.
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final all = List.generate(100, (i) => _productRow(i + 1));
      Future<CatalogPage> capped({required int limit, required int offset}) async {
        final rows = all.skip(offset).take(48).toList();
        return CatalogPage(rows: rows, total: offset == 0 ? 100 : -1);
      }
      final result = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: capped,
        fetchStores: _pager(const []),
        fetchCategories: _pager(const []),
        pageSize: 50,
        delay: (_) async {},
      );
      expect(result.complete, isTrue);
      expect(result.products, 100);
      expect(await CatalogDao(db).productCount('city:1'), 100);
    });

    test('short page with unknown total still ends the walk', () async {      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final result = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: _pager([_productRow(1), _productRow(2)], total: -1),
        fetchStores: _pager(const []),
        fetchCategories: _pager(const []),
        pageSize: 50,
        delay: (_) async {},
      );
      expect(result.complete, isTrue);
      expect(result.products, 2);
    });

    test('cancel during stores walk reports cancelled, not done', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      Future<CatalogPage> slowStores(
          {required int limit, required int offset}) async {
        svc.cancel();
        return CatalogPage(rows: [_storeRow(1)], total: 1);
      }

      final result = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: _pager([_productRow(1)]),
        fetchStores: slowStores,
        fetchCategories: _pager(const []),
        delay: (_) async {},
      );
      expect(result.complete, isFalse);
      expect(result.cancelled, isTrue);
    });
  });

  group('verification fixes: empty-result envelope', () {
    test('Arabic past-end signal maps to end-of-data', () {
      expect(
          isEmptyCatalogPage(ApiResult(
              {'status': 0, 'message': 'لم يتم العثور على منتجات'})),
          isTrue);
      expect(
          isEmptyCatalogPage(
              ApiResult({'status': 0, 'message': 'لم يتم العثور على فئات!'})),
          isTrue);
    });

    test('real errors stay errors', () {
      expect(isEmptyCatalogPage(ApiResult({'status': 1, 'data': []})),
          isFalse);
      expect(
          isEmptyCatalogPage(ApiResult(
              {'status': 0, 'message': 'unauthenticated'})),
          isFalse);
      expect(
          isEmptyCatalogPage(ApiResult({
            'status': 0,
            'message': 'لم يتم العثور على منتجات',
            'data': [
              {'id': 1}
            ]
          })),
          isFalse);
    });

    test('past-end error page ends the walk cleanly (resume-safe)', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final all = [_productRow(1), _productRow(2)];
      var calls = 0;
      Future<CatalogPage> flakyPastEnd({required int limit, required int offset}) async {
        calls++;
        if (offset == 0) {
          // Checkpoint claims 3 (a row was deleted server-side afterwards).
          return CatalogPage(rows: all, total: 3);
        }
        // Verified live shape: HTTP 200 + status:0 + empty signal, no data.
        final res = ApiResult(
            {'status': 0, 'message': 'لم يتم العثور على منتجات'});
        if (isEmptyCatalogPage(res)) {
          return CatalogPage(rows: const [], total: offset);
        }
        return CatalogPage(rows: const [], ok: false, error: res.message);
      }
      final result = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: flakyPastEnd,
        fetchStores: _pager(const []),
        fetchCategories: _pager(const []),
        pageSize: 50,
        delay: (_) async {},
      );
      expect(result.complete, isTrue);
      expect(await CatalogDao(db).productCount('city:1'), 2);
      expect(calls, greaterThanOrEqualTo(2));
    });
  });

  group('verification fixes: reconciliation', () {
    test('clean full walk unlists rows missing from the scan', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      var server = [_productRow(1), _productRow(2), _productRow(3)];
      Future<CatalogSyncResult> sync() => svc.syncScope(
            db: db,
            scope: 'city:1',
            fetchProducts: _pager(server),
            fetchStores: _pager(const []),
            fetchCategories: _pager(const []),
            delay: (_) async {},
          );
      expect((await sync()).complete, isTrue);
      expect(await CatalogDao(db).productCount('city:1'), 3);
      // Server deletes row 2 (update + delete between walks).
      server = [
        {..._productRow(1), 'name': 'product 1 v2'},
        _productRow(3),
      ];
      expect((await sync()).complete, isTrue);
      final dao = CatalogDao(db);
      expect(await dao.productCount('city:1'), 2);
      // Update propagated through re-upsert.
      expect(
          (await dao.getProductById('city:1', 1))!.name, 'product 1 v2');
      // Deleted row: unlisted from browse but resolvable by id.
      expect(await dao.getProductById('city:1', 2), isNotNull);
      expect(
          (await dao.searchProducts('city:1', 'product')).map((p) => p.serverId),
          unorderedEquals([1, 3]));
    });

    test('failed walk never reconciles (live rows preserved)', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final dao = CatalogDao(db);
      await dao.upsertProductBatch(
        scope: 'city:1',
        rows: [
          productUpsertFromRow(_productRow(1))!,
          productUpsertFromRow(_productRow(2))!,
        ],
        now: DateTime.now(),
      );
      // New walk fails on its only page: no reconcile may run.
      final res = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: _failing('boom'),
        fetchStores: _pager(const []),
        fetchCategories: _pager(const []),
        delay: (_) async {},
      );
      expect(res.complete, isFalse);
      expect(await dao.productCount('city:1'), 2);
    });

    test('cancelled walk never reconciles (committed rows kept listed)',
        () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final dao = CatalogDao(db);
      await dao.upsertProductBatch(
        scope: 'city:1',
        rows: [productUpsertFromRow(_productRow(1))!],
        now: DateTime.now(),
      );
      Future<CatalogPage> cancelFirst(
          {required int limit, required int offset}) async {
        svc.cancel();
        return CatalogPage(rows: [_productRow(2)], total: 2);
      }

      final res = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: cancelFirst,
        fetchStores: _pager(const []),
        fetchCategories: _pager(const []),
        delay: (_) async {},
      );
      expect(res.cancelled, isTrue);
      expect(await dao.productCount('city:1'), 1);
      expect((await dao.getProductById('city:1', 1))!.isListed, isTrue);
    });

    test('variant shrink across walks prunes ghost variants', () async {      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      var row = Map<String, dynamic>.from(_productRow(1));
      row['variants'] = [
        {'id': 11, 'name': 'a'},
        {'id': 12, 'name': 'b'},
      ];
      Future<CatalogSyncResult> sync(Map<String, dynamic> r) => svc.syncScope(
            db: db,
            scope: 'city:1',
            fetchProducts: _pager([r]),
            fetchStores: _pager(const []),
            fetchCategories: _pager(const []),
            delay: (_) async {},
          );
      expect((await sync(row)).complete, isTrue);
      final dao = CatalogDao(db);
      expect(
          (await dao.variantsForProduct('city:1', 1)).map((v) => v.serverId),
          unorderedEquals([11, 12]));
      row = Map<String, dynamic>.from(row);
      row['variants'] = [
        {'id': 11, 'name': 'a'},
      ];
      expect((await sync(row)).complete, isTrue);
      expect(
          (await dao.variantsForProduct('city:1', 1)).map((v) => v.serverId),
          [11]);
      expect(await dao.orphanCounts(), {'variants': 0, 'fts': 0});
    });

    test('mid-walk server change converges on the next walk', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final server = [_productRow(1), _productRow(2)];
      var calls = 0;
      Future<CatalogPage> mutating({required int limit, required int offset}) async {
        calls++;
        // Second page fetch happens after a concurrent insert.
        if (calls == 2) server.add(_productRow(3));
        return CatalogPage(
          rows: server.skip(offset).take(limit).toList(),
          total: server.length,
        );
      }
      Future<CatalogSyncResult> sync() => svc.syncScope(
            db: db,
            scope: 'city:1',
            fetchProducts: mutating,
            fetchStores: _pager(const []),
            fetchCategories: _pager(const []),
            pageSize: 2,
            delay: (_) async {},
          );
      expect((await sync()).complete, isTrue);
      // Next full walk converges exactly, with no duplicates.
      expect((await sync()).complete, isTrue);
      final dao = CatalogDao(db);
      expect(await dao.productCount('city:1'), 3);
      final ids = (await dao.listProducts('city:1', limit: 10))
          .map((p) => p.serverId)
          .toList();
      expect(ids.toSet(), {1, 2, 3});
    });

    test('empty catalog completes, then fills on transition', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      var server = <Map<String, dynamic>>[];
      Future<CatalogSyncResult> sync() => svc.syncScope(
            db: db,
            scope: 'city:1',
            fetchProducts: _pager(server),
            fetchStores: _pager(const []),
            fetchCategories: _pager(const []),
            delay: (_) async {},
          );
      expect((await sync()).complete, isTrue);
      final dao = CatalogDao(db);
      expect(await dao.productCount('city:1'), 0);
      expect((await dao.getSyncState('city:1'))!.phase, 'full_complete');
      server = [_productRow(1)];
      expect((await sync()).complete, isTrue);
      expect(await dao.productCount('city:1'), 1);
    });
  });

  group('verification fixes: payload + checkpoint compatibility', () {
    test('null-valued row maps, syncs, and stays filter-neutral', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final row = {
        'id': 1,
        'name': 'Nullish',
        'seller_id': 7,
        'price': null,
        'rating': null,
        'variants': null,
      };
      final up = productUpsertFromRow(row);
      expect(up, isNotNull);
      expect(up!.minPrice, isNull);
      expect(up.inStock, isNull);
      expect(up.hasOffer, isNull);
      final result = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: _pager([row]),
        fetchStores: _pager(const []),
        fetchCategories: _pager(const []),
        delay: (_) async {},
      );
      expect(result.complete, isTrue);
      final dao = CatalogDao(db);
      expect(await dao.productCount('city:1'), 1);
      // Unknowns never filter out and sort last.
      expect(
          (await dao.queryProducts('city:1',
                  priceMin: 1000, inStockOnly: true, offersOnly: true))
              .length,
          1);
    });

    test('corrupt checkpoint phase recovers to a clean walk', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final dao = CatalogDao(db);
      await dao.saveSyncState(SyncStatesCompanion.insert(
        scope: 'city:1',
        phase: 'garbage!!phase',
        coverage: const Value('best_effort'),
        lastOffset: const Value(-999),
        storedCount: const Value(0),
        updatedAt: DateTime.now(),
      ));
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final result = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: _pager([_productRow(1)]),
        fetchStores: _pager(const []),
        fetchCategories: _pager(const []),
        delay: (_) async {},
      );
      // Walks always start at 0, so corrupt stored offsets are inert; the
      // clean walk overwrites the corrupt phase.
      expect(result.complete, isTrue);
      expect((await dao.getSyncState('city:1'))!.phase, 'full_complete');
      expect(await dao.productCount('city:1'), 1);
    });
  });

  group('verification fixes: image filename hygiene', () {    test('distinct urls map to distinct files', () {
      final a = ImagePrefetch.fileNameFor('https://cdn.test/a.jpg');
      final b = ImagePrefetch.fileNameFor('https://cdn.test/b.jpg');
      expect(a, isNot(equals(b)));
    });

    test('query-string format hint does not force extension', () {
      final name = ImagePrefetch.fileNameFor(
          'https://cdn.test/img?format=png&x=1');
      expect(name.endsWith('.jpg'), isTrue);
    });

    test('real path extension is honored', () {
      expect(
          ImagePrefetch.fileNameFor('https://cdn.test/x.png?sig=1')
              .endsWith('.png'),
          isTrue);
      expect(
          ImagePrefetch.fileNameFor('https://cdn.test/x.webp')
              .endsWith('.webp'),
          isTrue);
    });
  });

  group('verification fixes: account snapshot removal', () {
    test('removeDoc deletes one snapshot key', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = OfflineCache(LocalStore(prefs));
      await cache.writeDoc('oc:snap::assistant_thread::u:1', [
        {'role': 'user', 'text': 'hi'}
      ], scope: 'u:1');
      expect(cache.readDoc('oc:snap::assistant_thread::u:1'), isNotNull);
      await cache.removeDoc('oc:snap::assistant_thread::u:1');
      expect(cache.readDoc('oc:snap::assistant_thread::u:1'), isNull);
    });

    test('removeAccountSnapshot drops assistant thread', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = AppController();
      c.injectForTest(
          prefs: prefs, testApi: CustomerApi(baseUrl: 'http://t.invalid'));
      c.setUser({'id': 9});
      await c.cacheAccountSnapshot('assistant_thread', [
        {'role': 'user', 'text': 'hi'}
      ]);
      expect(c.readAccountSnapshot('assistant_thread'), isNotNull);
      await c.removeAccountSnapshot('assistant_thread');
      expect(c.readAccountSnapshot('assistant_thread'), isNull);
    });
  });
}
