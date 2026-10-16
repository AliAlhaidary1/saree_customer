import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Durable, account-isolated key/value document store on top of
/// SharedPreferences (existing storage backend — no migration risk).
///
/// Design notes (why not Drift/SQLite here):
/// * Cached payloads are small display documents (guards already cap shop at
///   400KB and categories at 200KB). A relational engine adds native
///   migration risk with no query benefit (no joins, no FTS needed —
///   offline search filters the cached pages in memory).
/// * Reuses the existing storage format/keys (`shop_cache`, `cats_cache`,
///   `guest_cart`, `city`) so upgrades never erase customer data.
/// * Corrupt values (interrupted writes, older builds) are quarantined per
///   key instead of failing startup or wiping the whole store.
/// * Large documents are size-guarded; oversized payloads stay memory-only.
///
/// Account isolation: user-scoped keys embed a stable account id
/// (`u:<id>` or `guest`). Global catalog keys stay shared. On logout only
/// user-scoped keys are removed; the guest cart is preserved separately.

class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static const int maxDocumentBytes = 400 * 1024;

  /// Encoded byte size of a JSON-encodable document. Storage limits are
  /// enforced on UTF-8 bytes, not Dart string length (Arabic payloads are
  /// ~2x larger in bytes than `String.length` suggests).
  static int documentBytes(Object? value) {
    try {
      return utf8.encode(jsonEncode(value)).length;
    } catch (_) {
      return maxDocumentBytes + 1;
    }
  }

  static String accountScope(String? accountId) =>
      accountId == null || accountId.isEmpty ? 'guest' : 'u:$accountId';

  static String scopedKey(String base, String scope) => '$base::$scope';

  String? readString(String key) {
    try {
      return _prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<bool> writeString(String key, String value) async {
    try {
      return await _prefs.setString(key, value);
    } catch (_) {
      return false;
    }
  }

  Future<bool> remove(String key) async {
    try {
      return await _prefs.remove(key);
    } catch (_) {
      return false;
    }
  }

  /// Reads a JSON document; returns null when missing/unparseable.
  /// Corrupt values are removed so the next write starts clean, but sibling
  /// keys are never touched.
  dynamic readJson(String key) {
    final raw = readString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      // Quarantine corrupt document (fire-and-forget).
      remove(key);
      return null;
    }
  }

  /// Writes a JSON-encodable document with a size guard. Returns false and
  /// keeps the previous value when the payload is oversized.
  Future<bool> writeJson(String key, Object? value) async {
    try {
      final dump = jsonEncode(value);
      if (utf8.encode(dump).length > maxDocumentBytes) return false;
      return await writeString(key, dump);
    } catch (_) {
      return false;
    }
  }

  int? readTimestampMs(String key) {
    try {
      return _prefs.getInt(key);
    } catch (_) {
      return null;
    }
  }

  Future<bool> writeTimestampNow(String key) async {
    try {
      return await _prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      return false;
    }
  }

  DateTime? readTime(String atKey) {
    final ms = readTimestampMs(atKey);
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Removes every key starting with [prefix] (account-scoped wipe).
  Future<void> removeWherePrefix(String prefix) async {
    try {
      final keys = _prefs.getKeys().where((k) => k.startsWith(prefix));
      for (final k in keys.toList()) {
        await _prefs.remove(k);
      }
    } catch (_) {}
  }

  /// Lists keys starting with [prefix] (eviction scans, tests). Never throws.
  List<String> keysWithPrefix(String prefix) {
    try {
      return _prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    } catch (_) {
      return [];
    }
  }
}
