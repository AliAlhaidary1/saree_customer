import 'dart:async';

import 'package:flutter/foundation.dart';

import '../catalog_db/catalog_database.dart';
import '../json_util.dart';

class CartItem {
  CartItem({
    required this.productId,
    required this.variantId,
    required this.qty,
    required this.sellerId,
    required this.name,
    required this.imageUrl,
    required this.price,
    this.variantLabel,
    this.slug,
    this.stock,
    this.totalStock,
    this.isUnlimitedStock,
    this.stockStatus,
    this.totalAllowedQuantity,
    this.savedAmount,
  });

  final int productId;
  final int variantId;
  final int qty;
  final int sellerId;
  final String name;
  final String imageUrl;
  final double price;
  final String? variantLabel;
  final String? slug;
  final int? stock;
  final int? totalStock;
  final bool? isUnlimitedStock;
  final String? stockStatus;
  final int? totalAllowedQuantity;
  final double? savedAmount;

  Map<String, dynamic> toMap() => {
        'product_id': productId,
        'product_variant_id': variantId,
        'qty': qty,
        'seller_id': sellerId,
        'name': name,
        'image_url': imageUrl,
        'price': price,
        'variant_label': variantLabel,
        'slug': slug,
        'stock': stock,
        'total_stock': totalStock,
        'is_unlimited_stock': isUnlimitedStock,
        'stock_status': stockStatus,
        'total_allowed_quantity': totalAllowedQuantity,
        'saved_amount': savedAmount,
      };

  static CartItem fromMap(Map<String, dynamic> m) => CartItem(
        productId: J.i(m['product_id']),
        variantId: J.i(m['product_variant_id']),
        qty: J.i(m['qty'], 1),
        sellerId: J.i(m['seller_id']),
        name: J.str(m['name']),
        imageUrl: J.str(m['image_url']),
        price: J.d(m['price']),
        variantLabel: m['variant_label']?.toString(),
        slug: m['slug']?.toString(),
        stock: m['stock'] != null ? J.i(m['stock']) : null,
        totalStock: m['total_stock'] != null ? J.i(m['total_stock']) : null,
        isUnlimitedStock: m['is_unlimited_stock'] == true || J.i(m['is_unlimited_stock']) == 1,
        stockStatus: m['stock_status']?.toString(),
        totalAllowedQuantity: m['total_allowed_quantity'] != null ? J.i(m['total_allowed_quantity']) : null,
        savedAmount: m['saved_amount'] != null ? J.d(m['saved_amount']) : null,
      );

  CartItem copyWith({int? qty}) => CartItem(
        productId: productId,
        variantId: variantId,
        qty: qty ?? this.qty,
        sellerId: sellerId,
        name: name,
        imageUrl: imageUrl,
        price: price,
        variantLabel: variantLabel,
        slug: slug,
        stock: stock,
        totalStock: totalStock,
        isUnlimitedStock: isUnlimitedStock,
        stockStatus: stockStatus,
        totalAllowedQuantity: totalAllowedQuantity,
        savedAmount: savedAmount,
      );
}

class LocalCartRepository extends ChangeNotifier {
  LocalCartRepository(this._db);

  final CatalogDatabase _db;
  final List<CartItem> _items = [];
  bool _loaded = false;

  List<CartItem> get items => List.unmodifiable(_items);
  int get itemCount => _items.fold(0, (sum, item) => sum + item.qty);
  double get subtotal => _items.fold(0.0, (sum, item) => sum + item.price * item.qty);
  bool get isEmpty => _items.isEmpty;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final rows = await _db.customSelect(
      'SELECT * FROM cart_items ORDER BY added_at DESC',
    ).get();
    _items.clear();
    for (final row in rows) {
      final data = row.data;
      _items.add(CartItem(
        productId: J.i(data['product_id']),
        variantId: J.i(data['variant_id']),
        qty: J.i(data['qty'], 1),
        sellerId: J.i(data['seller_id']),
        name: J.str(data['name']),
        imageUrl: J.str(data['image_url']),
        price: J.d(data['price']),
        variantLabel: data['variant_label'] as String?,
        slug: data['slug'] as String?,
        stock: data['stock'] as int?,
        totalStock: data['total_stock'] as int?,
        isUnlimitedStock: (data['is_unlimited_stock'] as int?) == 1,
        stockStatus: data['stock_status'] as String?,
        totalAllowedQuantity: data['total_allowed_quantity'] as int?,
        savedAmount: data['saved_amount'] as double?,
      ));
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> addItem(CartItem item) async {
    final existingIndex = _items.indexWhere(
      (i) => i.productId == item.productId && i.variantId == item.variantId,
    );
    if (existingIndex >= 0) {
      final existing = _items[existingIndex];
      final newQty = existing.qty + item.qty;
      _items[existingIndex] = existing.copyWith(qty: newQty);
      await _db.customStatement(
        'UPDATE cart_items SET qty = ? WHERE product_id = ? AND variant_id = ?',
        [newQty, item.productId, item.variantId],
      );
    } else {
      _items.add(item);
      await _db.customStatement(
        'INSERT OR REPLACE INTO cart_items '
        '(product_id, variant_id, qty, seller_id, name, image_url, price, '
        'variant_label, slug, stock, total_stock, is_unlimited_stock, '
        'stock_status, total_allowed_quantity, saved_amount, added_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          item.productId,
          item.variantId,
          item.qty,
          item.sellerId,
          item.name,
          item.imageUrl,
          item.price,
          item.variantLabel,
          item.slug,
          item.stock,
          item.totalStock,
          item.isUnlimitedStock == true ? 1 : 0,
          item.stockStatus,
          item.totalAllowedQuantity,
          item.savedAmount,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
    }
    notifyListeners();
  }

  Future<void> updateQty(int productId, int variantId, int qty) async {
    final index = _items.indexWhere(
      (i) => i.productId == productId && i.variantId == variantId,
    );
    if (index < 0) return;
    if (qty <= 0) {
      _items.removeAt(index);
      await _db.customStatement(
        'DELETE FROM cart_items WHERE product_id = ? AND variant_id = ?',
        [productId, variantId],
      );
    } else {
      _items[index] = _items[index].copyWith(qty: qty);
      await _db.customStatement(
        'UPDATE cart_items SET qty = ? WHERE product_id = ? AND variant_id = ?',
        [qty, productId, variantId],
      );
    }
    notifyListeners();
  }

  Future<void> removeItem(int productId, int variantId) async {
    _items.removeWhere(
      (i) => i.productId == productId && i.variantId == variantId,
    );
    await _db.customStatement(
      'DELETE FROM cart_items WHERE product_id = ? AND variant_id = ?',
      [productId, variantId],
    );
    notifyListeners();
  }

  Future<void> clear() async {
    _items.clear();
    await _db.customStatement('DELETE FROM cart_items');
    notifyListeners();
  }

  int qtyForVariant(int productId, int variantId) {
    final item = _items.firstWhere(
      (i) => i.productId == productId && i.variantId == variantId,
      orElse: () => CartItem(
        productId: 0,
        variantId: 0,
        qty: 0,
        sellerId: 0,
        name: '',
        imageUrl: '',
        price: 0,
      ),
    );
    return item.qty;
  }

  List<int> get sellerIds => _items.map((i) => i.sellerId).toSet().toList();

  Map<String, dynamic> toMap() => {
        'items': _items.map((i) => i.toMap()).toList(),
        'sub_total': subtotal,
        'item_count': itemCount,
      };

  }
