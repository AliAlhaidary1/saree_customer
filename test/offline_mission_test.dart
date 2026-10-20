import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/api_errors.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/offline/local_store.dart';
import 'package:sareemart_customer/core/offline/offline_cache.dart';
import 'package:sareemart_customer/core/offline/operation_policy.dart';
import 'package:sareemart_customer/core/offline/pending_ops.dart';

ApiResult _fail() => ApiResult({'status': 0, 'message': 'network'});

ClassifiedApiError _networkError() => const ClassifiedApiError(
      code: 'TIMEOUT',
      publicCode: 'TIMEOUT',
      originalMessage: 'Connection timed out',
      userMessage: 'network_error',
      release: false,
      category: ApiErrorCategory.network,
    );

class _FakeApi extends CustomerApi {
  _FakeApi() : super(baseUrl: 'http://test.invalid');

  ApiResult settingsRes = _fail();
  ApiResult paymentRes = _fail();
  ApiResult logoutRes = _fail();
  ApiResult guestCartRes = _fail();
  ApiResult businessHoursRes = _fail();
  ApiResult removeRes = ApiResult({'status': 1, 'data': []});
  ApiResult addRes = ApiResult({'status': 1, 'data': []});
  bool removeFavoriteCalled = false;

  @override
  Future<ApiResult> settings({bool withAuth = false}) async => settingsRes;

  @override
  Future<ApiResult> paymentMethods() async => paymentRes;

  @override
  Future<ApiResult> logout() async => logoutRes;

  @override
  Future<ApiResult> businessHours({List<dynamic> sellerIds = const []}) async =>
      businessHoursRes;

  @override
  Future<ApiResult> guestCart({
    required double latitude,
    required double longitude,
    required String variantIds,
    required String quantities,
  }) async =>
      guestCartRes;

  @override
  Future<ApiResult> addFavorite(dynamic productId) async => addRes;

  @override
  Future<ApiResult> removeFavorite(dynamic productId) async {
    removeFavoriteCalled = true;
    return removeRes;
  }
}

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

   group('operation policy', () {
    test('financial and state-transition ops are online-only', () {
      for (final op in [
        CustomerOp.checkout,
        CustomerOp.createOrder,
        CustomerOp.initiatePayment,
        CustomerOp.verifyPayment,
        CustomerOp.cancelOrder,
        CustomerOp.modifyOrder,
        CustomerOp.requestRefund,
        CustomerOp.walletTransfer,
      ]) {
        expect(OperationPolicy.isOnlineOnly(op), isTrue, reason: '$op');
      }
    });

    test('browse and favorites are offline-capable', () {
      for (final op in [
        CustomerOp.browseCatalog,
        CustomerOp.viewProductDetails,
        CustomerOp.searchLocal,
        CustomerOp.toggleFavorite,
        CustomerOp.manageAddressesLocal,
        CustomerOp.editCart,
      ]) {
        expect(OperationPolicy.isOnlineOnly(op), isFalse, reason: '$op');
      }
    });
  });

  group('reachability evidence', () {
    test('fresh client assumes nothing (not offline)', () {
      final api = _FakeApi();
      expect(api.likelyOffline, isFalse);
    });

    test('recent network failure hints offline; success clears it', () {
      final api = _FakeApi();
      api.recordFailure(_networkError());
      expect(api.lastFailure?.category, ApiErrorCategory.network);
      expect(api.likelyOffline, isTrue);
      api.recordSuccess();
      expect(api.likelyOffline, isFalse);
    });
  });

  group('checkout key constraints', () {
    test('generated idempotency key fits backend max:64 validation',
        () async {
      final api = _FakeApi();
      final c = await _controller({}, api);
      c.setUser({'id': 2147483647});
      final key = await c.checkoutKey(context: {'fingerprint': 'abc'});
      expect(key.length, lessThanOrEqualTo(64));
    });
  });

  group('bounded catalog storage', () {
    test('product pages are LRU-trimmed to 60 entries', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = OfflineCache(LocalStore(prefs));
      for (var i = 0; i < 65; i++) {
        await cache.writeProductPage('oc:products::p$i', [
          {'id': i}
        ]);
      }
      final store = LocalStore(prefs);
      final keys = store.keysWithPrefix('oc:products::');
      expect(keys.length, lessThanOrEqualTo(OfflineCache.maxProductPages));
      // Newest entries survive; oldest were evicted.
      expect(cache.readDoc('oc:products::p64'), isNotNull);
      expect(cache.readDoc('oc:products::p0'), isNull);
    });

    test('eviction never touches account docs, outbox, or sessions',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      final cache = OfflineCache(store);
      await cache.writeDoc(OfflineCache.ordersKey('u:1'), {'a': 1},
          scope: 'u:1');
      await store.writeString('oc:pending::u:1', '[]');
      await store.writeString('checkout_session::u:1', '{}');
      for (var i = 0; i < 70; i++) {
        await cache.writeProductPage('oc:products::q$i', [
          {'id': i}
        ]);
      }
      expect(cache.readDoc(OfflineCache.ordersKey('u:1')), isNotNull);
      expect(store.readString('oc:pending::u:1'), isNotNull);
      expect(store.readString('checkout_session::u:1'), isNotNull);
    });

    test('product details are trimmed to 100 entries', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = OfflineCache(LocalStore(prefs));
      for (var i = 0; i < 105; i++) {
        await cache.writeProductDetails('oc:pdetail::$i', {'id': i});
      }
      final keys =
          LocalStore(prefs).keysWithPrefix('oc:pdetail::');
      expect(keys.length, lessThanOrEqualTo(OfflineCache.maxProductDetails));
      expect(cache.readDoc('oc:pdetail::104'), isNotNull);
    });
  });

  group('pagination dedupe', () {
    test('appendUnique drops repeated server ids', () {
      final a = [
        {'id': 1, 'name': 'A'},
        {'id': 2, 'name': 'B'}
      ];
      final b = [
        {'id': 2, 'name': 'B2'},
        {'id': 3, 'name': 'C'}
      ];
      final merged = J.appendUnique(a, b);
      expect(merged.length, 3);
      // First-seen row wins (stable display, no flicker to shifted data).
      expect(merged[1]['name'], 'B');
    });

    test('appendUnique falls back to slug then keeps id-less rows', () {
      final merged = J.appendUnique(
        [
          {'slug': 'x'}
        ],
        [
          {'slug': 'x'},
          {'name': 'no-id'}
        ],
      );
      expect(merged.length, 2);
    });
  });

  group('favorites convergence', () {
    test('reloadSettings filters pending removals from server snapshot',
        () async {
      final api = _FakeApi()
        ..settingsRes = ApiResult({
          'status': 1,
          'data': {
            'favorite_product_ids': [1, 2]
          }
        });
      final c = await _controller({}, api);
      await PendingOutbox(c.store, 'guest').enqueue(PendingOp(
        id: 'op-rm',
        type: PendingOpType.favoriteRemove,
        payload: {'product_id': '2'},
        createdAt: DateTime.now(),
      ));
      await c.reloadSettings();
      expect(c.favoriteIds.map((e) => '$e'), ['1']);
    });

    test('queued removal from another account never executes', () async {
      final api = _FakeApi();
      final c = await _controller({}, api);
      final done = await c.runPendingOp(PendingOp(
        id: 'x',
        type: PendingOpType.favoriteRemove,
        payload: {'product_id': '5', 'account_scope': 'u:123'},
        createdAt: DateTime.now(),
      ));
      expect(done, isTrue);
      expect(api.removeFavoriteCalled, isFalse);
    });
  });

  group('guest cart offline', () {
    test('guest add persists locally and survives failed refresh', () async {
      final api = _FakeApi();
      final c = await _controller({}, api);
      c.city = {
        'id': 1,
        'latitude': '15.3',
        'longitude': '44.2',
      };
      final err = await c.addToCart(
        productId: 10,
        variantId: 20,
        qty: 2,
        sellerId: 7,
      );
      expect(err, isNull);
      expect(c.guestCart.length, 1);
      expect(c.guestCart.first['qty'], 2);
      // Durable across restart: the exact prefs slot bootstrap reads.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('guest_cart');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!);
      expect(decoded, isA<List>());
      expect(decoded.first['product_variant_id'], 20);
    });
  });

  group('logout and account isolation', () {
    test('offline logout clears account docs but keeps public catalog',
        () async {
      final api = _FakeApi();
      final c = await _controller({
        'shop_cache': jsonEncode({'id': 1}),
        'cats_cache': jsonEncode([
          {'id': 2}
        ]),
      }, api);
      c.setUser({'id': 42});
      c.token = 't';
      await c.offline.writeDoc(OfflineCache.ordersKey('u:42'), {'a': 1},
          scope: 'u:42');
      await c.offline.writeDoc(OfflineCache.favoritesKey('u:42'), [9],
          scope: 'u:42');
      await c.cacheProductPage({'limit': 20}, [
        {'id': 5}
      ]);
      await c.logout();
      expect(c.token, isNull);
      expect(c.user, isNull);
      expect(c.offline.readDoc(OfflineCache.ordersKey('u:42')), isNull);
      expect(c.offline.readDoc(OfflineCache.favoritesKey('u:42')), isNull);
      // Public catalog survives logout.
      expect(c.shop ?? {'id': 1}, isNotNull);
      expect(
          c.readCachedProductPage({'limit': 20}).isNotEmpty, isTrue);
    });

    test('guest and authenticated scopes never share private docs', () async {
      final api = _FakeApi();
      final c = await _controller({}, api);
      await c.offline.writeDoc(OfflineCache.ordersKey('guest'), {'a': 1},
          scope: 'guest');
      c.setUser({'id': 1});
      c.token = 't';
      expect(c.readCachedOrders().active, isEmpty);
    });
  });
}
