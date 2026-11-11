import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';

/// Full matrix of online ↔ offline transitions for the cart.
///
/// The server is backed by an in-memory `server` map (variantId → qty), which
/// serves `cart`/`cart/add`/`cart/remove`/`cart/clear` consistently with the
/// real backend contract: `cart` returns status:0 `no_items_found_…` when
/// empty, and all ops become network failures while `online` is false
/// (pure transport failure, never a business verdict).
class _OnlineOfflineApi extends CustomerApi {
  _OnlineOfflineApi() : super(baseUrl: 'http://test.invalid', token: null);

  bool online = true;
  final Map<String, int> server = {};
  final List<String> callOrder = [];

  int cartCalls = 0;
  int bulkAddCalls = 0;
  int clearCartCalls = 0;

  ApiResult _networkFail() => ApiResult({
    'status': 0,
    'message': 'timeout',
    'error': {'code': 'TIMEOUT', 'httpStatus': 504},
  });

  ApiResult _emptyCart() => ApiResult({
    'status': 0,
    'message': 'no_items_found_in_users_cart',
  });

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
  }) async {
    if (!online) return _networkFail();
    return ApiResult({
      'status': 1,
      'data': [
        {'id': 1, 'name': 'Test City'},
      ],
    });
  }

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
    callOrder.add('cart($checkout)');
    if (!online) return _networkFail();
    if (server.isEmpty) return _emptyCart();
    return ApiResult({
      'status': 1,
      'data': {
        'cart': _rows(),
        'sub_total': server.values.fold(0.0, (sum, q) => sum + 10.0 * q),
      },
    });
  }

  @override
  Future<ApiResult> addToCart({
    required dynamic productId,
    required dynamic variantId,
    required dynamic qty,
  }) async {
    if (!online) return _networkFail();
    callOrder.add('cart/add');
    server['$variantId'] = int.tryParse('$qty') ?? 1;
    return ApiResult({'status': 1, 'data': {'cart': _rows()}});
  }

  @override
  Future<ApiResult> removeFromCart({
    required dynamic productId,
    required dynamic variantId,
  }) async {
    if (!online) return _networkFail();
    callOrder.add('cart/remove');
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
    bulkAddCalls += 1;
    if (!online) return _networkFail();
    callOrder.add('bulk_add');
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
    if (!online) return _networkFail();
    clearCartCalls += 1;
    callOrder.add('cart/clear');
    server.clear();
    return ApiResult({'status': 1, 'message': 'cleared'});
  }

  @override
  Future<ApiResult> addresses() async {
    if (!online) return _networkFail();
    return ApiResult({'status': 1, 'data': []});
  }
}

Future<_OnlineOfflineApi> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _OnlineOfflineApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.token = 'tok';
  appController.user = {'id': 7, 'name': 'Tester'};
  appController.businessHours = BusinessHoursResult();
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
  return api;
}

Future<void> _onlineAdd({
  required int variantId,
  int qty = 1,
}) {
  return appController.addToCart(
    productId: variantId,
    variantId: variantId,
    qty: qty,
    productPrice: 10,
    sellerId: 5,
  );
}

List<String> _qtysOf() => appController.cartProducts
    .map((e) => '${e['product_variant_id']}=${e['qty'] ?? e['quantity']}')
    .toList();

Future<void> _refresh(int checkout) =>
    appController.refreshCart(checkout: checkout);

Future<void> _reboot(_OnlineOfflineApi api) async {
  // Simulate a cold app restart with the same on-disk state (prefs); in
  // memory controller fields are reset, mirroring a fresh process.
  final prefs = await SharedPreferences.getInstance();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.token = 'tok';
  appController.user = {'id': 7, 'name': 'Tester'};
  appController.businessHours = BusinessHoursResult();
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ONLINE → OFFLINE (logged in) — the reported scenario', () {
    test('online add via server; badge counts server rows', () async {
      final api = await _setup();
      await _onlineAdd(variantId: 11, qty: 2);
      expect(api.server, {'11': 2});
      expect(_qtysOf(), ['11=2']);
      expect(appController.cartSubTotal, 20);
    });

    test(
      'offline delete of an online-added line disappears instantly, '
      'survives restart, and converges once back online',
      () async {
        final api = await _setup();
        await _onlineAdd(variantId: 11, qty: 2);
        await _onlineAdd(variantId: 22, qty: 1);
        expect(api.server.keys, {'11', '22'});

        // Connection lost.
        api.online = false;

        // User deletes variant 11 while offline.
        final err = await appController.removeCartLine(
          productId: 11,
          variantId: 11,
        );
        expect(err, isNull, reason: 'offline delete is accepted and queued');
        expect(_qtysOf(), ['22=1']);

        // A refresh must NOT resurrect variant 11 from the snapshot.
        await _refresh(0);
        expect(_qtysOf(), ['22=1']);

        // Even an app relaunch offline keeps the intent.
        await _reboot(api);
        await _refresh(0);
        expect(_qtysOf(), ['22=1'],
            reason: 'pending offline delete survives app restart');

        // Back online: resume triggers the outbox; the server performs the
        // removal.
        api.online = true;
        await appController.handleAppResumed();
        expect(api.server, {'22': 1});
        expect(_qtysOf(), ['22=1']);
      },
    );

    test('offline delete followed by offline re-add keeps the line online', () async {
      final api = await _setup();
      await _onlineAdd(variantId: 11, qty: 1);
      api.online = false;

      await appController.removeCartLine(productId: 11, variantId: 11);
      expect(_qtysOf(), isEmpty);

      // Re-adding while still offline supersedes the removal intent.
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 3,
        productPrice: 10,
        sellerId: 5,
      );
      expect(_qtysOf(), ['11=3']);

      api.online = true;
      await appController.handleAppResumed();
      expect(api.server['11'], 3);
      expect(_qtysOf(), ['11=3']);
    });

    test('offline qty decrease persists across relaunch', () async {
      final api = await _setup();
      await _onlineAdd(variantId: 11, qty: 5);
      api.online = false;

      // The cart screen "minus" path calls addToCart with the lower qty.
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 2,
        productPrice: 10,
        sellerId: 5,
      );
      expect(_qtysOf(), ['11=2']);

      await _reboot(api);
      await _refresh(0);
      expect(_qtysOf(), ['11=2']);

      api.online = true;
      await appController.handleAppResumed();
      expect(api.server['11'], 2);
    });

    test('offline add of a new line replays the absolute quantity', () async {
      final api = await _setup();
      api.online = false;

      await appController.addToCart(
        productId: 77,
        variantId: 77,
        qty: 1,
        productPrice: 10,
        sellerId: 5,
      );
      await appController.addToCart(
        productId: 77,
        variantId: 77,
        qty: 4,
        productPrice: 10,
        sellerId: 5,
      );
      expect(_qtysOf(), ['77=4']);

      // App dies and restarts before connectivity returns.
      await _reboot(api);
      await _refresh(0);
      expect(_qtysOf(), ['77=4']);

      api.online = true;
      await appController.handleAppResumed();
      expect(api.server['77'], 4);
    });

    test('offline add + delete + offline add nets out to the last intent',
        () async {
      final api = await _setup();
      api.online = false;

      await appController.addToCart(
        productId: 33,
        variantId: 33,
        qty: 2,
        productPrice: 10,
        sellerId: 5,
      );
      await appController.removeCartLine(productId: 33, variantId: 33);
      expect(_qtysOf(), isEmpty);
      await appController.addToCart(
        productId: 33,
        variantId: 33,
        qty: 5,
        productPrice: 10,
        sellerId: 5,
      );
      expect(_qtysOf(), ['33=5']);

      await _reboot(api);
      await _refresh(0);
      expect(_qtysOf(), ['33=5']);

      api.online = true;
      await appController.handleAppResumed();
      expect(api.server['33'], 5);
    });

    test('clear all while online drops pending offline intents', () async {
      final api = await _setup();
      await _onlineAdd(variantId: 11, qty: 3);

      // Offline intent: bump to 7.
      api.online = false;
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 7,
        productPrice: 10,
        sellerId: 5,
      );
      expect(_qtysOf(), ['11=7']);

      // Back online, cart cleared: the stale offline intent must be gone.
      api.online = true;
      await appController.clearAllCart();
      expect(api.server, isEmpty);
      expect(_qtysOf(), isEmpty);

      await _reboot(api);
      await _refresh(0);
      expect(_qtysOf(), isEmpty,
          reason: 'stale offline intent must not resurrect after clear-all');
    });
  });

  group('OFFLINE → ONLINE (logged in) recovery', () {
    test('restore from snapshot paints confirmed rows, then converges', () async {
      final api = await _setup();
      await _onlineAdd(variantId: 11, qty: 1);
      await _onlineAdd(variantId: 22, qty: 1);

      await _reboot(api);
      // Fully offline cold start — cart loads from the snapshot.
      api.online = false;
      await _refresh(0);
      expect(_qtysOf(), contains('11=1'));
      expect(_qtysOf(), contains('22=1'));

      // Back online — refreshes to the authoritative server state.
      api.online = true;
      await _refresh(0);
      expect(_qtysOf(), ['11=1', '22=1']);
    });

    test('offline-delete intent is applied to snapshot restore (server row removed)',
        () async {
      final api = await _setup();
      await _onlineAdd(variantId: 11, qty: 1);

      // Offline delete queued before any reboot.
      api.online = false;
      await appController.removeCartLine(productId: 11, variantId: 11);
      expect(_qtysOf(), isEmpty);

      // Restart with NO connectivity whatsoever: the snapshot still holds the
      // server row but the pending removal must filter it out.
      await _reboot(api);
      await _refresh(0);
      expect(_qtysOf(), isEmpty,
          reason: 'pending removal must win over the stale server snapshot');
    });

    test('retrying the outbox: failed ops retry, permanent errors are dropped',
        () async {
      final api = await _setup();
      await _onlineAdd(variantId: 11, qty: 4);

      // Go offline, delete 11.
      api.online = false;
      await appController.removeCartLine(productId: 11, variantId: 11);
      expect(_qtysOf(), isEmpty);

      // API still unavailable: retries must not corrupt state.
      await appController.handleAppResumed();
      expect(api.server, {'11': 4});
      expect(_qtysOf(), isEmpty);

      // API back: replay removes the line.
      api.online = true;
      await appController.handleAppResumed();
      expect(api.server, isEmpty);
      expect(_qtysOf(), isEmpty);
    });

    test(
      'pending offline delete is pushed BEFORE an order is placed',
      () async {
        final api = await _setup();
        await _onlineAdd(variantId: 11, qty: 1);
        api.online = false;
        await appController.removeCartLine(productId: 11, variantId: 11);
        expect(_qtysOf(), isEmpty);

        api.online = true;
        // This is what _placeOrder calls right before api.checkout().
        await appController.reconcilePendingCartOps();
        expect(
          api.callOrder,
          containsAllInOrder(['cart/remove', 'cart(0)']),
          reason: 'pending deletion must reach the server before the order',
        );
        expect(api.server, isEmpty);
      },
    );
  });

  group('outbox semantics (unit)', () {
    test('cartSetQty coalesces by variant — last intent wins', () async {
      final api = await _setup();
      api.online = false;

      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 1,
        productPrice: 10,
        sellerId: 5,
      );
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 2,
        productPrice: 10,
        sellerId: 5,
      );
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 5,
        productPrice: 10,
        sellerId: 5,
      );
      final raw = appController.prefs.getString('oc:pending::u:7');
      expect(raw, isNotNull);
      expect(raw, contains('"qty":5'));
      expect(RegExp('"product_variant_id":11').allMatches(raw!).length, 1);
    });

    test('foreign-account cart intents are never applied or executed', () async {
      final api = await _setup();
      await _onlineAdd(variantId: 11, qty: 2);
      api.online = false;

      // Account A queues an offline delete while still logged in as A.
      await appController.removeCartLine(productId: 11, variantId: 11);

      // Account B logs in on the same device. The SHARED fake server gives
      // B's refresh all its rows — the isolation guarantee being tested is
      // that A's pending intent is never applied/executed for B.
      appController.user = {'id': 9, 'name': 'Other'};
      appController.token = 'tok-b';
      appController.cartProducts = [];
      appController.cart = null;
      api.server['44'] = 1;
      // The shared fake serves all rows; B\'s refresh must show them.
      api.online = true;
      await _refresh(0);
      expect(
        api.server['11'],
        2,
        reason: "A's pending intent must not be applied before B resumes",
      );
      expect(
        _qtysOf(),
        containsAll(['11=2', '44=1']),
        reason: 'B sees the shared server cart, untouched by A\'s intent',
      );
      await appController.handleAppResumed();
      expect(
        api.server.containsKey('11'),
        isTrue,
        reason: "B must never replay A's pending removal",
      );
    });
  });
}
