import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/catalog_db/catalog_database.dart';
import 'package:sareemart_customer/core/catalog_store.dart';
import 'package:sareemart_customer/features/products/products_screens.dart';
import 'package:drift/drift.dart' show Value;

class _FailingApi extends CustomerApi {
  _FailingApi() : super(baseUrl: 'http://test.invalid');

  @override
  Future<ApiResult> products({
    required double latitude,
    required double longitude,
    Map<String, dynamic> filters = const {},
    String tagNames = '',
    String slug = '',
  }) async =>
      ApiResult({'status': 0, 'message': 'offline'});
}

Future<void> _setupController(CatalogDatabase db) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  appController.injectForTest(prefs: prefs, testApi: _FailingApi());
  appController.setCatalogDbForTest(db);
  appController.city = {'id': 4};
  appController.catalogSync.progress.value = CatalogSyncProgress();
}

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: ProductsScreen()));
  await tester.pumpAndSettle();
}

void main() {
  group('catalogScopeState', () {
    test('neverSynced with no checkpoint row', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      await _setupController(db);
      final state = await appController.catalogScopeState();
      expect(state.status, CatalogScopeStatus.neverSynced);
    });

    test('syncing while a walk runs for this scope', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      await _setupController(db);
      appController.catalogSync.progress.value = CatalogSyncProgress(
        phase: CatalogSyncPhase.syncing,
        scope: 'city:4',
      );
      final state = await appController.catalogScopeState();
      expect(state.status, CatalogScopeStatus.syncing);
      appController.catalogSync.progress.value = CatalogSyncProgress();
    });

    test('failed after an incomplete walk (rows may still exist)', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      await _setupController(db);
      final dao = CatalogDao(db);
      await dao.upsertProductBatch(
        scope: 'city:4',
        rows: [
          ProductUpsert(serverId: 1, name: 'P1', storeId: 7, payload: '{}')
        ],
        now: DateTime.now(),
      );
      await dao.saveSyncState(SyncStatesCompanion.insert(
        scope: 'city:4',
        phase: 'full_running',
        coverage: const Value('best_effort'),
        lastOffset: const Value(1),
        storedCount: const Value(1),
        updatedAt: DateTime.now(),
      ));
      final state = await appController.catalogScopeState();
      expect(state.status, CatalogScopeStatus.failed);
      expect(state.listedCount, 1);
    });

    test('empty after a clean walk of an empty catalog', () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      await _setupController(db);
      await CatalogDao(db).saveSyncState(SyncStatesCompanion.insert(
        scope: 'city:4',
        phase: 'full_complete',
        coverage: const Value('best_effort'),
        lastOffset: const Value(0),
        storedCount: const Value(0),
        updatedAt: DateTime.now(),
      ));
      final state = await appController.catalogScopeState();
      expect(state.status, CatalogScopeStatus.empty);
    });

    test('ready with rows; stale flag follows the product-list TTL',
        () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      await _setupController(db);
      final dao = CatalogDao(db);
      await dao.upsertProductBatch(
        scope: 'city:4',
        rows: [
          ProductUpsert(serverId: 1, name: 'P1', storeId: 7, payload: '{}')
        ],
        now: DateTime.now(),
      );
      await dao.saveSyncState(SyncStatesCompanion.insert(
        scope: 'city:4',
        phase: 'full_complete',
        coverage: const Value('best_effort'),
        lastOffset: const Value(1),
        storedCount: const Value(1),
        updatedAt: DateTime.now(),
      ));
      final fresh = await appController.catalogScopeState();
      expect(fresh.status, CatalogScopeStatus.ready);
      expect(fresh.stale, isFalse);
      expect(fresh.listedCount, 1);
      // Age the checkpoint beyond the TTL: stale advisory flips.
      await dao.saveSyncState(SyncStatesCompanion.insert(
        scope: 'city:4',
        phase: 'full_complete',
        coverage: const Value('best_effort'),
        lastOffset: const Value(1),
        storedCount: const Value(1),
        updatedAt: DateTime.now().subtract(const Duration(hours: 7)),
      ));
      final aged = await appController.catalogScopeState();
      expect(aged.status, CatalogScopeStatus.ready);
      expect(aged.stale, isTrue);
    });
  });

  group('catalogEmptyMessage', () {
    String t(String key) => 'T:$key';
    test('every status maps distinctly', () {
      expect(catalogEmptyMessage(CatalogScopeStatus.neverSynced, t),
          'T:not_synced_yet');
      expect(catalogEmptyMessage(CatalogScopeStatus.syncing, t),
          'T:catalog_syncing');
      expect(catalogEmptyMessage(CatalogScopeStatus.failed, t),
          'T:catalog_sync_failed');
      expect(catalogEmptyMessage(CatalogScopeStatus.empty, t),
          'T:no_products_found');
      expect(catalogEmptyMessage(CatalogScopeStatus.ready, t),
          'T:no_products_found');
    });
  });

  group('ProductsScreen empty states (widget)', () {
    testWidgets('never-synced scope shows not_synced_yet', (tester) async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      await _setupController(db);
      await _pumpScreen(tester);
      expect(find.text('not_synced_yet'), findsOneWidget);
      expect(find.text('no_products_found'), findsNothing);
    });

    testWidgets('failed scope shows sync-failed copy', (tester) async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      await _setupController(db);
      await CatalogDao(db).saveSyncState(SyncStatesCompanion.insert(
        scope: 'city:4',
        phase: 'full_running',
        coverage: const Value('best_effort'),
        lastOffset: const Value(0),
        storedCount: const Value(0),
        updatedAt: DateTime.now(),
      ));
      await _pumpScreen(tester);
      expect(find.text('catalog_sync_failed'), findsOneWidget);
      expect(find.text('not_synced_yet'), findsNothing);
    });

    testWidgets('genuinely empty catalog shows no_products_found',
        (tester) async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      await _setupController(db);
      await CatalogDao(db).saveSyncState(SyncStatesCompanion.insert(
        scope: 'city:4',
        phase: 'full_complete',
        coverage: const Value('best_effort'),
        lastOffset: const Value(0),
        storedCount: const Value(0),
        updatedAt: DateTime.now(),
      ));
      await _pumpScreen(tester);
      expect(find.text('no_products_found'), findsOneWidget);
      expect(find.text('not_synced_yet'), findsNothing);
    });
  });
}
