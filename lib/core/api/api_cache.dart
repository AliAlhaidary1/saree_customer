import '../json_util.dart';

/// Device-safe in-memory cache for idempotent browse endpoints.
///
/// - Bounded size (LRU-ish eviction) so it never harms the device.
/// - Short TTLs so new products/stores appear quickly (stale-while-revalidate).
/// - Only used for public catalog data (sliders/brands/countries/sellers/
///   categories/shop). Never for cart/favorites/orders/user data.
class ApiCache {
  ApiCache({this.maxEntries = 80});

  final int maxEntries;
  final Map<String, _Entry> _store = {};

  ApiResult? get(String key, Duration ttl) {
    final e = _store[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > ttl) {
      _store.remove(key);
      return null;
    }
    // LRU touch.
    _store.remove(key);
    _store[key] = e;
    return e.value;
  }

  /// Returns stale entry even past TTL (for instant paint + background refresh).
  ApiResult? getStale(String key) => _store[key]?.value;

  void set(String key, ApiResult value) {
    _store.remove(key);
    _store[key] = _Entry(value, DateTime.now());
    while (_store.length > maxEntries) {
      _store.remove(_store.keys.first);
    }
  }

  void invalidate(String prefix) {
    _store.removeWhere((k, _) => k.startsWith(prefix));
  }

  void clear() => _store.clear();
}

class _Entry {
  _Entry(this.value, this.at);
  final ApiResult value;
  final DateTime at;
}
