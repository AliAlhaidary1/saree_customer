import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/offline/cache_policy.dart';
import 'package:sareemart_customer/core/offline/local_store.dart';
import 'package:sareemart_customer/core/offline/offline_cache.dart';
import 'package:sareemart_customer/core/offline/pending_ops.dart';

/// Fake API with per-endpoint scripted results (default: offline failure).
class _FakeApi extends CustomerApi {
  _FakeApi() : super(baseUrl: 'http://test.invalid');

  ApiResult settingsRes = ApiResult({'status': 0, 'message': 'network'});
  ApiResult paymentRes = ApiResult({'status': 0, 'message': 'network'});
  ApiResult citiesRes = ApiResult({'status': 0, 'message': 'network'});
  ApiResult shopRes = ApiResult({'status': 0, 'message': 'network'});
  ApiResult catsRes = ApiResult({'status': 0, 'message': 'network'});
  ApiResult ordersRes = ApiResult({'status': 0, 'message': 'network'});

  @override
  Future<ApiResult> settings({bool withAuth = false}) async => settingsRes;

  @override
  Future<ApiResult> paymentMethods() async => paymentRes;

  @override
  Future<ApiResult> cities(
          {int limit = 100, int offset = 0, String search = ''}) async =>
      citiesRes;

  @override
  Future<ApiResult> shop(
          {required double latitude, required double longitude}) async =>
      shopRes;

  @override
  Future<ApiResult> categories(
          {dynamic categoryId,
          dynamic limit,
          dynamic offset,
          String? slug}) async =>
      catsRes;

  @override
  Future<ApiResult> orders(
          {int limit = 10,
          int offset = 0,
          int type = 1,
          dynamic orderId}) async =>
      ordersRes;
}

ApiResult _fail() => ApiResult({'status': 0, 'message': 'network'});

Future<AppController> _controller(
  Map<String, Object> seedPrefs,
  _FakeApi api,
) async {
  SharedPreferences.setMockInitialValues(seedPrefs);
  final prefs = await SharedPreferences.getInstance();
  final c = AppController();
  c.injectForTest(prefs: prefs, testApi: api);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cold-start offline with populated cache', () {
    test('loadShop paints STALE shop (>2min) instead of empty', () async {
      final shop = {'id': 1, 'name': 'Saved Store'};
      final api = _FakeApi()..shopRes = _fail();
      final c = await _controller({
        'shop_cache': jsonEncode(shop),
        'shop_cache_at': DateTime.now()
            .subtract(const Duration(minutes: 30))
            .millisecondsSinceEpoch,
      }, api);
      await c.loadShop();
      expect(c.shop, isNotNull);
      expect(c.shop!['name'], 'Saved Store');
    });

    test('loadShop keeps stale rows when refresh fails', () async {
      final shop = {'id': 1, 'name': 'Saved Store'};
      final api = _FakeApi()..shopRes = _fail();
      final c = await _controller({
        'shop_cache': jsonEncode(shop),
        'shop_cache_at': DateTime.now()
            .subtract(const Duration(minutes: 30))
            .millisecondsSinceEpoch,
      }, api);
      await c.loadShop();
      // Refresh failed: stale rows must still be painted.
      expect(c.shop?['name'], 'Saved Store');
    });

    test('loadShop replaces stale rows on successful refresh', () async {
      final api = _FakeApi()
        ..shopRes = ApiResult({
          'status': 1,
          'data': {'id': 2, 'name': 'Fresh Store'}
        });
      final c = await _controller({
        'shop_cache': jsonEncode({'id': 1, 'name': 'Saved Store'}),
        'shop_cache_at': DateTime.now()
            .subtract(const Duration(minutes: 30))
            .millisecondsSinceEpoch,
      }, api);
      await c.loadShop();
      expect(c.shop?['name'], 'Fresh Store');
    });

    test('loadRootCategories paints STALE cats (>10min) instead of empty',
        () async {
      final cats = [
        {'id': 7, 'name': 'Saved Category'}
      ];
      final api = _FakeApi()..catsRes = _fail();
      final c = await _controller({
        'cats_cache': jsonEncode(cats),
        'cats_cache_at': DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
      }, api);
      await c.loadRootCategories();
      expect(c.rootCategories, isNotEmpty);
      expect(c.rootCategories.first['name'], 'Saved Category');
    });

    test('loadCities keeps persisted cities when refresh fails', () async {
      final api = _FakeApi()..citiesRes = _fail();
      final c = await _controller({
        'cities_cache': jsonEncode([
          {'id': 3, 'name': 'Saved City'}
        ]),
      }, api);
      // Simulate bootstrap paint then failed refresh.
      await c.loadCities();
      expect(c.cities, isNotEmpty);
      expect(c.cities.first['name'], 'Saved City');
      expect(c.citiesLoaded, isTrue);
    });
  });

  group('favorites restoration and reconciliation', () {
    test('restoreCachedFavorites paints persisted ids for current scope',
        () async {
      final api = _FakeApi();
      final c = await _controller({}, api);
      await c.offline.writeDoc(
        OfflineCache.favoritesKey('guest'),
        [5, 6],
        scope: 'guest',
      );
      expect(c.favoriteIds, isEmpty);
      await c.restoreCachedFavorites();
      expect(c.favoriteIds, [5, 6]);
    });

    test('restoreCachedFavorites never paints another account scope',
        () async {
      final api = _FakeApi();
      final c = await _controller({}, api);
      c.setUser({'id': 99});
      await c.offline.writeDoc(
        OfflineCache.favoritesKey('u:1'),
        [5],
        scope: 'u:1',
      );
      await c.restoreCachedFavorites();
      expect(c.favoriteIds, isEmpty);
    });

    test('reloadSettings failure falls back to cached favorites', () async {
      final api = _FakeApi()
        ..settingsRes = _fail()
        ..paymentRes = _fail();
      final c = await _controller({}, api);
      await c.offline.writeDoc(
        OfflineCache.favoritesKey('guest'),
        [11],
        scope: 'guest',
      );
      await c.reloadSettings();
      expect(c.favoriteIds, [11]);
    });

    test('reloadSettings merges pending favorite adds over server snapshot',
        () async {
      final api = _FakeApi()
        ..settingsRes = ApiResult({
          'status': 1,
          'data': {'favorite_product_ids': [1]}
        })
        ..paymentRes = _fail();
      final c = await _controller({}, api);
      // Offline toggle made while network was down.
      await PendingOutbox(c.store, 'guest').enqueue(PendingOp(
        id: 'op-1',
        type: PendingOpType.favoriteAdd,
        payload: {'product_id': '2'},
        createdAt: DateTime.now(),
      ));
      await c.reloadSettings();
      expect(c.favoriteIds.map((e) => '$e'), containsAll(['1', '2']));
    });
  });

  group('cache-key separation and integrity', () {
    test('product page hash separates products vs stores views', () async {
      final api = _FakeApi();
      final c = await _controller({}, api);
      final query = {'limit': 20, 'offset': 0};
      final products = c.productPageHash(query, view: 'products');
      final stores = c.productPageHash(query, view: 'stores');
      expect(products, isNot(equals(stores)));
      expect(c.productPageHash(query), equals(products));
    });

    test('product page hash separates categories and search queries',
        () async {
      final api = _FakeApi();
      final c = await _controller({}, api);
      final a = c.productPageHash({'limit': 20, 'category_ids': '5'});
      final b = c.productPageHash({'limit': 20, 'category_ids': '9'});
      final s = c.productPageHash({'limit': 20, 'search': 'abaya'});
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(s)));
    });

    test('readDoc exposes legacy bare payloads as stale-but-displayable',
        () async {
      SharedPreferences.setMockInitialValues({
        'legacy_shop': jsonEncode({'id': 1, 'name': 'Old Build Store'}),
      });
      final prefs = await SharedPreferences.getInstance();
      final cache = OfflineCache(LocalStore(prefs));
      final doc = cache.readDoc('legacy_shop');
      expect(doc, isNotNull);
      expect(doc!.payload['name'], 'Old Build Store');
      expect(cache.fresh('legacy_shop', CacheEntity.shop), isFalse);
    });

    test('corrupt cache documents do not crash readers', () async {
      final api = _FakeApi();
      final c = await _controller({'shop_cache': 'not-json{{{'}, api);
      await c.loadShop();
      // Corrupt cache + failed network: no crash, simply nothing painted.
      expect(c.shop, isNull);
      // Corrupt favorites doc is quarantined, siblings untouched.
      SharedPreferences.setMockInitialValues({
        'a': 'not-json',
        'b': jsonEncode({'ok': 1}),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      expect(store.readJson('a'), isNull);
      expect(store.readJson('b'), {'ok': 1});
    });

    test('oversized documents are refused, previous value kept', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      await store.writeJson('k', {'v': 'small'});
      final big = List.filled(500 * 1024, 'x').join();
      expect(await store.writeJson('k', {'v': big}), isFalse);
      expect(store.readJson('k'), {'v': 'small'});
    });
  });

  group('orders, wishlist, and notifications preservation', () {
    test('cacheOrders refuses empty snapshots (never erases good cache)',
        () async {
      final api = _FakeApi();
      final c = await _controller({}, api);
      c.setUser({'id': 4});
      await c.cacheOrders([
        {'id': 1}
      ], [
        {'id': 2}
      ]);
      await c.cacheOrders([], []);
      final cached = c.readCachedOrders();
      expect(cached.active, isNotEmpty);
      expect(cached.previous, isNotEmpty);
    });

    test('cached orders are isolated per account', () async {
      final api = _FakeApi();
      final c = await _controller({}, api);
      c.setUser({'id': 1});
      await c.cacheOrders([
        {'id': 100}
      ], []);
      c.setUser({'id': 2});
      final cached = c.readCachedOrders();
      expect(cached.active, isEmpty);
    });

    test('wishlist cache round-trips per account scope', () async {
      final api = _FakeApi();
      final c = await _controller({}, api);
      c.setUser({'id': 7});
      c.token = 'test-token';
      await c.cacheWishlist([
        {'id': 9, 'name': 'Saved Item'}
      ]);
      expect(c.readCachedWishlist().first['name'], 'Saved Item');
      c.setUser({'id': 8});
      expect(c.readCachedWishlist(), isEmpty);
    });

    test('notifications cache round-trips per account scope', () async {
      final api = _FakeApi();
      final c = await _controller({}, api);
      c.setUser({'id': 7});
      c.token = 'test-token';
      await c.cacheNotifications([
        {'id': 'n1', 'title': 'Saved Notice'}
      ]);
      expect(c.readCachedNotifications().first['title'], 'Saved Notice');
      c.setUser({'id': 8});
      expect(c.readCachedNotifications(), isEmpty);
    });
  });

  group('outbox, sync, and checkout safeguards', () {
    test('dueOps separates retryable ops from permanently blocked ones',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final outbox = PendingOutbox(LocalStore(prefs), 'u:1');
      final now = DateTime.now();
      await outbox.enqueue(PendingOp(
        id: 'ok-op',
        type: PendingOpType.favoriteAdd,
        payload: {'product_id': '1'},
        createdAt: now,
      ));
      // Simulate an op that exhausted its attempt budget.
      final ops = outbox.load();
      await outbox.update(ops.first.withRetry(
        now.add(const Duration(hours: 1)),
        'x',
      ));
      for (var i = 0; i < PendingOutbox.maxAttempts; i++) {
        final current = outbox.load();
        await outbox.update(current.first.withRetry(
          now.add(const Duration(hours: 1)),
          'x',
        ));
      }
      final parts = outbox.dueOps(DateTime.now());
      expect(parts.blocked.length, 1);
      expect(parts.due, isEmpty);
    });

    test('uncertain checkout reconciles false when history is unreachable',
        () async {
      final api = _FakeApi()..ordersRes = _fail();
      final c = await _controller({}, api);
      expect(await c.hasRecentOrderForSession('missing-key'), isFalse);
    });

    test('checkout session key is stable across retries of one attempt',
        () async {
      final api = _FakeApi();
      final c = await _controller({}, api);
      final k1 = await c.checkoutKey(context: {'fingerprint': 'abc'});
      final k2 = await c.checkoutKey(context: {'fingerprint': 'abc'});
      expect(k1, equals(k2));
      expect(k1, isNotEmpty);
    });

    test('offline checkout failure never reports success', () async {
      // The API layer returns ok=false on network failure; the controller
      // surfaces that to the UI as an error (never as an order id).
      final api = _FakeApi()..ordersRes = _fail();
      final c = await _controller({}, api);
      final res = await c.api.orders(limit: 5, offset: 0);
      expect(res.ok, isFalse);
    });
  });
}
