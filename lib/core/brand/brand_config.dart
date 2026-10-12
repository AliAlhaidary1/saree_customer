import 'package:flutter/material.dart';

/// Platform brand tokens from /customer/brand API with offline fallbacks.
class BrandConfig {
  const BrandConfig({
    required this.version,
    required this.identity,
    required this.colors,
    required this.assets,
  });

  final int version;
  final Map<String, String> identity;
  final Map<String, String> colors;
  final Map<String, String?> assets;

  static const defaults = BrandConfig(
    version: 1,
    identity: {
      'name_ar': 'سريع MART',
      'name_en': 'SAREE MART',
    },
    colors: {
      'primary': '#0A2540',
      'primary_soft': '#123152',
      'accent': '#FF6B00',
      'accent_dark': '#E05E00',
      'background': '#FFFFFF',
      'surface': '#F3F4F6',
      'text_primary': '#0A2540',
      'text_secondary': '#6B7280',
      'error': '#DC2626',
      'success': '#16A34A',
    },
    assets: {},
  );

  factory BrandConfig.fromJson(Map<String, dynamic> json) {
    final base = defaults;
    final identity = Map<String, String>.from(base.identity);
    final id = json['identity'];
    if (id is Map) {
      id.forEach((k, v) => identity['$k'] = '$v');
    }

    final colors = Map<String, String>.from(base.colors);
    final c = json['colors'];
    if (c is Map) {
      c.forEach((k, v) {
        if (v != null && '$v'.isNotEmpty) colors['$k'] = '$v';
      });
    }

    final assets = <String, String?>{};
    final a = json['assets'];
    if (a is Map) {
      a.forEach((k, v) {
        final key = '$k';
        if (key.endsWith('_url')) {
          assets[key] = v == null ? null : '$v';
        } else if (v != null && '$v'.isNotEmpty) {
          assets[key] = '$v';
          final url = a['${key}_url'];
          if (url != null) assets['${key}_url'] = '$url';
        }
      });
    }

    return BrandConfig(
      version: int.tryParse('${json['version']}') ?? base.version,
      identity: identity,
      colors: colors,
      assets: assets,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'identity': identity,
        'colors': colors,
        'assets': assets,
      };

  String get nameAr => identity['name_ar'] ?? defaults.identity['name_ar']!;
  String get nameEn => identity['name_en'] ?? defaults.identity['name_en']!;

  Color get primary => _color('primary', 0xFF0A2540);
  Color get accent => _color('accent', 0xFFFF6B00);
  Color get accentDark => _color('accent_dark', 0xFFE05E00);
  Color get background => _color('background', 0xFFFFFFFF);
  Color get surface => _color('surface', 0xFFF3F4F6);
  Color get textPrimary => _color('text_primary', 0xFF0A2540);
  Color get textSecondary => _color('text_secondary', 0xFF6B7280);
  Color get error => _color('error', 0xFFDC2626);
  Color get success => _color('success', 0xFF16A34A);

  String? get logoUrl =>
      assets['logo_png_url'] ?? assets['logo_svg_url'] ?? assets['logo_png'];

  Color _color(String key, int fallback) {
    final raw = colors[key];
    if (raw == null || raw.isEmpty) return Color(fallback);
    var hex = raw.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}
