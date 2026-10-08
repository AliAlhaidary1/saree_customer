import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Parity with front `src/utils/notificationRead.js`.
/// Backend returns a global broadcast list (total + data) without per-user
/// read state, so "viewed = read" and read IDs are stored locally per user.
class NotificationRead {
  static const _prefix = 'saree_notif_read_';
  static const _cap = 500;

  static String keyFor(dynamic userId) {
    final uid = userId == null || '$userId'.isEmpty ? 'guest' : '$userId';
    return '$_prefix$uid';
  }

  static List<String> _normalize(dynamic ids) {
    if (ids is! List) return const [];
    return ids.map((e) => '$e').where((e) => e.isNotEmpty).toSet().toList();
  }

  static Future<List<String>> getReadIds(dynamic userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(keyFor(userId));
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return _normalize(decoded);
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> markAsRead(dynamic userId, List<dynamic> ids) async {
    final incoming = _normalize(ids);
    if (incoming.isEmpty) return getReadIds(userId);
    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = await getReadIds(userId);
      final merged = {...prev, ...incoming}.toList();
      final trimmed = merged.length > _cap ? merged.sublist(merged.length - _cap) : merged;
      await prefs.setString(keyFor(userId), jsonEncode(trimmed));
      return trimmed;
    } catch (_) {
      return incoming;
    }
  }

  static int computeUnreadCount(int total, List<String> readIds) {
    if (total <= 0) return 0;
    return (total - readIds.length).clamp(0, total);
  }

  /// When server total shrinks (old notifications pruned), trim oldest read IDs.
  static Future<List<String>> prune(dynamic userId, int total) async {
    final prev = await getReadIds(userId);
    if (prev.length <= total) return prev;
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = prev.sublist(prev.length - total);
      await prefs.setString(keyFor(userId), jsonEncode(trimmed));
      return trimmed;
    } catch (_) {
      return prev;
    }
  }

  static Future<void> clear(dynamic userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyFor(userId));
    } catch (_) {}
  }
}
