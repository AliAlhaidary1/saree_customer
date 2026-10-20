import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/offline/offline_cache.dart';
import 'package:sareemart_customer/features/cart/cart_screens.dart';

class _EmptyCartApi extends CustomerApi {
  _EmptyCartApi() : super(baseUrl: 'http://test.invalid');

  @override
  Future<ApiResult> cart({
    required double latitude,
    required double longitude,
    int checkout = 0,
  }) async =>
      ApiResult({'status': 0, 'message': 'No item(s) found in users cart'});
}

class _OfflineCartApi extends CustomerApi {
  _OfflineCartApi() : super(baseUrl: 'http://test.invalid');

  @override
  Future<ApiResult> cart({
    required double latitude,
    required double longitude,
    int checkout = 0,
  }) async => ApiResult({
    'status': 0,
    'message': 'connection refused',
    'error': {'code': 'ECONNREFUSED'},
  });
}

Future<void> _setup(CustomerApi api) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.4624, 'longitude': 45.3228};
  appController.cart = null;
  appController.cartProducts = [];
  appController.cartSubTotal = 0;
  appController.token = 'test-token';
  appController.user = {'id': 99};
}

Future<void> _pumpCart(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: CartScreen())),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('reachable empty cart shows the empty state, not an error', (
    tester,
  ) async {
    await _setup(_EmptyCartApi());
    await _pumpCart(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(appController.t('empty_cart')), findsOneWidget);
    expect(find.text(appController.t('cart_load_failed')), findsNothing);
  });

  testWidgets('offline cart restores the cached snapshot', (tester) async {
    await _setup(_OfflineCartApi());
    await appController.offline.writeDoc(
      OfflineCache.snapshotKey('cart::${appController.accountScope}'),
      {
        'products': [
          {
            'product_variant_id': 11,
            'name': 'Cached item',
            'qty': 1,
            'price': 50,
          },
        ],
        'subTotal': 50,
      },
      scope: appController.accountScope,
    );
    await _pumpCart(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Cached item'), findsOneWidget);
    expect(find.text(appController.t('cart_load_failed')), findsNothing);
  });

  testWidgets('offline cart without a snapshot shows a retryable error', (
    tester,
  ) async {
    await _setup(_OfflineCartApi());
    await _pumpCart(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(appController.t('cart_load_failed')), findsOneWidget);
  });
}
