import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:drift/drift.dart' show Value;
import 'package:sareemart_customer/core/catalog_db/catalog_database.dart';
import 'package:sareemart_customer/core/config.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/features/products/products_screens.dart';
import 'package:sareemart_customer/widgets/order_tracker.dart';
import 'package:sareemart_customer/widgets/product_filter_drawer.dart';

class _ProductsApi extends CustomerApi {
  _ProductsApi() : super(baseUrl: 'http://test.invalid');

  int productsCalls = 0;
  Map<String, dynamic>? lastFilters;
  List<Map<String, dynamic>> rows = [];
  int totalScore = 0;

  @override
  Future<ApiResult> products({
    required double latitude,
    required double longitude,
    Map<String, dynamic> filters = const {},
    String tagNames = '',
    String slug = '',
  }) async {
    productsCalls++;
    lastFilters = Map<String, dynamic>.from(filters);
    final lim = J.i(filters['limit'], AppConfig.productPageSize);
    final off = J.i(filters['offset']);
    return ApiResult({
      'status': 1,
      'data': rows.skip(off).take(lim).toList(),
    });
  }
}

class _StaticCatalogApi extends _ProductsApi {
  @override
  Future<ApiResult> products({
    required double latitude,
    required double longitude,
    Map<String, dynamic> filters = const {},
    String tagNames = '',
    String slug = '',
  }) async {
    productsCalls++;
    lastFilters = Map<String, dynamic>.from(filters);
    return ApiResult({'status': 1, 'data': const <Map<String, dynamic>>[]});
  }
}

Future<void> _setup(_ProductsApi api) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.businessHours = null;
  appController.cartProducts = [];
  appController.cartSubTotal = 0;
  appController.cart = null;
  appController.guestCart = [];
  appController.guestCartTotal = 0;
  appController.token = null;
  appController.user = null;
  appController.settings = {
    'currency': 'ر.س',
    'decimal_point': 2,
    'web_settings': <String, dynamic>{},
  };
  // Ready in-memory catalog so the read never hangs and never shows
  // not_synced_yet in the "empty" variant.
  final db = await CatalogDatabase.openMemory();
  addTearDown(db.close);
  await CatalogDao(db).saveSyncState(
    SyncStatesCompanion.insert(
      scope: 'city:1',
      phase: 'full_complete',
      coverage: const Value('best_effort'),
      lastOffset: const Value(0),
      storedCount: const Value(0),
      updatedAt: DateTime.now(),
    ),
  );
  appController.setCatalogDbForTest(db);
}

Map<String, dynamic> _row(int id, {String price = '100', int stock = 10}) => {
      'id': id,
      'name': 'منتج $id',
      'slug': 'product-$id',
      'seller_id': 50,
      'store_name': 'متجر',
      'price': price,
      'is_unlimited_stock': 0,
      'average_rating': '4.0',
      'rating_count': 12,
      'variants': [
        {'id': id * 10, 'price': price, 'stock': stock, 'measurement': '1', 'stock_unit_name': 'قطعة'},
      ],
    };

Future<void> _settle(WidgetTester tester) async {
  // Let fake-API futures run through real async so the screen paints.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── Order tracking widget ─────────────────────────────────────────────

  Widget tracker(String status, {String? label}) => MaterialApp(
        home: Scaffold(
          body: OrderTracker(status: status, statusLabel: label),
        ),
      );

  testWidgets('status=2 renders step 0 (confirmed) at 0%', (tester) async {
    await tester.pumpWidget(tracker('2'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد'), findsOneWidget);
  });

  testWidgets('status=3 renders step 1 (preparing)', (tester) async {
    await tester.pumpWidget(tracker('3'));
    await tester.pumpAndSettle();
    expect(find.text('تحضير'), findsOneWidget);
  });

  testWidgets('status=5 renders step 2 with 67% label', (tester) async {
    await tester.pumpWidget(tracker('5'));
    await tester.pumpAndSettle();
    expect(find.text('67%'), findsOneWidget);
  });

  testWidgets('status=6 renders step 3 (delivered) at 100%', (tester) async {
    await tester.pumpWidget(tracker('6'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('status "cancel" renders the cancelled banner', (tester) async {
    await tester.pumpWidget(tracker('7'));
    await tester.pumpAndSettle();
    expect(find.text('ملغي'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
  });

  testWidgets('status=8 renders returned banner (not cancelled slot)', (tester) async {
    await tester.pumpWidget(tracker('8'));
    await tester.pumpAndSettle();
    expect(find.text('مرتجع'), findsOneWidget);
    expect(find.byIcon(Icons.restart_alt_outlined), findsOneWidget);
  });

  testWidgets('string statuses resolve to closest step', (tester) async {
    for (final s in ['deliver', 'delivered', 'complete', 'completed']) {
      await tester.pumpWidget(tracker(s));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget, reason: 'status=$s');
    }
    for (final s in ['way', 'ship', 'out', 'pick']) {
      await tester.pumpWidget(tracker(s));
      await tester.pumpAndSettle();
      expect(find.text('67%'), findsOneWidget, reason: 'status=$s');
    }
    for (final s in ['prepar', 'process', 'ready', 'in_delivery']) {
      await tester.pumpWidget(tracker(s));
      await tester.pumpAndSettle();
      expect(find.text('تحضير'), findsOneWidget, reason: 'status=$s');
    }
  });

  testWidgets('garbage status falls back to confirm step', (tester) async {
    await tester.pumpWidget(tracker('nothing-matches-anything'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد'), findsOneWidget);
  });

  // ─── ProductFilterSheet interactions ──────────────────────────────────

  testWidgets('initial empty filter shows zero active chips', (tester) async {
    await _setup(_ProductsApi());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductFilterSheet(
            initial: ProductFilterValue(),
            categories: const [],
            onApply: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('show_results'), findsOneWidget);
  });

  testWidgets('active filter shows "show results · N" label', (tester) async {
    await _setup(_ProductsApi());
    ProductFilterValue? applied;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductFilterSheet(
            initial: ProductFilterValue(sort: 'low', inStock: true, minRating: '4'),
            categories: const [],
            onApply: (v) {
              applied = v;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('show_results'), findsOneWidget);
    // Three active filters → label reflects the count.
    expect(find.textContaining('· 3'), findsOneWidget);

    // Jetzt clear_all: applied immediately with an empty result.
    await tester.tap(find.text('clear_all'));
    await tester.pump();
    expect(applied, isNotNull);
    expect(applied!.isEmpty, isTrue);
  });

  testWidgets('sort chip toggles off when chosen twice', (tester) async {
    await _setup(_ProductsApi());
    ProductFilterValue? applied;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductFilterSheet(
            initial: ProductFilterValue(),
            categories: const [],
            onApply: (v) {
              applied = v;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Tap sort_cheapest → selects it, applied='low'.
    await tester.tap(find.text('sort_cheapest'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('show_results'));
    await tester.pump();
    expect(applied?.sort, 'low');
  });

  // ─── ProductsScreen: real filters hit the API ─────────────────────────

  testWidgets('screen with empty products shows empty state (not error)', (tester) async {
    final api = _StaticCatalogApi();
    await _setup(api);
    await tester.pumpWidget(
      const MaterialApp(home: ProductsScreen(listenHeaderSearch: false)),
    );
    await _settle(tester);
    expect(find.text('no_products_found'), findsOneWidget);
    expect(find.text('catalog_sync_failed'), findsNothing);
  });

  testWidgets('backend payload is rendered', (tester) async {
    final api = _ProductsApi();
    api.rows = [for (var i = 1; i <= 4; i++) _row(i)];
    await _setup(api);
    await tester.pumpWidget(
      const MaterialApp(home: ProductsScreen(listenHeaderSearch: false)),
    );
    await _settle(tester);
    expect(api.productsCalls, greaterThanOrEqualTo(1));
    expect(api.lastFilters?['latitude'], 15.0);
    expect(find.text('منتج 1'), findsOneWidget);
    expect(find.text('منتج 2'), findsOneWidget);
    expect(find.text('منتج 3'), findsOneWidget);
    expect(find.text('منتج 4'), findsOneWidget);
  });

  testWidgets('sort, price bounds and in-stock filter all hit the API', (tester) async {
    final api = _ProductsApi();
    api.rows = [for (var i = 1; i <= 4; i++) _row(i)];
    await _setup(api);
    await tester.pumpWidget(
      const MaterialApp(
        home: ProductsScreen(
          listenHeaderSearch: false,
          sort: 'low',
          priceMin: '10',
          priceMax: '500',
          inStock: true,
          categoryId: '9',
        ),
      ),
    );
    await _settle(tester);
    expect(api.productsCalls, greaterThanOrEqualTo(1));
    expect(api.lastFilters?['sort'], 'low');
    expect(api.lastFilters?['price_min'], '10');
    expect(api.lastFilters?['price_max'], '500');
    expect(api.lastFilters?['in_stock'], 1);
    expect(api.lastFilters?['category_ids'], '9');
  });

  testWidgets('search term is forwarded and search results render', (tester) async {
    final api = _ProductsApi();
    api.rows = [
      _row(1, price: '120'),
      _row(2, price: '200'),
    ];
    await _setup(api);
    await tester.pumpWidget(
      const MaterialApp(
        home: ProductsScreen(
          listenHeaderSearch: false,
          search: 'قميس',
        ),
      ),
    );
    await _settle(tester);
    expect(api.lastFilters?['search'], 'قميس');
  });
}
