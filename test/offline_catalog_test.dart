import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/catalog_db/catalog_config.dart';
import 'package:sareemart_customer/core/catalog_db/catalog_database.dart';
import 'package:sareemart_customer/core/catalog_store.dart';
import 'package:sareemart_customer/core/image_prefetch.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/offline/local_store.dart';
import 'package:sareemart_customer/core/offline/offline_cache.dart';
import 'package:sareemart_customer/core/offline/pending_ops.dart';

Map<String, dynamic> _productRow(int id) => {
  'id': id,
  'name': 'عباية رقم $id',
  'description': 'وصف المنتج $id',
  'seller_id': 7,
  'store_name': 'متجر سبعة',
  'category_id': 3,
  'price': '${100 + id}',
  'rating': 4.5,
  'status': 1,
};

/// Offset-paged fake fetch over [all]. Fails the [failOnCall]-th call.
CatalogPageFetch pager(
  List<Map<String, dynamic>> all, {
  int? total,
  int failOnCall = -1,
}) {
  var calls = 0;
  return ({required int limit, required int offset}) async {
    calls++;
    if (calls == failOnCall) {
      return CatalogPage(rows: const [], ok: false, error: 'boom');
    }
    return CatalogPage(
      rows: all.skip(offset).take(limit).toList(),
      total: total ?? all.length,
    );
  };
}

class _SessionApi extends CustomerApi {
  _SessionApi() : super(baseUrl: 'http://test.invalid');

  ApiResult? me;

  @override
  Future<ApiResult> userDetails() async => me ?? ApiResult({'status': 0});
}

class _CatalogApi extends CustomerApi {
  _CatalogApi() : super(baseUrl: 'http://test.invalid');

  List<Map<String, dynamic>> allProducts = [];
  List<Map<String, dynamic>> allStores = [];
  List<Map<String, dynamic>> allCategories = [];

  @override
  Future<ApiResult> products({
    required double latitude,
    required double longitude,
    Map<String, dynamic> filters = const {},
    String tagNames = '',
    String slug = '',
  }) async {
    final offset = J.i(filters['offset']);
    final limit = J.i(filters['limit'], 50);
    final slice = allProducts.skip(offset).take(limit).toList();
    return ApiResult({'status': 1, 'data': slice, 'total': allProducts.length});
  }

  @override
  Future<ApiResult> sellers({
    double? latitude,
    double? longitude,
    int limit = 50,
    int offset = 0,
    String? search,
    String? sort,
    String? type,
    dynamic minRating,
  }) async {
    final slice = allStores.skip(offset).take(limit).toList();
    return ApiResult({'status': 1, 'data': slice, 'total': allStores.length});
  }

  @override
  Future<ApiResult> categories({
    dynamic categoryId,
    dynamic limit,
    dynamic offset,
    String? slug,
  }) async {
    return ApiResult({'status': 1, 'data': allCategories});
  }
}

Future<AppController> _controller(
  Map<String, Object> seedPrefs,
  CustomerApi api,
) async {
  SharedPreferences.setMockInitialValues(seedPrefs);
  final prefs = await SharedPreferences.getInstance();
  final c = AppController();
  c.injectForTest(prefs: prefs, testApi: api);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('encoded byte guards', () {
    test('documentBytes counts UTF-8 bytes, not Dart chars', () {
      final arabic = 'م' * 1000; // 1000 chars, 2000 bytes in UTF-8
      expect(arabic.length, 1000);
      expect(LocalStore.documentBytes({'v': arabic}), greaterThan(1500));
    });

    test('writeJson refuses payloads oversized in bytes', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      final big = 'م' * (300 * 1024); // 300k chars ~= 600KB
      expect(await store.writeJson('huge', {'v': big}), isFalse);
      expect(store.readJson('huge'), isNull);
      expect(await store.writeJson('small', {'v': 'ok'}), isTrue);
    });

    test('enqueue refuses oversized op payloads', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final out = PendingOutbox(LocalStore(prefs), 'u:1');
      final ok = await out.enqueue(
        PendingOp(
          id: 'a',
          type: PendingOpType.favoriteAdd,
          payload: {'product_id': '1'},
          createdAt: DateTime.now(),
        ),
      );
      expect(ok, isTrue);
      final refused = await out.enqueue(
        PendingOp(
          id: 'b',
          type: PendingOpType.favoriteAdd,
          payload: {'product_id': 'x' * 40000},
          createdAt: DateTime.now(),
        ),
      );
      expect(refused, isFalse);
      expect(out.load().length, 1);
    });
  });

  group('drafts and snapshot isolation', () {
    test(
      'draft round-trips per scope and never leaks across accounts',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final cache = OfflineCache(LocalStore(prefs));
        await cache.writeDraft('u:1', 'checkout_form', {'method': 'COD'});
        expect(cache.readDraft('u:1', 'checkout_form'), {'method': 'COD'});
        expect(cache.readDraft('u:2', 'checkout_form'), isNull);
        await cache.clearAccountDocs('u:1');
        expect(cache.readDraft('u:1', 'checkout_form'), isNull);
      },
    );

    test('logout wipes account snapshots, keeps global ones', () async {
      final c = await _controller(
        {},
        CustomerApi(baseUrl: 'http://test.invalid'),
      );
      c.setUser({'id': 42});
      c.token = 't';
      await c.cacheAccountSnapshot('wallet', [
        {'id': 1},
      ]);
      await c.cachePublicSnapshot('faqs', [
        {'q': 'x'},
      ]);
      await c.offline.writeDraft('u:42', 'checkout_form', {'method': 'COD'});
      await c.logout();
      expect(c.readAccountSnapshot('wallet'), isNull);
      expect(c.offline.readDraft('u:42', 'checkout_form'), isNull);
      expect(c.readPublicSnapshot('faqs'), isNotNull);
    });
  });

  group('session validation keeps login offline', () {
    test('network failure keeps token and user', () async {
      final api = _SessionApi()
        ..me = ApiResult({
          'status': 0,
          'message': 'timeout',
          'error': {'code': 'TIMEOUT'},
        });
      final c = await _controller({}, api);
      c.token = 't';
      c.setUser({'id': 1});
      await c.validateSession();
      expect(c.token, 't');
      expect(c.user?['id'], 1);
    });

    test('auth failure clears the session', () async {
      final api = _SessionApi()
        ..me = ApiResult({
          'status': 0,
          'message': 'gone',
          'error': {'code': 'HTTP_401', 'httpStatus': 401},
        });
      final c = await _controller({}, api);
      c.token = 't';
      c.setUser({'id': 1});
      await c.validateSession();
      expect(c.token, isNull);
      expect(c.user, isNull);
    });

    test('offline restart restores last user snapshot', () async {
      final api = _SessionApi()
        ..me = ApiResult({
          'status': 0,
          'message': 'timeout',
          'error': {'code': 'TIMEOUT'},
        });
      final c = await _controller({}, api);
      c.token = 't';
      // user lost from memory (process restart), snapshot persisted before.
      await c.offline.writeDoc(OfflineCache.snapshotKey('user::guest'), {
        'id': 9,
        'name': 'N',
      }, scope: 'guest');
      await c.validateSession();
      expect(c.token, 't');
      expect(c.user?['id'], 9);
    });
  });

  group('bounded local state', () {
    test('variant labels are capped', () async {
      final c = await _controller(
        {},
        CustomerApi(baseUrl: 'http://test.invalid'),
      );
      for (var i = 0; i < 600; i++) {
        await c.rememberVariantLabel(i, 'label $i');
      }
      expect(c.variantLabelFor(0), isEmpty);
      expect(c.variantLabelFor(599), 'label 599');
    });

    test('oversized guest cart stays memory-only', () async {
      final c = await _controller(
        {},
        CustomerApi(baseUrl: 'http://test.invalid'),
      );
      c.guestCart = List.generate(
        2000,
        (i) => {'product_variant_id': i, 'qty': 1, 'note': 'م' * 400},
      );
      await c.persistGuestCart();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('guest_cart'), isNull);
      expect(c.guestCart.length, 2000);
    });

    test('recent searches dedupe and cap at 10', () async {
      final c = await _controller(
        {},
        CustomerApi(baseUrl: 'http://test.invalid'),
      );
      for (var i = 0; i < 12; i++) {
        await c.addRecentSearch('q$i');
      }
      await c.addRecentSearch('q11');
      final recent = c.recentSearches();
      expect(recent.length, 10);
      expect(recent.first, 'q11');
    });

    test('catalog scope follows city', () {
      expect(catalogScopeForCity({'id': 4}), 'city:4');
      expect(catalogScopeForCity(null), 'global');
      expect(catalogScopeForCity({}), 'global');
    });
  });

  group('authenticated cart snapshot', () {
    test('offline refresh restores last confirmed lines as stale', () async {
      final c = await _controller(
        {},
        CustomerApi(baseUrl: 'http://test.invalid'),
      );
      c.city = {'id': 1, 'latitude': '15.3', 'longitude': '44.2'};
      c.setUser({'id': 5});
      c.token = 't';
      await c.offline.writeDoc(OfflineCache.snapshotKey('cart::u:5'), {
        'products': [
          {'product_variant_id': 9, 'qty': 2},
        ],
        'subTotal': 50.0,
      }, scope: 'u:5');
      final res = await c.refreshCart();
      expect(res.ok, isFalse);
      expect(c.cartProducts.length, 1);
      expect(c.cartSubTotal, 50.0);
    });
  });

  group('CatalogSyncService', () {
    test('happy path syncs, indexes FTS, checkpoints best_effort', () async {
      final db = await CatalogDatabase.openMemory();
      final svc = CatalogSyncService();
      final all = List.generate(120, (i) => _productRow(i + 1));
      final result = await svc.syncScope(
        db: db,
        scope: 'city:4',
        fetchProducts: pager(all),
        fetchStores: pager([
          {'id': 7, 'name': 'Store Seven'},
        ]),
        fetchCategories: pager([
          {'id': 3, 'name': 'Abayas'},
        ]),
        delay: (_) async {},
      );
      expect(result.complete, isTrue);
      expect(result.products, 120);
      final dao = CatalogDao(db);
      expect(await dao.productCount('city:4'), 120);
      // Arabic FTS over synchronized rows.
      expect(
        (await dao.searchProducts('city:4', 'عباية')).length,
        greaterThan(0),
      );
      expect((await dao.searchProducts('city:9', 'عباية')), isEmpty);
      final state = await dao.getSyncState('city:4');
      expect(state?.coverage, 'best_effort');
      expect(state?.lastOffset, 120);
      expect(svc.progress.value.phase, CatalogSyncPhase.done);
      await db.close();
    });

    test('interrupted run re-walks from the start without duplicates', () async {
      final db = await CatalogDatabase.openMemory();
      final svc = CatalogSyncService();
      final all = List.generate(120, (i) => _productRow(i + 1));
      final first = await svc.syncScope(
        db: db,
        scope: 'city:4',
        fetchProducts: pager(all, failOnCall: 2),
        fetchStores: pager(const []),
        fetchCategories: pager(const []),
        delay: (_) async {},
      );
      expect(first.complete, isFalse);
      expect(first.products, 48);
      expect(await CatalogDao(db).productCount('city:4'), 48);
      // Every walk starts at offset 0 (partial resume would poison
      // end-of-walk reconciliation), so the retry re-walks fully — idempotent
      // upserts make repeats no-ops.
      var firstOffset = -1;
      final second = await svc.syncScope(
        db: db,
        scope: 'city:4',
        fetchProducts: ({required int limit, required int offset}) async {
          if (firstOffset < 0) firstOffset = offset;
          return pager(all)(limit: limit, offset: offset);
        },
        fetchStores: pager(const []),
        fetchCategories: pager(const []),
        delay: (_) async {},
      );
      expect(firstOffset, 0);
      expect(second.complete, isTrue);
      expect(await CatalogDao(db).productCount('city:4'), 120);
      await db.close();
    });

    test('failed page preserves prior data and checkpoint', () async {
      final db = await CatalogDatabase.openMemory();
      final svc = CatalogSyncService();
      final all = List.generate(60, (i) => _productRow(i + 1));
      final result = await svc.syncScope(
        db: db,
        scope: 'city:4',
        fetchProducts: pager(all, failOnCall: 1),
        fetchStores: pager(const []),
        fetchCategories: pager(const []),
        delay: (_) async {},
      );
      expect(result.complete, isFalse);
      expect(result.error, isNotEmpty);
      expect(await CatalogDao(db).productCount('city:4'), 0);
      expect(await CatalogDao(db).getSyncState('city:4'), isNull);
      await db.close();
    });

    test('malformed page stops without advancing', () async {
      final db = await CatalogDatabase.openMemory();
      final svc = CatalogSyncService();
      final result = await svc.syncScope(
        db: db,
        scope: 'city:4',
        fetchProducts: pager([
          {'no_id': 1},
        ]),
        fetchStores: pager(const []),
        fetchCategories: pager(const []),
        delay: (_) async {},
      );
      expect(result.complete, isFalse);
      expect(result.error, 'malformed_page');
      expect(await CatalogDao(db).productCount('city:4'), 0);
      await db.close();
    });

    test('cancel keeps committed pages', () async {
      final db = await CatalogDatabase.openMemory();
      final svc = CatalogSyncService();
      final all = List.generate(120, (i) => _productRow(i + 1));
      var calls = 0;
      final result = await svc.syncScope(
        db: db,
        scope: 'city:4',
        fetchProducts: ({required int limit, required int offset}) async {
          calls++;
          if (calls == 2) svc.cancel();
          return pager(all)(limit: limit, offset: offset);
        },
        fetchStores: pager(const []),
        fetchCategories: pager(const []),
        delay: (_) async {},
      );
      expect(result.cancelled, isTrue);
      expect(result.complete, isFalse);
      expect(await CatalogDao(db).productCount('city:4'), 48);
      await db.close();
    });
  });

  group('row mapping and local filtering', () {
    test('rows without identity are skipped', () {
      expect(productUpsertFromRow({'name': 'x'}), isNull);
      expect(productUpsertFromRow({'id': 1}), isNull);
      expect(
        storeCompanionFromRow({'name': 'x'}, 'city:4', DateTime.now()),
        isNull,
      );
      expect(
        categoryCompanionFromRow(
          {'id': 0, 'name': 'x'},
          'city:4',
          DateTime.now(),
        ),
        isNull,
      );
      expect(productUpsertFromRow(_productRow(5))?.serverId, 5);
    });

    test('filters never hide rows missing the field', () {
      final rows = [
        {'id': 1, 'price': '100', 'rating': 4.0},
        {'id': 2, 'name': 'no price row'},
      ];
      expect(filterCatalogRows(rows, priceMin: '200').length, 1);
      expect(filterCatalogRows(rows, minRating: '5').length, 1);
      expect(sortCatalogRows(rows, 'high').first['id'], 1);
      expect(sortCatalogRows(rows, 'new').first['id'], 2);
    });
  });

  group('controller catalog end-to-end', () {
    test('sync then browse/search locally with scope isolation', () async {
      expect(CatalogDbConfig.enabledForUse, isTrue);
      final api = _CatalogApi()
        ..allProducts = List.generate(30, (i) => _productRow(i + 1))
        ..allStores = [
          {'id': 7, 'name': 'Store Seven'},
        ]
        ..allCategories = [
          {'id': 3, 'name': 'Abayas'},
        ];
      final c = await _controller({}, api);
      c.city = {'id': 4};
      final db = await CatalogDatabase.openMemory();
      c.setCatalogDbForTest(db);
      final result = await c.syncCatalogNow();
      expect(result?.complete, isTrue);
      expect(await c.catalogProductCountLocal(), 30);
      final page = await c.catalogProductsLocal(limit: 50);
      expect(page.length, 30);
      final found = await c.catalogProductsLocal(search: 'عباية', limit: 50);
      expect(found.length, 30);
      final detail = await c.catalogProductLocal(id: 3);
      expect(detail?['id'], 3);
      expect((await c.catalogStoresLocal()).length, 1);
      expect((await c.catalogCategoriesLocal()).length, 1);
      // Idempotent re-sync: no duplicates.
      await c.syncCatalogNow();
      expect(await c.catalogProductCountLocal(), 30);
      // Other city scope sees nothing (no leakage).
      c.city = {'id': 9};
      expect(await c.catalogProductCountLocal(), 0);
      expect(await c.catalogProductsLocal(limit: 50), isEmpty);
      await db.close();
    });

    test('city A-B-A switch keeps scopes isolated across syncs', () async {
      final c = await _controller(
        {},
        CustomerApi(baseUrl: 'http://test.invalid'),
      );
      final db = await CatalogDatabase.openMemory();
      c.setCatalogDbForTest(db);
      final svc = c.catalogSync;
      Future<CatalogSyncResult> syncCity(List<Map<String, dynamic>> rows) =>
          svc.syncScope(
            db: db,
            scope: c.catalogScope,
            fetchProducts: pager(rows),
            fetchStores: pager(const []),
            fetchCategories: pager(const []),
            delay: (_) async {},
          );
      c.city = {'id': 4};
      expect((await syncCity([_productRow(1), _productRow(2)])).complete,
          isTrue);
      c.city = {'id': 5};
      expect((await syncCity([_productRow(9)])).complete, isTrue);
      expect(await c.catalogProductCountLocal(), 1);
      expect(
        (await c.catalogProductsLocal(limit: 50)).map((m) => m['id']),
        [9],
      );
      // Switch back: city 4 rows intact, city 5 rows invisible here.
      c.city = {'id': 4};
      expect(await c.catalogProductCountLocal(), 2);
      expect(
        (await c.catalogProductsLocal(search: 'عباية', limit: 50)).length,
        2,
      );
      final state4 = await c.catalogScopeState();
      expect(state4.status, CatalogScopeStatus.ready);
      c.city = {'id': 6};
      final state6 = await c.catalogScopeState();
      expect(state6.status, CatalogScopeStatus.neverSynced);
      await db.close();
    });
  });

  group('image manifest hygiene', () {
    test('fileNameFor is stable and distinct', () {
      expect(
        ImagePrefetch.fileNameFor('https://x/y.jpg'),
        ImagePrefetch.fileNameFor('https://x/y.jpg'),
      );
      expect(
        ImagePrefetch.fileNameFor('https://x/a.jpg') ==
            ImagePrefetch.fileNameFor('https://x/b.jpg'),
        isFalse,
      );
    });

    test('reconcile drops manifest rows for missing files', () async {
      final db = await CatalogDatabase.openMemory();
      final dao = CatalogDao(db);
      await dao.putImage(
        url: 'https://x/missing.jpg',
        localPath: '/definitely/not/here.jpg',
        bytes: 10,
        now: DateTime.now(),
      );
      expect(await dao.imagesTotalBytes(), 10);
      await ImagePrefetch.reconcile(db);
      expect(await dao.imagesTotalBytes(), 0);
      await db.close();
    });
  });
}
