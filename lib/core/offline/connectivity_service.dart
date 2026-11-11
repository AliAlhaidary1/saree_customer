import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// Live internet-reachability monitor.
///
/// Backed by [internet_connection_checker_plus], which verifies actual
/// internet access (HTTP reachability to well-known, always-on endpoints)
/// rather than the mere presence of a Wi‑Fi/mobile interface — a phone on
/// Wi‑Fi without internet (captive portal, dead router) is unreachable, and
/// that distinction is exactly what this app needs to paint the catalog
/// versus serve cached Drift rows.
///
/// [connectivity_plus] is wired in as the interface-trigger stream so an
/// instant probe fires the moment Wi‑Fi/mobile toggles, instead of waiting
/// for the default polling interval.
///
/// Deliberately NOT wired to our backend: this monitor answers "is there
/// internet?", not "is sareemart up?". [CustomerApi.likelyOffline] is kept
/// as the complementary signal for server reachability; [AppController]
/// merges both into `looksOffline` and everything (catalog, orders,
/// notifications, checkout …) reads that merged flag.
///
/// Tests construct this with fake seams ([statusStream]/[probe]) — no real
/// network, no real timers — and pin transitions directly.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService({
    this._statusStream,
    this._probe,
  });

  /// Test seams: inject a canned status stream (fake timer-free transitions)
  /// and/or a canned probe. When both are null the real library stack is
  /// used (production code path).
  final Stream<InternetStatus>? _statusStream;
  final Future<bool> Function()? _probe;

  InternetConnection? _connection;
  StreamSubscription<InternetStatus>? _sub;

  /// Optimistic default: assume online until a probe says otherwise. A
  /// cold-start user with internet gets fresh paint immediately while the
  /// probe settles; a cold-start offline user sees the very same fallbacks
  /// they already see today (the probe flips this within a second or two).
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  bool _started = false;

  /// Create the owned library instance lazily so tests (which inject the
  /// seams) never pay for the real endpoints or timers.
  InternetConnection _ensureConnection() {
    return _connection ??= InternetConnection.createInstance(
      triggerStream: Connectivity().onConnectivityChanged,
    );
  }

  /// Probe once, then keep re-probing on interface changes + library polls.
  /// Idempotent; safe to call from bootstrap (fire-and-forget). Never throws.
  Future<void> init() async {
    if (_started) return;
    _started = true;
    try {
      final probe = _probe;
      final connected = probe != null
          ? await probe()
          : await _ensureConnection().hasInternetAccess;
      _set(connected);
    } catch (_) {
      // Unresolved probe counts as offline evidence — the screens' offline
      // fallbacks already handle that case honestly.
      _set(false);
    }
    try {
      _sub = (_statusStream ?? _ensureConnection().onStatusChange).listen(
        (status) => _set(status == InternetStatus.connected),
        onError: (_) {},
      );
    } catch (_) {
      // Stream already closed or unavailable: the one-shot probe above is
      // still a valid signal; monitor stays static but functional.
    }
  }

  void _set(bool value) {
    if (_isOnline == value) return;
    _isOnline = value;
    notifyListeners();
  }

  /// Test hook: flip the flag synchronously without any network, timers or
  /// library wiring. Isolated to tests via @visibleForTesting semantics.
  void overrideForTest(bool value) => _set(value);

  @override
  void dispose() {
    _sub?.cancel();
    _connection?.dispose();
    super.dispose();
  }
}
