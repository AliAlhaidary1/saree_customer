import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/features/cart/cart_screens.dart';

/// Reproduces the exact device symptom reported by the user AFTER all the
/// earlier fixes:
///   1. Offline: user taps "أضف إلى السلة" — line appears locally, outbox
///      queues a cartSetQty:1 intent.
///   2. User flips the WiFi back ON.
///   3. User opens checkout — the screen shows the {stale row, totals as the
///      server sees them} — i.e. "الإجماليات قد تكون قديمة" — because the
///      outbox has not replayed yet. The place-order CTA is therefore
///      effectively disabled until the screen re-loads or the connectivity
///      heal completes.
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

ApiResult _ok([dynamic data]) =>
    ApiResult({'status': 1, 'data': data ?? const {}});

class _OnlineAfterSeedApi extends CustomerApi {
  _OnlineAfterSeedApi() : super(baseUrl: 'http://test.invalid');

  bool serverOnline = false;
  int cartCalls = 0;
  int bulkAddCalls = 0;
  int businessHoursCalls = 0;

  @override
  Future<ApiResult> cities({
    int limit = 100,
    int offset = 0,
    String search = '',
  }) async =>
      _ok([
        {'id': 1, 'name': 'City'},
      ]);

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
  }) async {
    if (!serverOnline) return _networkFail();
    return _ok({'cart': [_row()], 'sub_total': 200});
  }

  @override
  Future<ApiResult> bulkAddToCart({
    required String variantIds,
    required String quantities,
  }) async {
    bulkAddCalls += 1;
    if (!serverOnline) return _networkFail();
    return _ok({'cart': [_row()], 'sub_total': 200});
  }

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

Future<_OnlineAfterSeedApi> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _OnlineAfterSeedApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  addTearDown(() {
    appController.overrideConnectivityForTest(true);
  });
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
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
  appController.addresses = [
    {
      'id': 3,
      'address': 'Street A',
      'is_default': 1,
      'latitude': '15.0',
      'longitude': '45.0',
    },
  ];
  appController.selectedAddress = appController.addresses.first;

  // 1. OFFLINE add (simulates the user tapping "أضف إلى السلة" while offline).
  await appController.addToCart(
    productId: 1,
    variantId: 11,
    qty: 2,
    productPrice: 100,
    sellerId: 5,
  );

  // 2. Connect back online — but the test will only flip connectivity when
  //    the widget is already mounted as checkout, to mimic the user's exact
  //    sequence of "offline add → network on → open checkout".
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'add-while-offline, then open checkout online: CTA re-enables without taps',
    (tester) async {
      final api = await _setup();
      appController.overrideConnectivityForTest(false);

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CheckoutScreen())));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      // Scroll down to build the CTA (ListView virtualizes lazily).
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('checkout-place-order')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      // Offline → CTA disabled (cannot place order without network).
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('checkout-place-order')),
            )
            .onPressed,
        isNull,
      );

      // Flip the link.
      api.serverOnline = true;
      appController.overrideConnectivityForTest(true);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      final btn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('checkout-place-order')),
      );
      expect(btn.onPressed, isNotNull,
          reason: 'CTA re-enables once connectivity returns');
    },
  );
}
