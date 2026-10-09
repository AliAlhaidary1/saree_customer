import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sreamart_customer/core/api/api_errors.dart';

void main() {
  group('development: detailed errors remain visible', () {
    test('preserves ECONNREFUSED', () {
      final classified = classifyDio(
        DioException(
          requestOptions: RequestOptions(path: '/settings'),
          type: DioExceptionType.connectionError,
          error: 'SocketException: Connection refused ECONNREFUSED 127.0.0.1:8000',
          message: 'connect ECONNREFUSED 127.0.0.1:8000',
        ),
        release: false,
      );
      expect(classified.code, 'ECONNREFUSED');
      final map = classified.toResultMap();
      expect(map['status'], 0);
      expect(map['message'], contains('ECONNREFUSED'));
      expect(map['error']['code'], 'ECONNREFUSED');
    });

    test('preserves timeout details', () {
      final classified = classifyDio(
        DioException(
          requestOptions: RequestOptions(path: '/shop'),
          type: DioExceptionType.receiveTimeout,
          message: 'The request timed out',
        ),
        release: false,
      );
      expect(classified.code, 'TIMEOUT');
      expect(classified.toResultMap()['message'], contains('timed out'));
    });

    test('preserves Laravel exception and SQL error', () {
      final classified = classifyDio(
        DioException(
          requestOptions: RequestOptions(path: '/place_order'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/place_order'),
            statusCode: 500,
            data: {
              'message': 'SQLSTATE[HY000]: General error',
              'exception': r'Illuminate\Database\QueryException',
              'file': '/var/www/app/Http/Controllers/OrderController.php',
              'line': 88,
              'trace': [
                {'file': '/var/www/vendor/laravel/framework/src/Illuminate/Database/Connection.php'},
              ],
            },
          ),
        ),
        release: false,
      );
      expect(classified.code, 'LARAVEL_EXCEPTION');
      final map = classified.toResultMap();
      expect(map['message'], contains('SQLSTATE'));
      expect('${map['error']['details']}', contains('Illuminate'));
    });

    test('preserves HTTP 422 validation', () {
      final classified = classifyDio(
        DioException(
          requestOptions: RequestOptions(path: '/register'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/register'),
            statusCode: 422,
            data: {
              'message': 'The mobile field is required.',
              'errors': {'mobile': ['required']},
            },
          ),
        ),
        release: false,
      );
      expect(classified.code, 'HTTP_422');
      expect(classified.toResultMap()['message'], contains('mobile field is required'));
    });

    test('preserves authentication errors', () {
      final classified = classifyDio(
        DioException(
          requestOptions: RequestOptions(path: '/user_details'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/user_details'),
            statusCode: 401,
            data: {'message': 'Unauthenticated.'},
          ),
        ),
        release: false,
      );
      expect(classified.code, 'HTTP_401');
      expect(classified.toResultMap()['message'], contains('Unauthenticated'));
    });
  });

  group('production: sanitizes internals and returns user-safe fallback', () {
    test('hides SQL, Laravel class, paths, and traces', () {
      final classified = classifyDio(
        DioException(
          requestOptions: RequestOptions(path: '/place_order'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/place_order'),
            statusCode: 500,
            data: {
              'message': 'SQLSTATE[HY000]: General error',
              'exception': r'Illuminate\Database\QueryException',
              'file': '/var/www/app/Http/Controllers/OrderController.php',
              'line': 88,
              'access_token': 'secret-token-value',
              'trace': ['/var/www/vendor/laravel'],
            },
          ),
        ),
        release: true,
      );
      final map = classified.toResultMap();
      final serialized = map.toString();
      expect(map['status'], 0);
      expect(serialized.contains('SQLSTATE'), isFalse);
      expect(serialized.contains('Illuminate'), isFalse);
      expect(serialized.contains('/var/www'), isFalse);
      expect(serialized.contains('secret-token-value'), isFalse);
      expect(map['error']['code'], 'UNAVAILABLE');
      expect(map['message'], isNot(contains('SQLSTATE')));
    });

    test('hides ECONNREFUSED and internal URLs', () {
      final classified = classifyDio(
        DioException(
          requestOptions: RequestOptions(path: '/settings'),
          type: DioExceptionType.connectionError,
          error: 'Connection refused 127.0.0.1:8000 ECONNREFUSED',
          message: 'connect ECONNREFUSED 127.0.0.1:8000',
        ),
        release: true,
      );
      final serialized = classified.toResultMap().toString();
      expect(serialized.contains('ECONNREFUSED'), isFalse);
      expect(serialized.contains('127.0.0.1'), isFalse);
      expect(classified.toResultMap()['error']['code'], 'UNAVAILABLE');
    });

    test('failed checkout/payment is never status=1', () {
      final classified = classifyDio(
        DioException(
          requestOptions: RequestOptions(path: '/place_order'),
          type: DioExceptionType.receiveTimeout,
          message: 'timeout',
        ),
        release: true,
      );
      expect(classified.toResultMap()['status'], 0);
      expect(inferRequestKind('/place_order', method: 'POST'), ApiRequestKind.mutation);
      expect(
        shouldRetryApi(
          error: classified,
          attempt: 0,
          kind: ApiRequestKind.mutation,
          release: true,
        ),
        isFalse,
      );
    });
  });

  group('retry policy', () {
    test('development does not retry', () {
      final error = classifyUnknown('ECONNREFUSED', release: false);
      expect(
        shouldRetryApi(
          error: error,
          attempt: 0,
          kind: ApiRequestKind.public,
          release: false,
        ),
        isFalse,
      );
    });

    test('production retries public network failures once', () {
      final error = classifyUnknown('ECONNREFUSED', release: true);
      expect(
        shouldRetryApi(
          error: error,
          attempt: 0,
          kind: ApiRequestKind.public,
          release: true,
        ),
        isTrue,
      );
      expect(
        shouldRetryApi(
          error: error,
          attempt: 1,
          kind: ApiRequestKind.public,
          release: true,
        ),
        isFalse,
      );
    });
  });

  test('sensitive detector', () {
    expect(containsSensitive('SQLSTATE[HY000]'), isTrue);
    expect(containsSensitive('Bearer abc.def'), isTrue);
    expect(looksLikeLaravelException({
      'exception': 'Error',
      'file': '/app/x.php',
      'line': 1,
    }), isTrue);
  });
}
