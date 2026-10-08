import 'json_util.dart';

class BusinessHoursSlot {
  BusinessHoursSlot({
    required this.isOpen,
    this.nextOpeningAt,
    this.storeName,
    this.sellerId,
  });
  final bool isOpen;
  final String? nextOpeningAt;
  final String? storeName;
  final String? sellerId;

  static BusinessHoursSlot? from(dynamic raw) {
    if (raw == null) return null;
    final m = J.map(raw);
    if (m.isEmpty) return null;
    return BusinessHoursSlot(
      isOpen: m['is_open'] == true || m['is_open'] == 1 || m['is_open'] == '1',
      nextOpeningAt: m['next_opening_at']?.toString(),
      storeName: J.str(m['store_name']).isEmpty ? null : J.str(m['store_name']),
      sellerId: m['seller_id']?.toString() ?? m['id']?.toString(),
    );
  }
}

class BusinessHoursResult {
  BusinessHoursResult({this.platform, this.sellers = const {}});
  final BusinessHoursSlot? platform;
  final Map<String, BusinessHoursSlot> sellers;

  static BusinessHoursResult from(ApiResult res) {
    final data = res.dataMap.isNotEmpty ? res.dataMap : J.map(res.raw['data']);
    return fromMap(data);
  }

  static BusinessHoursResult fromMap(Map<String, dynamic> data) {
    final platform = BusinessHoursSlot.from(data['platform']);
    final sellersRaw = J.map(data['sellers']);
    final sellers = <String, BusinessHoursSlot>{};
    sellersRaw.forEach((k, v) {
      final slot = BusinessHoursSlot.from(v);
      if (slot != null) sellers[k] = slot;
    });
    if (sellers.isEmpty && data['sellers'] is List) {
      for (final item in J.maps(data['sellers'])) {
        final sid = '${item['seller_id'] ?? item['id']}';
        final slot = BusinessHoursSlot.from(item);
        if (sid.isNotEmpty && slot != null) sellers[sid] = slot;
      }
    }
    return BusinessHoursResult(platform: platform, sellers: sellers);
  }
}

String formatBusinessTime(String? value) {
  if (value == null || value.isEmpty) return '';
  final parts = value.split(':');
  if (parts.length < 2) return value;
  return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
}

String buildMarketplaceClosedMessage(BusinessHoursSlot? platform) {
  if (platform == null || platform.isOpen) return '';
  final t = formatBusinessTime(platform.nextOpeningAt);
  if (t.isNotEmpty) return 'المنصة مغلقة حالياً حتى $t';
  return 'المنصة مغلقة حالياً';
}

String buildSellerClosedMessage(BusinessHoursSlot? seller, String storeName) {
  if (seller == null || seller.isOpen) return '';
  final name = storeName.trim().isNotEmpty
      ? storeName.trim()
      : (seller.storeName ?? '');
  final label = name.isNotEmpty ? name : 'البائع';
  final t = formatBusinessTime(seller.nextOpeningAt);
  if (t.isNotEmpty) return 'المتجر البائع ($label) مغلق حتى $t';
  return 'المتجر البائع ($label) مغلق حالياً';
}

enum ProductClosedKind { none, platform, seller }

ProductClosedKind productClosedKind(
  Map<String, dynamic>? product, {
  BusinessHoursResult? hours,
}) {
  if (hours?.platform != null && !hours!.platform!.isOpen) {
    return ProductClosedKind.platform;
  }
  final sellerHours = BusinessHoursSlot.from(
    product?['seller_business_hours'] ??
        product?['business_hours'] ??
        J.map(product?['seller'])['business_hours'],
  );
  if (sellerHours != null && !sellerHours.isOpen) {
    return ProductClosedKind.seller;
  }
  final sid = J.sellerId(product);
  if (sid != null && hours != null) {
    final cached = hours.sellers['$sid'];
    if (cached != null && !cached.isOpen) return ProductClosedKind.seller;
  }
  final flag = product?['seller_is_open'];
  if (flag == false || flag == 0 || flag == '0') {
    return ProductClosedKind.seller;
  }
  return ProductClosedKind.none;
}

String productClosedBadgeLabel(ProductClosedKind kind) {
  switch (kind) {
    case ProductClosedKind.platform:
      return 'المنصة مغلقة';
    case ProductClosedKind.seller:
      return 'مغلق';
    case ProductClosedKind.none:
      return '';
  }
}

class CanPlaceOrderResult {
  CanPlaceOrderResult({required this.allowed, this.reason, this.status});
  final bool allowed;
  final String? reason; // platform | seller | unavailable
  final BusinessHoursSlot? status;
}

CanPlaceOrderResult canPlaceOrderFromBusinessHours(BusinessHoursResult? bh) {
  if (bh == null) return CanPlaceOrderResult(allowed: false, reason: 'unavailable');
  if (bh.platform != null && !bh.platform!.isOpen) {
    return CanPlaceOrderResult(allowed: false, reason: 'platform', status: bh.platform);
  }
  for (final e in bh.sellers.values) {
    if (!e.isOpen) return CanPlaceOrderResult(allowed: false, reason: 'seller', status: e);
  }
  return CanPlaceOrderResult(allowed: true);
}

BusinessHoursSlot? closedSellerFromCheckout(BusinessHoursResult? bh) {
  if (bh == null) return null;
  for (final s in bh.sellers.values) {
    if (!s.isOpen) return s;
  }
  return null;
}

String? addToCartClosedMessage({
  required BusinessHoursResult? hours,
  dynamic sellerId,
  String storeName = '',
}) {
  if (hours == null) return null;
  if (hours.platform != null && !hours.platform!.isOpen) {
    return buildMarketplaceClosedMessage(hours.platform);
  }
  if (sellerId == null) return null;
  final key = '$sellerId';
  final seller = hours.sellers[key];
  if (seller != null && !seller.isOpen) {
    return buildSellerClosedMessage(seller, storeName);
  }
  return null;
}
