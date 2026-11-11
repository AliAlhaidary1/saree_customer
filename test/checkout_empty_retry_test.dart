import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/features/cart/cart_screens.dart';

ApiResult _networkFail() => ApiResult({
  'status': 0,
  'message': 'timeout',
  'error': {'code': 'TIMEOUT', 'httpStatus': 504},
});

ApiResult _ok([dynamic data]) =>
    ApiResult({'status': 1, 'data': data ?? const {}});

class _ReproApi extends CustomerApi {
  _ReproApi() : super(baseUrl: 'http://test.invalid', token: null);

  ApiResult cartResult = _networkFail();

  @override
  Future<ApiResult> cities({
    int limit = 100,
    int offset = 0,
    String search = '',
  }) async =>
      _ok([
        {'id': 1, 'name': 'Test City'},
      ]);

  @override
  Future<ApiResult> cart({
    required double latitude,
    required double longitude,
    int checkout = 0,
  }) async =>
      cartResult;

  @override
  Future<ApiResult> addresses() async =>
      _ok([
        {
          'id': 3,
          'address': 'Street 1',
          'is_default': 1,
          'latitude': '15.0',
          'longitude': '45.0',
        },
      ]);
}

Future<_ReproApi> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _ReproApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.token = 'tok';
  appController.user = {'id': 7, 'name': 'Tester'};
  appController.businessHours = BusinessHoursResult();
  appController.cart = {
    'cart': [
      {
        'product_id': 1,
        'product_variant_id': 11,
        'qty': 1,
        'price': 100,
        'name': 'P',
      },
    ],
    'sub_total': 100,
    'final_total': 120,
  };
  appController.cartProducts = J.maps(appController.cart!['cart']);
  appController.cartSubTotal = 100;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'reachable EMPTY server cart no longer wedges on a stale banner forever',
    (tester) async {
      final api = await _setup();
      await tester.pumpWidget(const MaterialApp(home: CheckoutScreen()));
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, -2000),
        2000,
      );
      await tester.pumpAndSettle();
      expect(find.text('checkout_stale_totals'), findsOneWidget);

      // Server reachable, but the cart on the server is legitimately empty.
      api.cartResult = ApiResult({
        'status': 0,
        'message': 'no_items_found_in_users_cart',
      });

      await tester.tap(find.text('retry'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('checkout_stale_totals'), findsNothing);
    },
  );

  testWidgets(
    'reachable business failure still shows the reason to the user',
    (tester) async {
      final api = await _setup();
      await tester.pumpWidget(const MaterialApp(home: CheckoutScreen()));
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, -2000),
        2000,
      );
      await tester.pumpAndSettle();
      expect(find.text('checkout_stale_totals'), findsOneWidget);

      // Server reachable, business refusal with a reason.
      api.cartResult = ApiResult({
        'status': 0,
        'message': 'cannot compute delivery for this address',
      });

      await tester.tap(find.text('retry'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('checkout_stale_totals'), findsOneWidget);
      expect(
        find.text('cannot compute delivery for this address'),
        findsOneWidget,
      );
    },
  );
}
