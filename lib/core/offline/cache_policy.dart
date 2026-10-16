/// Per-entity cache freshness policy (offline-first).
///
/// A TTL is display policy only: it decides when cached rows may be painted
/// instantly and when a background refresh is required. It is NEVER proof
/// that a price, stock level, or order status is still correct — financial
/// and inventory decisions stay server-authoritative (see checkout flows).
library;

/// Maximum age after which a background refresh should be attempted.
/// Stale rows remain visible; only the refresh is (re)triggered.
enum CacheEntity {
  shop,
  categories,
  sliders,
  productList,
  productDetails,
  favorites,
  addresses,
  orders,
  orderDetails,
  checkoutConfig,
}

class CachePolicy {
  const CachePolicy._();

  static Duration ttlOf(CacheEntity entity) {
    switch (entity) {
      case CacheEntity.shop:
        return const Duration(minutes: 2);
      case CacheEntity.sliders:
        return const Duration(minutes: 10);
      case CacheEntity.categories:
        return const Duration(minutes: 30);
      case CacheEntity.productList:
        return const Duration(minutes: 5);
      case CacheEntity.productDetails:
        return const Duration(minutes: 10);
      case CacheEntity.favorites:
        return const Duration(minutes: 5);
      case CacheEntity.addresses:
        return const Duration(minutes: 15);
      case CacheEntity.orders:
        return const Duration(minutes: 5);
      case CacheEntity.orderDetails:
        return const Duration(minutes: 5);
      case CacheEntity.checkoutConfig:
        return const Duration(minutes: 15);
    }
  }

  /// Whether stale rows of [entity] may be painted while refreshing.
  /// Orders/order-details are painted but always badged as "saved status".
  static bool allowStale(CacheEntity entity) => true;

  static bool isFresh(DateTime? refreshedAt, CacheEntity entity) {
    if (refreshedAt == null) return false;
    return DateTime.now().difference(refreshedAt) <= ttlOf(entity);
  }
}
