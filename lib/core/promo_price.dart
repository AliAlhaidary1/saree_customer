class DisplayPrice {
  const DisplayPrice({
    required this.finalPrice,
    required this.original,
    required this.isFlash,
    required this.hasDiscount,
    required this.discountPercent,
  });

  final double finalPrice;
  final double original;
  final bool isFlash;
  final bool hasDiscount;
  final int discountPercent;
}

DisplayPrice variantDisplayPrice(Map<String, dynamic>? variant) {
  if (variant == null) {
    return const DisplayPrice(
      finalPrice: 0,
      original: 0,
      isFlash: false,
      hasDiscount: false,
      discountPercent: 0,
    );
  }
  final original = double.tryParse('${variant['price']}') ?? 0;
  var finalPrice = original;
  var isFlash = false;

  final flashPrice = double.tryParse('${variant['flash_price']}') ?? 0;
  final promoPrice = double.tryParse('${variant['promo_price']}') ?? 0;
  final discounted = double.tryParse('${variant['discounted_price']}') ?? 0;
  final hasOriginal = original > 0;

  if ((variant['is_flash'] == true ||
          variant['is_flash'] == 1 ||
          variant['is_flash'] == '1') &&
      flashPrice > 0 &&
      (!hasOriginal || flashPrice < original)) {
    finalPrice = flashPrice;
    isFlash = true;
  } else if (promoPrice > 0 && hasOriginal && promoPrice < original) {
    finalPrice = promoPrice;
  } else if (discounted > 0 && hasOriginal && discounted < original) {
    finalPrice = discounted;
  }

  final hasDiscount = finalPrice > 0 && original > 0 && finalPrice < original;
  final discountPercent = hasDiscount
      ? (((original - finalPrice) / original) * 100).round()
      : 0;

  return DisplayPrice(
    finalPrice: finalPrice,
    original: original,
    isFlash: isFlash,
    hasDiscount: hasDiscount,
    discountPercent: discountPercent,
  );
}

String formatCountdown(int totalSeconds) {
  final s = totalSeconds < 0 ? 0 : totalSeconds;
  final h = (s ~/ 3600).toString().padLeft(2, '0');
  final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final sec = (s % 60).toString().padLeft(2, '0');
  return '$h:$m:$sec';
}

String money(dynamic amount, String currency, [int decimals = 2]) {
  final value = double.tryParse('$amount') ?? 0;
  return '${value.toStringAsFixed(decimals)} $currency';
}
