import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/features/cart/cart_screens.dart';

/// Mimics the exact device scenario: app goes offline BEFORE any business
/// hours have been fetched (cold start offline), the user adds a product
/// offline, then opens checkout and cannot place the order because
/// `businessHours` is null and `canPlaceOrder()` returns allowed:false.
///
/// Then connectivity returns — the checkout must re-validate automatically
/// and re-enable the place-order CTA without any user action (no pull-to-
/// refresh, no retry tap, no re-entering the screen).
Map<String, dynamic> _row() => {
      'product_id': 1,
      'product_variant_id': 11,
      'qty': 2,
      'price': 100,
      'name': 'منتج تجريبي',
      'seller_id': 5,
      'stock': 5,
    };

ApiResult _networkFail() => ApiResult({
      'status': 0,
      'message': 'timeout',
      'error': {'code': 'TIMEOUT', 'httpStatus': 504},
    });

ApiResult _ok([dynamic data]) => ApiResult({'status': 1, 'data': data ?? const {}});

class _ColdOfflineApi extends CustomerApi {
  _ColdOfflineApi() : super(baseUrl: 'http://test.invalid');

  bool serverOnline = false;
  int businessHoursCalls = 0;
  int cartCalls = 0;

  @override
  Future<ApiResult> cities({
    int limit = 100,
    int offset = 0,
    String search = '',
  }) async => ApiResult({
        'status': 1,
        'data': [
          {'id': 1, 'name': 'City'},
        ],
      });

  @override
  Future<ApiResult> businessHours({List<dynamic> sellerIds = const []}) async {
    businessHoursCalls += 1;
    if (!serverOnline) return _networkFail();
    return _ok({
      'platform': {'is_open': true},
      'sellers': {'5': {'is_open': true, 'seller_id': 5}},
    });
  }

  @override
  Future<ApiResult> timeSlots({List<dynamic> sellerIds = const []}) async =>
      _ok([]);

  @override
  Future<ApiResult> checkoutConfig() async =>
      _ok({'max_sellers_per_checkout': 0, 'min_order_amount': 0});

  @override
  Future<ApiResult> cart({
    required double latitude,
    required double longitude,
    int checkout = 0,
  }) async {
    cartCalls += 1;
    if (!serverOnline) return _networkFail();
    return _ok({
      'cart': [_row()],
      'sub_total': 200,
      'final_total': 200,
      'delivery_charge': {'total_delivery_charge': 15},
      'seller_groups': [
        {'seller_id': 5, 'store_name': 'متجر', 'items': [_row()]},
      ],
    });
  }

  @override
  Future<ApiResult> addToCart({
    required dynamic productId,
    required dynamic variantId,
    required dynamic qty,
  }) async =>
      serverOnline
          ? _ok({'cart': [_row()], 'sub_total': 200})
          : _networkFail();

  @override
  Future<ApiResult> addresses() async =>
      serverOnline
          ? _ok([
              {
                'id': 3,
                'address': 'Street A',
                'is_default': 1,
                'latitude': '15.0',
                'longitude': '45.0',
              },
            ])
          : _networkFail();
}

Future<_ColdOfflineApi> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _ColdOfflineApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  addTearDown(() {
    appController.overrideConnectivityForTest(true);
  });
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  // Critical for this regression: the device has NO cached business hours
  // because the network failed before we could fetch them. In that state the
  // place-order CTA MUST be allowed=true anyway (mirroring the production
  // rule that orders are still validated against the server at checkout).
  appController.businessHours = null;
  appController.timeSlots = [];
  appController.token = 'tok';
  appController.user = {'id': 7, 'name': 'T', 'balance': 0};
  appController.settings = {
    'currency': 'ر.س',
    'decimal_point': 2,
    'min_order_amount': 0,
    'max_sellers_per_checkout': 0,
    'web_settings': <String, dynamic>{},
  };
  appController.paymentSettings = {'cod_payment_method': '1'};
  appController.cartProducts = [];
  appController.cart = null;
  appController.cartSubTotal = 0;
  appController.guestCart = [];
  appController.guestCartTotal = 0;
  appController.addresses = [];
  appController.selectedAddress = {
    'id': 3,
    'address': 'Street A',
    'is_default': 1,
    'latitude': '15.0',
    'longitude': '45.0',
  };
  appController.addresses = [appController.selectedAddress!];

  // Add product offline.
  await appController.addToCart(
    productId: 1,
    variantId: 11,
    qty: 2,
    productPrice: 100,
    sellerId: 5,
  );

  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'offline-cold-start checkout: CTA is disabled while stale, re-enables after reconnect with NO taps',
    (tester) async {
      final api = await _setup();
      appController.overrideConnectivityForTest(false);

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CheckoutScreen())));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      // Scroll to build + reveal the CTA (ListView virtualizes lazily).
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('checkout-place-order')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      final FilledButton offlineBtn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('checkout-place-order')),
      );
      expect(offlineBtn.onPressed, isNull,
          reason: 'no connectivity → cannot place');

      // Flip the network ON.
      api.serverOnline = true;
      appController.overrideConnectivityForTest(true);

      // App-level heal runs (reconcilePendingCartOps scheduled with a delay).
      // Checkout screen's _connListener fires _load which re-fetches business
      // hours + cart. Pump enough so the microtasks + http sequence settle.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      final FilledButton onlineBtn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('checkout-place-order')),
      );
      expect(onlineBtn.onPressed, isNotNull,
          reason: 'after connectivity returns the CTA re-enables automatically');
      expect(api.businessHoursCalls, greaterThanOrEqualTo(1),
          reason: 'business hours were fetched after reconnect');
    },
  );
}
