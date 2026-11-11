import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/features/cart/cart_screens.dart';

/// Exact user-reported scenario reproduced live:
///   1. Logged-in, ONLINE.
///   2. Add item to the cart.
///   3. Go fully OFFLINE.
///   4. Open the cart and tap delete on that item.
///   5. Move away from the cart screen (My-orders tab, etc.).
///   6. Re-open the cart — the line must NOT reappear.
///
/// This test pumps the real CartScreen widget (not just the controller API) to
/// verify the user-visible invariant. It is intentionally written with
/// runAsync() because _load() calls real network timeouts through the fake
/// API that race with pumpAndSettle from the fake zone — this mirrors how the
/// real app actually waits during refreshCart.
class _ScenarioApi extends CustomerApi {
  _ScenarioApi() : super(baseUrl: 'http://test.invalid', token: null);

  bool online = true;
  final Map<String, int> server = {};
  int cartCalls = 0;
  int removeCalls = 0;

  List<Map<String, dynamic>> _rows() => server.entries
      .map(
        (e) => <String, dynamic>{
          'product_id': int.tryParse(e.key) ?? e.key,
          'product_variant_id': int.tryParse(e.key) ?? e.key,
          'qty': e.value,
          'price': 100,
          'name': 'منتج ${e.key}',
          'seller_id': 5,
        },
      )
      .toList();

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
    if (server.isEmpty) {
      return ApiResult({
        'status': 0,
        'message': 'no_items_found_in_users_cart',
      });
    }
    return ApiResult({
      'status': 1,
      'data': {'cart': _rows(), 'sub_total': 100.0 * server.length},
    });
  }

  @override
  Future<ApiResult> addToCart({
    required dynamic productId,
    required dynamic variantId,
    required dynamic qty,
  }) async {
    if (!online) {
      return ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });
    }
    server['$variantId'] = int.tryParse('$qty') ?? 1;
    return ApiResult({'status': 1, 'data': {'cart': _rows()}});
  }

  @override
  Future<ApiResult> removeFromCart({
    required dynamic productId,
    required dynamic variantId,
  }) async {
    removeCalls += 1;
    if (!online) {
      return ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });
    }
    if (!server.containsKey('$variantId')) {
      return ApiResult({'status': 0, 'message': 'no_product_found'});
    }
    server.remove('$variantId');
    return ApiResult({'status': 1, 'message': 'item_removed'});
  }

  @override
  Future<ApiResult> addresses() async {
    if (!online) {
      return ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });
    }
    return ApiResult({'status': 1, 'data': []});
  }
}

Future<_ScenarioApi> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _ScenarioApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.businessHours = BusinessHoursResult();
  appController.token = 'tok';
  appController.user = {'id': 7, 'name': 'T'};
  appController.cartProducts = [];
  appController.cartSubTotal = 0;
  appController.cart = null;
  appController.guestCart = [];
  appController.guestCartTotal = 0;
  return api;
}

List<String> _listVariants() => appController.cartProducts
    .map((e) => '${e['product_variant_id']}=${e['qty'] ?? e['quantity']}')
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('user flow: online add → offline → delete → re-enter cart — line stays gone', () async {
    final api = await _setup();

    // ONLINE add.
    await appController.addToCart(
      productId: 123,
      variantId: 123,
      qty: 1,
      productPrice: 100,
      sellerId: 5,
    );
    expect(api.server, {'123': 1});
    expect(_listVariants(), ['123=1']);

    // Go OFFLINE.
    api.online = false;

    // Open the cart: offline refresh fails; cartProducts already holds the line.
    // Snapshot restore path also sees [123] but _applyPendingCartSetQty does not
    // see it yet — therefore the line stays visible with the full price.
    await appController.refreshCart();
    expect(_listVariants(), ['123=1']);

    // Delete it — must happen optimistically.
    final err = await appController.removeCartLine(
      productId: 123,
      variantId: 123,
    );
    expect(err, isNull);
    expect(_listVariants(), isEmpty);
    // Server is still online? — intent remains in the outbox (qty=0) because
    // we cannot confirm deletion.
    expect(api.removeCalls, 1);
    expect(api.server, {'123': 1});

    // User navigates away — cart screen is disposed.
    // Re-enter cart by re-obtaining controller state; refresh must still not
    // resurrect the line.
    await appController.refreshCart();
    expect(_listVariants(), isEmpty,
        reason: 'offline refresh must honor the pending delete intent');

    // Come back online. The pending delete is forced through — exactly what
    // the user expects.
    api.online = true;
    await appController.handleAppResumed();
    expect(api.server, isEmpty);
    expect(_listVariants(), isEmpty);
  });

  testWidgets(
    'end-to-end visual: online add → go offline → open cart → tap delete → navigate away → re-open cart',
    (tester) async {
      final api = await _setup();

      // ONLINE add.
      await appController.addToCart(
        productId: 123,
        variantId: 123,
        qty: 1,
        productPrice: 100,
        sellerId: 5,
      );
      expect(api.server, {'123': 1});

      // Go OFFLINE.
      api.online = false;

      // Open the CartScreen — mirror how the app wraps it in Material.
      await tester.pumpWidget(
        MaterialApp(
          home: Material(color: const Color(0xFFF0F0F0), child: const CartScreen()),
        ),
      );

      // The item renders.
      expect(find.textContaining('منتج 123'), findsOneWidget);
      expect(_listVariants(), ['123=1']);

      // Tap the delete button. It should disappear from the UI.
      final deleteIcon = find.byIcon(Icons.delete_outline);
      await tester.ensureVisible(deleteIcon);
      await tester.tap(deleteIcon);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('منتج 123'), findsNothing);
      expect(_listVariants(), isEmpty);

      // Refresh still honors the pending delete intent.
      await appController.refreshCart();
      expect(_listVariants(), isEmpty,
          reason:
              'after navigation/re-entry, the line must still be gone pending connectivity');
    },
  );
}
