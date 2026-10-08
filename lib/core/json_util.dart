import 'dart:convert';

class J {
  static Map<String, dynamic> map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> maps(dynamic value) {
    if (value is! List) return const [];
    return value.map(map).toList();
  }

  static List<dynamic> list(dynamic value) {
    if (value is List) return value;
    return const [];
  }

  static String str(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString();
    return text == 'null' ? fallback : text;
  }

  static int i(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    return int.tryParse('$value') ?? fallback;
  }

  static double d(dynamic value, [double fallback = 0]) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }

  static bool flag(dynamic value, [bool fallback = false]) {
    if (value == null || value == '' || value == 'null') return fallback;
    return value == true || value == 1 || value == '1';
  }

  static dynamic sellerId(Map<String, dynamic>? product) {
    if (product == null) return null;
    return product['seller_id'] ?? map(product['seller'])['id'];
  }

  static String html(dynamic value) {
    if (value == null) return '';
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty || text == 'null' || text == '[]' || text == '{}') return '';
      if ((text.startsWith('{') && text.endsWith('}')) ||
          (text.startsWith('[') && text.endsWith(']'))) {
        try {
          return html(jsonDecode(text));
        } catch (_) {}
      }
      return value;
    }
    if (value is Map) {
      return html(
        value['html'] ??
            value['content'] ??
            value['data'] ??
            value['ar'] ??
            value['en'] ??
            value['privacy_policy'] ??
            value['terms_conditions'] ??
            value['about_us'] ??
            value['contact_us'],
      );
    }
    if (value is List && value.isNotEmpty) return html(value.first);
    return '';
  }
}

class ApiResult {
  ApiResult(this.raw);

  final Map<String, dynamic> raw;

  int get status => J.i(raw['status']);
  bool get ok => status == 1;
  String get message => J.str(raw['message'] ?? raw['msg']);
  dynamic get data => raw['data'];
  Map<String, dynamic> get dataMap => J.map(raw['data']);
  List<Map<String, dynamic>> get dataMaps => J.maps(raw['data']);
  Map<String, dynamic> get user => J.map(raw['user']);
  String? get token {
    final value = raw['token'] ?? raw['access_token'] ?? dataMap['token'];
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  int get oneSellerError =>
      J.i(raw['one_seller_error_code'] ?? dataMap['one_seller_error_code']);

  String get html {
    if (data is String) return J.html(data);
    final fromMap = J.html(dataMap);
    if (fromMap.trim().isNotEmpty) return fromMap;
    return J.html(data);
  }
}
