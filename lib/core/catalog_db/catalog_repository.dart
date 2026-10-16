import 'dart:async';
import 'dart:convert';

import 'catalog_database.dart';

class CatalogRepository {
  CatalogRepository(this._db);

  final CatalogDatabase _db;

  Future<List<Map<String, dynamic>>> getProducts({
    required String scope,
    int? categoryId,
    int? storeId,
    String search = '',
    String sort = '',
    double? priceMin,
    double? priceMax,
    double? minRating,
    bool inStockOnly = false,
    bool offersOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await CatalogDao(_db).queryProducts(
      scope,
      categoryId: categoryId,
      storeId: storeId,
      search: search,
      sort: sort,
      priceMin: priceMin,
      priceMax: priceMax,
      minRating: minRating,
      inStockOnly: inStockOnly,
      offersOnly: offersOnly,
      limit: limit,
      offset: offset,
    );
    return rows.map(_productToMap).toList();
  }

  Future<int> countProducts({
    required String scope,
    int? categoryId,
    int? storeId,
    String search = '',
    double? priceMin,
    double? priceMax,
    double? minRating,
    bool inStockOnly = false,
    bool offersOnly = false,
  }) async {
    return CatalogDao(_db).countProducts(
      scope,
      categoryId: categoryId,
      storeId: storeId,
      search: search,
      priceMin: priceMin,
      priceMax: priceMax,
      minRating: minRating,
      inStockOnly: inStockOnly,
      offersOnly: offersOnly,
    );
  }

  Future<Map<String, dynamic>?> getProductById(String scope, int serverId) async {
    final row = await CatalogDao(_db).getProductById(scope, serverId);
    if (row == null) return null;
    final variants = await CatalogDao(_db).variantsForProduct(scope, serverId);
    final map = _productToMap(row);
    map['variants'] = variants
        .map((v) => jsonDecode(v.payload) as Map<String, dynamic>)
        .toList();
    return map;
  }

  Future<Map<String, dynamic>?> getProductBySlug(String scope, String slug) async {
    final row = await CatalogDao(_db).getProductBySlug(scope, slug);
    if (row == null) return null;
    final variants = await CatalogDao(_db).variantsForProduct(scope, row.serverId);
    final map = _productToMap(row);
    map['variants'] = variants
        .map((v) => jsonDecode(v.payload) as Map<String, dynamic>)
        .toList();
    return map;
  }

  Future<List<Map<String, dynamic>>> getStores({
    required String scope,
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await CatalogDao(_db).listStores(scope, limit: limit, offset: offset);
    return rows.map(_storeToMap).toList();
  }

  Future<Map<String, dynamic>?> getStoreById(String scope, int serverId) async {
    final row = await CatalogDao(_db).getStoreById(scope, serverId);
    return row == null ? null : _storeToMap(row);
  }

  Future<Map<String, dynamic>?> getStoreBySlug(String scope, String slug) async {
    final row = await CatalogDao(_db).getStoreBySlug(scope, slug);
    return row == null ? null : _storeToMap(row);
  }

  Future<List<Map<String, dynamic>>> getCategories({
    required String scope,
    String? type,
  }) async {
    final dao = CatalogDao(_db);
    final rows = await dao.listCategories(scope);
    final maps = rows.map(_categoryToMap).toList();
    if (type != null) {
      return maps.where((m) => m['type'] == type).toList();
    }
    return maps;
  }

  Future<List<Map<String, dynamic>>> searchProducts({
    required String scope,
    required String query,
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await CatalogDao(_db).searchProducts(scope, query, limit: limit, offset: offset);
    return rows.map(_productToMap).toList();
  }

  Future<int> getProductCount(String scope) async {
    return CatalogDao(_db).productCount(scope);
  }

  Future<int> getSectionCount(String scope) async {
    return CatalogDao(_db).sectionHarajCount(scope, 'section');
  }

  Future<int> getHarajCount(String scope) async {
    return CatalogDao(_db).sectionHarajCount(scope, 'haraj');
  }

  Map<String, dynamic> _productToMap(Product p) {
    final payload = jsonDecode(p.payload) as Map<String, dynamic>;
    payload['local_image_path'] = p.localImagePath;
    payload['min_price'] = p.minPrice;
    payload['in_stock'] = p.inStock;
    payload['has_offer'] = p.hasOffer;
    payload['is_listed'] = p.isListed;
    return payload;
  }

  Map<String, dynamic> _storeToMap(Store s) {
    return jsonDecode(s.payload) as Map<String, dynamic>;
  }

  Map<String, dynamic> _categoryToMap(Category c) {
    return {
      'id': c.serverId,
      'name': c.name,
      'slug': c.slug,
      'parent_id': c.parentId,
      'image': c.imageUrl,
      'row_order': c.rowOrder,
      'type': c.type,
    };
  }
}
