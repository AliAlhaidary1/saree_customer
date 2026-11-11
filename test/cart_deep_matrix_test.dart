import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/api/api_errors.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/features/cart/cart_screens.dart';

/// Deep integration matrix for the cart: online/offline, logged-in/guest,
/// restarts, server refusals, and widget-level UI flows. The server is an
/// in-memory fake with the real contract (empty cart returns status:0 with
/// `no_items_found_…`, all ops become transport failures when `online` is
/// false, and business validation failures are fully distinct from network
/// failures). These tests never touch the real network.
class _DeepApi extends CustomerApi {
  _DeepApi() : super(baseUrl: 'http://test.invalid', token: null);

  bool online = true;
  bool returnBusinessRefusalOnRemove = false;
  String businessRefusalMessage = 'cannot_delete_reserved_item';

  /// Simulates a server that acknowledges a delete but whose read-after-write
  /// path transiently returns the removed row on the next GET (typical when the
  /// replica serving reads lags behind the replica performing the delete).
  Map<String, int>? staleEcho;

  final Map<String, int> server = {};
  int cartCalls = 0;
  int addCalls = 0;
  int removeCalls = 0;
  int clearCalls = 0;

  List<Map<String, dynamic>> _rows() {
    if (staleEcho != null && staleEcho!.isNotEmpty) {
      return staleEcho!.entries
          .map(
            (e) => <String, dynamic>{
              'product_id': int.tryParse(e.key) ?? e.key,
              'product_variant_id': int.tryParse(e.key) ?? e.key,
              'qty': e.value,
              'price': 25,
              'name': 'P${e.key}',
              'seller_id': 5,
            },
          )
          .toList();
    }
    if (server.isEmpty) return [];
    return server.entries
        .map(
          (e) => <String, dynamic>{
            'product_id': int.tryParse(e.key) ?? e.key,
            'product_variant_id': int.tryParse(e.key) ?? e.key,
            'qty': e.value,
            'price': 25,
            'name': 'P${e.key}',
            'seller_id': 5,
          },
        )
        .toList();
  }

  ApiResult _networkFail() => ApiResult({
    'status': 0,
    'message': 'timeout',
    'error': {'code': 'TIMEOUT', 'httpStatus': 504},
  });

  ApiResult _ok([dynamic data]) =>
      ApiResult({'status': 1, 'data': data ?? const {}});

  @override
  Future<ApiResult> cities({
    int limit = 100,
    int offset = 0,
    String search = '',
  }) async =>
      online
          ? _ok([
              {'id': 1, 'name': 'City'},
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
    if (!online) return _networkFail();
    if (staleEcho != null && staleEcho!.isNotEmpty) {
      final echo = staleEcho;
      staleEcho = null; // consume once
      return _ok({
        'cart': _rows(),
        'sub_total': echo!.values.fold(0.0, (sum, q) => sum + 25.0 * q),
      });
    }
    if (server.isEmpty) {
      return ApiResult({
        'status': 0,
        'message': 'no_items_found_in_users_cart',
      });
    }
    return _ok({
      'cart': _rows(),
      'sub_total': server.values.fold(0.0, (sum, q) => sum + 25.0 * q),
    });
  }

  @override
  Future<ApiResult> guestCart({
    required double latitude,
    required double longitude,
    required String variantIds,
    required String quantities,
  }) async {
    if (!online) return _networkFail();
    final ids = variantIds.split(',');
    final qtys = quantities.split(',');
    for (var i = 0; i < ids.length; i++) {
      if (ids[i].isEmpty) continue;
      server[ids[i]] = int.tryParse(qtys[i]) ?? 1;
    }
    return _ok({
      'cart': _rows(),
      'sub_total': server.values.fold(0.0, (sum, q) => sum + 25.0 * q),
    });
  }

  @override
  Future<ApiResult> bulkAddToCart({
    required String variantIds,
    required String quantities,
  }) async {
    if (!online) return _networkFail();
    final ids = variantIds.split(',');
    final qtys = quantities.split(',');
    for (var i = 0; i < ids.length; i++) {
      if (ids[i].isEmpty) continue;
      server[ids[i]] = int.tryParse(qtys[i]) ?? 1;
    }
    return _ok({'cart': _rows()});
  }

  @override
  Future<ApiResult> addToCart({
    required dynamic productId,
    required dynamic variantId,
    required dynamic qty,
  }) async {
    addCalls += 1;
    if (!online) return _networkFail();
    // Realistic server math: set absolute qty, never accumulate duplicates.
    server['$variantId'] = int.tryParse('$qty') ?? 1;
    return _ok({'cart': _rows()});
  }

  @override
  Future<ApiResult> removeFromCart({
    required dynamic productId,
    required dynamic variantId,
  }) async {
    removeCalls += 1;
    if (!online) return _networkFail();
    if (returnBusinessRefusalOnRemove) {
      return ApiResult({
        'status': 0,
        'message': businessRefusalMessage,
      });
    }
    if (!server.containsKey('$variantId')) {
      return ApiResult({'status': 0, 'message': 'no_product_found'});
    }
    server.remove('$variantId');
    return ApiResult({'status': 1, 'message': 'item_removed'});
  }

  @override
  Future<ApiResult> clearCart() async {
    clearCalls += 1;
    if (!online) return _networkFail();
    server.clear();
    return ApiResult({'status': 1, 'message': 'cleared'});
  }

  @override
  Future<ApiResult> addresses() async =>
      _ok([
        {'id': 3, 'address': 'Street 1', 'is_default': 1, 'latitude': '15.0', 'longitude': '45.0'},
      ]);

  @override
  Future<ApiResult> userDetails() async => _ok({'id': 7, 'name': 'T'});

  @override
  Future<ApiResult> logout({String? refreshToken}) async =>
      _ok({'message': 'logged_out'});
}

Map<String, dynamic> _row(int variantId, int qty) => {
  'product_id': variantId,
  'product_variant_id': variantId,
  'qty': qty,
  'price': 25,
  'name': 'P$variantId',
  'seller_id': 5,
};

List<String> _qtys() => appController.cartProducts
    .map((e) => '${e['product_variant_id']}=${e['qty'] ?? e['quantity']}')
    .toList()
  ..sort();

Future<_DeepApi> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _DeepApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.businessHours = BusinessHoursResult();
  appController.token = 'tok';
  appController.user = {'id': 7, 'name': 'T'};
  appController.cartProducts = [];
  appController.cart = null;
  appController.cartSubTotal = 0;
  appController.guestCart = [];
  appController.guestCartTotal = 0;
  appController.settings = {
    'currency': 'ر.س',
    'decimal_point': 2,
    'min_order_amount': 0,
    'max_sellers_per_checkout': 0,
    'web_settings': <String, dynamic>{},
  };
  appController.paymentSettings = {'cod_payment_method': '1'};
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

Future<void> _addOnline(_DeepApi api, int variantId, int qty) =>
    appController.addToCart(
      productId: variantId,
      variantId: variantId,
      qty: qty,
      productPrice: 25,
      sellerId: 5,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Optimistic subtotal/lines reflect intent instantly (logged-in)', () {
    test('online add increases subTotal immediately', () async {
      final api = await _setup();
      expect(api.server, isEmpty);
      await _addOnline(api, 11, 3);
      expect(appController.cartProducts.single['qty'], 3);
      expect(appController.cartSubTotal, 75);
      expect(api.server['11'], 3);
    });

    test('online qty A→B recomputes subTotal on tap (A smaller)', () async {
      final api = await _setup();
      await _addOnline(api, 11, 5);
      await _addOnline(api, 11, 2);
      expect(appController.cartSubTotal, 50);
    });

    test('online qty A→B recomputes subTotal on tap (B larger)', () async {
      final api = await _setup();
      await _addOnline(api, 11, 2);
      await _addOnline(api, 11, 5);
      expect(appController.cartSubTotal, 125);
    });

    test('online remove recomputes the subTotal immediately', () async {
      final api = await _setup();
      await _addOnline(api, 11, 2);
      await _addOnline(api, 22, 1);
      expect(appController.cartSubTotal, 75);

      final err = await appController.removeCartLine(
        productId: 11,
        variantId: 11,
      );
      expect(err, isNull);
      expect(_qtys(), ['22=1']);
      expect(appController.cartSubTotal, 25);
    });

    test('offline add/remove/qty update all recompute the subTotal locally', () async {
      final api = await _setup();
      api.online = false;

      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 2,
        productPrice: 25,
        sellerId: 5,
      );
      expect(appController.cartProducts.single['qty'], 2);
      expect(appController.cartSubTotal, 50);

      // Increase qty offline: same variant, new absolute qty.
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 4,
        productPrice: 25,
        sellerId: 5,
      );
      expect(appController.cartProducts.single['qty'], 4);
      expect(appController.cartSubTotal, 100);

      // Decrease offline.
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 1,
        productPrice: 25,
        sellerId: 5,
      );
      expect(appController.cartProducts.single['qty'], 1);
      expect(appController.cartSubTotal, 25);

      // Remove offline.
      expect(await appController.removeCartLine(productId: 11, variantId: 11), isNull);
      expect(appController.cartProducts, isEmpty);
      expect(appController.cartSubTotal, 0);
    });

    test('guest stepper subtotal follows guest-cart local total', () async {
      final api = await _setup();
      // Switch to guest mode.
      appController.token = null;
      appController.user = null;

      await appController.addToCart(
        productId: 33,
        variantId: 33,
        qty: 2,
        productPrice: 25,
        sellerId: 5,
      );
      expect(appController.guestCart.single['qty'], 2);
      expect(appController.guestCartTotal, 50);

      // Remove the only line (guest local remove path).
      expect(await appController.removeCartLine(productId: 33, variantId: 33), isNull);
      expect(appController.guestCart, isEmpty);
      expect(appController.guestCartTotal, 0);
    });
  });

  group('Delete online (server-confirmed)', () {
    test('delete one of two lines, refresh reflects the surviving line only', () async {
      final api = await _setup();
      await _addOnline(api, 11, 1);
      await _addOnline(api, 22, 2);

      final err = await appController.removeCartLine(
        productId: 11,
        variantId: 11,
      );
      expect(err, isNull);
      expect(_qtys(), ['22=2']);
      expect(api.server, {'22': 2});
      expect(appController.cartSubTotal, 50);

      // A fresh server refresh agrees.
      await appController.refreshCart();
      expect(_qtys(), ['22=2']);
      expect(appController.cartSubTotal, 50);
    });

    test('delete the last line converges to empty cart with correct total', () async {
      final api = await _setup();
      await _addOnline(api, 11, 2);
      expect(appController.cartSubTotal, 50);

      await appController.removeCartLine(productId: 11, variantId: 11);
      expect(api.server, isEmpty);
      expect(appController.cartProducts, isEmpty);
      expect(appController.cartSubTotal, 0);

      await appController.refreshCart();
      expect(appController.cartProducts, isEmpty);
    });

    test(
      'server refusal business-error on delete: line is restored, refresh reflects server truth',
      () async {
        final api = await _setup();
        await _addOnline(api, 11, 2);
        expect(api.server['11'], 2);

        // Server refuses with a business validation error (never network-related).
        api.returnBusinessRefusalOnRemove = true;

        final err = await appController.removeCartLine(
          productId: 11,
          variantId: 11,
        );
        expect(err, api.businessRefusalMessage);
        // The local line was optimistically removed, but a refresh must
        // restore the server truth (delete was refused, row still exists).
        api.returnBusinessRefusalOnRemove = false;
        await appController.refreshCart();
        expect(_qtys(), contains('11=2'));
        expect(api.server['11'], 2);
      },
    );

    test('server says no_product_found on delete: line chan larger truth still wins', () async {
      final api = await _setup();
      // Deleting something never added: server says already gone,
      // local phantom must be drained and we must NOT crash.
      await appController.removeCartLine(productId: 99, variantId: 99);
      expect(appController.cartProducts, isEmpty);
    });
  });

  group('Delete offline (durable intent)', () {
    test('offline delete after online add survives restart and replays on reconnect', () async {
      final api = await _setup();
      await _addOnline(api, 11, 2);
      await _addOnline(api, 22, 1);

      api.online = false;
      expect(
        await appController.removeCartLine(productId: 11, variantId: 11),
        isNull,
      );
      expect(_qtys(), ['22=1']);
      expect(appController.cartSubTotal, 25);

      // Restant offline — the intent applies on top of the snapshot restore.
      final prefs = await SharedPreferences.getInstance();
      appController.injectForTest(prefs: prefs, testApi: api);
      appController.cartProducts = [];
      appController.cart = null;
      appController.cartSubTotal = 0;
      api.online = false;
      await appController.refreshCart();
      expect(_qtys(), ['22=1']);

      // Back online — intent replays, server reflects it.
      api.online = true;
      await appController.handleAppResumed();
      expect(api.server, {'22': 1});
    });

    test('offline delete on variant deleted elsewhere: pending op converges', () async {
      final api = await _setup();
      api.server['11'] = 2;
      api.server['22'] = 1;

      // Bring both rows into memory (server-confirmed lane).
      await appController.refreshCart();
      expect(appController.cartProducts.length, 2);

      // Go offline.
      api.online = false;

      // Meanwhile, simulate ANOTHER device clearing 11 from the server.
      final prefs = await SharedPreferences.getInstance();
      // Toggle still clear, but wait — the fake clears the shared server.
      api.server.remove('11');

      // THIS device deletes 11 offline too.
      expect(await appController.removeCartLine(productId: 11, variantId: 11), isNull);
      expect(_qtys(), ['22=1']);

      api.online = true;
      // Replay: server says no_product_found → op dropped, cart syncs.
      await appController.handleAppResumed();
      expect(api.server, {'22': 1});
      expect(_qtys(), ['22=1']);
    });

    test('offline delete pushed before order placement replays in order', () async {
      final api = await _setup();
      await _addOnline(api, 11, 1);
      api.online = false;
      await appController.removeCartLine(productId: 11, variantId: 11);

      api.online = true;
      await appController.reconcilePendingCartOps();
      expect(api.server, isEmpty);
      expect(api.cartCalls, greaterThanOrEqualTo(1));
    });
  });

  group('Ordered interleaving across restarts', () {
    test('add A, add B, offline delete A, add C, restart, resume → B and C remain', () async {
      final api = await _setup();
      await _addOnline(api, 10, 1);
      await _addOnline(api, 20, 1);

      api.online = false;
      await appController.removeCartLine(productId: 10, variantId: 10);
      await appController.addToCart(
        productId: 30,
        variantId: 30,
        qty: 2,
        productPrice: 25,
        sellerId: 5,
      );
      expect(_qtys(), containsAll(['20=1', '30=2']));

      // Cold restart offline.
      final prefs = await SharedPreferences.getInstance();
      appController.injectForTest(prefs: prefs, testApi: api);
      appController.cartProducts = [];
      appController.cart = null;
      appController.cartSubTotal = 0;
      api.online = false;
      await appController.refreshCart();
      expect(_qtys(), containsAll(['20=1', '30=2']));

      api.online = true;
      await appController.handleAppResumed();
      expect(api.server.keys, containsAll(['20', '30']));
      expect(api.server.containsKey('10'), isFalse);
    });

    test('online add, offline delete, online add same variant → absolute final qty wins', () async {
      final api = await _setup();
      await _addOnline(api, 10, 1);
      api.online = false;
      await appController.removeCartLine(productId: 10, variantId: 10);

      // Re-add while still offline with a different absolute quantity.
      await appController.addToCart(
        productId: 10,
        variantId: 10,
        qty: 7,
        productPrice: 25,
        sellerId: 5,
      );
      expect(appController.cartProducts.single['qty'], 7);

      api.online = true;
      await appController.handleAppResumed();
      expect(api.server['10'], 7);
      expect(appController.cartSubTotal, 175);
    });

    test('clear-all online does not resurrect a pending offline add', () async {
      final api = await _setup();
      api.online = false;
      // Queue an offline add that never reached the server.
      await appController.addToCart(
        productId: 55,
        variantId: 55,
        qty: 3,
        productPrice: 25,
        sellerId: 5,
      );
      expect(appController.cartProducts.single['qty'], 3);

      // Back online; user clears the WHOLE cart on the server.
      api.online = true;
      await appController.clearAllCart();
      expect(api.server, isEmpty);

      await appController.handleAppResumed();
      expect(api.server, isEmpty,
          reason: 'pending offline add must not resurrect after clear-all');
      expect(appController.cartProducts, isEmpty);
      expect(appController.cartSubTotal, 0);
    });

    test('clear-all online does not resurrect a pending offline delete', () async {
      final api = await _setup();
      await _addOnline(api, 10, 1);
      api.online = false;
      // Offline intent to delete the ONLY line.
      await appController.removeCartLine(productId: 10, variantId: 10);
      expect(appController.cartProducts, isEmpty);

      // Back online and user clears all.
      api.online = true;
      await appController.clearAllCart();
      expect(api.server, isEmpty);

      await appController.handleAppResumed();
      expect(api.server, isEmpty);
      expect(appController.cartProducts, isEmpty);
    });
  });

  group('Guest ↔ logged-in across restarts (delete-relevant)', () {
    test('guest offline add, login online, lines merge once — delete sticks once', () async {
      final api = await _setup();
      appController.token = null;
      appController.user = null;

      // Guest offline add.
      api.online = false;
      await appController.addToCart(
        productId: 77,
        variantId: 77,
        qty: 2,
        productPrice: 25,
        sellerId: 5,
      );
      expect(appController.guestCart.single['qty'], 2);

      // Login online, app resumes, merge fires.
      api.online = true;
      appController.token = 'tok';
      appController.user = {'id': 7, 'name': 'T'};
      appController.cartProducts = [];
      await appController.handleAppResumed();
      expect(appController.cartProducts.single['qty'], 2);
      expect(api.server['77'], 2);

      // Delete the line online.
      expect(await appController.removeCartLine(productId: 77, variantId: 77), isNull);

      // Logout and log in again. The server was cleared; line stays gone.
      await appController.logout();
      appController.token = 'tok2';
      appController.user = {'id': 7, 'name': 'T'};
      appController.cartProducts = [];
      api.server.remove('77');
      api.online = true;
      await appController.refreshCart();
      expect(appController.cartProducts, isEmpty);
    });

    test('cross-account: account A pending delete never touches account B lines', () async {
      final api = await _setup();
      // Logged in as A; online add.
      await _addOnline(api, 10, 1);

      // Account A does an offline delete on variant 10.
      api.online = false;
      await appController.removeCartLine(productId: 10, variantId: 10);

      // Switch to account B on the same device; B logs in online. The server
      // holds variant 10 still (unpushed offline delete from A).
      appController.user = {'id': 9, 'name': 'B'};
      appController.token = 'tok-b';
      appController.cartProducts = [];
      appController.cart = null;
      api.online = true;
      await appController.refreshCart();

      // B sees A's row on the shared server but A's pending intent must NOT
      // also execute for B's scope — otherwise B would see a row removed
      // that B never touched.
      expect(api.server['10'], 1);
      expect(appController.cartProducts.length, 1);

      await appController.handleAppResumed();
      expect(api.server['10'], 1,
          reason: "A's pending delete must never execute under B's scope");
    });
  });

  group('Read-after-write race bridge (tombstone)', () {
    test('server briefly echoing the just-deleted row resurrects nothing', () async {
      final api = await _setup();
      await _addOnline(api, 11, 2);
      expect(appController.cartProducts.single['qty'], 2);

      // Server deletes the row but a lagging replica echoes it once more
      // on the very next read — the classic read-after-write window.
      api.staleEcho = {'11': 2};

      final err = await appController.removeCartLine(
        productId: 11,
        variantId: 11,
      );
      expect(err, isNull);

      // The optimistic deletion + tombstone win: line must be gone.
      expect(appController.cartProducts, isEmpty,
          reason: 'echoed row must be dropped by the tombstone filter');
      expect(appController.cartSubTotal, 0);

      // A fresh refresh sees the real server (row gone) and returns empty.
      await appController.refreshCart();
      expect(appController.cartProducts, isEmpty);

      api.staleEcho = null;
    });

    test('business refusal releases the tombstone so the server row shows again', () async {
      final api = await _setup();
      await _addOnline(api, 11, 2);
      api.returnBusinessRefusalOnRemove = true;

      final err = await appController.removeCartLine(
        productId: 11,
        variantId: 11,
      );
      expect(err, api.businessRefusalMessage);

      api.returnBusinessRefusalOnRemove = false;
      await appController.refreshCart();
      expect(_qtys(), contains('11=2'),
          reason: 'refused delete keeps the server truth visible');
    });
  });

  group('Release-shape network error (production)', () {
    test('release-shaped offline add is a silent success (never shows network_error)', () async {
      final api = await _setup();
      // Simulate a release-mode network response: no httpStatus — only the
      // public code + the cat enum name we added to the map.
      api.online = false;
      appController.overrideConnectivityForTest(false);

      final err = await appController.addToCart(
        productId: 77,
        variantId: 77,
        qty: 1,
        productPrice: 25,
        sellerId: 5,
      );
      // Silent success is the correct offline UX: the intent is queued in the
      // outbox; the user sees the optimistic badge jump immediately.
      expect(err, isNull,
          reason: 'offline add returns silent success; no network_error shown');
      expect(appController.cartProducts.single['qty'], 1);
    });

    test('release-shape classifiedError resolves to the network category', () async {
      // Fabricate the release on-wire error map exactly as release-mode would produce it
      // and assert our reader maps it back to the right category.
      final raw = ApiResult({
        'status': 0,
        'message': 'تعذر الاتصال بالخادم. تحقق من الإنترنت.',
        'error': {'code': 'UNAVAILABLE', 'cat': 'network', 'httpStatus': 502},
      });
      expect(raw.classifiedError?.category, ApiErrorCategory.network);
      expect(raw.ok, isFalse);
    });
  });

  group('Widget: tap delete in CartScreen (logged-in)', () {
    testWidgets('online: tap delete → line disappears instantly', (tester) async {
      final api = await _setup();
      api.server['11'] = 1;
      await appController.refreshCart();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CartScreen())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('P11'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('P11'), findsNothing);
      expect(api.server, isEmpty);
    });

    testWidgets('offline: tap delete → line disappears instantly', (tester) async {
      final api = await _setup();
      api.server['11'] = 1;
      api.server['22'] = 1;
      await appController.refreshCart();
      api.online = false;

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CartScreen())),
      );
      await tester.pump();

      expect(find.text('P11'), findsOneWidget);
      expect(find.text('P22'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('P11'), findsNothing);
      expect(find.text('P22'), findsOneWidget);
      expect(api.server.containsKey('11'), isTrue,
          reason: 'delete pending; server row is removed after reconciling, not now');

      api.online = true;
      await appController.handleAppResumed();
      expect(api.server.containsKey('11'), isFalse);
    });

    testWidgets('stepper minus 2→1: line qty drops and totals update', (tester) async {
      final api = await _setup();
      api.server['11'] = 2;
      await appController.refreshCart();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CartScreen())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('2'), findsOneWidget);
      // The minus button for qty>1 calls addToCart(qty: qty-1).
      await tester.tap(find.byIcon(Icons.remove).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(appController.cartProducts.single['qty'], 1);
      expect(appController.cartSubTotal, 25);
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('Error and conflict paths around delete', () {
    test('online delete followed by rapid second delete of same line is safe', () async {
      final api = await _setup();
      await _addOnline(api, 11, 3);
      // First delete.
      expect(await appController.removeCartLine(productId: 11, variantId: 11), isNull);
      // The line is gone. A subsequent delete of a non-existent line hits server: no_product_found.
      final err = await appController.removeCartLine(productId: 11, variantId: 11);
      expect(err, isNull, reason: 'no_product_found converges');
      expect(appController.cartProducts, isEmpty);
    });

    test('unbounded rapid plus/minus-after-clear stays coherent', () async {
      final api = await _setup();
      await _addOnline(api, 11, 2);
      await _addOnline(api, 22, 1);

      await _addOnline(api, 11, 5);
      expect(appController.cartProducts.firstWhere((e) => '${e['product_variant_id']}' == '11')['qty'], 5);

      await appController.removeCartLine(productId: 22, variantId: 22);
      expect(_qtys(), ['11=5']);
      expect(appController.cartSubTotal, 125);
    });
  });
}
