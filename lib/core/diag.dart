import 'package:flutter/foundation.dart';

/// Opt-in performance probes.
///
/// Enable at build time with `--dart-define=DIAG=true`; every probe is a
/// no-op otherwise (one compile-time const check, no allocations).
///
/// Logs are prefixed with `[DIAG +Nms]` where N is milliseconds since
/// process start, so startup waves can be read as a timeline in logcat or
/// the `flutter run` console.
abstract final class Diag {
  static const bool enabled = bool.fromEnvironment('DIAG');

  static final Stopwatch _uptime = Stopwatch()..start();

  static int get uptimeMs => _uptime.elapsedMilliseconds;

  static void log(String tag, [Object? extra]) {
    if (!enabled) return;
    debugPrint('[DIAG +${uptimeMs}ms] $tag${extra == null ? '' : ' $extra'}');
  }

  /// Runs [body] and logs its wall time under [tag].
  static Future<T> timed<T>(
    String tag,
    Future<T> Function() body, {
    Object? Function(T value)? detail,
  }) async {
    if (!enabled) return body();
    final sw = Stopwatch()..start();
    try {
      final value = await body();
      log('$tag ${sw.elapsedMilliseconds}ms',
          detail == null ? null : detail(value));
      return value;
    } catch (error) {
      log('$tag ${sw.elapsedMilliseconds}ms FAILED', error);
      rethrow;
    }
  }
}
