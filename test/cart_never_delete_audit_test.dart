import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';

/// Root-cause audit for the user-reported bug:
///   "online add → go fully offline → open cart → tap delete → exit → return
///   → line is back and can never be deleted"
///
/// This audit asserts the three hard invariants the UI relies on:
///   1. `removeCartLine` is always honoured optimistically, even offline.
///   2. The open-cart view never shows the deleted line until connectivity
///      re-confirms the server state.
///   3. After connectivity returns, the line is impossible to resurrect via
///      snapshot restore, via fold, or via cross-account account bleed.
class _AuditApi extends CustomerApi {
  _AuditApi() : super(baseUrl: 'http://test.invalid', token: null);

  bool online = true;
  final Map<String, int> server = {};
  ApiResult? cartResult;

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
    if (cartResult != null) return cartResult!;
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
}

Future<_AuditApi> _setup({required bool online, String uid = '7'}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _AuditApi();
  api.online = online;
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.token = 'tok';
  appController.user = {'id': int.tryParse(uid) ?? 7, 'name': 'T'};
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

List<String> _qtys() => appController.cartProducts
    .map((e) => '${e['product_variant_id']}=${e['qty'] ?? e['quantity']}')
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('remove line invariants — never resurrect a confirmed removal', () {
    test('delete online, exit screen, back — stays gone forever', () async {
      final api = await _setup(online: true);
      // Two items, online cart.
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 2,
        productPrice: 10,
        sellerId: 5,
      );
      await appController.addToCart(
        productId: 22,
        variantId: 22,
        qty: 1,
        productPrice: 20,
        sellerId: 5,
      );
      expect(_qtys(), containsAll(['11=2', '22=1']));

      // Delete online; server rows update.
      await appController.removeCartLine(productId: 11, variantId: 11);
      expect(_qtys(), ['22=1']);
      expect(api.server, {'22': 1});

      // Pull-to-refresh offline — line must never come back.
      api.online = false;
      await appController.refreshCart();
      expect(_qtys(), ['22=1'],
          reason: 'offline refresh must not resurrect a server-confirmed removal');

      // Pull-to-refresh online — line must never come back.
      api.online = true;
      await appController.refreshCart();
      expect(_qtys(), ['22=1'],
          reason: 'online refresh must not resurrect a deleted line');
    });

    test('delete offline, exit, back online — stays gone forever', () async {
      final api = await _setup(online: true);
      await appController.addToCart(
        productId: 11,
        variantId: 11,
        qty: 2,
        productPrice: 10,
        sellerId: 5,
      );
      await appController.addToCart(
        productId: 22,
        variantId: 22,
        qty: 1,
        productPrice: 20,
        sellerId: 5,
      );
      // Fresh cold refresh for the snapshot.
      await appController.refreshCart();
      expect(_qtys(), containsAll(['11=2', '22=1']));

      // Go fully offline.
      api.online = false;

      // Delete while OFFLINE: optimistic removal, durable intent queued.
      final err = await appController.removeCartLine(
        productId: 11,
        variantId: 11,
      );
      expect(err, isNull,
          reason: 'removal is accepted and queued — no dialog');
      expect(_qtys(), ['22=1']);

      // Exit & re-enter cart while offline: line must not reappear.
      await appController.refreshCart();
      expect(_qtys(), ['22=1'],
          reason: 'offline refresh must not resurrect the deleted line');

      // Back online; the pending removal replays.
      api.online = true;
      await appController.handleAppResumed();
      expect(api.server, {'22': 1});
      expect(_qtys(), ['22=1']);
    });

    test(
      'add offline then reconcile then delete then refresh — stays deleted',
      () async {
        final api = await _setup(online: false);
        // Offline add.
        await appController.addToCart(
          productId: 33,
          variantId: 33,
          qty: 1,
          productPrice: 10,
          sellerId: 5,
        );
        expect(_qtys(), ['33=1']);

        // Go online; app resumes; outbox replays the add.
        api.online = true;
        await appController.handleAppResumed();
        expect(api.server, {'33': 1});
        expect(_qtys(), ['33=1']);

        // Delete while online again.
        await appController.removeCartLine(productId: 33, variantId: 33);
        expect(_qtys(), isEmpty);
        expect(api.server, isEmpty);

        // Exit & re-enter — the line must not reappear.
        await appController.refreshCart();
        expect(_qtys(), isEmpty);
      },
    );

    test(
      'add offline + delete offline + re-add then online — final intent wins',
      () async {
        final api = await _setup(online: false);
        await appController.addToCart(
          productId: 44,
          variantId: 44,
          qty: 1,
          productPrice: 10,
          sellerId: 5,
        );
        await appController.removeCartLine(productId: 44, variantId: 44);
        expect(_qtys(), isEmpty);

        // Re-add while still offline — the pending delete/add replaces.
        await appController.addToCart(
          productId: 44,
          variantId: 44,
          qty: 2,
          productPrice: 10,
          sellerId: 5,
        );
        expect(_qtys(), ['44=2']);

        api.online = true;
        await appController.handleAppResumed();
        expect(api.server['44'], 2);

        await appController.refreshCart();
        expect(_qtys(), ['44=2']);
      },
    );
  });
}
