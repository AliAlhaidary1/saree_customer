import 'package:flutter_test/flutter_test.dart';

import 'package:sareemart_customer/core/promo_price.dart';

void main() {
  test('flash price wins over promo and discounted', () {
    final price = variantDisplayPrice({
      'price': 100,
      'discounted_price': 80,
      'promo_price': 70,
      'flash_price': 50,
      'is_flash': 1,
    });
    expect(price.finalPrice, 50);
    expect(price.isFlash, isTrue);
    expect(price.discountPercent, 50);
  });
}
