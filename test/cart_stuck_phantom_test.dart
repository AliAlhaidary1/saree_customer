import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/json_util.dart';

/// Regression tests for the "stuck cart line" bug:
///
/// 1. A guest adds a product while offline (line lives in the local guest
///    cart).
/// 2. Internet opens / the user is logged in, the bulk guest-cart merge
///    FAILS on the server, and the line is folded into the server cart
///    optimistically.
/// 3. Deleting the line made it disappear visually but never removed the
///    pending guest-merge intent, so the next app resume / login merged it
///    back onto the server and the deleted line reappeared.
///
/// Additionally, a failed merge stamps the pending lines with the account
/// scope; another account logging in on the same device must never inherit
/// (or silently merge) them.
class _StuckPhantomCartApi extends CustomerApi {
  _StuckPhantomCartApi() : super(baseUrl: 'http://test.invalid');

  /// variantId -> qty of the SERVER cart. Empty = server has nothing.
  final Map<String, int> server = {};
  bool bulkShouldFail = true;
  int bulkCalls = 0;

  @override
  Future<ApiResult> cities({
    int limit = 100,
    int offset = 0,
    String search = '',
  }) async => ApiResult({
        'status': 1,
        'data': [
          {'id': 1, 'name': 'Test City'},
        ],
      });

  @override
  Future<ApiResult> businessHours({List<dynamic> sellerIds = const []}) async =>
      ApiResult({'status': 1, 'data': []});

  @override
  Future<ApiResult> guestCart({
    required double latitude,
    required double longitude,
    required String variantIds,
    required String quantities,
  }) async => ApiResult({
        'status': 0,
        'message': 'network unreachable',
        'error': {'code': 'ECONNREFUSED'},
      });

  @override
  Future<ApiResult> cart({
    required double latitude,
    required double longitude,
    int checkout = 0,
  }) async {
    if (server.isEmpty) {
      return ApiResult({
        'status': 0,
        'message': 'no_items_found_in_users_cart',
      });
    }
    return ApiResult({'status': 1, 'data': _cartData()});
  }

  @override
  Future<ApiResult> bulkAddToCart({
    required String variantIds,
    required String quantities,
  }) async {
    bulkCalls += 1;
    if (bulkShouldFail) {
      // A backend refusal phrase the client does not (and should not have
      // to) recognize — e.g. stock/one-seller validation failure.
      return ApiResult({'status': 0, 'message': 'variant_unavailable_zzz'});
    }
    final ids = variantIds.split(',');
    final qtys = quantities.split(',');
    for (var i = 0; i < ids.length; i++) {
      server[ids[i]] = int.tryParse(qtys[i]) ?? 1;
    }
    return ApiResult({'status': 1, 'data': _cartData()});
  }

  @override
  Future<ApiResult> removeFromCart({
    required dynamic productId,
    required dynamic variantId,
  }) async {
    if (!server.containsKey('$variantId')) {
      // Realistic not-found phrasing for an attempt to remove a stale id —
      // must be treated as a converged removal (no error surfaced).
      return ApiResult({
        'status': 0,
        'message': 'no_product_found',
      });
    }
    server.remove('$variantId');
    return ApiResult({'status': 1, 'message': 'item_removed'});
  }

  @override
  Future<ApiResult> clearCart() async {
    server.clear();
    return ApiResult({'status': 1, 'message': 'cleared'});
  }

  Map<String, dynamic> _cartData() =>
      {'cart': rows(), 'sub_total': 10.0 * rows().length};

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
}

Future<_StuckPhantomCartApi> _setup({required bool loggedIn}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _StuckPhantomCartApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.token = loggedIn ? 'tok' : null;
  appController.user = loggedIn ? {'id': 7, 'name': 'Tester'} : null;
  appController.guestCart = [];
  appController.guestCartTotal = 0;
  appController.cartProducts = [];
  appController.cart = null;
  appController.cartSubTotal = 0;
  appController.businessHours = null;
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'offline guest item deleted after a failed merge never resurrects',
    () async {
      // ── Step 1: guest adds the product to the cart while OFFLINE ──
      final api = await _setup(loggedIn: false);
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 2,
        productPrice: 10,
        sellerId: 5,
      );
      expect(
        appController.guestCart.map((e) => '${e['product_variant_id']}'),
        contains('11'),
      );

      // ── Step 2: internet opens; merge into the account FAILS server-side ──
      appController.token = 'tok';
      appController.user = {'id': 7, 'name': 'Tester'};
      await appController.mergeGuestCartForTest();
      // Folded optimistically so it stays visible…
      expect(
        appController.cartProducts.map((e) => '${e['product_variant_id']}'),
        contains('11'),
        reason: 'failed merge keeps the pending line visible',
      );
      // …but the pending guest intent survives for a later retry.
      expect(
        appController.guestCart.map((e) => '${e['product_variant_id']}'),
        contains('11'),
      );

      // ── Step 3: the user deletes the line ──
      final err = await appController.removeCartLine(
        productId: 11,
        variantId: 11,
      );
      expect(err, isNull, reason: 'server absence converges silently');
      expect(appController.cartProducts, isEmpty);
      expect(appController.guestCart, isEmpty);
      // The persisted mirror must be empty as well.
      final raw = appController.prefs.getString('guest_cart');
      expect(raw == null || raw == '[]', isTrue);

      // ── Step 4: app resume with everything online must NOT re-add it ──
      api.bulkShouldFail = false;
      final callsBefore = api.bulkCalls;
      await appController.mergeGuestCartForTest();
      expect(
        api.bulkCalls,
        callsBefore,
        reason: 'deleted pending intent must never merge again',
      );
      expect(appController.cartProducts, isEmpty);
      expect(api.server, isEmpty);
    },
  );

  test(
    'delete cancels the pending intent even when the merge later succeeds',
    () async {
      final api = await _setup(loggedIn: false);
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 1,
        productPrice: 10,
        sellerId: 5,
      );
      // Login with a failing merge → folded + pending (stays in guest cart).
      appController.token = 'tok';
      appController.user = {'id': 7, 'name': 'Tester'};
      await appController.mergeGuestCartForTest();
      expect(appController.cartProducts, isNotEmpty);

      // Delete while the merge still has not succeeded.
      final err = await appController.removeCartLine(
        productId: 11,
        variantId: 11,
      );
      expect(err, isNull);

      // Now the merge CAN succeed — but there is nothing left to merge.
      api.bulkShouldFail = false;
      final callsBefore = api.bulkCalls;
      await appController.mergeGuestCartForTest();
      expect(api.bulkCalls, callsBefore);
      expect(appController.cartProducts, isEmpty);
      expect(api.server, isEmpty, reason: 'deleted item must not reach server');
    },
  );

  test(
    "another account on the shared device never inherits a failed account's "
    'pending guest lines',
    () async {
      final api = await _setup(loggedIn: false);
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 1,
        productPrice: 10,
        sellerId: 5,
      );

      // Account u:7 logs in; its merge fails → the lines become stamped u:7.
      appController.token = 'tok-a';
      appController.user = {'id': 7, 'name': 'Account A'};
      await appController.mergeGuestCartForTest();
      expect(appController.cartProducts, isNotEmpty);

      // Account u:9 now logs in on the same device. The parked line must
      // stay hidden and untouched — never merged into u:9's cart.
      appController.token = 'tok-b';
      appController.user = {'id': 9, 'name': 'Account B'};
      appController.cartProducts = [];
      appController.cart = null;
      api.bulkShouldFail = false;
      await appController.mergeGuestCartForTest();
      expect(
        appController.cartProducts,
        isEmpty,
        reason: 'foreign parked line must not leak into another account',
      );
      expect(api.server, isEmpty);

      // Account u:7 returns and the merge CAN succeed: its line is restored.
      appController.token = 'tok-a';
      appController.user = {'id': 7, 'name': 'Account A'};
      await appController.mergeGuestCartForTest();
      expect(
        api.server.keys,
        contains('11'),
        reason: 'owning account still owns (and now merges) the pending line',
      );
      expect(appController.guestCart, isEmpty);
    },
  );

  test('clear-cart cancels this account\'s pending guest import', () async {
    final api = await _setup(loggedIn: false);
    await appController.addToCart(
      productId: 11,
      variantId: 11,
      qty: 1,
      productPrice: 10,
      sellerId: 5,
    );

    // u:7 merge fails → folded + pending.
    appController.token = 'tok-a';
    appController.user = {'id': 7, 'name': 'Account A'};
    await appController.mergeGuestCartForTest();
    expect(appController.cartProducts, isNotEmpty);

    // "Clear cart" must also cancel the pending import for THIS account.
    await appController.clearAllCart();
    expect(appController.cartProducts, isEmpty);
    expect(appController.guestCart, isEmpty);

    api.bulkShouldFail = false;
    final callsBefore = api.bulkCalls;
    await appController.mergeGuestCartForTest();
    expect(api.bulkCalls, callsBefore);
    expect(appController.cartProducts, isEmpty);
  });

  test(
    'guest (not logged in) delete still works and persists',
    () async {
      await _setup(loggedIn: false);
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 2,
        productPrice: 10,
        sellerId: 5,
      );
      expect(appController.guestCart, isNotEmpty);

      final err = await appController.removeCartLine(
        productId: 11,
        variantId: 11,
      );
      expect(err, isNull);
      expect(appController.guestCart, isEmpty);
      final raw = appController.prefs.getString('guest_cart');
      expect(raw == null || raw == '[]', isTrue);
    },
  );
}
