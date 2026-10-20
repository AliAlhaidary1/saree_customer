import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class I18n extends ChangeNotifier {
  I18n();

  String code = 'ar';
  Map<String, String> _strings = {};

  /// Dart-side fallbacks keep newly added labels translated even when the
  /// bundled JSON assets are stale (e.g. after a hot reload without restart).
  static const _fallbacks = <String, Map<String, String>>{
    'ar': {
      'order_number': 'رقم الطلب',
      'order_items': 'عناصر الطلب',
      'unknown_date': 'تاريخ غير معروف',
      'cached_data': 'مخزن مؤقتاً',
      'delivery_to_home': 'توصيل للبيت',
      'delivery_to_office': 'توصيل للمكتب',
      'delivery_to_shop': 'توصيل للمتجر',
      'delivery_to_other': 'توصيل لعنوان آخر',
    },
    'en': {
      'order_number': 'Order Number',
      'order_items': 'Order Items',
      'unknown_date': 'Unknown date',
      'cached_data': 'Cached',
      'delivery_to_home': 'Home delivery',
      'delivery_to_office': 'Office delivery',
      'delivery_to_shop': 'Shop delivery',
      'delivery_to_other': 'Delivery to another address',
    },
  };

  bool get isRtl => code == 'ar';
  TextDirection get direction => isRtl ? TextDirection.rtl : TextDirection.ltr;
  Locale get locale => Locale(code);

  String t(String key) => _strings[key] ?? _fallbacks[code]?[key] ?? key;

  Future<void> load(String languageCode) async {
    code = languageCode == 'en' ? 'en' : 'ar';
    final raw = await rootBundle.loadString('assets/i18n/$code.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _strings = decoded.map((key, value) => MapEntry(key, '$value'));
    notifyListeners();
  }
}
