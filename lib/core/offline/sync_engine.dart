import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pending_ops.dart';

/// Controlled synchronization engine for the durable outbox.
///
/// Guarantees:
/// * Coalesced triggers (rapid resume/network-flap bursts run once).
/// * No concurrent conflicting syncs (single-flight gate).
/// * Bounded retries with per-op exponential backoff ([PendingOutbox]).
/// * Permanent failures surfaced as "blocked" instead of retried forever.
/// * UI notified via [status] (a [ValueNotifier]) — no scattered listeners.
///
/// Reachability is determined by API results, NOT by interface state: a
/// Wi-Fi link without internet still yields failures, which re-arm backoff.
/// Checkout/payment are never executed here (see [PendingOutbox] docs).

enum SyncState { idle, syncing, waiting, blocked }

class SyncStatus {
  SyncStatus({
    this.state = SyncState.idle,
    this.pending = 0,
    this.blocked = 0,
    this.lastRun,
    this.lastError = '',
  });

  final SyncState state;
  final int pending;
  final int blocked;
  final DateTime? lastRun;
  final String lastError;

  SyncStatus copyWith({
    SyncState? state,
    int? pending,
    int? blocked,
    DateTime? lastRun,
    String? lastError,
  }) =>
      SyncStatus(
        state: state ?? this.state,
        pending: pending ?? this.pending,
        blocked: blocked ?? this.blocked,
        lastRun: lastRun ?? this.lastRun,
        lastError: lastError ?? this.lastError,
      );
}

typedef OpExecutor = Future<bool> Function(PendingOp op);

class SyncEngine extends ChangeNotifier {
  SyncEngine({required this._outboxForCurrentScope});

  final PendingOutbox Function() _outboxForCurrentScope;

  final ValueNotifier<SyncStatus> status =
      ValueNotifier(SyncStatus());

  bool _running = false;
  bool _queued = false;
  Timer? _deferred;

  /// Coalesced trigger: safe to call from resume handlers, retry buttons,
  /// and post-mutation hooks. Concurrent calls collapse into one run.
  void requestSync() {
    if (_running) {
      _queued = true;
      return;
    }
    unawaited(run());
  }

  /// Deferred trigger used after a failure (backoff already encoded per-op,
  /// this only avoids tight loops at the engine level).
  void requestSyncDelayed(Duration delay) {
    _deferred?.cancel();
    _deferred = Timer(delay, requestSync);
  }

  Future<void> run({OpExecutor? executor}) async {
    if (_running) {
      _queued = true;
      return;
    }
    _running = true;
    try {
      do {
        _queued = false;
        await _runOnce(executor);
      } while (_queued);
    } finally {
      _running = false;
    }
  }

  Future<void> _runOnce(OpExecutor? executor) async {
    final outbox = _outboxForCurrentScope();
    final now = DateTime.now();
    final pending = outbox.load();
    var parts = outbox.dueOps(now);
    status.value = status.value.copyWith(
      state: SyncState.syncing,
      pending: parts.due.length,
      blocked: parts.blocked.length,
    );
    if (executor == null || parts.due.isEmpty) {
      status.value = status.value.copyWith(
        state: parts.blocked.isNotEmpty
            ? SyncState.blocked
            : (parts.due.isEmpty && pending.isEmpty
                ? SyncState.idle
                : SyncState.waiting),
        lastRun: now,
      );
      notifyListeners();
      return;
    }
    var firstFailure = '';
    for (final op in parts.due) {
      bool ok = false;
      try {
        ok = await executor(op);
      } catch (e) {
        ok = false;
        firstFailure = '$e';
      }
      if (ok) {
        await outbox.remove(op.id);
      } else {
        final next = now.add(PendingOutbox.backoffForAttempt(op.attempts));
        await outbox.update(op.withRetry(
          next,
          firstFailure.isEmpty ? 'sync_failed' : firstFailure,
        ));
        if (firstFailure.isEmpty) firstFailure = 'sync_failed';
        // Stop the pass on first failure: likely offline — remaining ops
        // keep their schedule instead of burning attempts in a loop.
        break;
      }
    }
    parts = outbox.dueOps(DateTime.now());
    status.value = SyncStatus(
      state: parts.blocked.isNotEmpty
          ? SyncState.blocked
          : (parts.due.isEmpty ? SyncState.idle : SyncState.waiting),
      pending: parts.due.length,
      blocked: parts.blocked.length,
      lastRun: DateTime.now(),
      lastError: firstFailure,
    );
    notifyListeners();
  }

  int pendingCount() {
    try {
      return _outboxForCurrentScope().load().length;
    } catch (_) {
      return 0;
    }
  }

  @override
  void dispose() {
    _deferred?.cancel();
    status.dispose();
    super.dispose();
  }
}
