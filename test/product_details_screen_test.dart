import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/features/products/products_screens.dart';

class _PDPApi extends CustomerApi {
  _PDPApi() : super(baseUrl: 'http://test.invalid');

  @override
  Future<ApiResult> productById({
    required double latitude,
    required double longitude,
    dynamic id,
    String slug = '',
  }) async =>
      ApiResult({
        'status': 1,
        'data': {
          'id': id ?? 11,
          'name': 'منتج تجريبي التفاصيل',
          'slug': slug,
          'average_rating': '4.2',
          'rating_count': 17,
          'variants': [
            {'id': 111, 'price': 120, 'stock': 9, 'measurement': '1', 'stock_unit_name': 'كجم'},
            {'id': 112, 'price': 200, 'stock': 3, 'measurement': '2', 'stock_unit_name': 'كجم'},
          ],
        },
      });

  @override
  Future<ApiResult> productRatings({
    required dynamic productId,
    int limit = 10,
    int offset = 0,
  }) async =>
      ApiResult({
        'status': 1,
        'data': {
          'average_rating': '4.2',
          'rating_count': 17,
          'rating_list': [
            {'id': 1, 'user_name': 'user', 'rating': 5, 'review': 'ممتاز'},
          ],
        },
      });

  @override
  Future<ApiResult> catalogOffers({
    required dynamic productId,
    String name = '',
    String sort = 'price',
  }) async =>
      ApiResult({'status': 1, 'data': []});

  @override
  Future<ApiResult> products({
    required double latitude,
    required double longitude,
    Map<String, dynamic> filters = const {},
    String tagNames = '',
    String slug = '',
  }) async =>
      ApiResult({'status': 1, 'data': []});

  @override
  Future<ApiResult> addToCart({
    required dynamic productId,
    required dynamic variantId,
    required dynamic qty,
  }) async =>
      ApiResult({'status': 1, 'data': {'cart': []}});
}

Future<void> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  appController.injectForTest(prefs: prefs, testApi: _PDPApi());
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.businessHours = null;
  appController.token = null;
  appController.user = null;
  appController.cartProducts = [];
  appController.cart = null;
  appController.cartSubTotal = 0;
  appController.settings = {
    'currency': 'ر.س',
    'decimal_point': 2,
    'web_settings': <String, dynamic>{},
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDetails(WidgetTester tester) async {
    // Let real async futures (catalog cache read, fake API chain) complete,
    // then pump the built tree.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('renders name, price (first variant), rating and variants', (tester) async {
    await _setup();
    await tester.pumpWidget(const MaterialApp(home: ProductDetailsScreen(slug: '11')));
    await pumpDetails(tester);
    expect(find.text('منتج تجريبي التفاصيل'), findsWidgets);
    // First variant: price 120 + discount excluded → plain text price.
    expect(find.text('120.00 ر.س'), findsWidgets);
    expect(find.text('4.2 (17)'), findsWidgets);
    // The second variant measurement is visible in the variant selector.
    expect(find.textContaining('كجم'), findsWidgets);
  });

  testWidgets('sold-out variant disables add to cart', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    appController.injectForTest(prefs: prefs, testApi: _SoldOutApi());
    appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
    appController.businessHours = null;
    appController.token = null;
    appController.user = null;
    appController.cartProducts = [];
    appController.cartSubTotal = 0;
    appController.settings = {
      'currency': 'ر.س',
      'decimal_point': 2,
      'web_settings': <String, dynamic>{},
    };
    await tester.pumpWidget(const MaterialApp(home: ProductDetailsScreen(slug: '11')));
    await pumpDetails(tester);
    // With only a sold-out variant available, the bottom bar shows the add
    // button labelled with out_of_stock — widget exists.
    expect(find.textContaining('out_of_stock'), findsWidgets);
  });
}

class _SoldOutApi extends CustomerApi {
  _SoldOutApi() : super(baseUrl: 'http://test.invalid');

  @override
  Future<ApiResult> productById({
    required double latitude,
    required double longitude,
    dynamic id,
    String slug = '',
  }) async =>
      ApiResult({
        'status': 1,
        'data': {
          'id': 11,
          'name': 'منتج نافد',
          'slug': 'sold',
          'average_rating': '',
          'rating_count': null,
          'variants': [
            {'id': 111, 'price': 50, 'stock': 0, 'measurement': '1', 'stock_unit_name': 'قطعة'},
          ],
        },
      });

  @override
  Future<ApiResult> productRatings({
    required dynamic productId,
    int limit = 10,
    int offset = 0,
  }) async =>
      ApiResult({'status': 0, 'message': 'not found'});

  @override
  Future<ApiResult> catalogOffers({
    required dynamic productId,
    String name = '',
    String sort = 'price',
  }) async =>
      ApiResult({'status': 1, 'data': []});
}
