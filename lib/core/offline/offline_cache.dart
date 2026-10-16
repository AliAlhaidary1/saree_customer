import 'dart:convert';

import 'cache_policy.dart';
import 'local_store.dart';

/// Typed cache envelope: payload + refresh metadata + owning account.
///
/// `refreshedAtMs` is the last *successful* server refresh. A failed refresh
/// never clears the payload — stale rows stay visible with a freshness badge.

class CachedDoc {
  CachedDoc({
    required this.payload,
    required this.refreshedAt,
    required this.scope,
  });

  final dynamic payload;
  final DateTime refreshedAt;
  final String scope;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'scope': scope,
    'refreshedAt': refreshedAt.millisecondsSinceEpoch,
    'payload': payload,
  };

  static CachedDoc? fromJson(dynamic decoded, {String scope = 'guest'}) {
    if (decoded is! Map) return null;
    try {
      final ms = (decoded['refreshedAt'] is int)
          ? decoded['refreshedAt'] as int
          : int.tryParse('${decoded['refreshedAt']}') ?? 0;
      if (ms <= 0) return null;
      return CachedDoc(
        payload: decoded['payload'],
        refreshedAt: DateTime.fromMillisecondsSinceEpoch(ms),
        scope: '${decoded['scope'] ?? scope}',
      );
    } catch (_) {
      return null;
    }
  }
}

/// High-level offline document cache with per-entity freshness.
///
/// Keys (v1 namespace, backward compatible with existing keys where they
/// already exist — `shop_cache`/`cats_cache`/`guest_cart` keep their legacy
/// names so upgrades preserve data):
/// * `shop_cache` (+`shop_cache_at`), `cats_cache` (+`cats_cache_at`)
/// * `oc:products::<hash>` product pages, `oc:pdetail::<id>` details
/// * `oc:favs::<scope>`, `oc:addrs::<scope>`, `oc:orders::<scope>`,
///   `oc:odetail::<scope>::<id>`
class OfflineCache {
  OfflineCache(this._store);

  final LocalStore _store;

  // ---- legacy keys (do not rename: upgrades must preserve data) ----
  static const shopKey = 'shop_cache';
  static const shopAtKey = 'shop_cache_at';
  static const catsKey = 'cats_cache';
  static const catsAtKey = 'cats_cache_at';

  static String productsKey(String hash) => 'oc:products::$hash';
  static String productDetailsKey(String id) => 'oc:pdetail::$id';
  static String favoritesKey(String scope) => 'oc:favs::$scope';
  static String wishlistKey(String scope) => 'oc:wishlist::$scope';
  static String notificationsKey(String scope) => 'oc:notifs::$scope';
  static String addressesKey(String scope) => 'oc:addrs::$scope';
  static String ordersKey(String scope) => 'oc:orders::$scope';
  static String orderDetailsKey(String scope, String id) =>
      'oc:odetail::$scope::$id';

  /// Generic small-document snapshot namespace (sliders/offers/campaigns/
  /// sections/FAQs/CMS/haraj/akhdimni snapshots). Account-scoped snapshots
  /// embed the scope in [name] (see AppController helpers).
  static String snapshotKey(String name) => 'oc:snap::$name';

  /// Local form-draft key. Drafts are never auto-submitted: the user reviews
  /// and explicitly sends them after reconnecting. [formId] is a stable
  /// per-screen identifier (e.g. `checkout_form`, `haraj_create`).
  static String draftKey(String scope, String formId) =>
      'oc:draft::$scope::$formId';

  /// Stable hash for a product-query map (sorted key=value pairs).
  static String queryHash(Map<String, dynamic> query) {
    final parts =
        query.entries
            .where((e) => e.value != null && '${e.value}'.isNotEmpty)
            .map((e) => '${e.key}=${e.value}')
            .toList()
          ..sort();
    // Short deterministic hash (djb2) — avoids unbounded key growth.
    var h = 5381;
    final s = parts.join('&');
    for (var i = 0; i < s.length; i++) {
      h = ((h << 5) + h + s.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  CachedDoc? readDoc(String key) {
    final decoded = _store.readJson(key);
    if (decoded == null) return null;
    if (decoded is Map && decoded.containsKey('payload')) {
      return CachedDoc.fromJson(decoded);
    }
    // Legacy bare payloads (shop/cats written by older builds as raw JSON
    // without an envelope): still displayable, but always treated as stale
    // so the UI paints them with a freshness badge and refreshes.
    // The epoch timestamp forces `fresh()` to false without hiding content.
    if (decoded is Map && decoded.isNotEmpty) {
      return CachedDoc(
        payload: decoded,
        refreshedAt: DateTime.fromMillisecondsSinceEpoch(1),
        scope: 'guest',
      );
    }
    if (decoded is List && decoded.isNotEmpty) {
      return CachedDoc(
        payload: decoded,
        refreshedAt: DateTime.fromMillisecondsSinceEpoch(1),
        scope: 'guest',
      );
    }
    return null;
  }

  Future<bool> writeDoc(String key, dynamic payload, {String scope = 'guest'}) {
    return _store.writeJson(key, {
      'v': 1,
      'scope': scope,
      'refreshedAt': DateTime.now().millisecondsSinceEpoch,
      'payload': payload,
    });
  }

  /// Removes one cached document (e.g. account snapshot delete).
  Future<void> removeDoc(String key) => _store.remove(key);

  // ---- Bounded reconstructible catalog storage (LRU eviction) ----
  //
  // Product pages/details accumulate as the user browses; without a bound
  // SharedPreferences grows indefinitely. These writers keep at most
  // [maxProductPages] pages and [maxProductDetails] details, evicting the
  // least-recently-written first. Eviction only ever discards reconstructible
  // catalog rows (a future miss re-downloads them) — account docs, the
  // pending outbox, checkout sessions, and the guest cart are NEVER evicted
  // here and live under different key prefixes.
  static const int maxProductPages = 60;
  static const int maxProductDetails = 100;
  static const String _pagesIndexKey = 'oc:index:products';
  static const String _detailsIndexKey = 'oc:index:pdetails';

  Future<bool> writeProductPage(String key, dynamic payload) async {
    final ok = await writeDoc(key, payload);
    if (ok) {
      await _trackBounded(
        _pagesIndexKey,
        key,
        maxProductPages,
        'oc:products::',
      );
    }
    return ok;
  }

  Future<bool> writeProductDetails(String key, dynamic payload) async {
    final ok = await writeDoc(key, payload);
    if (ok) {
      await _trackBounded(
        _detailsIndexKey,
        key,
        maxProductDetails,
        'oc:pdetail::',
      );
    }
    return ok;
  }

  Future<void> _trackBounded(
    String indexKey,
    String key,
    int maxEntries,
    String prefix,
  ) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final raw = _store.readJson(indexKey);
      final entries = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map && '${item['k']}'.isNotEmpty && item['k'] != key) {
            entries.add({
              'k': '${item['k']}',
              'at': item['at'] is int ? item['at'] as int : 0,
            });
          }
        }
      }
      entries.add({'k': key, 'at': now});
      // Keys predating the index (older app versions) count as oldest.
      final indexed = entries.map((e) => '${e['k']}').toSet();
      final existing = _store.keysWithPrefix(prefix);
      final untracked = existing.where((k) => !indexed.contains(k)).toList()
        ..sort();
      var overflow = (untracked.length + entries.length) - maxEntries;
      final evict = <String>[];
      var u = 0;
      while (overflow > 0 && u < untracked.length) {
        evict.add(untracked[u++]);
        overflow--;
      }
      var e = 0;
      while (overflow > 0 && e < entries.length) {
        // Never evict the key just written (it is last in [entries]).
        if (e == entries.length - 1) break;
        evict.add('${entries[e]['k']}');
        e++;
      }
      for (final k in evict) {
        await _store.remove(k);
      }
      final kept = entries
          .where((en) => !evict.contains('${en['k']}'))
          .toList();
      // The index itself stays small (bounded by maxEntries).
      await _store.writeString(indexKey, jsonEncode(kept));
    } catch (_) {}
  }

  bool fresh(String key, CacheEntity entity) {
    final doc = readDoc(key);
    if (doc == null) return false;
    return CachePolicy.isFresh(doc.refreshedAt, entity);
  }

  /// Writes a local form draft for [scope]. Drafts are plain local state:
  /// they are never sent automatically and never presented as confirmed.
  Future<bool> writeDraft(
    String scope,
    String formId,
    Map<String, dynamic> draft,
  ) {
    return writeDoc(draftKey(scope, formId), draft, scope: scope);
  }

  /// Reads a local form draft, or null when missing, corrupt, or owned by
  /// another account scope.
  Map<String, dynamic>? readDraft(String scope, String formId) {
    try {
      final doc = readDoc(draftKey(scope, formId));
      if (doc?.scope != scope) return null;
      final payload = doc?.payload;
      if (payload is Map) return Map<String, dynamic>.from(payload);
    } catch (_) {}
    return null;
  }

  Future<void> removeDraft(String scope, String formId) =>
      _store.remove(draftKey(scope, formId));

  /// Clears only user-scoped offline docs (logout/account switch). Global
  /// catalog keys (`shop_cache`, `cats_cache`, product pages) are shared and
  /// safe to keep; per-account docs must never leak across users.
  Future<void> clearAccountDocs(String scope) async {
    await _store.removeWherePrefix('oc:favs::$scope');
    await _store.removeWherePrefix('oc:wishlist::$scope');
    await _store.removeWherePrefix('oc:notifs::$scope');
    await _store.removeWherePrefix('oc:addrs::$scope');
    await _store.removeWherePrefix('oc:orders::$scope');
    await _store.removeWherePrefix('oc:odetail::$scope');
    await _store.removeWherePrefix('oc:pending::$scope');
    await _store.removeWherePrefix('oc:draft::$scope');
    // Account-scoped generic snapshots (`oc:snap::<name>::<scope>`). Global
    // snapshots (`oc:snap::<name>`) are shared public data and are kept.
    try {
      for (final k in _store.keysWithPrefix('oc:snap::')) {
        if (k.endsWith('::$scope')) await _store.remove(k);
      }
    } catch (_) {}
    await _store.remove('checkout_session::$scope');
  }

  static String encodeForTest(Map<String, dynamic> doc) => jsonEncode(doc);
}

/// A draft write captured atomically at schedule time: owning scope plus a
/// field snapshot taken together. Debounced form writers (e.g. the checkout
/// draft's 800ms timer) must capture both up front and call [forScope] when
/// the timer fires: an account switch inside the window drops the write
/// instead of filing one account's form under another identity. Pure and
/// unit-tested; screens delegate to it.
class ScopedDraftWrite {
  ScopedDraftWrite({required this.scope, required Map<String, dynamic> fields})
    : fields = Map<String, dynamic>.unmodifiable(fields);

  final String scope;
  final Map<String, dynamic> fields;

  /// The fields to write, or null when the write must be dropped because the
  /// active scope changed since capture.
  Map<String, dynamic>? forScope(String currentScope) =>
      currentScope == scope ? Map<String, dynamic>.from(fields) : null;
}
