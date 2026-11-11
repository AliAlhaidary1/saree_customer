import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/widgets/product_variant_sheet.dart';

/// Reproduces the exact on-device symptom when offline: Tap "أضف إلى السلة"
/// on a variant dialog while the server is unreachable. The snackbar
/// "تعذر الاتصال بالخادم. تحقق من الإنترنت." appears even though the offline
/// intent was queued and the badge shows the item.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> _product() => {
        'id': 99,
        'name': 'طماطم بلدية',
        'store_name': 'سوق البلدية',
        'seller_id': 5,
        'seller': {'id': 5, 'store_name': 'سوق البلدية'},
        'measurement': '1 كجم',
        'stock_unit_name': 'كجم',
        'variants': [
          {
            'id': 991,
            'product_variant_id': 991,
            'measurement': '1 كجم',
            'stock_unit_name': 'كجم',
            'price': 463.45,
            'stock': 10,
            'name': '1 كجم',
          },
          {
            'id': 992,
            'product_variant_id': 992,
            'measurement': '2 كجم',
            'stock_unit_name': 'كجم',
            'price': 589.95,
            'stock': 10,
            'name': '2 كجم',
          },
        ],
      };

  Future<void> _setup() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    appController.injectForTest(prefs: prefs, testApi: _OfflineFailingApi());
    appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
    appController.businessHours = BusinessHoursResult();
    appController.token = 'tok';
    appController.user = {'id': 7, 'name': 'T'};
    appController.cartProducts = [];
    appController.cart = null;
    appController.cartSubTotal = 0;
    appController.guestCart = [];
    appController.guestCartTotal = 0;
    appController.settings = {
      'currency': 'ر.س',
      'decimal_point': 2,
      'min_order_amount': 0,
      'max_sellers_per_checkout': 0,
      'web_settings': <String, dynamic>{},
    };
    appController.paymentSettings = {'cod_payment_method': '1'};
    appController.overrideConnectivityForTest(false);
  }

  testWidgets(
    'offline add: enqueue succeeds and UI must not report network error',
    (tester) async {
      await _setup();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductVariantSheet(product: _product()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('طماطم بلدية'), findsOneWidget);

      // Tap "add_to_cart" on the 1 كجم variant (raw key in tests).
      await tester.tap(find.text('add_to_cart').first);

      // Let the async addToCart complete WITHOUT pumpAndSettle (connectivity
      // dialogs may linger); use pump cycles instead.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // The cart must show the line as added optimistically.
      expect(
        appController.cartProducts.any(
          (e) => '${e['product_variant_id']}' == '991',
        ),
        isTrue,
        reason: 'offline intent must persist locally',
      );

      // The snackbar must NOT show a network error for a queued silent-success add.
      expect(find.text('network_error'), findsNothing);
      expect(find.text('تعذر الاتصال بالخادم. تحقق من الإنترنت.'), findsNothing);
    },
  );
}

class _OfflineFailingApi extends CustomerApi {
  _OfflineFailingApi() : super(baseUrl: 'http://test.invalid', token: null);

  @override
  Future<ApiResult> cities({
    int limit = 100,
    int offset = 0,
    String search = '',
  }) async => ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });

  @override
  Future<ApiResult> businessHours({List<dynamic> sellerIds = const []}) async =>
      ApiResult({'status': 1, 'data': []});

  @override
  Future<ApiResult> addToCart({
    required dynamic productId,
    required dynamic variantId,
    required dynamic qty,
  }) async => ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });

  @override
  Future<ApiResult> cart({
    required double latitude,
    required double longitude,
    int checkout = 0,
  }) async => ApiResult({
        'status': 0,
        'message': 'no_items_found_in_users_cart',
      });
}
