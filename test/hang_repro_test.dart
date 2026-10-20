import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/catalog_db/catalog_database.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/features/more/more_screens.dart';
import 'package:sareemart_customer/features/products/products_screens.dart';

ApiResult _fail() => ApiResult({'status': 0, 'message': 'timeout'});

class _HangApi extends CustomerApi {
  _HangApi() : super(baseUrl: 'http://test.invalid', token: null);

  @override
  Future<ApiResult> products({
    required double latitude,
    required double longitude,
    Map<String, dynamic> filters = const {},
    String tagNames = '',
    String slug = '',
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _fail();
  }

  int sellersCalls = 0;

  @override
  Future<ApiResult> sellers({
    double? latitude,
    double? longitude,
    int limit = 50,
    int offset = 0,
    String? search,
    String? sort,
    String? type,
    dynamic minRating,
  }) async {
    sellersCalls++;
    await Future.delayed(const Duration(milliseconds: 100));
    if (!_onlineFullPages) return _fail();
    // Two full pages then a short tail.
    final start = offset;
    final count = offset < 48 ? 24 : 5;
    return ApiResult({
      'status': 1,
      'total': 53,
      'data': List.generate(
        count,
        (i) => {'id': start + i + 1, 'name': 'Net Store ${start + i + 1}'},
      ),
    });
  }

  bool _onlineFullPages = false;
}

Future<void> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  appController.injectForTest(prefs: prefs, testApi: _HangApi());
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  final db = await CatalogDatabase.openMemory();
  appController.setCatalogDbForTest(db);
}

Future<void> _seedStores(int n) async {
  final db = await appController.ensureCatalogDb();
  final dao = CatalogDao(db!);
  final now = DateTime.now();
  await dao.upsertStores(
    scope: appController.catalogScope,
    rows: List.generate(
      n,
      (i) => StoresCompanion.insert(
        scope: appController.catalogScope,
        serverId: i + 1,
        name: 'Store ${i + 1}',
        payload: '{"id": ${i + 1}, "name": "Store ${i + 1}"}',
        refreshedAt: now,
        lastSeenAt: now,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sellers settles offline with synced rows', (tester) async {
    await _setup();
    await _seedStores(30);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SellersScreen())),
    );
    await tester.pumpAndSettle(const Duration(seconds: 30));
    expect(find.text('Store 1'), findsOneWidget);
  });

  testWidgets('sellers settles offline with empty db', (tester) async {
    await _setup();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SellersScreen())),
    );
    await tester.pumpAndSettle(const Duration(seconds: 30));
    expect(find.text('no_stores_found'), findsOneWidget);
  });

  testWidgets('products settles offline with empty db', (tester) async {
    await _setup();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProductsScreen())),
    );
    await tester.pumpAndSettle(const Duration(seconds: 30));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('sellers online stops requesting after auto-fill', (tester) async {
    await _setup();
    final api = appController.api as _HangApi;
    api._onlineFullPages = true;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SellersScreen())),
    );
    await tester.pumpAndSettle(const Duration(seconds: 30));
    expect(find.text('Net Store 1'), findsOneWidget);
    // reset + a single auto-fill: must never machine-gun all pages.
    expect(api.sellersCalls, lessThanOrEqualTo(3));
  });
}
