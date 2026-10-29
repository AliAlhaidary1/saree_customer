import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/app.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/app_navigation.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/features/account/account_screens.dart';
import 'package:sareemart_customer/features/cart/cart_screens.dart';

class _FailingApi extends CustomerApi {
  _FailingApi() : super(baseUrl: 'http://test.invalid');

  @override
  Future<ApiResult> products({
    required double latitude,
    required double longitude,
    Map<String, dynamic> filters = const {},
    String tagNames = '',
    String slug = '',
  }) async => ApiResult({'status': 0, 'message': 'offline'});
}

Future<void> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  appController.injectForTest(prefs: prefs, testApi: _FailingApi());
  appController.city = {'id': 1, 'latitude': 15.4624, 'longitude': 45.3228};
}

void main() {
  test('classifies shell branch destinations', () {
    for (final path in const [
      '/',
      '/products',
      '/products?type=2',
      '/haraj',
      '/haraj?page=2',
      '/orders',
      '/akhdimni',
    ]) {
      expect(isShellBranchLocation(path), isTrue, reason: path);
    }
    for (final path in const [
      '/cart',
      '/account',
      '/notifications',
      '/product/some-slug',
      '/orders/12',
      '/haraj/12',
      '/haraj/create',
      '/akhdimni/create',
      '/akhdimni/orders/12',
      '/sellers?type=2',
      '',
    ]) {
      expect(isShellBranchLocation(path), isFalse, reason: path);
    }
  });

  testWidgets('opening a shell branch from cart replaces instead of pushing', (
    tester,
  ) async {
    await _setup();
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    router.push('/cart');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    final context = tester.element(find.byType(CartScreen));
    openAppLocation(context, '/orders');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/orders');
  });

  testWidgets('opening a shell branch from account does not throw', (
    tester,
  ) async {
    await _setup();
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    router.go('/account');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    final context = tester.element(find.byType(AccountScreen));
    openAppLocation(context, '/orders');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/orders');
  });

  testWidgets('opening a detail route from cart still pushes', (tester) async {
    await _setup();
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    router.push('/cart');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    final context = tester.element(find.byType(CartScreen));
    openAppLocation(context, '/product/some-slug');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(router.canPop(), isTrue);
  });

  testWidgets('cart/account are not tab routes and hide the bottom bar', (
    tester,
  ) async {
    await _setup();
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(NavigationBar), findsOneWidget);

    router.push('/cart');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(NavigationBar), findsNothing);

    router.go('/account');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(NavigationBar), findsNothing);
  });
}
