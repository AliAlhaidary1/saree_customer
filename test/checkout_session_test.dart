import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/offline/checkout_session.dart';
import 'package:sareemart_customer/core/offline/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<CheckoutSession> freshSession(String scope) async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    return CheckoutSession(LocalStore(p), scope);
  }

  group('CheckoutSession', () {
    test('reuses key when fingerprint matches', () async {
      final s = await freshSession('u:1');
      final key1 = await s.begin(context: {'fingerprint': 'fp1'});
      final key2 = await s.begin(context: {'fingerprint': 'fp1'});
      expect(key1, key2);
      expect(s.matchesFingerprint('fp1'), isTrue);
    });

    test('generates fresh key when fingerprint changes', () async {
      final s = await freshSession('u:1');
      final key1 = await s.begin(context: {'fingerprint': 'fp1'});
      final key2 = await s.begin(context: {'fingerprint': 'fp2'});
      expect(key1, isNot(key2));
      expect(s.matchesFingerprint('fp2'), isTrue);
      expect(s.matchesFingerprint('fp1'), isFalse);
    });

    test('clear removes persisted session', () async {
      final s = await freshSession('u:1');
      await s.begin(context: {'fingerprint': 'fp1'});
      expect(s.key, isNotNull);
      await s.clear();
      expect(s.key, isNull);
    });

    test('survives reconstruction from LocalStore', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final s1 = CheckoutSession(LocalStore(p), 'u:1');
      final key = await s1.begin(context: {'fingerprint': 'fp1'});
      final s2 = CheckoutSession(LocalStore(p), 'u:1');
      expect(s2.key, key);
      expect(s2.matchesFingerprint('fp1'), isTrue);
    });
  });

  group('cartFingerprint', () {
    test('is stable for same cart snapshot', () {
      final items = [
        {'product_variant_id': 2, 'qty': 1},
        {'product_variant_id': 1, 'qty': 3},
      ];
      final a = cartFingerprint(items: items, addressId: 5, paymentMethod: 'COD');
      final b = cartFingerprint(items: items, addressId: 5, paymentMethod: 'COD');
      expect(a, b);
    });

    test('changes when items, quantities, address, payment, delivery, or promo change', () {
      final base = cartFingerprint(
        items: [{'product_variant_id': 1, 'qty': 1}],
        addressId: 5,
        paymentMethod: 'COD',
      );
      expect(
        cartFingerprint(
          items: [{'product_variant_id': 2, 'qty': 1}],
          addressId: 5,
          paymentMethod: 'COD',
        ),
        isNot(base),
      );
      expect(
        cartFingerprint(
          items: [{'product_variant_id': 1, 'qty': 2}],
          addressId: 5,
          paymentMethod: 'COD',
        ),
        isNot(base),
      );
      expect(
        cartFingerprint(
          items: [{'product_variant_id': 1, 'qty': 1}],
          addressId: 6,
          paymentMethod: 'COD',
        ),
        isNot(base),
      );
      expect(
        cartFingerprint(
          items: [{'product_variant_id': 1, 'qty': 1}],
          addressId: 5,
          paymentMethod: 'Wallet',
        ),
        isNot(base),
      );
      expect(
        cartFingerprint(
          items: [{'product_variant_id': 1, 'qty': 1}],
          addressId: 5,
          paymentMethod: 'COD',
          deliveryTime: '10:00',
        ),
        isNot(base),
      );
      expect(
        cartFingerprint(
          items: [{'product_variant_id': 1, 'qty': 1}],
          addressId: 5,
          paymentMethod: 'COD',
          promoCodeId: 'PROMO',
        ),
        isNot(base),
      );
    });

    test('is independent of item order', () {
      final a = cartFingerprint(items: [
        {'product_variant_id': 1, 'qty': 1},
        {'product_variant_id': 2, 'qty': 3},
      ]);
      final b = cartFingerprint(items: [
        {'product_variant_id': 2, 'qty': 3},
        {'product_variant_id': 1, 'qty': 1},
      ]);
      expect(a, b);
    });
  });
}
