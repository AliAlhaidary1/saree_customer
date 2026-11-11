import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/catalog_db/catalog_database.dart';
import 'package:drift/drift.dart' show Value;

/// User-visible product-sync behavior as it flows through the real
/// `AppController` singleton — offline-first reads, network refresh, and
/// the automatic catalog reconciliation on reconnect.
class _SyncApi extends CustomerApi {
  _SyncApi() : super(baseUrl: 'http://test.invalid');

  bool online = true;
  final Map<int, Map<String, dynamic>> catalog = {};

  List<Map<String, dynamic>> _rows() => catalog.values
      .map((e) => Map<String, dynamic>.from(e))
      .toList()
    ..sort((a, b) => J.i(a['id']).compareTo(J.i(b['id'])));

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
  Future<ApiResult> products({
    required double latitude,
    required double longitude,
    Map<String, dynamic> filters = const {},
    String tagNames = '',
    String slug = '',
  }) async {
    if (!online) {
      return ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });
    }
    final limit = J.i(filters['limit'], 48);
    final offset = J.i(filters['offset']);
    final rows = _rows();
    final slice =
        offset < rows.length
            ? rows.sublist(
              offset,
              (offset + limit).clamp(0, rows.length),
            )
            : <Map<String, dynamic>>[];
    return ApiResult({
      'status': 1,
      'data': slice,
      'total': rows.length,
    });
  }

  @override
  Future<ApiResult> sellers({
    double? latitude,
    double? longitude,
    int limit = 50,
    int offset = 0,
    String? search,
    String? sort,
    String? type,
    dynamic minRating,
  }) async {
    if (!online) {
      return ApiResult({'status': 0, 'message': 'timeout'});
    }
    return ApiResult({'status': 1, 'data': [], 'total': 0});
  }

  @override
  Future<ApiResult> categories({
    dynamic categoryId,
    dynamic limit,
    dynamic offset,
    String? slug,
  }) async {
    if (!online) {
      return ApiResult({'status': 0, 'message': 'timeout'});
    }
    return ApiResult({'status': 1, 'data': [], 'total': 0});
  }
}

Future<_SyncApi> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _SyncApi();
  final db = await CatalogDatabase.openMemory();
  addTearDown(db.close);
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.setCatalogDbForTest(db);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.businessHours = BusinessHoursResult();
  appController.cartProducts = [];
  appController.cartSubTotal = 0;
  appController.cart = null;
  appController.guestCart = [];
  appController.guestCartTotal = 0;
  // A clean slate for each test: the controller is a global singleton.
  final dao = CatalogDao(db);
  await dao.saveSyncState(
    SyncStatesCompanion.insert(
      scope: 'city:1',
      phase: 'full_complete',
      coverage: const Value('best_effort'),
      lastOffset: const Value(0),
      storedCount: const Value(0),
      updatedAt: DateTime.now(),
    ),
  );
  return api;
}

Map<String, dynamic> _row(int id, String price, {int stock = 5}) => {
      'id': id,
      'name': 'منتج $id',
      'slug': 'p-$id',
      'seller_id': 50,
      'store_name': 'Store',
      'price': price,
      'is_unlimited_stock': 0,
      'average_rating': '4.5',
      'rating_count': 10,
      'created_at': '2026-01-${id.toString().padLeft(2, '0')} 00:00:00',
      'variants': [
        {'id': id * 100, 'price': price, 'stock': stock, 'measurement': '1', 'stock_unit_name': 'لتر'},
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'auto sync on reconnect picks up a NEW backend product (visible offline after)',
    () async {
      final api = await _setup();

      // Server state 1: one product.
      api.catalog[1] = _row(1, '50');
      await appController.syncCatalogNow();
      expect(appController.catalogFilteredCountLocal(), completion(1));

      // Go offline: local cache must keep serving rows (never "empty").
      api.online = false;
      final offlineRows = await appController.catalogProductsLocal(limit: 10);
      expect(offlineRows.length, 1);
      expect(J.i(offlineRows.single['id']), 1);

      // Go online: a new product is added on the backend.
      api.online = true;
      api.catalog[2] = _row(2, '99');
      await appController.syncCatalogNow();

      // Local cache now holds both.
      final rows = await appController.catalogProductsLocal(limit: 10);
      expect(rows.map((r) => J.i(r['id'])), containsAll([1, 2]));

      // Offline again: both visible (no stale "one product only" cache).
      api.online = false;
      final offlineRows2 = await appController.catalogProductsLocal(limit: 10);
      expect(offlineRows2.length, 2);
    },
  );

  test(
    'auto sync on reconnect picks up EDITED price (visible offline after)',
    () async {
      final api = await _setup();
      api.catalog[1] = _row(1, '50');
      await appController.syncCatalogNow();

      api.online = false;
      final before = await appController.catalogProductsLocal(limit: 10);
      final beforePrice =
          J.d((J.maps(before.single['variants']).first)['price']);
      expect(beforePrice, 50.0);

      api.online = true;
      api.catalog[1] = {
        ...api.catalog[1]!,
        'variants': [
          {
            'id': 100,
            'price': '75',
            'stock': 5,
            'measurement': '1',
            'stock_unit_name': 'لتر',
          },
        ],
      };
      await appController.syncCatalogNow();

      api.online = false;
      final after = await appController.catalogProductsLocal(limit: 10);
      expect(J.d((J.maps(after.single['variants']).first)['price']), 75.0);
    },
  );

  test(
    'auto sync on reconnect picks up DELETIONS (unlisted → disappears from list)',
    () async {
      final api = await _setup();
      api.catalog[1] = _row(1, '50');
      api.catalog[2] = _row(2, '99');
      await appController.syncCatalogNow();

      api.online = false;
      final before = await appController.catalogProductsLocal(limit: 10);
      expect(before.length, 2);

      api.online = true;
      api.catalog.remove(1);
      await appController.syncCatalogNow();

      api.online = false;
      final after = await appController.catalogProductsLocal(limit: 10);
      expect(after.length, 1);
      expect(J.i(after.single['id']), 2);
    },
  );

  test(
    'local catalog survives interrupted sync (error mid-walk: rows still readable)',
    () async {
      final api = await _setup();
      api.catalog[1] = _row(1, '50');
      await appController.syncCatalogNow();
      expect((await appController.catalogProductsLocal(limit: 10)).length, 1);

      // Simulate a failed sync mid-walk: kill network and start a NEW scope.
      // Previous committed rows remain readable.
      api.online = false;
      final mutate = await appController.syncCatalogNow();
      expect(
        (await appController.catalogProductsLocal(limit: 10)).length,
        1,
        reason: 'partial sync never trashes committed local rows',
      );
      expect(mutate?.complete ?? false, isFalse);
    },
  );

  test(
    'sync is a no-op when offline and does not corrupt state',
    () async {
      final api = await _setup();
      api.catalog[1] = _row(1, '50');
      await appController.syncCatalogNow();
      api.online = false;
      // Forcing a sync while offline must return quickly without throwing.
      await appController.syncCatalogNow();
      final rows = await appController.catalogProductsLocal(limit: 10);
      expect(rows.length, 1);
    },
  );

  test(
    'NEVER_SYNCED vs EMPTY vs ready classification survives a flaky failure',
    () async {
      final api = await _setup();
      api.online = true;
      // Empty server catalog — sync runs successfully, marks scope ready-with-0.
      final first = await appController.syncCatalogNow();
      expect(first?.complete, isTrue);
      expect(
        await appController.catalogFilteredCountLocal(),
        0,
      );

      // Network error mid-flight records the attempt but does not erase good
      // state.
      api.online = false;
      await appController.syncCatalogNow();
      expect(
        await appController.catalogFilteredCountLocal(),
        0,
      );

      // Ready data returns to the sight after a successful sync.
      api.online = true;
      api.catalog[1] = _row(1, '50');
      final rescan = await appController.syncCatalogNow();
      expect(rescan?.complete, isTrue);
      expect(await appController.catalogFilteredCountLocal(), 1);
    },
  );

  test(
    'cold offline start: products readable without any network request',
    () async {
      final api = await _setup();
      api.catalog[1] = _row(1, '50');
      await appController.syncCatalogNow();
      // Simulate cold start by clearing in-memory state.
      appController.cart = null;
      appController.cartProducts = [];
      appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};

      api.online = false;
      final rows = await appController.catalogProductsLocal(limit: 10);
      expect(rows.length, 1);
      expect(J.str(rows.single['name']), 'منتج 1');
      expect(J.str(rows.single['store_name']), 'Store');
    },
  );

  test(
    'full browse path: local-first show + network refresh paints same page',
    () async {
      final api = await _setup();
      api.catalog[1] = _row(1, '50');
      await appController.syncCatalogNow();
      api.online = true;

      // Local paint is immediate (no network needed) even after online comes
      // back — but the network refresh still goes ahead and gets fresh rows.
      final localFirst = await appController.catalogProductsLocal(limit: 10);
      expect(localFirst.length, 1);

      // Sync refreshes from the live server; edits on the backend land here.
      api.catalog[2] = _row(2, '75');
      await appController.syncCatalogNow();
      final refreshed = await appController.catalogProductsLocal(limit: 10);
      expect(refreshed.map((r) => J.i(r['id'])), containsAll([1, 2]));
    },
  );
}
