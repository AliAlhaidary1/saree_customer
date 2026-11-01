import '../../core/json_util.dart';

/// Converts web/backend locations to routes implemented by the Flutter app.
String assistantAppPath(String path) {
  const map = {
    '/?login=1': '/login',
    '/login': '/login',
    '/forgot-password': '/login',
    '/faqs': '/faq',
    '/faq': '/faq',
    '/privacy-policy': '/privacy',
    '/returns': '/policy/ReturnsAndExchangesPolicy',
    '/shipping': '/policy/Shipping_Policy',
    '/cancellation': '/policy/Cancellation_Policy',
    '/favorites': '/wishlist',
    '/orders': '/orders',
    '/profile/orders': '/orders',
    '/addresses': '/addresses',
    '/profile/address': '/addresses',
    '/wallet': '/wallet',
    '/profile/wallet-transaction': '/wallet',
    '/seller/register': '/register',
    '/register/customer': '/register',
    '/register/seller': '/register',
    '/register/delivery': '/register',
    '/categories': '/',
    '/flash-sales': '/offers',
    '/profile/wishlist': '/wishlist',
  };
  final raw = path.trim();
  if (raw.isEmpty || raw == '#') return '/';
  if (map.containsKey(raw)) return map[raw]!;
  if (raw.startsWith('/store/')) {
    return '/store/${raw.substring('/store/'.length)}';
  }
  return raw;
}

/// Normalizes both contracts supported by the backend:
/// 1) a direct product object, and 2) a PRODUCT_CARD containing `product`.
Map<String, dynamic> assistantProductAction(Map<String, dynamic> card) {
  final nested = J.map(card['product']);
  final source = nested.isNotEmpty ? nested : card;
  final url = J.str(
    source['url'] ?? source['path'] ?? card['url'] ?? card['path'],
  );
  final image = J.str(source['image'] ?? source['image_url']);
  final price = source['price'] ?? source['price_text'];
  return {
    'type': 'PRODUCT_CARD',
    'label': J.str(card['label']).isNotEmpty
        ? J.str(card['label'])
        : J.str(source['name']),
    'url': url,
    'product': {
      ...source,
      if (url.isNotEmpty) 'url': url,
      if (image.isNotEmpty) 'image': image,
      'price': ?price,
    },
  };
}

List<Map<String, dynamic>> assistantProductActions(dynamic raw) {
  return J.maps(raw).map(assistantProductAction).toList(growable: false);
}
