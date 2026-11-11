import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';

/// Reproduces the exact scenario the user reports:
///   bootstrap (cold start) starts a cart refresh → user opens checkout
///   before that call lands → the checkout's refreshCart call hits an
///   in-flight one and used to receive a fake `{status:1, coalesced:1}` —
///   an "ok" result with no items, zero totals and an empty form that
///   fooled nobody: it looked like a broken connectivity/cart state and
///   the checkout screen was unrecoverable until a manual retry.
///
/// These two references coalesce the same way: a refreshCart started while
/// another is in flight must wait for it, not fabricate a result.
class _RefreshCoalesceApi extends CustomerApi {
  _RefreshCoalesceApi() : super(baseUrl: 'http://test.invalid');

  int cartCalls = 0;
  bool online = true;
  Duration delay = Duration.zero;

  Map<String, Map<String, dynamic>> server = {
    // variantId → qty
    '11': {
      'product_id': 1,
      'product_variant_id': 11,
      'qty': 5,
      'price': 10,
      'name': 'Coalesce Line',
      'seller_id': 5,
    },
  };

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
    cartCalls += 1;
    if (!online) {
      return ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });
    }
    if (delay != Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (server.isEmpty) {
      return ApiResult({
        'status': 0,
        'message': 'no_items_found_in_users_cart',
      });
    }
    final rows = server.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return ApiResult({
      'status': 1,
      'data': {'cart': rows, 'sub_total': 10.0 * rows.length},
    });
  }
}

Future<_RefreshCoalesceApi> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _RefreshCoalesceApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.businessHours = BusinessHoursResult();
  appController.token = 'tok';
  appController.user = {'id': 7, 'name': 'T'};
  appController.cartProducts = [];
  appController.cartSubTotal = 0;
  appController.cart = null;
  appController.addresses = [];
  appController.guestCart = [];
  appController.guestCartTotal = 0;
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'two overlapping refreshCarts share the same server response (no synthetic result)',
    () async {
      final api = await _setup();

      // Kick off an artificial slow refresh (bootstrap path), then immediately
      // a second one (checkout path).
      api.delay = const Duration(milliseconds: 120);
      final first = appController.refreshCart();
      final second = appController.refreshCart();

      final a = await first;
      final b = await second;

      // Exactly ONE real request reached the fake server.
      expect(api.cartCalls, 1);
      // Both got a real, data-rich result.
      expect(a.ok, isTrue);
      expect(b.ok, isTrue);
      // Both carry the actual cart contents — never a fabricated empty 200.
      expect(a.dataMap['cart'], isNotNull);
      expect(b.dataMap['cart'], isNotNull);
      expect(
        (a.dataMap['cart'] as List).length,
        1,
      );

      // Controller state matches: cartProducts is populated from one refresh.
      expect(appController.cartProducts.length, 1);
      expect(appController.cartProducts.single['product_variant_id'], 11);

      api.delay = Duration.zero;
    },
  );

  test(
    'coalesced checkout-mode refresh never returns a fake 200-with-empty',
    () async {
      final api = await _setup();

      // Simulate that bootstrap's checkout refresh (mode 1) is already in flight
      api.delay = const Duration(milliseconds: 150);
      final bootstrapCartRefresh = appController.refreshCart();
      final userCartRefresh = appController.refreshCart(checkout: 1);

      final b = await bootstrapCartRefresh;
      final u = await userCartRefresh;

      expect(api.cartCalls, 1);
      expect(b.ok, isTrue);
      expect(u.ok, isTrue);
      expect(u.dataMap, isNotEmpty);
      expect(u.raw['coalesced'], isNull,
          reason: 'coalesced is never leaked as a fake data shape');

      api.delay = Duration.zero;
    },
  );

  test(
    'coalesced refresh converges to the server state after it finishes',
    () async {
      final api = await _setup();
      api.delay = const Duration(milliseconds: 80);

      final userRefreshing = appController.refreshCart(checkout: 1);
      final anotherUserRefreshing = appController.refreshCart();
      await userRefreshing;
      await anotherUserRefreshing;

      expect(api.cartCalls, 1);
      expect(appController.cartProducts.length, 1);
      expect(appController.cartSubTotal, 10);

      // The next refresh is a genuine new call.
      api.delay = Duration.zero;
      await appController.refreshCart();
      expect(api.cartCalls, 2);

      api.delay = Duration.zero;
    },
  );

  test(
    'functional detect connectivity failure still allows checkout retry to converge',
    () async {
      final api = await _setup();
      // Default online; bootstrap refresh triggered; then turn offline —
      // next refresh must return a non-ok result with the stale snapshot.
      api.delay = const Duration(milliseconds: 10);
      await appController.refreshCart();

      // Come offline.
      api.online = false;
      final offlineResult = await appController.refreshCart();
      expect(offlineResult.ok, isFalse);

      // Back online: retry must pick up the server state.
      api.online = true;
      final backOnline = await appController.refreshCart();
      expect(backOnline.ok, isTrue);
      expect(appController.cartProducts.length, 1);
      expect(appController.cartSubTotal, 10);

      api.delay = Duration.zero;
    },
  );
}
