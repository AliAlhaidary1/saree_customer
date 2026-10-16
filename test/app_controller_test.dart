import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/auth/token_vault.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/offline/local_store.dart';
import 'package:sareemart_customer/core/offline/offline_cache.dart';
import 'package:sareemart_customer/core/offline/pending_ops.dart';
import 'package:sareemart_customer/core/offline/sync_engine.dart';

class _FakeApi extends CustomerApi {
  _FakeApi() : super(baseUrl: 'http://test', token: null);

  bool addFavoriteCalled = false;
  bool removeFavoriteCalled = false;
  bool bulkAddToCartCalled = false;
  ApiResult addResult = ApiResult({'status': 0, 'message': 'network'});
  ApiResult removeResult = ApiResult({'status': 0, 'message': 'error'});

  @override
  Future<ApiResult> addFavorite(dynamic productId) async {
    addFavoriteCalled = true;
    return addResult;
  }

  @override
  Future<ApiResult> removeFavorite(dynamic productId) async {
    removeFavoriteCalled = true;
    return removeResult;
  }

  @override
  Future<ApiResult> bulkAddToCart({required String variantIds, required String quantities}) async {
    bulkAddToCartCalled = true;
    return ApiResult({'status': 0, 'message': 'error'});
  }

  ApiResult loginResult = ApiResult({'status': 0, 'message': 'invalid'});

  @override
  Future<ApiResult> loginMobile(
      {required String mobile,
      required String password,
      String fcm = '',
      String countryCode = '967'}) async {
    return loginResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppController> freshController() async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final c = AppController();
    c.vault = TokenVault(prefs: p);
    c.store = LocalStore(p);
    c.api = _FakeApi();
    return c;
  }

  Future<AppController> loginController() async {
    final c = await freshController();
    c.offline = OfflineCache(c.store);
    c.sync = SyncEngine(
      outboxForCurrentScope: () => PendingOutbox(c.store, c.accountScope),
    );
    return c;
  }

  group('runPendingOp', () {
    test('favoriteAdd treats "already favorite" as success', () async {
      final c = await freshController();
      final fake = c.api as _FakeApi;
      fake.addResult = ApiResult({
        'status': 0,
        'message': 'product already added as favorite',
      });
      final done = await c.runPendingOp(PendingOp(
        id: '1',
        type: PendingOpType.favoriteAdd,
        payload: {'product_id': '5'},
        createdAt: DateTime.now(),
      ));
      expect(done, isTrue);
      expect(fake.addFavoriteCalled, isTrue);
    });

    test('favoriteAdd retries on network/server failures', () async {
      final c = await freshController();
      final fake = c.api as _FakeApi;
      fake.addResult = ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504, 'publicCode': 'TIMEOUT'},
      });
      final done = await c.runPendingOp(PendingOp(
        id: '1',
        type: PendingOpType.favoriteAdd,
        payload: {'product_id': '5'},
        createdAt: DateTime.now(),
      ));
      expect(done, isFalse);
    });

    test('favoriteRemove replays with a valid product id', () async {
      final c = await freshController();
      final fake = c.api as _FakeApi;
      fake.removeResult = ApiResult({'status': 1, 'data': []});
      final done = await c.runPendingOp(PendingOp(
        id: '1',
        type: PendingOpType.favoriteRemove,
        payload: {'product_id': '5'},
        createdAt: DateTime.now(),
      ));
      expect(fake.removeFavoriteCalled, isTrue);
      expect(done, isTrue);
    });

    test('favoriteRemove treats already-removed as converged', () async {
      final c = await freshController();
      final fake = c.api as _FakeApi;
      fake.removeResult =
          ApiResult({'status': 0, 'message': 'no_product_found'});
      final done = await c.runPendingOp(PendingOp(
        id: '1',
        type: PendingOpType.favoriteRemove,
        payload: {'product_id': '5'},
        createdAt: DateTime.now(),
      ));
      expect(fake.removeFavoriteCalled, isTrue);
      expect(done, isTrue);
    });

    test('favoriteRemove retries on transient failure', () async {
      final c = await freshController();
      final fake = c.api as _FakeApi;
      fake.removeResult = ApiResult({'status': 0, 'message': 'timeout'});
      final done = await c.runPendingOp(PendingOp(
        id: '1',
        type: PendingOpType.favoriteRemove,
        payload: {'product_id': '5'},
        createdAt: DateTime.now(),
      ));
      expect(fake.removeFavoriteCalled, isTrue);
      expect(done, isFalse);
    });

    test('favoriteRemove with empty product id is dropped, never executed',
        () async {
      final c = await freshController();
      final fake = c.api as _FakeApi;
      for (final bad in ['', 'null', null]) {
        fake.removeFavoriteCalled = false;
        final done = await c.runPendingOp(PendingOp(
          id: '1',
          type: PendingOpType.favoriteRemove,
          payload: {'product_id': bad},
          createdAt: DateTime.now(),
        ));
        expect(done, isTrue);
        expect(fake.removeFavoriteCalled, isFalse);
      }
    });

    test('favoriteRemove from another account scope is dropped', () async {
      final c = await freshController();
      final fake = c.api as _FakeApi;
      final done = await c.runPendingOp(PendingOp(
        id: '1',
        type: PendingOpType.favoriteRemove,
        payload: {'product_id': '5', 'account_scope': 'u:999'},
        createdAt: DateTime.now(),
      ));
      // Controller scope here is guest; op belongs to u:999.
      expect(done, isTrue);
      expect(fake.removeFavoriteCalled, isFalse);
    });

    test('guestCartMerge is drained without calling bulkAddToCart', () async {
      final c = await freshController();
      final fake = c.api as _FakeApi;
      final done = await c.runPendingOp(PendingOp(
        id: '1',
        type: PendingOpType.guestCartMerge,
        payload: {'variant_ids': '1,2', 'quantities': '1,1'},
        createdAt: DateTime.now(),
      ));
      expect(done, isTrue);
      expect(fake.bulkAddToCartCalled, isFalse);
    });
  });

  group('login completion (D1)', () {
    setUp(() {
      FlutterSecureStoragePlatform.instance =
          TestFlutterSecureStoragePlatform({});
    });

    Map<String, dynamic> serverLoginShape() => {
          'status': 1,
          'message': 'ok',
          'total': 1,
          'data': {
            'user': {'id': 81, 'name': 'T', 'mobile': '780000001'},
            'access_token': 'jwt-for-tests',
            'session_max_age': 3600,
          },
        };

    test('ApiResult.token reads nested data.access_token', () {
      final res = ApiResult(serverLoginShape());
      expect(res.ok, isTrue);
      expect(res.token, 'jwt-for-tests');
    });

    test('successful login persists token, sets header, normalizes user id',
        () async {
      final c = await loginController();
      final fake = c.api as _FakeApi;
      fake.loginResult = ApiResult(serverLoginShape());
      final message = await c.login(mobile: '780000001', password: 'x');
      expect(message, isNull);
      expect(c.token, 'jwt-for-tests');
      expect(c.user?['id'], 81);
      expect(c.accountScope, 'u:81');
      expect(await c.vault.read(), 'jwt-for-tests');
    });

    test('invalid credentials return the message and set no session',
        () async {
      final c = await loginController();
      final fake = c.api as _FakeApi;
      fake.loginResult =
          ApiResult({'status': 0, 'message': 'invalid_mobile_or_password'});
      final message = await c.login(mobile: '780000001', password: 'wrong');
      expect(message, 'invalid_mobile_or_password');
      expect(c.token, isNull);
      expect(c.isLoggedIn, isFalse);
    });

    test('missing token surfaces StateError instead of half session',
        () async {
      final c = await loginController();
      final fake = c.api as _FakeApi;
      fake.loginResult = ApiResult({'status': 1, 'data': {}});
      expect(() => c.login(mobile: '780000001', password: 'x'),
          throwsA(isA<StateError>()));
      expect(c.token, isNull);
    });

    test('repeated logins each complete and keep the latest session',
        () async {
      final c = await loginController();
      final fake = c.api as _FakeApi;
      fake.loginResult = ApiResult(serverLoginShape());
      expect(await c.login(mobile: '780000001', password: 'x'), isNull);
      expect(await c.login(mobile: '780000001', password: 'x'), isNull);
      expect(c.token, 'jwt-for-tests');
      expect(c.user?['id'], 81);
    });

    test('restored vault token validates into a user session', () async {
      final c = await loginController();
      final fake = c.api as _FakeApi;
      fake.loginResult = ApiResult(serverLoginShape());
      expect(await c.login(mobile: '780000001', password: 'x'), isNull);
      // New controller sharing the same secure storage sees the token.
      final c2 = await freshController();
      expect(await c2.vault.read(), 'jwt-for-tests');
    });
  });

  group('favorite outbox last-writer-wins (D3)', () {
    List<PendingOp> queued(AppController c) =>
        PendingOutbox(c.store, c.accountScope).load();

    test('stale queued remove is cancelled by a successful add', () async {
      final c = await loginController();
      final fake = c.api as _FakeApi;
      c.token = 't';
      c.favoriteIds = [37];
      // Offline remove: direct call fails, remove is queued.
      fake.removeResult = ApiResult({'status': 0, 'message': 'timeout'});
      await c.toggleFavorite(37);
      expect(queued(c).length, 1);
      expect(queued(c).single.type, PendingOpType.favoriteRemove);
      // Back online: direct add succeeds; the stale remove must go.
      fake.addResult = ApiResult({'status': 1});
      await c.toggleFavorite(37);
      expect(c.isFavorite(37), isTrue);
      expect(queued(c), isEmpty);
    });

    test('stale queued add is cancelled by a successful remove', () async {
      final c = await loginController();
      final fake = c.api as _FakeApi;
      c.token = 't';
      // Offline add: direct call fails, add is queued.
      fake.addResult = ApiResult({'status': 0, 'message': 'timeout'});
      await c.toggleFavorite(38);
      expect(queued(c).single.type, PendingOpType.favoriteAdd);
      // Back online: direct remove succeeds; the stale add must go.
      c.favoriteIds = [38];
      fake.removeResult = ApiResult({'status': 1});
      await c.toggleFavorite(38);
      expect(c.isFavorite(38), isFalse);
      expect(queued(c), isEmpty);
    });

    test('offline add/remove/add coalesces to a single add', () async {
      final c = await loginController();
      final fake = c.api as _FakeApi;
      c.token = 't';
      fake.addResult = ApiResult({'status': 0, 'message': 'timeout'});
      fake.removeResult = ApiResult({'status': 0, 'message': 'timeout'});
      await c.toggleFavorite(39); // add queued
      await c.toggleFavorite(39); // remove queued (coalesced)
      await c.toggleFavorite(39); // add queued (coalesced)
      final ops = queued(c);
      expect(ops.length, 1);
      expect(ops.single.type, PendingOpType.favoriteAdd);
      expect('${ops.single.payload['product_id']}', '39');
    });

    test('unrelated products keep their retry guarantees', () async {
      final c = await loginController();
      final fake = c.api as _FakeApi;
      c.token = 't';
      fake.removeResult = ApiResult({'status': 0, 'message': 'timeout'});
      fake.addResult = ApiResult({'status': 0, 'message': 'timeout'});
      c.favoriteIds = [37, 38];
      await c.toggleFavorite(37); // remove queued for 37
      await c.toggleFavorite(38); // remove queued for 38
      expect(queued(c).length, 2);
      // Successful add for 37 cancels only 37's remove.
      fake.addResult = ApiResult({'status': 1});
      await c.toggleFavorite(37);
      final ops = queued(c);
      expect(ops.length, 1);
      expect('${ops.single.payload['product_id']}', '38');
    });
  });
}
