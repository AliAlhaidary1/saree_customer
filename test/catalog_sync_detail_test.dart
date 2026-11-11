import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sareemart_customer/core/catalog_db/catalog_database.dart';
import 'package:sareemart_customer/core/catalog_store.dart';
import 'package:sareemart_customer/core/json_util.dart';

/// End-to-end catalog sync coverage:
/// New products appearing, products being edited, products being removed,
/// stores and categories being added/edited/removed â€” through the real
/// [CatalogSyncService] + [CatalogDao], without any HTTP.

class _Backend {
  final Map<int, Map<String, dynamic>> products = {};
  final Map<int, Map<String, dynamic>> stores = {};
  final Map<int, Map<String, dynamic>> categories = {};

  bool failFirstPage = false;

  List<Map<String, dynamic>> _sorted(Map<int, Map<String, dynamic>> m) {
    final rows = m.values.map((e) => Map<String, dynamic>.from(e)).toList();
    rows.sort((a, b) => J.i(a['id']).compareTo(J.i(b['id'])));
    return rows;
  }

  Future<CatalogPage> fetchProducts({required int limit, required int offset}) async {
    if (failFirstPage && offset == 0) {
      return CatalogPage(rows: const [], ok: false, error: 'boom');
    }
    final rows = _sorted(products);
    final slice = offset < rows.length
        ? rows.sublist(offset, (offset + limit).clamp(0, rows.length))
        : <Map<String, dynamic>>[];
    return CatalogPage(rows: slice, total: rows.length);
  }

  Future<CatalogPage> fetchStores({required int limit, required int offset}) async {
    if (failFirstPage && offset == 0) {
      return CatalogPage(rows: const [], ok: false, error: 'boom');
    }
    final rows = _sorted(stores);
    final slice = offset < rows.length
        ? rows.sublist(offset, (offset + limit).clamp(0, rows.length))
        : <Map<String, dynamic>>[];
    return CatalogPage(rows: slice, total: rows.length);
  }

  Future<CatalogPage> fetchCategories({required int limit, required int offset}) async {
    if (failFirstPage && offset == 0) {
      return CatalogPage(rows: const [], ok: false, error: 'boom');
    }
    final rows = _sorted(categories);
    final slice = offset < rows.length
        ? rows.sublist(offset, (offset + limit).clamp(0, rows.length))
        : <Map<String, dynamic>>[];
    return CatalogPage(rows: slice, total: rows.length);
  }
}

Map<String, dynamic> productRow({
  required int id,
  required int storeId,
  String name = 'Product',
  String variantPrice = '100',
  int stock = 10,
  bool unlimited = false,
  bool tag = false,
}) =>
    {
      'id': id,
      'name': '$name $id',
      'slug': 'product-$id',
      'seller_id': storeId,
      'store_name': 'Store $storeId',
      'created_at': '2025-01-${id.toString().padLeft(2, '0')} 00:00:00',
      'status': 1,
      'variants': [
        {
          'id': id * 10,
          'price': variantPrice,
          'stock': stock,
          'is_unlimited_stock': unlimited ? 1 : 0,
        },
      ],
    };

Map<String, dynamic> storeRow(int id, String name) => {
      'id': id,
      'store_name': name,
      'slug': 'store-$id',
      'status': 1,
      'rating': '4.5',
    };

Map<String, dynamic> categoryRow(int id, String name, {int? parent}) => {
      'id': id,
      'name': name,
      'slug': 'category-$id',
      'parent_id': parent,
      'status': 1,
    };

Future<CatalogSyncResult> _runSync(
  _Backend server,
  CatalogDatabase db,
  String scope,
) async {
  final svc = CatalogSyncService();
  final res = await svc.syncScope(
    db: db,
    scope: scope,
    fetchProducts: server.fetchProducts,
    fetchStores: server.fetchStores,
    fetchCategories: server.fetchCategories,
    pageSize: 50,
    storePageSize: 50,
    delay: (_) async {},
  );
  svc.dispose();
  return res;
}

Future<List<Map<String, dynamic>>> listPayload(CatalogDao dao, String scope) async {
  final rows = await dao.listProducts(scope, limit: 100);
  return rows.map((p) => jsonDecode(p.payload) as Map<String, dynamic>).toList();
}

Future<Map<String, dynamic>?> onePayload(CatalogDao dao, String scope, int id) async {
  final row = await dao.getProductById(scope, id);
  if (row == null) return null;
  final payload = jsonDecode(row.payload) as Map<String, dynamic>;
  return payload;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = 'city:1';

  test('new product added on the backend appears after a re-sync', () async {
    final server = _Backend()
      ..products[1] = productRow(id: 1, storeId: 50, variantPrice: '100')
      ..products[2] = productRow(id: 2, storeId: 50, variantPrice: '150');
    final db = await CatalogDatabase.openMemory();
    addTearDown(db.close);
    final dao = CatalogDao(db);

    expect((await _runSync(server, db, scope)).complete, isTrue);
    expect((await listPayload(dao, scope)).map((e) => J.i(e['id'])), [1, 2]);

    // Backend inserts a new product and edits an existing one.
    server.products[3] = productRow(id: 3, storeId: 50, variantPrice: '200');
    server.products[1] = {
      ...server.products[1]!,
      'variants': [
        {'id': 10, 'price': '88', 'stock': 4, 'is_unlimited_stock': 0},
      ],
    };

    expect((await _runSync(server, db, scope)).complete, isTrue);
    final after = await listPayload(dao, scope);
    expect(after.map((e) => J.i(e['id'])), [1, 2, 3]);
    // Edited product reflects the new price snapshot.
    final edited = await onePayload(dao, scope, 1);
    expect(edited, isNotNull);
    final editedPrice = J.d((J.maps(edited!['variants'])).first['price']);
    expect(editedPrice, 88.0);
  });

  test('product removed on the backend disappears from listings but detail stays live',
      () async {
    final server = _Backend()
      ..products[1] = productRow(id: 1, storeId: 50)
      ..products[2] = productRow(id: 2, storeId: 50);
    final db = await CatalogDatabase.openMemory();
    addTearDown(db.close);
    final dao = CatalogDao(db);
    expect((await _runSync(server, db, scope)).complete, isTrue);

    // Server deletes product 2 and changes product 1's name.
    server.products.remove(2);
    server.products[1] = {...server.products[1]!, 'name': 'ط§ط³ظ… ط¬ط¯ظٹط¯ 1'};

    expect((await _runSync(server, db, scope)).complete, isTrue);
    // Reconciliation: removed product is no longer listed.
    final listed = await listPayload(dao, scope);
    expect(listed.map((e) => J.i(e['id'])), [1]);
    // Detail lookup still resolves the unlisted product (detail pages never break).
    final hidden = await dao.getProductById(scope, 2);
    expect(hidden, isNotNull);
    expect(hidden!.isListed, isFalse);
    // FTS search cannot find the unlisted product.
    final search = await dao.searchProducts(scope, 'Product 2');
    expect(search, isEmpty);
    // The edit is in the payload.
    expect((await onePayload(dao, scope, 1))!['name'], 'ط§ط³ظ… ط¬ط¯ظٹط¯ 1');
  });

  test('store edit propagates and deleted store disappears', () async {
    final server = _Backend()
      ..stores[50] = storeRow(50, 'ط§ط³ظ… ط§ظ„ظ…طھط¬ط±')
      ..products[1] = productRow(id: 1, storeId: 50);
    final db = await CatalogDatabase.openMemory();
    addTearDown(db.close);
    final dao = CatalogDao(db);
    expect((await _runSync(server, db, scope)).complete, isTrue);

    // Rename the store and drop a second store after a fresh walk.
    server.stores[50] = storeRow(50, 'ط§ط³ظ… ظ…ط®طھظ„ظپ');
    expect((await _runSync(server, db, scope)).complete, isTrue);
    expect((await dao.getStoreById(scope, 50))!.name, 'ط§ط³ظ… ظ…ط®طھظ„ظپ');

    server.stores.remove(50);
    expect((await _runSync(server, db, scope)).complete, isTrue);
    expect(await dao.getStoreById(scope, 50), isNull);
    // Product remains browsable; its store link is only a reference column.
    final listed = await listPayload(dao, scope);
    expect(listed.map((e) => J.i(e['id'])), [1]);
  });

  test('category added later appears after a re-sync', () async {
    final server = _Backend()
      ..products[1] = productRow(id: 1, storeId: 50)
      ..categories[100] = categoryRow(100, 'طھطµظ†ظٹظپ ظ‚ط¯ظٹظ…');
    final db = await CatalogDatabase.openMemory();
    addTearDown(db.close);
    final dao = CatalogDao(db);
    expect((await _runSync(server, db, scope)).complete, isTrue);

    server.categories[200] = categoryRow(200, 'طھطµظ†ظٹظپ ط¬ط¯ظٹط¯', parent: 100);
    expect((await _runSync(server, db, scope)).complete, isTrue);
    final cats = await dao.listCategories(scope);
    expect(cats.map((c) => c.serverId), containsAll([100, 200]));
  });

  test('variant set change (stock 0 â†’ available) re-syncs from upsert', () async {
    final server = _Backend()
      ..products[7] = productRow(id: 7, storeId: 50, stock: 0);
    final db = await CatalogDatabase.openMemory();
    addTearDown(db.close);
    final dao = CatalogDao(db);
    expect((await _runSync(server, db, scope)).complete, isTrue);
    final stock0 = J.maps((await onePayload(dao, scope, 7))!['variants']).first['stock'];
    expect(J.i(stock0), 0);

    // Stock is replenished on the backend.
    server.products[7] = {
      ...server.products[7]!,
      'variants': [
        {'id': 70, 'price': '100', 'stock': 25, 'is_unlimited_stock': 0},
      ],
    };
    expect((await _runSync(server, db, scope)).complete, isTrue);
    final p = await onePayload(dao, scope, 7);
    expect(p, isNotNull);
    final v = J.maps(p!['variants']);
    expect(v.length, 1);
    expect(J.i(v.first['stock']), 25);
  });
}
