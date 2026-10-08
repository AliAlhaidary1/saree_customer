import 'json_util.dart';

String? firstImageUrl(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }
  if (value is Map) {
    return firstImageUrl(
      value['image_url'] ??
          value['image'] ??
          value['url'] ??
          value['main_image'] ??
          value['thumbnail'],
    );
  }
  if (value is List) {
    for (final item in value) {
      final url = firstImageUrl(item);
      if (url != null) return url;
    }
  }
  return null;
}

List<String> productImageUrls(
  Map<String, dynamic>? product, {
  Map<String, dynamic>? variant,
}) {
  if (product == null) return const [];
  final seen = <String>{};
  final urls = <String>[];

  void add(dynamic value) {
    final url = firstImageUrl(value);
    if (url == null || seen.contains(url)) return;
    seen.add(url);
    urls.add(url);
  }

  add(variant);
  add(product['image_url']);
  add(product['image']);
  add(product['main_image']);
  add(product['thumbnail']);
  add(product['images']);
  for (final item in J.maps(product['variants'])) {
    add(item['image_url'] ?? item['image']);
  }
  return urls;
}

String productImageUrl(
  Map<String, dynamic>? product, {
  Map<String, dynamic>? variant,
  String placeholder = '',
}) {
  final urls = productImageUrls(product, variant: variant);
  if (urls.isNotEmpty) return urls.first;
  return placeholder;
}
