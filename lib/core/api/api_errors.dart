import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../json_util.dart';

enum ApiRequestKind { public, private, mutation }

/// Stable error categories used for retry and sync decisions.
/// Do NOT rely on user-visible [ClassifiedApiError.userMessage] for logic.
enum ApiErrorCategory {
  /// Network unreachable / timeout / DNS. Safe to retry for idempotent reads.
  network,

  /// Server 5xx. Safe to retry for idempotent reads.
  server,

  /// 401/403. Authentication/authorization failure; do not retry blindly.
  auth,

  /// 422 / validation / business-rule failure. Do not retry the same payload.
  validation,

  /// 404 / not found. Treat as permanent for mutations, retryable for reads
  /// only when the resource is expected to exist later.
  notFound,

  /// 429 rate limited. Retry after [retryAfter] if provided.
  rateLimit,

  /// Response could not be parsed. Usually transient.
  malformed,

  /// Unknown / unexpected. Conservative: do not retry mutations.
  unknown,
}

class ApiErrorPolicy {
  const ApiErrorPolicy({required this.release});

  final bool release;

  static ApiErrorPolicy current = ApiErrorPolicy(
    release: const bool.fromEnvironment('dart.vm.product'),
  );
}

class ClassifiedApiError {
  const ClassifiedApiError({
    required this.code,
    required this.publicCode,
    required this.originalMessage,
    required this.userMessage,
    required this.release,
    required this.category,
    this.httpStatus,
    this.cause,
    this.details,
    this.retryAfter,
  });

  final String code;
  final String publicCode;
  final String originalMessage;
  final String userMessage;
  final bool release;
  final int? httpStatus;
  final String? cause;
  final Object? details;
  final ApiErrorCategory category;

  /// Seconds to wait before retrying when the server returns 429 or a
  /// Retry-After header. Null when not applicable.
  final int? retryAfter;

  Map<String, dynamic> toResultMap() {
    if (!release) {
      return {
        'status': 0,
        'message': originalMessage,
        'error': {
          'code': code,
          'httpStatus': httpStatus,
          'cause': cause,
          'details': details,
        },
      };
    }
    return {
      'status': 0,
      'message': userMessage,
      'error': {'code': publicCode},
    };
  }
}

/// Extracts the classified error produced by [CustomerApi._guard].
extension ApiResultErrorX on ApiResult {
  ClassifiedApiError? get classifiedError {
    final err = raw['error'];
    if (err is! Map) return null;
    final httpStatus = err['httpStatus'] is int ? err['httpStatus'] as int : null;
    final code = '${err['code'] ?? 'UNKNOWN'}';
    return ClassifiedApiError(
      code: code,
      publicCode: '${err['publicCode'] ?? _publicCodes[code] ?? 'UNAVAILABLE'}',
      originalMessage: '${raw['message'] ?? ''}',
      userMessage: '${raw['message'] ?? _userMessages[code] ?? _userMessages['UNKNOWN']!}',
      release: true,
      category: _categoryFor(code: code, httpStatus: httpStatus),
      httpStatus: httpStatus,
      details: err['details'],
      retryAfter: err['retryAfter'] is int ? err['retryAfter'] as int : null,
    );
  }
}

final _sensitive = RegExp(
  r'(sqlstate|stack trace|Bearer\s+\S+|access_token|mysql_|postgres|Illuminate\\|PDOException|/var/www|/home/|APP_KEY|localhost:\d+|127\.0\.0\.1)',
  caseSensitive: false,
);

const _userMessages = <String, String>{
  'ECONNREFUSED': 'تعذر الاتصال بالخادم. حاول لاحقاً.',
  'TIMEOUT': 'انتهت مهلة الطلب. حاول مرة أخرى.',
  'HTTP_500': 'حدث خطأ في الخادم. حاول لاحقاً.',
  'HTTP_422': 'تحقق من البيانات المدخلة وحاول مرة أخرى.',
  'HTTP_429': 'الخدمة مشغولة. حاول مرة أخرى بعد قليل.',
  'HTTP_401': 'انتهت الجلسة. سجّل الدخول مجدداً.',
  'HTTP_403': 'ليست لديك صلاحية لهذا الإجراء.',
  'HTTP_404': 'العنصر المطلوب غير موجود.',
  'MALFORMED_RESPONSE': 'استجابة غير متوقعة من الخادم.',
  'AUTH_ERROR': 'فشل التحقق من الهوية. حاول مرة أخرى.',
  'LARAVEL_EXCEPTION': 'حدث خطأ في الخادم. حاول لاحقاً.',
  'NETWORK': 'تعذر الاتصال بالخادم. تحقق من الإنترنت.',
  'UNKNOWN': 'حدث خطأ ما. حاول مرة أخرى.',
};

const _publicCodes = <String, String>{
  'ECONNREFUSED': 'UNAVAILABLE',
  'TIMEOUT': 'TIMEOUT',
  'HTTP_500': 'UNAVAILABLE',
  'HTTP_422': 'VALIDATION',
  'HTTP_429': 'RATE_LIMIT',
  'HTTP_401': 'AUTH',
  'HTTP_403': 'FORBIDDEN',
  'HTTP_404': 'NOT_FOUND',
  'MALFORMED_RESPONSE': 'UNAVAILABLE',
  'AUTH_ERROR': 'AUTH',
  'LARAVEL_EXCEPTION': 'UNAVAILABLE',
  'NETWORK': 'UNAVAILABLE',
  'UNKNOWN': 'UNAVAILABLE',
};

bool containsSensitive(String? value) {
  if (value == null || value.isEmpty) return false;
  return _sensitive.hasMatch(value);
}

bool looksLikeLaravelException(dynamic data) {
  if (data is! Map) return false;
  return data.containsKey('exception') ||
      data.containsKey('trace') ||
      (data.containsKey('file') && data.containsKey('line'));
}

ApiRequestKind inferRequestKind(String path, {String method = 'GET'}) {
  final value = path.toLowerCase();
  // Non-idempotent / financial operations: never auto-retried.
  if (RegExp(
    r'place_order|place_multi_seller|checkout|add_transaction|initiate_transaction|update_status|update_order_status|akhdimni/place|payment|cart/add|cart/remove|cart/bulk|favorites/add|favorites/remove|address/add|address/update|address/delete|login|register|haraj/posts/create|complaints',
  ).hasMatch(value)) {
    return ApiRequestKind.mutation;
  }
  if (method.toUpperCase() != 'GET') return ApiRequestKind.private;
  // Idempotent public catalog reads: safe for one bounded retry in release.
  if (RegExp(
    r'^(sliders|offers|brands|countries|sellers|seller/|categories|shop|sections|flash_sales|campaigns|managed-campaigns|cities|settings|faqs|countries)',
  ).hasMatch(value)) {
    return ApiRequestKind.public;
  }
  return ApiRequestKind.private;
}

bool shouldRetryApi({
  required ClassifiedApiError error,
  required int attempt,
  required ApiRequestKind kind,
  required bool release,
}) {
  if (!release) return false;
  if (kind != ApiRequestKind.public) return false;
  if (attempt >= 1) return false;
  return error.code == 'ECONNREFUSED' ||
      error.code == 'TIMEOUT' ||
      error.code == 'NETWORK';
}

void logApiFailure(ClassifiedApiError error, {String? path}) {
  if (const bool.fromEnvironment('dart.vm.product')) return;
  debugPrint(
    '[backend] code=${error.code} status=${error.httpStatus} path=$path message=${error.originalMessage}',
  );
}

ClassifiedApiError classifyDio(DioException error, {required bool release}) {
  final status = error.response?.statusCode;
  final data = error.response?.data;
  final message = error.message ?? error.toString();
  final type = error.type;
  final osCode = error.error?.toString() ?? '';

  if (type == DioExceptionType.connectionTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.receiveTimeout) {
    return _build('TIMEOUT', message, release, httpStatus: 504, cause: type.name);
  }

  if (type == DioExceptionType.connectionError ||
      osCode.contains('ECONNREFUSED') ||
      message.contains('ECONNREFUSED') ||
      osCode.contains('Connection refused')) {
    final code = (osCode.contains('ECONNREFUSED') ||
            message.contains('ECONNREFUSED') ||
            osCode.contains('Connection refused'))
        ? 'ECONNREFUSED'
        : 'NETWORK';
    return _build(code, message, release, httpStatus: 502, cause: osCode);
  }

  if (status == 422) {
    return _build(
      'HTTP_422',
      _messageFromBody(data, 'HTTP 422'),
      release,
      httpStatus: 422,
      details: data,
    );
  }

  if (status == 429) {
    final retryAfterRaw = error.response?.headers.value('retry-after') ??
        (data is Map ? data['retry_after'] ?? data['retryAfter'] : null);
    int? retryAfter;
    if (retryAfterRaw != null) {
      retryAfter = int.tryParse('$retryAfterRaw');
    }
    return _build(
      'HTTP_429',
      _messageFromBody(data, 'HTTP 429'),
      release,
      httpStatus: 429,
      details: data,
      retryAfter: retryAfter,
    );
  }

  if (status == 401 || status == 403) {
    return _build(
      status == 401 ? 'HTTP_401' : 'HTTP_403',
      _messageFromBody(data, 'HTTP $status'),
      release,
      httpStatus: status,
      details: data,
    );
  }

  if (looksLikeLaravelException(data) || containsSensitive('$data')) {
    return _build(
      'LARAVEL_EXCEPTION',
      _messageFromBody(data, message),
      release,
      httpStatus: status ?? 500,
      details: data,
    );
  }

  if (status != null && status >= 500) {
    final malformed = data is! Map;
    return _build(
      malformed ? 'MALFORMED_RESPONSE' : 'HTTP_500',
      _messageFromBody(data, 'HTTP $status'),
      release,
      httpStatus: status,
      details: data,
    );
  }

  if (type == DioExceptionType.badResponse) {
    if (status == 404) {
      return _build(
        'HTTP_404',
        _messageFromBody(data, message),
        release,
        httpStatus: 404,
        details: data,
      );
    }
    if (status != null && status >= 400 && status < 500) {
      return _build(
        'HTTP_422',
        _messageFromBody(data, message),
        release,
        httpStatus: status,
        details: data,
      );
    }
    return _build(
      'HTTP_500',
      _messageFromBody(data, message),
      release,
      httpStatus: status ?? 500,
      details: data,
    );
  }

  return _build('UNKNOWN', message, release, cause: type.name, details: data);
}

ClassifiedApiError classifyUnknown(Object error, {required bool release}) {
  final message = '$error';
  if (message.contains('ECONNREFUSED') || message.contains('Connection refused')) {
    return _build('ECONNREFUSED', message, release, httpStatus: 502);
  }
  if (message.toLowerCase().contains('timeout')) {
    return _build('TIMEOUT', message, release, httpStatus: 504);
  }
  return _build('UNKNOWN', message, release);
}

ApiErrorCategory _categoryFor({required String code, int? httpStatus}) {
  switch (code) {
    case 'ECONNREFUSED':
    case 'TIMEOUT':
    case 'NETWORK':
      return ApiErrorCategory.network;
    case 'HTTP_500':
    case 'LARAVEL_EXCEPTION':
      return ApiErrorCategory.server;
    case 'HTTP_401':
    case 'HTTP_403':
      return ApiErrorCategory.auth;
    case 'HTTP_422':
      return ApiErrorCategory.validation;
    case 'HTTP_404':
      return ApiErrorCategory.notFound;
    case 'MALFORMED_RESPONSE':
      return ApiErrorCategory.malformed;
    case 'HTTP_429':
      return ApiErrorCategory.rateLimit;
    default:
      if (httpStatus == 429) return ApiErrorCategory.rateLimit;
      if (httpStatus != null && httpStatus >= 500) return ApiErrorCategory.server;
      if (httpStatus == 401 || httpStatus == 403) return ApiErrorCategory.auth;
      if (httpStatus == 422) return ApiErrorCategory.validation;
      if (httpStatus == 404) return ApiErrorCategory.notFound;
      return ApiErrorCategory.unknown;
  }
}

ClassifiedApiError _build(
  String code,
  String original,
  bool release, {
  int? httpStatus,
  String? cause,
  Object? details,
  int? retryAfter,
}) {
  var userMessage = _userMessages[code] ?? _userMessages['UNKNOWN']!;
  if (code == 'HTTP_422' && !containsSensitive(original)) {
    userMessage = original;
  }
  return ClassifiedApiError(
    code: code,
    publicCode: _publicCodes[code] ?? 'UNAVAILABLE',
    originalMessage: original,
    userMessage: userMessage,
    release: release,
    category: _categoryFor(code: code, httpStatus: httpStatus),
    httpStatus: httpStatus,
    cause: cause,
    details: release ? _sanitizeDetails(details) : details,
    retryAfter: retryAfter,
  );
}

Object? _sanitizeDetails(Object? details) {
  if (details is Map) {
    final out = <String, dynamic>{};
    details.forEach((key, value) {
      final name = '$key'.toLowerCase();
      if (name.contains('token') ||
          name.contains('exception') ||
          name.contains('trace') ||
          name.contains('sql') ||
          name == 'file' ||
          name == 'line') {
        return;
      }
      out['$key'] = value;
    });
    return out;
  }
  if (details is String && containsSensitive(details)) return '[redacted]';
  return null;
}

String _messageFromBody(dynamic data, String fallback) {
  if (data is Map) {
    final message = data['message'] ?? data['msg'] ?? data['error'];
    if (message is String && message.trim().isNotEmpty) return message;
  }
  if (data is String && data.trim().isNotEmpty) {
    try {
      final parsed = jsonDecode(data);
      return _messageFromBody(parsed, fallback);
    } catch (_) {
      return data.length > 300 ? fallback : data;
    }
  }
  return fallback;
}
