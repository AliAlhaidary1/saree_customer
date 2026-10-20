import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/json_util.dart';

/// Stateful fake that mirrors the real backend cart contract:
/// * `cart` GET returns `status:1` with rows while non-empty, and a bare
///   `status:0` `no_items_found_in_users_cart` once the cart is empty (no
///   `error` map — exactly like [CommonHelper::responseError]).
/// * `cart/remove` deletes the row and answers success; a second remove of
///   the same variant answers `no_items_found_in_users_cart`.
/// * `cart/add` upserts the row.
///
/// This reproduces the "delete the last item twice" bug: after the last line
/// is gone the follow-up refresh is a business `status:0`, and the client must
/// treat that as an EMPTY cart (not as offline) so it never restores the
/// stale offline snapshot that still contains the just-deleted line.
class _StatefulCartApi extends CustomerApi {
  _StatefulCartApi() : super(baseUrl: 'http://test.invalid', token: null);

  /// variantId -> qty, the server's source of truth.
  final Map<String, int> server = {};

  /// When set, overrides the [cart] response (used to inject transport
  /// failures for the offline-restore assertion).
  ApiResult? cartResult;

  @override
  Future<ApiResult> cities({
    int limit = 100,
    int offset = 0,
    String search = '',
  }) async {
    return ApiResult({
      'status': 1,
      'data': [
        {'id': 1, 'name': 'Test City'}
      ],
    });
  }

  @override
  Future<ApiResult> businessHours({List<dynamic> sellerIds = const []}) async {
    return ApiResult({'status': 1, 'data': []});
  }

  @override
  Future<ApiResult> addToCart({
    required dynamic productId,
    required dynamic variantId,
    required dynamic qty,
  }) async {
    server['$variantId'] = int.tryParse('$qty') ?? 1;
    return ApiResult({'status': 1, 'data': _cartData()});
  }

  @override
  Future<ApiResult> removeFromCart({
    required dynamic productId,
    required dynamic variantId,
  }) async {
    if (!server.containsKey('$variantId')) {
      return ApiResult({
        'status': 0,
        'message': 'no_items_found_in_users_cart',
      });
    }
    server.remove('$variantId');
    return ApiResult({'status': 1, 'message': 'item_removed'});
  }

  @override
  Future<ApiResult> cart({
    required double latitude,
    required double longitude,
    int checkout = 0,
  }) async {
    final override = cartResult;
    if (override != null) return override;
    if (server.isEmpty) {
      return ApiResult({
        'status': 0,
        'message': 'no_items_found_in_users_cart',
      });
    }
    return ApiResult({'status': 1, 'data': _cartData()});
  }

  List<Map<String, dynamic>> rows() => server.entries
      .map(
        (e) => <String, dynamic>{
          'product_id': int.tryParse(e.key) ?? e.key,
          'product_variant_id': int.tryParse(e.key) ?? e.key,
          'qty': e.value,
          'price': 10,
          'name': 'P${e.key}',
          'seller_id': 5,
        },
      )
      .toList();

  Map<String, dynamic> _cartData() => {'cart': rows(), 'sub_total': 0};
}

Future<_StatefulCartApi> _setupLoggedIn() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _StatefulCartApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.token = 'tok';
  appController.user = {'id': 7, 'name': 'Tester'};
  appController.guestCart = [];
  appController.cartProducts = [];
  appController.cart = null;
  appController.cartSubTotal = 0;
  appController.businessHours = null;
  return api;
}

List<String> _variantIdsOfCart() => appController.cartProducts
    .map((e) => '${e['product_variant_id']}')
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deleting the last of two items never resurrects it', () async {
    final api = await _setupLoggedIn();

    await appController.addToCart(
      productId: 11,
      variantId: 11,
      qty: 1,
      productPrice: 10,
      sellerId: 5,
    );
    await appController.addToCart(
      productId: 22,
      variantId: 22,
      qty: 1,
      productPrice: 10,
      sellerId: 5,
    );
    expect(api.server.keys.toSet(), {'11', '22'});
    expect(_variantIdsOfCart().toSet(), {'11', '22'});

    // Delete the first item: the second must survive.
    await appController.removeCartLine(productId: 11, variantId: 11);
    expect(_variantIdsOfCart(), ['22'], reason: 'first delete keeps item 2');

    // Delete the last item: it must stay gone (this used to resurrect it from
    // the stale offline snapshot, forcing a second delete).
    await appController.removeCartLine(productId: 22, variantId: 22);
    expect(_variantIdsOfCart(), isEmpty, reason: 'last delete must stick');

    // ...and it must not come back on any subsequent refresh.
    await appController.refreshCart();
    expect(_variantIdsOfCart(), isEmpty, reason: 'refresh stays empty');
    expect(appController.cartSubTotal, 0);
  });

  test('deleting all lines one-by-one converges to an empty cart', () async {
    final api = await _setupLoggedIn();
    for (final id in [11, 22, 33]) {
      await appController.addToCart(
        productId: id,
        variantId: id,
        qty: 1,
        productPrice: 10,
        sellerId: 5,
      );
    }
    expect(api.server.length, 3);

    for (final id in [11, 22, 33]) {
      await appController.removeCartLine(productId: id, variantId: id);
    }

    expect(api.server, isEmpty);
    expect(appController.cartProducts, isEmpty);
    await appController.refreshCart();
    expect(appController.cartProducts, isEmpty);
  });

  test('offline refresh still restores the last confirmed snapshot', () async {
    final api = await _setupLoggedIn();
    await appController.addToCart(
      productId: 11,
      variantId: 11,
      qty: 2,
      productPrice: 10,
      sellerId: 5,
    );
    expect(_variantIdsOfCart(), ['11']);

    // Simulate a genuine transport failure (network category) with an empty
    // local cart (fresh app offline): the snapshot must be restored.
    appController.cartProducts = [];
    api.cartResult = ApiResult({
      'status': 0,
      'message': 'timeout',
      'error': {'code': 'TIMEOUT', 'httpStatus': 504},
    });
    await appController.refreshCart();
    expect(
      _variantIdsOfCart(),
      ['11'],
      reason: 'offline restore is still allowed on a transport failure',
    );
  });
}
