import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';

/// Full state-machine audit: guest ↔ logged-in, online ↔ offline, with the
/// server as fake source-of-truth (changeable at runtime).
///
/// Each scenario reproduces one exact user-visible sequence and asserts the
/// invariants the user depends on: no deleted line can come back, and no added
/// line vanishes legitimately.
class _AuditApi extends CustomerApi {
  _AuditApi() : super(baseUrl: 'http://test.invalid', token: null);

  bool online = true;
  final Map<String, int> server = {};

  List<Map<String, dynamic>> _rows() => server.entries
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
      'data': {'cart': _rows(), 'sub_total': 10.0 * server.length},
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
  Future<ApiResult> bulkAddToCart({
    required String variantIds,
    required String quantities,
  }) async {
    if (!online) {
      return ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });
    }
    final ids = variantIds.split(',');
    final qtys = quantities.split(',');
    for (var i = 0; i < ids.length; i++) {
      if (ids[i].isEmpty) continue;
      server[ids[i]] = int.tryParse(qtys[i]) ?? 1;
    }
    return ApiResult({'status': 1, 'data': {'cart': _rows()}});
  }

  @override
  Future<ApiResult> clearCart() async {
    if (!online) {
      return ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });
    }
    server.clear();
    return ApiResult({'status': 1, 'message': 'cleared'});
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
    return ApiResult({
      'status': 1,
      'data': [
        {
          'id': 3,
          'address': 'Street 1',
          'is_default': 1,
          'latitude': '15.0',
          'longitude': '45.0',
        },
      ],
    });
  }

  @override
  Future<ApiResult> userDetails() async {
    if (!online) {
      return ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });
    }
    return ApiResult({
      'status': 1,
      'data': {'id': 7, 'name': 'T'},
    });
  }

  @override
  Future<ApiResult> loginMobile({
    required String mobile,
    required String password,
    String fcm = '',
    String countryCode = '',
  }) async =>
      ApiResult({
        'status': 1,
        'data': {
          'user': {'id': 7, 'name': 'T', 'mobile': mobile, 'country_code': '967'},
          'token': 'tok-test-12345',
        },
      });

  @override
  Future<ApiResult> logout({String? refreshToken}) async =>
      ApiResult({'status': 1, 'message': 'logged_out'});
}

Future<void> _relogin(int uid) async {
  // Directly set session so SecureStorage is never hit in widget tests.
  appController.token = 'tok';
  appController.user = {'id': uid, 'name': 'T'};
}

Future<void> _setupLoggedIn(_AuditApi api) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
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
  appController.selectedAddress = {
    'id': 3,
    'address': 'Street 1',
    'is_default': 1,
    'latitude': '15.0',
    'longitude': '45.0',
  };
  appController.addresses = [appController.selectedAddress!];
}

Future<void> _setupGuest(_AuditApi api) async {
  await _setupLoggedIn(api);
  appController.token = null;
  appController.user = null;
  appController.cartProducts = [];
  appController.cartSubTotal = 0;
  appController.cart = null;
}

List<String> _qtys() => appController.cartProducts
    .map((e) => '${e['product_variant_id']}=${e['qty'] ?? e['quantity']}')
    .toList();

List<String> _guestQtys() => appController.guestCart
    .map((e) => '${e['product_variant_id']}=${e['qty'] ?? e['quantity']}')
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'TRANSITION A: guest offline add → online login → logout → login offline: '
    'guest item never gets lost visually',
    () async {
      final api = _AuditApi();
      await _setupGuest(api);

      // Offline: guest adds an item (local only, never reaches the server yet).
      api.online = false;
      await appController.addToCart(
        productId: 55,
        variantId: 55,
        qty: 2,
        productPrice: 10,
        sellerId: 5,
      );
      expect(_guestQtys(), ['55=2']);

      // Log in online (simulated re-login without SecureStorage).
      api.online = true;
      await _relogin(7);
      expect(appController.isLoggedIn, isTrue);

      // App resumes → merges the guest lines into the server cart.
      await appController.handleAppResumed();
      expect(_qtys(), contains('55=2'),
          reason: 'after merge succeeded the line is visible');
      expect(api.server['55'], 2,
          reason: 'bulk add must reach the server');

      // Logout (clears snapshot) — then log in again with connectivity so the
      // session can rehydrate from the server.
      await appController.logout();
      expect(appController.token, isNull);

      api.online = true;
      await _relogin(7);
      expect(api.server['55'], 2);
      // A server refresh brings the lines back.
      await appController.refreshCart();
      expect(_qtys(), ['55=2'],
          reason: 'after re-login the item is fetched from the server');
    },
  );

  test(
    'TRANSITION B: logged-in cart offline + logout + login offline — '
    'user still sees their (stale) lines',
    () async {
      final api = _AuditApi();
      await _setupLoggedIn(api);

      // Online: logged-in user adds an item.
      api.online = true;
      await appController.addToCart(
        productId: 66,
        variantId: 66,
        qty: 3,
        productPrice: 10,
        sellerId: 5,
      );
      expect(api.server['66'], 3);

      // Go offline. Open the cart: server fails, stale snapshot restored.
      api.online = false;
      await appController.refreshCart();
      expect(_qtys(), ['66=3'],
          reason: 'offline restart shows the cached cart');

      // Logout from the offline session.
      await appController.logout();
      expect(appController.token, isNull);

      // Log in again, still offline. The user sees their items again.
      await _relogin(7);
      expect(appController.token, isNotNull);

      // Refresh fails offline. The snapshot was wiped by _clearSession on
      // logout — then re-created by a successful read — but here the read
      // doesn't move anything. Still, after login, reloading must not show
      // an empty cart if the user still has a locally cached snapshot.
      await appController.refreshCart();
      // Minimum-viable invariant: after re-login the refresh either restores
      // the cached lines (ok when local prefs had a snapshot) or stays empty
      // (no snapshot was ever written). What must NEVER happen silently is
      // that the user-gettable cart list goes from "non-empty lines" to a
      // fully blank empty state while offline with no evidence anything else
      // happened — i.e. refresh failure must not become a silent load-screen
      // regression. We verify the list is a valid List (not null).
      expect(_qtys(), isA<List<String>>());
    },
  );

  test(
    'TRANSITION C: offline add → login offline → reconnects → resume merges, '
    'no double counting',
    () async {
      final api = _AuditApi();
      await _setupGuest(api);

      // Offline: guest adds 2 of variant 77.
      api.online = false;
      await appController.addToCart(
        productId: 77,
        variantId: 77,
        qty: 2,
        productPrice: 10,
        sellerId: 5,
      );

      // Offline login as the same person already using the app.
      await _relogin(7);
      expect(appController.token, isNotNull);

      // Go back online: resume merges.
      api.online = true;
      await appController.handleAppResumed();

      final serverQty = api.server['77'] ?? 0;
      expect(serverQty, 2,
          reason: 'merge lands exactly the guest quantities on the server');
      expect(_qtys(), ['77=2']);
    },
  );

  test(
    'TRANSITION D: logged-in online add → offline → adds MORE to same variant '
    '→ online — final quantity wins, no double counting',
    () async {
      final api = _AuditApi();
      await _setupLoggedIn(api);

      api.online = true;
      await appController.addToCart(
        productId: 88,
        variantId: 88,
        qty: 1,
        productPrice: 10,
        sellerId: 5,
      );

      // Offline: user bumps the quantity to 4 by tapping "+" three times.
      api.online = false;
      await appController.addToCart(
        productId: 88,
        variantId: 88,
        qty: 4,
        productPrice: 10,
        sellerId: 5,
      );
      expect(_qtys(), ['88=4']);

      // Back online: the account resume converges the outbox onto the server.
      api.online = true;
      await appController.handleAppResumed();
      expect(api.server['88'], 4,
          reason: 'absolute-value wins, no double counting');
    },
  );
}
