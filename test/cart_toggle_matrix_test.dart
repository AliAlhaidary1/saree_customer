import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/api/api_errors.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/offline/offline_cache.dart';

/// Simulates a realistic server that:
///  * when online, keeps an in-memory cart map itself and persists what the
///    client requests on cart/add / cart/remove;
///  * when offline, every call becomes a network error.
class _FlakyServerApi extends CustomerApi {
  _FlakyServerApi() : super(baseUrl: 'http://test.invalid', token: null);

  bool online = true;
  /// The real upstream. ALWAYS attempt the call; the faked transport
  /// decides whether it actually goes through.
  final Map<String, int> up = {};

  List<Map<String, dynamic>> _rows() => up.entries
      .map((e) => <String, dynamic>{
            'product_id': int.tryParse(e.key) ?? e.key,
            'product_variant_id': int.tryParse(e.key) ?? e.key,
            'qty': e.value,
            'price': 25,
            'name': 'P${e.key}',
            'seller_id': 5,
          })
      .toList();

  ApiResult _networkFail() => ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });

  @override
  Future<ApiResult> cities({
    int limit = 100,
    int offset = 0,
    String search = '',
  }) async =>
      ApiResult({
        'status': 1,
        'data': [
          {'id': 1, 'name': 'City'},
        ],
      });

  @override
  Future<ApiResult> businessHours({List<dynamic> sellerIds = const []}) async =>
      ApiResult({'status': 1, 'data': []});

  @override
  Future<ApiResult> cart({
    required double latitude,
    required double longitude,
    int checkout = 0,
  }) async {
    if (!online) return _networkFail();
    if (up.isEmpty) {
      return ApiResult({'status': 0, 'message': 'no_items_found_in_users_cart'});
    }
    return ApiResult({
      'status': 1,
      'data': {
        'cart': _rows(),
        'sub_total': up.values.fold(0.0, (sum, q) => sum + 25.0 * q),
      },
    });
  }

  @override
  Future<ApiResult> addToCart({
    required dynamic productId,
    required dynamic variantId,
    required dynamic qty,
  }) async {
    if (!online) return _networkFail();
    up['$variantId'] = int.tryParse('$qty') ?? 1;
    return ApiResult({'status': 1, 'data': {'cart': _rows()}});
  }

  @override
  Future<ApiResult> removeFromCart({
    required dynamic productId,
    required dynamic variantId,
  }) async {
    if (!online) return _networkFail();
    if (!up.containsKey('$variantId')) {
      return ApiResult({'status': 0, 'message': 'no_product_found'});
    }
    up.remove('$variantId');
    return ApiResult({'status': 1, 'message': 'item_removed'});
  }
}

List<String> _qtys() => appController.cartProducts
    .map((e) => '${e['product_variant_id']}=${e['qty'] ?? e['quantity']}')
    .toList()
  ..sort();

Future<_FlakyServerApi> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _FlakyServerApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.businessHours = BusinessHoursResult();
  appController.token = 'tok';
  appController.user = {'id': 7, 'name': 'T'};
  appController.cartProducts = [];
  appController.cart = null;
  appController.cartSubTotal = 0;
  appController.guestCart = [];
  appController.guestCartTotal = 0;
  appController.selectedAddress = {
    'id': 3,
    'address': 'Street 1',
    'is_default': 1,
    'latitude': '15.0',
    'longitude': '45.0',
  };
  appController.addresses = [appController.selectedAddress!];
  return api;
}

Future<_FlakyServerApi> _onlineAdd(_FlakyServerApi api, int variantId, int qty) async {
  await appController.addToCart(
    productId: variantId,
    variantId: variantId,
    qty: qty,
    productPrice: 25,
    sellerId: 5,
  );
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'snapshot written with pending ops applied — deleted row never reappears on restart',
    () async {
      final api = await _setup();
      api.up['11'] = 2;
      api.up['22'] = 1;

      // Online seed.
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.refreshCart();
      expect(_qtys(), ['11=2', '22=1']);

      // Offline delete variant 11.
      api.online = false;
      appController.overrideConnectivityForTest(false);
      expect(
        await appController.removeCartLine(productId: 11, variantId: 11),
        isNull,
      );
      expect(_qtys(), ['22=1']);

      // Now flip online and do another refresh. The snapshot written to the
      // offline cache must reflect the post-delete state — NOT resurrect 11.
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.refreshCart();
      expect(_qtys(), ['22=1']);

      // Cold restart: re-inject memory, read from snapshot, ensure 11 is gone.
      final prefs3 = await SharedPreferences.getInstance();
      appController.injectForTest(prefs: prefs3, testApi: api);
      appController.cartProducts = [];
      appController.cart = null;
      appController.cartSubTotal = 0;
      api.online = false;
      appController.overrideConnectivityForTest(false);
      await appController.refreshCart();
      expect(_qtys(), ['22=1'],
          reason: 'snapshot must carry deletion intents applied before persist');
      expect(appController.cartSubTotal, 25);
    },
  );

  test(
    'snapshot persisted reflects pending delete intent when saved (no stale entries)',
    () async {
      final api = await _setup();
      api.up['11'] = 2;

      // Online seed + observe refresh.
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.refreshCart();

      // OFFLINE delete and refresh (simulating a manual pull-to-refresh).
      api.online = false;
      appController.overrideConnectivityForTest(false);
      await appController.removeCartLine(productId: 11, variantId: 11);

      // Refresh offline to verify the snapshot written during the delete does
      // NOT contain the deleted line.
      await appController.refreshCart();
      expect(_qtys(), isEmpty);

      // Capture the persisted snapshot directly — verify its products list
      // does not carry the deleted row.
      final snap = appController.offline.readDoc(
        OfflineCache.snapshotKey('cart::${appController.accountScope}'),
      );
      expect(snap, isNotNull);
      final payload = J.map(snap?.payload);
      final products = J.maps(payload['products']);
      expect(products.where((p) => '${p['product_variant_id']}' == '11'), isEmpty,
          reason: 'pending delete intent must be filtered from the persisted snapshot');
    },
  );

  test(
    'delete ONLINE then OFFLINE then ONLINE — deleted line must NEVER reappear',
    () async {
      final api = await _setup();
      await _onlineAdd(api, 11, 2);
      await _onlineAdd(api, 22, 1);
      expect(_qtys(), ['11=2', '22=1']);

      // Toggle offline.
      api.online = false;
      appController.overrideConnectivityForTest(false);

      // Delete online's variant 11 OFFLINE.
      expect(await appController.removeCartLine(productId: 11, variantId: 11), isNull);
      expect(_qtys(), ['22=1']);

      // Toggle online.
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.handleAppResumed();

      // The server now knows about 11; cartProducts must reflect that.
      expect(_qtys(), ['22=1']);
      expect(api.up, {'22': 1});
    },
  );

  test(
    'delete OFFLINE for a server line then toggle ONLINE — line stays gone',
    () async {
      final api = await _setup();
      api.online = false;
      appController.overrideConnectivityForTest(false);

      // Seed upstream directly.
      api.up['11'] = 2;
      api.up['22'] = 1;

      // Bring online briefly to fetch.
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.refreshCart();
      expect(_qtys(), ['11=2', '22=1']);

      // OFFLINE delete.
      api.online = false;
      appController.overrideConnectivityForTest(false);
      expect(await appController.removeCartLine(productId: 11, variantId: 11), isNull);
      expect(_qtys(), ['22=1']);

      // Back online.
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.handleAppResumed();
      expect(_qtys(), ['22=1']);
      expect(api.up['11'], isNull);
    },
  );

  test(
    'adding then toggling offline and online with a delete in between — line must not return',
    () async {
      final api = await _setup();
      // 1. ONLINE seed
      await _onlineAdd(api, 10, 3);
      expect(_qtys(), ['10=3']);

      // 2. OFFLINE delete
      api.online = false;
      appController.overrideConnectivityForTest(false);
      expect(await appController.removeCartLine(productId: 10, variantId: 10), isNull);
      expect(_qtys(), isEmpty);

      // 3. ONLINE
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.handleAppResumed();
      expect(_qtys(), isEmpty);
      expect(api.up, isEmpty);

      // 4. OFFLINE add
      api.online = false;
      appController.overrideConnectivityForTest(false);
      await appController.addToCart(
        productId: 10,
        variantId: 10,
        qty: 4,
        productPrice: 25,
        sellerId: 5,
      );
      expect(_qtys(), ['10=4']);

      // 5. ONLINE
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.handleAppResumed();
      expect(_qtys(), ['10=4']);
      expect(api.up['10'], 4);
    },
  );

  test(
    'rapid flurry of toggles with deletes and re-adds — final state consistent',
    () async {
      final api = await _setup();
      api.up['10'] = 2;
      api.up['11'] = 7;
      api.up['12'] = 1;

      // Boot online.
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.refreshCart();
      expect(_qtys(), ['10=2', '11=7', '12=1']);

      // OFFLINE delete 11
      api.online = false;
      appController.overrideConnectivityForTest(false);
      expect(await appController.removeCartLine(productId: 11, variantId: 11), isNull);

      // ONLINE — the outbox should replay the delete.
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.handleAppResumed();
      expect(api.up.containsKey('11'), isFalse);
      expect(_qtys(), containsAll(['10=2', '12=1']));
      expect(_qtys(), isNot(contains('11=7')));

      // OFFLINE delete 10
      api.online = false;
      appController.overrideConnectivityForTest(false);
      expect(await appController.removeCartLine(productId: 10, variantId: 10), isNull);

      // ONLINE
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.handleAppResumed();
      expect(api.up.containsKey('10'), isFalse);
      expect(_qtys(), ['12=1']);
    },
  );

  test(
    'delete ONLINE then OFFLINE delete same line is silently consistent',
    () async {
      final api = await _setup();
      await _onlineAdd(api, 11, 2);

      // Online delete
      expect(await appController.removeCartLine(productId: 11, variantId: 11), isNull);
      expect(_qtys(), isEmpty);

      // Offline — delete an already-gone line (server fresh value irrelevant,
      // only local consequence matters).
      api.online = false;
      appController.overrideConnectivityForTest(false);
      expect(
        await appController.removeCartLine(productId: 11, variantId: 11),
        isNull,
        reason: 'deleting a line already gone is a silent no-op',
      );
      expect(_qtys(), isEmpty);

      // Back ONLINE — CartScreen loads (trigger _load-like refresh) and no
      // phantom appears.
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.refreshCart();
      expect(_qtys(), isEmpty);
    },
  );

  test(
    'OFFLINE delete does not silently quietly drop rows from other scopes',
    () async {
      final api = await _setup();
      await _onlineAdd(api, 11, 2);
      // Switch to account B
      appController.token = 'tok-b';
      appController.user = {'id': 9, 'name': 'B'};
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.refreshCart();

      // Switch back to A and delete.
      appController.token = 'tok';
      appController.user = {'id': 7, 'name': 'T'};
      api.online = false;
      appController.overrideConnectivityForTest(false);

      // Offline delete on the line that belongs to A's session.
      expect(await appController.removeCartLine(productId: 11, variantId: 11), isNull);

      // Back online — A's view: the line is gone. (Had B owned it, B would
      // still see it.)
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.handleAppResumed();
      expect(_qtys(), isEmpty);
    },
  );

  test(
    'delete ONLINE during a pending offline add for the same variant — final state empty',
    () async {
      final api = await _setup();
      api.up['11'] = 1;

      // Wire online so we can pre-seed cart.
      api.online = true;
      appController.overrideConnectivityForTest(true);
      await appController.refreshCart();
      expect(_qtys(), ['11=1']);

      // OFFLINE: bump qty to 5
      api.online = false;
      appController.overrideConnectivityForTest(false);
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 5,
        productPrice: 25,
        sellerId: 5,
      );
      expect(appController.cartProducts.single['qty'], 5);

      // ONLINE: user deletes the line.
      api.online = true;
      appController.overrideConnectivityForTest(true);
      expect(await appController.removeCartLine(productId: 11, variantId: 11), isNull);

      // Identical variant deleted online; outbox pending add for that variant
      // must not resurrect after refresh.
      await appController.refreshCart();
      expect(_qtys(), isEmpty);
      expect(api.up, isEmpty);
    },
  );
}
