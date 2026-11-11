import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/features/cart/cart_screens.dart';

/// Checkout connectivity behavior — the exact failure mode the customer hit:
/// cart looks fine online, but behind the scenes a coalesced/failed refresh
/// made the screen render an empty, never-converging form. These tests pin
/// down that the checkout:
///   1. paints fresh items the moment it is online,
///   2. surfaces a retry DIALOG (never a fake "normal" empty screen) when it
///      starts offline with no cache, and never renders stale items,
///   3. falls back to a retryable screen when the dialog is dismissed, and
///      auto-converges to fresh data once the link comes back — no app restart,
///   4. paints the last server-confirmed cart as stale content when offline
///      (never an unrecoverable blank form) when a cached cart exists,
///   5. renders the cart normally when only the addresses call fails.
///
/// The fake API's connectivity is toggled by swapping ApiResult fields, the
/// same way the offline integration suite does its scenarios.
ApiResult _networkFail() => ApiResult({
  'status': 0,
  'message': 'timeout',
  'error': {'code': 'TIMEOUT', 'httpStatus': 504},
});

ApiResult _ok([dynamic data]) =>
    ApiResult({'status': 1, 'data': data ?? const {}});

Map<String, dynamic> _row() => {
      'product_id': 1,
      'product_variant_id': 11,
      'qty': 2,
      'price': 100,
      'name': 'منتج تجريبي',
      'seller_id': 5,
      'stock': 5,
      'measurement': 'كجم',
      'stock_unit_name': 'كجم',
    };

ApiResult _cartOk() => _ok({
      'cart': [_row()],
      'sub_total': 200,
      'final_total': 200,
      'delivery_charge': {'total_delivery_charge': 15},
      'seller_groups': [
        {'seller_id': 5, 'store_name': 'متجر', 'items': [_row()]},
      ],
    });

class _CheckoutApi extends CustomerApi {
  _CheckoutApi() : super(baseUrl: 'http://test.invalid');

  ApiResult citiesResult = _ok([
    {'id': 1, 'name': 'Test City'},
  ]);
  ApiResult cartResult = _cartOk();
  int cartCalls = 0;
  int addressesCalls = 0;
  ApiResult addressesResult = _ok([
    {
      'id': 3,
      'address': 'Street A',
      'is_default': 1,
      'latitude': '15.0',
      'longitude': '45.0',
    },
  ]);

  @override
  Future<ApiResult> cities({
    int limit = 100,
    int offset = 0,
    String search = '',
  }) async =>
      citiesResult;

  @override
  Future<ApiResult> businessHours({List<dynamic> sellerIds = const []}) async =>
      _ok([]);

  @override
  Future<ApiResult> cart({
    required double latitude,
    required double longitude,
    int checkout = 0,
  }) async {
    cartCalls += 1;
    return cartResult;
  }

  @override
  Future<ApiResult> addresses() async {
    addressesCalls += 1;
    return addressesResult;
  }
}

Future<_CheckoutApi> _setup({Map<String, dynamic>? seededCart}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _CheckoutApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.businessHours = BusinessHoursResult();
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
  appController.cartProducts = seededCart == null ? [] : [_row()];
  appController.cartSubTotal = (seededCart?['sub_total'] as num?)?.toDouble() ?? 0;
  appController.cart = seededCart;
  appController.addresses = [];
  appController.selectedAddress = null;
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'online: checkout renders the fresh cart items, no retry dialog',
    (tester) async {
      await _setup();
      await tester.pumpWidget(const MaterialApp(home: CheckoutScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('منتج تجريبي'), findsOneWidget);
      expect(find.text('x2'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      expect(find.text('checkout_stale_totals'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline cold start, no cache: shows the retry dialog and never fakes data',
    (tester) async {
      final api = await _setup();
      api.citiesResult = _networkFail();
      api.cartResult = _networkFail();
      api.addressesResult = _networkFail();

      await tester.pumpWidget(const MaterialApp(home: CheckoutScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // The dialog IS the interface for connectivity failures; the cart must
      // not render phantom lines or a "normal empty" checkout.
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text('منتج تجريبي'), findsNothing);
      expect(find.text('internet_required_title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dismissed dialog falls back to retry screen; retry while offline re-offers the dialog; reconnect auto-heals',
    (tester) async {
      final api = await _setup();
      api.citiesResult = _networkFail();
      api.cartResult = _networkFail();
      api.addressesResult = _networkFail();

      await tester.pumpWidget(const MaterialApp(home: CheckoutScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

      // Dismiss the dialog (cancel): the plain retry screen appears.
      await tester.tap(find.text('cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(find.text('retry'), findsOneWidget);
      expect(find.text('منتج تجريبي'), findsNothing);

      // Tapping retry while still offline re-opens the connectivity dialog.
      await tester.tap(find.text('retry'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

      // Connectivity returns: dialog poll closes itself and the checkout
      // refreshes — no app restart, no manual navigation.
      api.citiesResult = _ok([
        {'id': 1, 'name': 'Test City'},
      ]);
      api.cartResult = _cartOk();
      api.addressesResult = _ok([
        {
          'id': 3,
          'address': 'Street A',
          'is_default': 1,
          'latitude': '15.0',
          'longitude': '45.0',
        },
      ]);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      expect(find.text('منتج تجريبي'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline with a server-confirmed cart: stale content renders, no dialog, stale totals badge',
    (tester) async {
      final api = await _setup(
        seededCart: {'cart': [_row()], 'sub_total': 200, 'final_total': 200},
      );
      api.citiesResult = _networkFail();
      api.cartResult = _networkFail();
      api.addressesResult = _networkFail();

      await tester.pumpWidget(const MaterialApp(home: CheckoutScreen()));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      expect(find.text('منتج تجريبي'), findsOneWidget);

      // The stale banner lives below the fold; ListView builds it on scroll.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('checkout-place-order')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(find.text('checkout_stale_totals'), findsOneWidget);
      // A stale checkout must NOT be placeable: buttons stay disabled until
      // the server re-validates prices/stock on an online refresh.
      final place = tester.widget<FilledButton>(
        find.byKey(const ValueKey('checkout-place-order')),
      );
      expect(place.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'partial failure: cart fine but addresses down — checkout still paints items, no dialog',
    (tester) async {
      final api = await _setup();
      api.addressesResult = _networkFail();

      await tester.pumpWidget(const MaterialApp(home: CheckoutScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('منتج تجريبي'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
