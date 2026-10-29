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

  test('ignores flash/discounted prices that exceed the original', () {
    final flash = variantDisplayPrice({
      'price': 100,
      'flash_price': 120,
      'discounted_price': 130,
      'is_flash': 1,
    });
    expect(flash.finalPrice, 100);
    expect(flash.isFlash, isFalse);
    expect(flash.hasDiscount, isFalse);

    final discounted = variantDisplayPrice({
      'price': 100,
      'discounted_price': 130,
    });
    expect(discounted.finalPrice, 100);
    expect(discounted.hasDiscount, isFalse);
  });

  test('invalid flash falls back to a valid promo price', () {
    final price = variantDisplayPrice({
      'price': 100,
      'flash_price': 110,
      'promo_price': 75,
      'is_flash': 1,
    });
    expect(price.finalPrice, 75);
    expect(price.isFlash, isFalse);
    expect(price.discountPercent, 25);
  });
}
