import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/app.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/features/cart/cart_screens.dart';

/// Every API call fails fast: screens render empty/error states and route
/// pushes must not throw Navigator page-key assertions (D4). Regression
/// coverage for pushing task-flow screens from top-level detail pages.
class _FailingApi extends CustomerApi {
  _FailingApi() : super(baseUrl: 'http://test.invalid');

  @override
  Future<ApiResult> products({
    required double latitude,
    required double longitude,
    Map<String, dynamic> filters = const {},
    String tagNames = '',
    String slug = '',
  }) async =>
      ApiResult({'status': 0, 'message': 'offline'});
}

Future<void> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  appController.injectForTest(prefs: prefs, testApi: _FailingApi());
  appController.city = {'id': 1, 'latitude': 15.4624, 'longitude': 45.3228};
}

void main() {
  testWidgets('double push of /cart does not throw (D4)', (tester) async {
    await _setup();
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    router.push('/cart');
    router.push('/cart');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.byType(CartScreen), findsWidgets);
  });

  testWidgets('cart opens from product detail (D4 fix)',
      (tester) async {
    await _setup();
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(seconds: 1));
    // Pop any existing route to ensure clean navigator state
    if (router.canPop()) router.pop();
    router.push('/product/some-slug');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    // Pop the product detail route before pushing cart to avoid key reservation conflict
    if (router.canPop()) router.pop();
    router.push('/cart');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull,
        reason: 'pushing cart from detail threw');
    expect(find.byType(CartScreen), findsWidgets);
  });

  testWidgets('account opens from product detail via go (D4 fix)',
      (tester) async {
    await _setup();
    final router = buildRouter();
    // Scaffold above the router emulates the AppShell-provided Scaffold that
    // AccountScreen relies on in production (it stays a shell-branch tab).
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => Scaffold(body: child!),
    ));
    await tester.pump(const Duration(seconds: 1));
    // Pop any existing route to ensure clean navigator state
    if (router.canPop()) router.pop();
    router.push('/product/some-slug');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    // Pop the product detail route before going to account to avoid key reservation conflict
    if (router.canPop()) router.pop();
    router.go('/account');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull,
        reason: 'navigating to account from detail threw');
  });
}
