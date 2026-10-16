import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../catalog_db/catalog_database.dart';
import '../catalog_db/sync_cursor.dart';
import '../json_util.dart';

class SyncOrchestrator extends ChangeNotifier {
  SyncOrchestrator({
    required this.db,
    required this.apiClient,
  });

  final CatalogDatabase db;
  final dynamic apiClient;

  final ValueNotifier<bool> isSyncing = ValueNotifier(false);
  final ValueNotifier<String> lastError = ValueNotifier('');
  final ValueNotifier<DateTime?> lastSyncTime = ValueNotifier(null);

  bool _disposed = false;

  void start() {
    unawaited(syncAll());
  }

  Future<void> syncAll() async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    lastError.value = '';

    try {
      final scopes = await _getScopes();
      for (final scope in scopes) {
        if (_disposed) break;
        await _syncScope(scope);
      }
      lastSyncTime.value = DateTime.now();
    } catch (e) {
      lastError.value = '$e';
    } finally {
      isSyncing.value = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<List<String>> _getScopes() async {
    final rows = await db.customSelect('SELECT DISTINCT scope FROM sync_states').get();
    return rows.map((r) => r.data['scope'] as String).toList();
  }

  Future<void> _syncScope(String scope) async {
    final dao = CatalogDao(db);
    final syncState = await dao.getSyncState(scope);
    final lastSync = syncState?.updatedAt;

    await _syncProducts(scope, lastSync);
    await _syncStores(scope, lastSync);
    await _syncCategories(scope, lastSync);
  }

  Future<void> _syncProducts(String scope, DateTime? lastSync) async {
    final dao = CatalogDao(db);
    var cursor = const SyncCursor.start();
    var hasMore = true;
    final now = DateTime.now();

    while (hasMore) {
      final params = <String, dynamic>{
        'limit': 48,
        'sort': 'old',
      };
      if (!cursor.isStart) {
        params['after_created_at'] = cursor.lastCreatedAt;
        params['after_id'] = cursor.lastId;
      }
      if (lastSync != null) {
        params['updated_after'] = lastSync.toIso8601String();
      }

      final response = await apiClient.post('products', data: params);
      if (!response is Map) break;

      final data = response['data'];
      if (data is! List || data.isEmpty) break;

      final batch = <ProductUpsert>[];
      for (final row in data) {
        final up = _productUpsertFromRow(row);
        if (up != null) batch.add(up);
      }

      if (batch.isNotEmpty) {
        await dao.upsertProductBatch(scope: scope, rows: batch, now: now);
      }

      final lastRow = data.last as Map<String, dynamic>;
      final createdAt = J.str(lastRow['created_at']);
      final id = J.i(lastRow['id']);
      if (createdAt.isNotEmpty && id > 0) {
        cursor = cursor.advance(createdAt: createdAt, id: id);
      }

      hasMore = data.length >= 48;
    }

    await dao.saveSyncState(
      SyncStatesCompanion.insert(
        scope: scope,
        phase: 'incremental_complete',
        coverage: const Value('best_effort'),
        lastOffset: const Value(0),
        storedCount: Value(await dao.productCount(scope)),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _syncStores(String scope, DateTime? lastSync) async {
    final dao = CatalogDao(db);
    var offset = 0;
    var hasMore = true;
    final now = DateTime.now();

    while (hasMore) {
      final params = <String, dynamic>{
        'limit': 48,
        'offset': offset,
      };
      if (lastSync != null) {
        params['updated_after'] = lastSync.toIso8601String();
      }

      final response = await apiClient.get('sellers', queryParameters: params);
      if (!response is Map) break;

      final data = response['data'];
      if (data is! List || data.isEmpty) break;

      final companions = <StoresCompanion>[];
      for (final row in data) {
        final c = _storeCompanionFromRow(row, scope, now);
        if (c != null) companions.add(c);
      }

      if (companions.isNotEmpty) {
        await dao.upsertStores(scope: scope, rows: companions);
      }

      hasMore = data.length >= 48;
      offset += data.length;
    }
  }

  Future<void> _syncCategories(String scope, DateTime? lastSync) async {
    final dao = CatalogDao(db);
    var offset = 0;
    var hasMore = true;
    final now = DateTime.now();

    while (hasMore) {
      final params = <String, dynamic>{
        'limit': 100,
        'offset': offset,
      };
      if (lastSync != null) {
        params['updated_after'] = lastSync.toIso8601String();
      }

      final response = await apiClient.get('categories', queryParameters: params);
      if (!response is Map) break;

      final data = response['data'];
      if (data is! List || data.isEmpty) break;

      final companions = <CategoriesCompanion>[];
      for (final row in data) {
        final c = _categoryCompanionFromRow(row, scope, now);
        if (c != null) companions.add(c);
      }

      if (companions.isNotEmpty) {
        await dao.upsertCategories(scope: scope, rows: companions);
      }

      hasMore = data.length >= 100;
      offset += data.length;
    }
  }

  ProductUpsert? _productUpsertFromRow(Map<String, dynamic> row) {
    final id = J.i(row['id'] ?? row['product_id']);
    if (id <= 0) return null;
    final name = J.str(row['name']);
    if (name.isEmpty) return null;

    final storeId = J.i(row['store_id'] ?? row['seller_id']);
    final categoryId = row['category_id'] != null ? J.i(row['category_id']) : null;

    final images = row['images'] is List
        ? List<dynamic>.from(row['images'] as List)
        : const [];
    var thumb = J.str(row['thumbnail'] ?? row['image'] ?? row['thumbnail_url']);
    if (thumb.isEmpty && images.isNotEmpty) {
      final first = images.first;
      thumb = first is Map ? J.str(first['url'] ?? first['image']) : J.str(first);
    }

    final variants = <VariantUpsert>[];
    double? minPrice;
    bool? anyInStock;
    bool? anyOffer;

    if (row['variants'] is List) {
      for (final v in (row['variants'] as List)) {
        if (v is! Map) continue;
        final vm = Map<String, dynamic>.from(v);
        final vid = J.i(vm['id'] ?? vm['variant_id']);
        if (vid <= 0) continue;
        variants.add(VariantUpsert(serverId: vid, payload: jsonEncode(vm)));
        final base = J.d(vm['price']);
        final disc = J.d(vm['discounted_price']);
        final effective = disc > 0 ? disc : base;
        if (effective > 0) {
          minPrice = minPrice == null || effective < minPrice ? effective : minPrice;
        }
        if (J.i(vm['stock']) > 0) anyInStock = true;
        if (disc > 0 && disc < base) anyOffer = true;
      }
    }

    bool? inStock;
    if (J.i(row['is_unlimited_stock']) == 1) {
      inStock = true;
    } else if (anyInStock == true) {
      inStock = true;
    } else if (variants.isNotEmpty) {
      inStock = false;
    }

    bool? hasOffer;
    if (anyOffer == true) {
      hasOffer = true;
    } else {
      final rowOffer = J.flag(row['has_offer']) || J.d(row['discount'] ?? row['discount_percent']) > 0;
      if (rowOffer) {
        hasOffer = true;
      } else if (row.containsKey('has_offer')) {
        hasOffer = false;
      }
    }

    return ProductUpsert(
      serverId: id,
      slug: J.str(row['slug']).isEmpty ? null : J.str(row['slug']),
      name: name,
      storeId: storeId,
      categoryId: categoryId,
      storeName: J.str(row['store_name'] ?? J.map(row['seller'])['name']),
      searchBlob: '$name ${J.str(row['description'])} ${J.str(row['tags'])}',
      priceSnapshot: jsonEncode({
        'price': J.str(row['price'] ?? row['selling_price']),
        'old_price': J.str(row['old_price'] ?? row['mrp']),
      }),
      thumbnailUrl: thumb.isEmpty ? null : thumb,
      rating: J.d(row['rating'] ?? row['avg_rating']),
      status: J.i(row['status'], 1),
      payload: jsonEncode(row),
      variants: variants,
      minPrice: minPrice,
      inStock: inStock,
      hasOffer: hasOffer,
    );
  }

  StoresCompanion? _storeCompanionFromRow(
    Map<String, dynamic> row,
    String scope,
    DateTime now,
  ) {
    final id = J.i(row['id'] ?? row['seller_id'] ?? row['store_id']);
    if (id <= 0) return null;
    final name = J.str(row['name'] ?? row['store_name'] ?? row['shop_name']);
    if (name.isEmpty) return null;

    return StoresCompanion.insert(
      scope: scope,
      serverId: id,
      name: name,
      slug: Value(J.str(row['slug']).isEmpty ? null : J.str(row['slug'])),
      latitude: Value(double.tryParse('${row['latitude'] ?? row['lat'] ?? ''}')),
      longitude: Value(double.tryParse('${row['longitude'] ?? row['lng'] ?? ''}')),
      rating: Value(J.d(row['rating'])),
      status: Value(J.i(row['status'], 1)),
      payload: jsonEncode(row),
      refreshedAt: now,
      lastSeenAt: now,
    );
  }

  CategoriesCompanion? _categoryCompanionFromRow(
    Map<String, dynamic> row,
    String scope,
    DateTime now,
  ) {
    final id = J.i(row['id'] ?? row['category_id']);
    if (id <= 0) return null;
    final name = J.str(row['name']);
    if (name.isEmpty) return null;

    final rawParent = row['parent_id'];
    final parentId = rawParent == null || '$rawParent'.isEmpty || J.i(rawParent) <= 0
        ? null
        : J.i(rawParent);
    final type = J.str(row['type']).isNotEmpty ? J.str(row['type']) : null;

    return CategoriesCompanion.insert(
      scope: scope,
      serverId: id,
      name: name,
      parentId: Value(parentId),
      slug: Value(J.str(row['slug']).isEmpty ? null : J.str(row['slug'])),
      imageUrl: Value(
        J.str(row['image'] ?? row['image_url']).isEmpty
            ? null
            : J.str(row['image'] ?? row['image_url']),
      ),
      rowOrder: Value(J.i(row['row_order'] ?? row['order'] ?? row['position'])),
      type: Value(type),
      refreshedAt: now,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    isSyncing.dispose();
    lastError.dispose();
    lastSyncTime.dispose();
    super.dispose();
  }
}
