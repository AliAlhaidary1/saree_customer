import 'dart:io' show Platform;

class AppConfig {
  static const accessKey = '903361';
  static const accessKeyHeader = 'x-access-key';
  static const countryDialCode = '967';
  static const platform = 'android';

  /// Real device platform for FCM (`fcm_token` + `platform` fields).
  /// Backend distinguishes android/ios targets — never send a hardcoded value.
  static String get devicePlatform {
    try {
      return Platform.isIOS ? 'ios' : 'android';
    } catch (_) {
      return platform;
    }
  }
  static const defaultApiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://admin.marabmall.cloud',
  );

  static bool isUnreachableOnDevice(String url) {
    final value = url.toLowerCase();
    return value.contains('10.0.2.2') ||
        value.contains('127.0.0.1') ||
        value.contains('localhost');
  }

  static const apiSubUrl = String.fromEnvironment(
    'API_SUBURL',
    defaultValue: '/customer',
  );
  static const defaultColor = 0xFF0A2540;
  static const accentColor = 0xFFFF6B00;
  static const productPageSize = 12;
}
