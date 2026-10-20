import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/offline/operation_policy.dart';
import 'package:sareemart_customer/features/cart/cart_screens.dart';

ApiResult _networkFail() => ApiResult({
      'status': 0,
      'message': 'timeout',
      'error': {'code': 'TIMEOUT', 'httpStatus': 504},
    });

ApiResult _serverFail() => ApiResult({
      'status': 0,
      'message': 'boom',
      'error': {'code': 'HTTP_500', 'httpStatus': 500},
    });

ApiResult _ok([dynamic data]) => ApiResult({
      'status': 1,
      'data': data ?? const {},
    });

class _ScenarioApi extends CustomerApi {
  _ScenarioApi() : super(baseUrl: 'http://test.invalid', token: null);

  ApiResult citiesResult = _ok([
    {'id': 1, 'name': 'Test City'}
  ]);
  ApiResult loginResult = _ok({
    'token': 'tok123',
    'user': {'id': 7, 'name': 'Tester', 'mobile': '777000000'}
  });
  ApiResult cartResult = _ok({
    'cart': [],
    'sub_total': 0,
  });
  ApiResult removeResult = _ok({});

  @override
  Future<ApiResult> cities(
      {int limit = 100, int offset = 0, String search = ''}) async {
    return citiesResult;
  }

  @override
  Future<ApiResult> loginMobile(
      {required String mobile,
      required String password,
      String fcm = '',
      String countryCode = '967'}) async {
    return loginResult;
  }

  @override
  Future<ApiResult> cart(
      {required double latitude,
      required double longitude,
      int checkout = 0}) async {
    return cartResult;
  }

  @override
  Future<ApiResult> removeFromCart({
    required dynamic productId,
    required dynamic variantId,
  }) async {
    return removeResult;
  }

  @override
  Future<ApiResult> guestCart(
      {required double latitude,
      required double longitude,
      required String variantIds,
      required String quantities}) async {
    return _networkFail();
  }
}

Future<_ScenarioApi> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _ScenarioApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.token = null;
  appController.user = null;
  appController.guestCart = [];
  appController.guestCartTotal = 0;
  appController.cartProducts = [];
  appController.cart = null;
  appController.promoCode = null;
  appController.addresses = [];
  appController.selectedAddress = null;
  appController.sellerGroups = [];
  appController.businessHours = null;
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('offline transition scenarios', () {
    test('guest add is accepted offline and cart is updated', () async {
      final api = await _setup();
      api.citiesResult = _networkFail();
      final err = await appController.addToCart(
        productId: 1,
        variantId: 11,
        qty: 1,
        productPrice: 100,
        sellerId: 5,
      );
      expect(err, isNull);
      expect(appController.guestCart, isNotEmpty);
    });

    test('guest add works online', () async {
      await _setup();
      final err = await appController.addToCart(
        productId: 1,
        variantId: 11,
        qty: 2,
        productPrice: 100,
        sellerId: 5,
      );
      expect(err, isNull);
      expect(appController.guestCart.length, 1);
      expect(appController.guestCart.first['qty'], 2);
    });

    test('guest remove is accepted offline and line is removed', () async {
      final api = await _setup();
      await appController.addToCart(
        productId: 1,
        variantId: 11,
        qty: 1,
        productPrice: 100,
        sellerId: 5,
      );
      api.citiesResult = _networkFail();
      final err = await appController.removeCartLine(productId: 1, variantId: 11);
      expect(err, isNull);
      expect(appController.guestCart, isEmpty);
    });

    test('login offline returns sentinel and session stays empty', () async {
      final api = await _setup();
      api.loginResult = _networkFail();
      final err =
          await appController.login(mobile: '777000000', password: 'secret123');
      expect(err, kRequiresInternet);
      expect(appController.token, isNull);
      expect(appController.user, isNull);
    });

    test('login validation error passes message through (no false block)',
        () async {
      final api = await _setup();
      api.loginResult = ApiResult({'status': 0, 'message': 'wrong password'});
      final err = await appController.login(mobile: '777000000', password: 'no');
      expect(err, 'wrong password');
    });

    test('hasInternetAccess: ok->true, server-fail->true, network->false',
        () async {
      final api = await _setup();
      expect(await appController.hasInternetAccess(), isTrue);
      api.citiesResult = _serverFail();
      expect(await appController.hasInternetAccess(), isTrue);
      api.citiesResult = _networkFail();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      appController.injectForTest(prefs: prefs, testApi: api);
      appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
      expect(await appController.hasInternetAccess(), isFalse);
    });
  });

  group('stale checkout gate (widget)', () {
    testWidgets('stale totals show warning and disable placing',
        (tester) async {
      final api = await _setup();
      api.cartResult = _networkFail();
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
          }
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
      };
      appController.addresses = [appController.selectedAddress!];
      await tester.pumpWidget(const MaterialApp(home: CheckoutScreen()));
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, -2000),
        2000,
      );
      await tester.pumpAndSettle();
      expect(find.text('checkout_stale_totals'), findsOneWidget);
      final placeOrder = tester.widget<FilledButton>(
        find.byKey(const ValueKey('checkout-place-order')),
      );
      expect(placeOrder.onPressed, isNull);
    });
  });

  group('convergent cart removal', () {
    test('logged-in remove converges when server says already gone (Arabic)',
        () async {
      final api = await _setup();
      appController.token = 'tok';
      appController.user = {'id': 7, 'name': 'Tester'};
      final line = {
        'product_id': 1,
        'product_variant_id': 11,
        'qty': 1,
        'price': 100,
        'name': 'P',
      };
      appController.cartProducts = [Map<String, dynamic>.from(line)];
      // Server claims the line does not exist, yet echoes it back on
      // refresh (stale id): the line must still disappear, with no error.
      api.removeResult = ApiResult(
          {'status': 0, 'message': 'المنتج غير موجود في السلة'});
      api.cartResult = _ok({
        'cart': [line],
        'sub_total': 100,
      });
      final err =
          await appController.removeCartLine(productId: 1, variantId: 11);
      expect(err, isNull);
      expect(appController.cartProducts, isEmpty);
    });

    test('logged-in remove converges on empty-cart phrasing', () async {
      final api = await _setup();
      appController.token = 'tok';
      appController.user = {'id': 7, 'name': 'Tester'};
      final line = {
        'product_id': 1,
        'product_variant_id': 11,
        'qty': 1,
        'price': 100,
        'name': 'P',
      };
      appController.cartProducts = [Map<String, dynamic>.from(line)];
      api.removeResult = ApiResult(
          {'status': 0, 'message': 'لم يتم العثور على عناصر في عربة المستخدم'});
      api.cartResult = _ok({
        'cart': [line],
        'sub_total': 100,
      });
      final err =
          await appController.removeCartLine(productId: 1, variantId: 11);
      expect(err, isNull);
      expect(appController.cartProducts, isEmpty);
    });

    test('logged-in remove still reports genuine server refusals', () async {
      final api = await _setup();
      appController.token = 'tok';
      appController.user = {'id': 7, 'name': 'Tester'};
      appController.cartProducts = [
        {
          'product_id': 1,
          'product_variant_id': 11,
          'qty': 1,
          'price': 100,
          'name': 'P',
        }
      ];
      api.removeResult =
          ApiResult({'status': 0, 'message': 'cannot_remove_stock_reserved'});
      api.cartResult = _ok({'cart': [], 'sub_total': 0});
      final err =
          await appController.removeCartLine(productId: 1, variantId: 11);
      expect(err, 'cannot_remove_stock_reserved');
    });
  });

  group('checkout offline dialog (widget)', () {
    testWidgets('empty checkout load failure offers the retry dialog',
        (tester) async {
      final api = await _setup();
      api.cartResult = _networkFail();
      appController.token = 'tok';
      appController.user = {'id': 7, 'name': 'Tester'};
      await tester.pumpWidget(const MaterialApp(home: CheckoutScreen()));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      // Dismissing falls back to the plain retry screen (no bare text only).
      await tester.tap(find.text('cancel'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      expect(find.text('retry'), findsOneWidget);
    });
  });

  group('offline cart UX (widget)', () {
    testWidgets('offline + tap keeps cart without dialog',
        (tester) async {
      final api = await _setup();
      api.citiesResult = _networkFail();
      appController.guestCart = [
        {
          'product_id': 1,
          'product_variant_id': 11,
          'qty': 1,
          'price': 100,
          'name': 'P',
          'image_url': '',
          'seller_id': 5,
        }
      ];
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CartScreen())),
      );
      await tester.pumpAndSettle();
      expect(find.text('P'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      expect(appController.guestCart.length, 1);
    });
  });
}
