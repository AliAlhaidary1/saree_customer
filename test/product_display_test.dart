import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/promo_price.dart';
import 'package:sareemart_customer/widgets/closed_store_badge.dart';
import 'package:sareemart_customer/widgets/product_card.dart';
import 'package:sareemart_customer/widgets/store_card.dart';

// ── Display math ────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    appController.injectForTest(prefs: prefs, testApi: CustomerApi(baseUrl: 'http://test.invalid'));
    appController.favoriteIds = [];
    appController.token = null;
    appController.user = null;
    appController.businessHours = null;
    appController.cartProducts = [];
    appController.cartSubTotal = 0;
    appController.settings = {
      'currency': 'ر.س',
      'decimal_point': 2,
      'web_settings': <String, dynamic>{},
    };
  });

  group('variantDisplayPrice', () {
    DisplayPrice p(Map<String, dynamic>? v) => variantDisplayPrice(v);

    test('null variant yields a zero price (never crashes)', () {
      final r = p(null);
      expect(r.finalPrice, 0);
      expect(r.hasDiscount, isFalse);
      expect(r.isFlash, isFalse);
    });

    test('plain price without any discount fields', () {
      final r = p({'price': 100});
      expect(r.finalPrice, 100);
      expect(r.discountPercent, 0);
      expect(r.hasDiscount, isFalse);
    });

    test('string numbers are parsed', () {
      final r = p({'price': '250', 'promo_price': '175'});
      expect(r.finalPrice, 175);
      expect(r.discountPercent, 30);
      expect(r.hasDiscount, isTrue);
    });

    test('zero/empty prices never produce a discount', () {
      final r = p({'price': 0, 'promo_price': 0, 'flash_price': 0, 'discounted_price': 0});
      expect(r.finalPrice, 0);
      expect(r.hasDiscount, isFalse);
    });

    test('flash equal to original price is NOT a discount', () {
      final r = p({'price': 100, 'flash_price': 100, 'is_flash': true});
      expect(r.finalPrice, 100);
      expect(r.isFlash, isFalse);
      expect(r.hasDiscount, isFalse);
    });

    test('isFlash accepted as bool, 1, "1" (forms from backend)', () {
      for (final v in [true, 1, '1']) {
        final r = p({'price': 100, 'flash_price': 80, 'is_flash': v});
        expect(r.isFlash, isTrue, reason: 'is_flash=$v');
        expect(r.finalPrice, 80);
      }
    });

    test('flash above original falls back to promo, then discounted', () {
      final promo = p({'price': 100, 'flash_price': 120, 'is_flash': true, 'promo_price': 90});
      expect(promo.finalPrice, 90);
      final discounted = p({
        'price': 100,
        'flash_price': 120,
        'is_flash': true,
        'discounted_price': 85,
      });
      expect(discounted.finalPrice, 85);
      expect(discounted.isFlash, isFalse);
    });

    test('promo wins nothing when equal to original', () {
      final r = p({'price': 100, 'promo_price': 100});
      expect(r.finalPrice, 100);
      expect(r.hasDiscount, isFalse);
    });

    test('discounted price lower-priority than promo', () {
      final r = p({'price': 100, 'promo_price': 90, 'discounted_price': 80});
      expect(r.finalPrice, 90);
    });

    test('discount percent rounds to nearest int', () {
      final r = p({'price': 100, 'promo_price': 87});
      expect(r.discountPercent, 13);
    });

    test('100% discount is impossible: promo=0 is rejected', () {
      final r = p({'price': 100, 'promo_price': 0});
      expect(r.finalPrice, 100);
      expect(r.hasDiscount, isFalse);
    });

    test('missing price list does not fall into bad math', () {
      final r = p(<String, dynamic>{});
      expect(r.finalPrice, 0);
      expect(r.hasDiscount, isFalse);
    });
  });

  group('money', () {
    test('formats negative, zero and positive amounts', () {
      expect(money(0, 'ر.س'), '0.00 ر.س');
      expect(money(10.5, 'ر.س'), '10.50 ر.س');
      expect(money(1234.567, 'ر.س'), '1234.57 ر.س');
      expect(money('25', 'ر.س'), '25.00 ر.س');
    });

    test('respects decimals argument', () {
      expect(money(10.126, 'ر.س', 3), '10.126 ر.س');
      expect(money(10.126, 'ر.س', 0), '10 ر.س');
    });
  });

  group('formatCountdown', () {
    test('negative seconds clamp to 00:00:00', () {
      expect(formatCountdown(-5), '00:00:00');
    });

    test('hours/minutes/seconds render zero padded', () {
      expect(formatCountdown(0), '00:00:00');
      expect(formatCountdown(3661), '01:01:01');
      expect(formatCountdown(3600 * 2 + 60 * 3 + 4), '02:03:04');
    });
  });

  // ── ProductCard widget ────────────────────────────────────────────────────

  Widget cardHost(Map<String, dynamic> product, {VoidCallback? onAdd, VoidCallback? onTap}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 340,
            child: ProductCard(
              product: product,
              onTap: onTap ?? () {},
              onAdd: onAdd,
            ),
          ),
        ),
      );

  Map<String, dynamic> sampleProduct({
    dynamic id = 11,
    String name = 'منتج تجريبي',
    String sellerName = 'متجر التجربي',
    dynamic price = 100,
    List<Map<String, dynamic>>? variants,
    int stock = 5,
    bool unlimited = false,
  }) =>
      {
        'id': id,
        'name': name,
        'seller_name': sellerName,
        'is_unlimited_stock': unlimited ? 1 : 0,
        'average_rating': '4.5',
        'rating_count': 8,
        if (variants != null)
          'variants': variants
        else
          'variants': [
            {'id': 111, 'price': price, 'stock': stock, 'is_unlimited_stock': unlimited ? 1 : 0},
          ],
      };

  testWidgets('renders name, seller name, price and rating', (tester) async {
    await tester.pumpWidget(cardHost(sampleProduct()));
    await tester.pumpAndSettle();
    expect(find.text('منتج تجريبي'), findsOneWidget);
    expect(find.text('متجر التجربي'), findsOneWidget);
    expect(find.text('100.00 ر.س'), findsOneWidget);
    expect(find.text('4.5 (8)'), findsOneWidget);
  });

  testWidgets('price uses promo/flash fields when lower than base', (tester) async {
    final p = sampleProduct(
      variants: [
        {'id': 111, 'price': 100, 'stock': 5, 'promo_price': 60},
      ],
    );
    await tester.pumpWidget(cardHost(p));
    await tester.pumpAndSettle();
    expect(find.text('60.00 ر.س'), findsOneWidget);
    expect(find.text('-40%'), findsOneWidget);
  });

  testWidgets('original price is struck through when discounted', (tester) async {
    final p = sampleProduct(
      variants: [
        {'id': 111, 'price': 100, 'stock': 5, 'discounted_price': 80},
      ],
    );
    await tester.pumpWidget(cardHost(p));
    await tester.pumpAndSettle();
    expect(find.text('100.00 ر.س'), findsOneWidget);
    final strikeText = tester.widget<Text>(find.text('100.00 ر.س'));
    expect(strikeText.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('out-of-stock variant shows out_of_stock and cannot be added', (tester) async {
    var added = 0;
    final p = sampleProduct(stock: 0);
    await tester.pumpWidget(cardHost(p, onAdd: () => added++));
    await tester.pumpAndSettle();
    expect(find.text('out_of_stock'), findsOneWidget);
    // Button is disabled.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('unlimited stock renders like normal even with stock=0', (tester) async {
    var added = 0;
    final p = sampleProduct(stock: 0, unlimited: true);
    await tester.pumpWidget(cardHost(p, onAdd: () => added++));
    await tester.pumpAndSettle();
    expect(find.text('add_to_cart'), findsOneWidget);
  });

  testWidgets('favorite tap as guest shows snackbar and does nothing', (tester) async {
    final p = sampleProduct();
    await tester.pumpWidget(cardHost(p));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();
    expect(find.text('required_login_message_for_wishlist'), findsOneWidget);
    expect(appController.favoriteIds, isEmpty);
  });

  testWidgets('favorite tap as logged-in user syncs local favorites', (tester) async {
    appController.token = 'tok';
    appController.user = {'id': 7, 'name': 'Tester'};
    final p = sampleProduct();
    await tester.pumpWidget(cardHost(p));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    // Advance fake timers so the background favorite sync fires and clears.
    await tester.pump(const Duration(seconds: 10));
    expect(appController.favoriteIds, contains(11));
  });

  testWidgets('simple product add shows a compact stepper once in cart', (tester) async {
    appController.token = 'tok';
    appController.user = {'id': 7, 'name': 'Tester'};
    appController.cartProducts = [
      {'product_variant_id': 111, 'qty': 2, 'price': 100},
    ];
    appController.cartSubTotal = 200;
    final p = sampleProduct();
    await tester.pumpWidget(cardHost(p, onAdd: () {}));
    await tester.pumpAndSettle();
    // Stepper path: [- qty +] visible with the cart quantity.
    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  testWidgets('card tap (no stepper tap) goes through onTap', (tester) async {
    var taps = 0;
    final p = sampleProduct();
    await tester.pumpWidget(cardHost(p, onTap: () => taps++));
    await tester.pumpAndSettle();
    // InkWell wraps the Ink; tap the visible name text instead.
    await tester.tap(find.text('منتج تجريبي'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  // ── StoreCard widget ────────────────────────────────────────────────────

  Widget storeHost(Map<String, dynamic> seller, {double? distanceKm, VoidCallback? onTap}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 160,
            child: StoreCard(seller: seller, onTap: onTap ?? () {}, distanceKm: distanceKm),
          ),
        ),
      );

  testWidgets('store card renders name, rating, count, distance', (tester) async {
    await tester.pumpWidget(storeHost(
      {
        'store_name': 'متجر تجربة',
        'average_rating': '4.8',
        'product_count': 123,
        'is_open': 1,
      },
      distanceKm: 2.5,
    ));
    await tester.pumpAndSettle();
    expect(find.text('متجر تجربة'), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('123 products'), findsOneWidget);
    expect(find.text('2.5 كم'), findsOneWidget);
  });

  testWidgets('closed store shows closed badge', (tester) async {
    await tester.pumpWidget(storeHost({
      'store_name': 'متجر مغلق',
      'is_open': false,
    }));
    await tester.pumpAndSettle();
    expect(find.text('closed'), findsOneWidget);
  });

  testWidgets('store_status variants map to open/closed', (tester) async {
    for (final v in [true, 1, '1', 'open', 'true']) {
      await tester.pumpWidget(storeHost({'store_name': 'متجر A', 'seller_is_open': v}));
      await tester.pumpAndSettle();
      expect(find.text('closed'), findsNothing);
    }
    for (final v in [false, 0, '0', 'closed', 'close']) {
      await tester.pumpWidget(storeHost({'store_name': 'متجر A', 'seller_is_open': v}));
      await tester.pumpAndSettle();
      expect(find.text('closed'), findsOneWidget);
    }
    await tester.pumpWidget(storeHost({'store_name': 'متجر A', 'store_status': 'closed'}));
    await tester.pumpAndSettle();
    expect(find.text('closed'), findsOneWidget);
    await tester.pumpWidget(storeHost({'store_name': 'متجر A', 'store_status': 'open'}));
    await tester.pumpAndSettle();
    expect(find.text('closed'), findsNothing);
  });

  testWidgets('store card tap triggers onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(storeHost(
      {'store_name': 'متجر تجربة'},
      onTap: () => taps++,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متجر تجربة'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  // ── Closed store badge & kind resolution ───────────────────────────────

  group('isProductStoreClosed', () {
    test('no business hours → never closed', () {
      appController.businessHours = null;
      expect(isProductStoreClosed({'seller_id': 1}), isFalse);
    });

    test('empty seller hours stays open', () {
      appController.businessHours = BusinessHoursResult();
      expect(isProductStoreClosed({'seller_id': 1}), isFalse);
    });

    test('seller hours explicitly closed → closed', () {
      appController.businessHours = BusinessHoursResult(
        platform: BusinessHoursSlot(isOpen: true),
        sellers: {
          '1': BusinessHoursSlot(isOpen: false),
        },
      );
      expect(isProductStoreClosed({'seller_id': 1}), isTrue);
    });

    test('platform closed cascades to every product', () {
      appController.businessHours = BusinessHoursResult(
        platform: BusinessHoursSlot(isOpen: false),
        sellers: {
          '1': BusinessHoursSlot(isOpen: true),
        },
      );
      expect(isProductStoreClosed({'seller_id': 1}), isTrue);
    });
  });
}


