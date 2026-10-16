import 'package:flutter/foundation.dart';

/// Composite synchronization cursor for keyset paging of the catalog.
///
/// Ordering contract (must match the backend listing exactly):
/// `ORDER BY created_at ASC, id ASC` (existing `sort=old` semantics).
/// A single `after_id` is NOT a valid cursor for this ordering: two rows can
/// share a `created_at` second, and clock granularity is backend-controlled.
/// The pair `(lastCreatedAt, lastId)` advances gap-free over inserts: every
/// insert lands strictly after some cursor position (equal timestamps are
/// broken by increasing `id`).
///
/// `lastCreatedAt` is intentionally opaque to the client (lexicographic
/// comparison over the backend's fixed timestamp format). A null
/// `lastCreatedAt` means "start of scope".
///
/// Capture rules:
/// * inserts → captured (positioned after the cursor by construction);
/// * updates → do NOT move rows; captured only via change feed (B2) or
///   refresh-window re-baseline (interim);
/// * deletes → remove rows; captured only via tombstones (B2).
@immutable
class SyncCursor {
  const SyncCursor({this.lastCreatedAt, this.lastId = 0});

  const SyncCursor.start() : lastCreatedAt = null, lastId = 0;

  final String? lastCreatedAt;
  final int lastId;

  bool get isStart => lastCreatedAt == null;

  /// Backend query parameters for the B1 composite-keyset contract.
  /// Offset-mode fallback ignores the cursor (best-effort only).
  Map<String, dynamic> toQueryParams({required int limit}) => {
        'sort': 'old',
        'limit': limit,
        if (lastCreatedAt != null) 'after_created_at': lastCreatedAt,
        'after_id': lastId,
      };

  /// Advances past a committed row. Rows must be processed in listing order;
  /// advancing out of order corrupts the checkpoint (callers: single-flight).
  SyncCursor advance({required String createdAt, required int id}) {
    if (isStart) return SyncCursor(lastCreatedAt: createdAt, lastId: id);
    final cmp = _compareTimestamps(createdAt, lastCreatedAt!);
    if (cmp > 0 || (cmp == 0 && id > lastId)) {
      return SyncCursor(lastCreatedAt: createdAt, lastId: id);
    }
    return this;
  }

  /// -1/0/1 over (createdAt, id). Null (start) sorts before everything.
  int compareTo(SyncCursor other) {
    if (lastCreatedAt == null && other.lastCreatedAt == null) {
      return lastId.compareTo(other.lastId);
    }
    if (lastCreatedAt == null) return -1;
    if (other.lastCreatedAt == null) return 1;
    final cmp = _compareTimestamps(lastCreatedAt!, other.lastCreatedAt!);
    if (cmp != 0) return cmp;
    return lastId.compareTo(other.lastId);
  }

  static int _compareTimestamps(String a, String b) => a.compareTo(b);

  @override
  bool operator ==(Object other) =>
      other is SyncCursor &&
      other.lastCreatedAt == lastCreatedAt &&
      other.lastId == lastId;

  @override
  int get hashCode => Object.hash(lastCreatedAt, lastId);

  @override
  String toString() => 'SyncCursor($lastCreatedAt, $lastId)';
}
