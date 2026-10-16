import 'dart:convert';

import 'local_store.dart';

/// Durable outbox of safe-to-retry local mutations.
///
/// Only idempotent, non-financial operations are queued here:
/// * favorite add/remove (stable product ids, server reconciles by id)
/// * guest-cart merge intent (replayed once after login; cleared on success)
///
/// CHECKOUT AND PAYMENT ARE NEVER QUEUED. Order placement stays online-only
/// and server-authoritative; an uncertain checkout must reconcile against
/// `orders` before any resubmission (see `CheckoutSession`).

enum PendingOpType { favoriteAdd, favoriteRemove, guestCartMerge }

class PendingOp {
  PendingOp({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastError,
  });

  final String id;
  final PendingOpType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastError;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'payload': payload,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'attempts': attempts,
    'nextAttemptAt': nextAttemptAt?.millisecondsSinceEpoch,
    'lastError': lastError,
  };

  static PendingOp? fromJson(dynamic v) {
    if (v is! Map) return null;
    try {
      final type = PendingOpType.values.firstWhere(
        (t) => t.name == '${v['type']}',
        orElse: () => PendingOpType.favoriteAdd,
      );
      final created = v['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(v['createdAt'] as int)
          : DateTime.now();
      final next = v['nextAttemptAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(v['nextAttemptAt'] as int)
          : null;
      return PendingOp(
        id: '${v['id']}',
        type: type,
        payload: Map<String, dynamic>.from((v['payload'] as Map?) ?? {}),
        createdAt: created,
        attempts: (v['attempts'] is int) ? v['attempts'] as int : 0,
        nextAttemptAt: next,
        lastError: v['lastError']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  PendingOp withRetry(DateTime next, String error) => PendingOp(
    id: id,
    type: type,
    payload: payload,
    createdAt: createdAt,
    attempts: attempts + 1,
    nextAttemptAt: next,
    lastError: error,
  );
}

class PendingOutbox {
  PendingOutbox(this._store, this.scope);

  final LocalStore _store;
  final String scope;

  static const int maxOps = 200;
  static const int maxAttempts = 8;

  /// Maximum encoded size of a single op payload. Favorite/cart-merge
  /// payloads are tiny (ids only); anything larger is a programming error and
  /// must never grow the outbox document without bound.
  static const int maxPayloadBytes = 32 * 1024;

  String get _key => 'oc:pending::$scope';

  List<PendingOp> load() {
    final raw = _store.readJson(_key);
    if (raw is! List) return [];
    final ops = <PendingOp>[];
    for (final item in raw) {
      final op = PendingOp.fromJson(item);
      if (op != null) ops.add(op);
    }
    return ops;
  }

  Future<void> _save(List<PendingOp> ops) async {
    final trimmed = ops.length > maxOps
        ? ops.sublist(ops.length - maxOps)
        : ops;
    await _store.writeString(
      _key,
      jsonEncode(trimmed.map((o) => o.toJson()).toList()),
    );
  }

  /// Enqueues [op], coalescing duplicate favorite ops for the same product so
  /// repeated taps never create duplicate server requests on replay.
  /// Returns false (without persisting) when the payload exceeds
  /// [maxPayloadBytes]; oversized ops must never bloat the queue.
  Future<bool> enqueue(PendingOp op) async {
    if (LocalStore.documentBytes(op.payload) > maxPayloadBytes) return false;
    final ops = load();
    if (op.type == PendingOpType.favoriteAdd ||
        op.type == PendingOpType.favoriteRemove) {
      final pid = '${op.payload['product_id']}';
      ops.removeWhere(
        (e) =>
            (e.type == PendingOpType.favoriteAdd ||
                e.type == PendingOpType.favoriteRemove) &&
            '${e.payload['product_id']}' == pid,
      );
      // Collapse add+remove pairs for the same product into the latest op.
      if (ops.isEmpty || true) {
        // keep latest only (already removed older ones above)
      }
    }
    ops.add(op);
    await _save(ops);
    return true;
  }

  Future<void> remove(String id) async {
    final ops = load()..removeWhere((o) => o.id == id);
    await _save(ops);
  }

  Future<void> update(PendingOp op) async {
    final ops = load();
    final i = ops.indexWhere((o) => o.id == op.id);
    if (i >= 0) {
      ops[i] = op;
      await _save(ops);
    }
  }

  /// Ops eligible for an attempt right now (due + under attempt budget).
  /// Permanently-failed ops (over budget) are returned separately so callers
  /// can surface them instead of retrying forever.
  ({List<PendingOp> due, List<PendingOp> blocked}) dueOps(DateTime now) {
    final due = <PendingOp>[];
    final blocked = <PendingOp>[];
    for (final op in load()) {
      if (op.attempts >= maxAttempts) {
        blocked.add(op);
        continue;
      }
      final next = op.nextAttemptAt;
      if (next == null || !next.isAfter(now)) due.add(op);
    }
    return (due: due, blocked: blocked);
  }

  /// Exponential backoff with jitter: 2s, 4s, 8s, ... capped at 10 min.
  static Duration backoffForAttempt(int attempt) {
    var seconds = 2 << (attempt < 8 ? attempt : 8);
    if (seconds > 600) seconds = 600;
    final jitterMs = (seconds * 200) % 1000; // deterministic jitter
    return Duration(seconds: seconds, milliseconds: jitterMs);
  }

  static int _idCounter = 0;

  static String newId(String prefix) {
    final n = _idCounter++;
    return '$prefix-${DateTime.now().millisecondsSinceEpoch}-$n';
  }
}
