import 'dart:async';

import 'package:flutter/foundation.dart';

/// Classification of an OTP-send failure.
enum OtpSendKind {
  // ignore: constant_identifier_names
  hard_limit,
  // ignore: constant_identifier_names
  cooldown,
  // ignore: constant_identifier_names
  error,
}

String extractOtpReason(Map<String, dynamic> raw) {
  final top = raw['reason'];
  if (top != null && '$top'.trim().isNotEmpty) return '$top';
  final data = raw['data'];
  if (data is Map) {
    final r = data['reason'];
    if (r != null && '$r'.trim().isNotEmpty) return '$r';
  }
  final err = raw['error'];
  if (err is Map) {
    final details = err['details'];
    if (details is Map) {
      final r = details['reason'];
      if (r != null && '$r'.trim().isNotEmpty) return '$r';
    }
  }
  return '';
}

int _asPositiveInt(dynamic value) {
  if (value is int && value > 0 && value <= 600) return value;
  if (value is double && value > 0 && value <= 600) return value.toInt();
  final parsed = int.tryParse('$value');
  if (parsed != null && parsed > 0 && parsed <= 600) return parsed;
  return 0;
}

int extractOtpRetryAfter(Map<String, dynamic> raw, String message) {
  final candidates = <dynamic>[
    raw['retry_after'],
    raw['retryAfter'],
    if (raw['data'] is Map) (raw['data'] as Map)['retry_after'],
    if (raw['data'] is Map) (raw['data'] as Map)['retryAfter'],
    if (raw['data'] is Map && (raw['data'] as Map)['data'] is Map)
      ((raw['data'] as Map)['data'] as Map)['retry_after'],
    if (raw['data'] is Map && (raw['data'] as Map)['data'] is Map)
      ((raw['data'] as Map)['data'] as Map)['retryAfter'],
    if (raw['headers'] is Map) (raw['headers'] as Map)['retry-after'],
    if (raw['headers'] is Map) (raw['headers'] as Map)['Retry-After'],
    if (raw['error'] is Map && (raw['error'] as Map)['details'] is Map)
      ((raw['error'] as Map)['details'] as Map)['retry_after'],
    if (raw['error'] is Map && (raw['error'] as Map)['details'] is Map)
      ((raw['error'] as Map)['details'] as Map)['retryAfter'],
  ];
  for (final c in candidates) {
    final v = _asPositiveInt(c);
    if (v > 0) return v;
  }
  final match = RegExp(r'\d+').firstMatch(message);
  if (match != null) {
    final v = int.tryParse(match.group(0) ?? '') ?? 0;
    if (v > 0 && v <= 600) return v;
  }
  return 0;
}

String extractOtpMessage(Map<String, dynamic> raw) {
  final value = raw['message'] ?? raw['msg'];
  final text = value == null ? '' : '$value'.trim();
  if (text.isEmpty) return '';
  final lower = text.toLowerCase();
  if (lower.contains('request failed') ||
      lower.contains('dioexception') ||
      lower.contains('dio exception')) {
    return '';
  }
  return text;
}

int extractOtpStatus(Map<String, dynamic> raw) {
  final value = raw['status'];
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}

int extractOtpHttpStatus(Map<String, dynamic> raw) {
  final candidates = <dynamic>[
    raw['httpStatus'],
    raw['http_status'],
    if (raw['error'] is Map) (raw['error'] as Map)['httpStatus'],
    if (raw['error'] is Map) (raw['error'] as Map)['http_status'],
    if (raw['error'] is Map) (raw['error'] as Map)['status'],
  ];
  for (final c in candidates) {
    final v = int.tryParse('$c');
    if (v != null && v > 0) return v;
  }
  final code = raw['error'] is Map ? '${(raw['error'] as Map)['code']}' : '';
  final m = RegExp(r'(\d{3})').firstMatch(code);
  if (m != null) return int.tryParse(m.group(1) ?? '') ?? 0;
  return 0;
}

final _hardReason = RegExp(
  r'rate.?limit|limit.?exceed|hourly|hour.?limit|quota|otp.?(block|banned|suspend)|send.?(block|banned|suspend)',
  caseSensitive: false,
);

final _hardMessage = RegExp(
  r'الساعي|اليومي|تجاوزت الحد|تجاوز.*الحد|exceed.*limit|limit.*exceed|hourly|daily limit|maximum.*(attempt|request|code)',
  caseSensitive: false,
);

final _coolReason = RegExp(
  r'rate.?limit|too.?many|throttl|cooldown|limit.?exceed|hourly|otp.?(limit|cooldown|block)|send.?(limit|cooldown|block)',
  caseSensitive: false,
);

final _coolMessage = RegExp(
  r'انتظر|ثوان|ثانية|دقيقة|الساعي|ساعة|متاح|لاحق|مؤقت|كثير|الحد|إعادة|wait|second|minute|hour|availab|later|temporar|many|limit|throttl|too many|try again|retry|cooldown|rate.?limit',
  caseSensitive: false,
);

OtpSendKind classifyOtpFailure({
  required String reason,
  String message = '',
  int retryAfter = 0,
  int status = 0,
  int httpStatus = 0,
}) {
  final hasRetryWindow = retryAfter >= 1 && retryAfter <= 300;
  final hardByReason = reason.isNotEmpty && _hardReason.hasMatch(reason);
  final hardByMessage = message.isNotEmpty && _hardMessage.hasMatch(message);
  if ((hardByReason || hardByMessage) && !hasRetryWindow) {
    return OtpSendKind.hard_limit;
  }
  if (status == 429 || httpStatus == 429) return OtpSendKind.cooldown;
  if (retryAfter > 0) return OtpSendKind.cooldown;
  if (reason.isNotEmpty && _coolReason.hasMatch(reason)) {
    return OtpSendKind.cooldown;
  }
  if (message.isNotEmpty && _coolMessage.hasMatch(message)) {
    return OtpSendKind.cooldown;
  }
  return OtpSendKind.error;
}

OtpSendKind classifyOtpRaw(Map<String, dynamic> raw) {
  final message = extractOtpMessage(raw);
  final reason = extractOtpReason(raw);
  final retryAfter = extractOtpRetryAfter(raw, message);
  final status = extractOtpStatus(raw);
  final httpStatus = extractOtpHttpStatus(raw);
  return classifyOtpFailure(
    reason: reason,
    message: message,
    retryAfter: retryAfter,
    status: status,
    httpStatus: httpStatus,
  );
}

/// Gate for OTP resend: 60s button lock + capped background auto-resend.
class OtpResendGate {
  OtpResendGate({this.onChange});

  VoidCallback? onChange;

  DateTime allowedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _unlockTimer;
  Timer? _bgTimer;
  int bgTries = 0;
  static const int maxBgTries = 2;

  bool get canSend => !DateTime.now().isBefore(allowedAt);

  bool get canBackground => bgTries < maxBgTries;

  void lock([int extraSec = 0]) {
    final secs = extraSec > 60 ? extraSec : 60;
    allowedAt = DateTime.now().add(Duration(seconds: secs));
    _unlockTimer?.cancel();
    _unlockTimer = Timer(Duration(seconds: secs), () {
      onChange?.call();
    });
    onChange?.call();
  }

  void scheduleBackground(Duration delay, void Function() fire) {
    if (bgTries >= maxBgTries) return;
    _bgTimer?.cancel();
    _bgTimer = Timer(delay, () {
      bgTries += 1;
      fire();
    });
  }

  void cancelBackground() {
    _bgTimer?.cancel();
    _bgTimer = null;
  }

  void resetBackground() {
    bgTries = 0;
    cancelBackground();
  }

  void dispose() {
    _unlockTimer?.cancel();
    _unlockTimer = null;
    _bgTimer?.cancel();
    _bgTimer = null;
  }
}
