import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';

/// Focused diagnostic: "what does offline addToCart return?"
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline addToCart returns exactly what string/null — probe', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _FailingApi();
    appController.injectForTest(prefs: prefs, testApi: api);
    appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
    appController.businessHours = BusinessHoursResult();
    appController.token = 'tok';
    appController.user = {'id': 7, 'name': 'T'};
    appController.cartProducts = [];
    appController.cart = null;
    appController.cartSubTotal = 0;
    appController.settings = {
      'currency': 'ر.س',
      'decimal_point': 2,
      'min_order_amount': 0,
      'max_sellers_per_checkout': 0,
      'web_settings': <String, dynamic>{},
    };
    appController.paymentSettings = {'cod_payment_method': '1'};
    appController.overrideConnectivityForTest(false);

    // Logged-in offline add — what does it return?
    final err = await appController.addToCart(
      productId: 5,
      variantId: 55,
      qty: 1,
      productPrice: 25,
      sellerId: 5,
      storeName: '',
      variantLabel: 'أصداف',
    );

    // ignore: avoid_print
    print('OFFLINE ADD RETURN: [${err ?? 'null'}]');
    expect(err, isNull, reason: 'silent success — nothing to show');

    // Guest offline add — same question.
    appController.token = null;
    appController.user = null;
    appController.cartProducts = [];
    appController.cart = null;
    appController.guestCart = [];
    appController.guestCartTotal = 0;
    final errGuest = await appController.addToCart(
      productId: 5,
      variantId: 55,
      qty: 1,
      productPrice: 25,
      sellerId: 5,
    );
    // ignore: avoid_print
    print('GUEST OFFLINE ADD RETURN: [${errGuest ?? 'null'}]');
    expect(errGuest, isNull);
  });
}

class _FailingApi extends CustomerApi {
  _FailingApi() : super(baseUrl: 'http://test.invalid', token: null);

  @override
  Future<ApiResult> cities({
    int limit = 100,
    int offset = 0,
    String search = '',
  }) async => ApiResult({'status': 0, 'message': 'timeout', 'error': {'code': 'TIMEOUT'}});

  @override
  Future<ApiResult> businessHours({List<dynamic> sellerIds = const []}) async =>
      ApiResult({'status': 1, 'data': []});

  @override
  Future<ApiResult> addToCart({
    required dynamic productId,
    required dynamic variantId,
    required dynamic qty,
  }) async =>
      ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });
}
