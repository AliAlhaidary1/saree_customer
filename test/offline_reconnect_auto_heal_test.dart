import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/features/cart/cart_screens.dart';

/// Reproduces the exact scenario reported against the online/offline
/// transition: the app is used while the link drops and comes back, and the
/// cart / checkout stale content never healed until the user tapped retry
/// (or re-entered the screen). These tests pin the ROOT FIX: flipping the
/// link back re-validates everything automatically — no taps, no reload.
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

ApiResult _networkFail() => ApiResult({
      'status': 0,
      'message': 'timeout',
      'error': {'code': 'TIMEOUT', 'httpStatus': 504},
    });

ApiResult _ok([dynamic data]) =>
    ApiResult({'status': 1, 'data': data ?? const {}});

class _ReconnectApi extends CustomerApi {
  _ReconnectApi() : super(baseUrl: 'http://test.invalid');

  bool serverOnline = true;
  int cartCalls = 0;
  int addCalls = 0;

  @override
  Future<ApiResult> cities({
    int limit = 100,
    int offset = 0,
    String search = '',
  }) async =>
      serverOnline
          ? _ok([
              {'id': 1, 'name': 'Test City'},
            ])
          : _networkFail();

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
  Future<ApiResult> addresses() async => serverOnline
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

  @override
  Future<ApiResult> addToCart({
    required dynamic productId,
    required dynamic variantId,
    required dynamic qty,
  }) async {
    addCalls += 1;
    if (!serverOnline) return _networkFail();
    return _ok({'cart': [_row()], 'sub_total': 200});
  }
}

Future<_ReconnectApi> _setup({Map<String, dynamic>? seededCart}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _ReconnectApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  addTearDown(() async {
    appController.overrideConnectivityForTest(true);
  });
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
  appController.cartSubTotal =
      (seededCart?['sub_total'] as num?)?.toDouble() ?? 0;
  appController.cart = seededCart;
  appController.addresses = [];
  appController.selectedAddress = null;
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'checkout opened offline shows stale content and disabled CTA; flipping the link back online heals it with NO taps',
    (tester) async {
      final api = await _setup(
        seededCart: {'cart': [_row()], 'sub_total': 200, 'final_total': 200},
      );
      api.serverOnline = false;
      appController.overrideConnectivityForTest(false);

      await tester.pumpWidget(const MaterialApp(home: CheckoutScreen()));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      await tester.pumpWidget(const MaterialApp(home: CheckoutScreen()));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      // ── Offline state at the top of the list: items paint. ──
      expect(find.text('منتج تجريبي'), findsOneWidget);

      // ListView builds children below the fold lazily; scroll down to
      // reveal the stale badge + the place-order CTA.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('checkout-place-order')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('checkout_stale_totals'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(
          find.byKey(const ValueKey('checkout-place-order')),
        ).onPressed,
        isNull,
      );

      // ── Flip the link back ON: no taps, no re-entering the screen. ──
      api.serverOnline = true;
      appController.overrideConnectivityForTest(true);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      // The badge dies with the rebuild and the CTA re-enables.
      expect(find.text('checkout_stale_totals'), findsNothing);
      expect(
        tester.widget<FilledButton>(
          find.byKey(const ValueKey('checkout-place-order')),
        ).onPressed,
        isNotNull,
        reason: 'place-order re-enables automatically once prices are re-validated online',
      );
      // Confirm the list still paints the re-validated items (scroll back up).
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('منتج تجريبي'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cart screen refetches itself when the link comes back (no pull-to-refresh)',
    (tester) async {
      final api = await _setup(
        seededCart: {'cart': [_row()], 'sub_total': 100},
      );
      api.serverOnline = false;
      appController.overrideConnectivityForTest(false);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CartScreen())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final callsWhileOffline = api.cartCalls;

      // Flip back online WITHOUT any user action on the screen.
      api.serverOnline = true;
      appController.overrideConnectivityForTest(true);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      expect(api.cartCalls, greaterThan(callsWhileOffline),
          reason: 'the heal replayed refreshCart against the real server');
      expect(find.text('منتج تجريبي'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline add-to-cart replays to the server the moment the link returns',
    (tester) async {
      final api = await _setup();
      api.serverOnline = false;
      appController.overrideConnectivityForTest(false);

      // Logged-in user adds a product while OFFLINE.
      final err = await appController.addToCart(
        productId: 1,
        variantId: 11,
        qty: 2,
        productPrice: 100,
        sellerId: 5,
      );
      expect(err, isNull, reason: 'offline add is kept locally');
      expect(appController.cartProducts.length, 1,
          reason: 'optimistic local line visible instantly');
      expect(api.addCalls, greaterThanOrEqualTo(1),
          reason: 'the network attempt was made');

      // Link returns.
      api.serverOnline = true;
      appController.overrideConnectivityForTest(true);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      // The outbox replayed (setQty 2) and the cart refreshed from server.
      expect(api.cartCalls, greaterThanOrEqualTo(1));
      expect(appController.cartProducts.single['qty'], 2,
          reason: 'server cart state wins after reconciliation');
      expect(appController.cartSubTotal, moreOrLessEquals(200));
    },
  );
}
