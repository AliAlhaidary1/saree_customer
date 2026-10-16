import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/catalog_db/catalog_database.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/search_scope.dart';
import 'package:sareemart_customer/features/haraj/haraj_screens.dart';
import 'package:sareemart_customer/features/more/more_screens.dart';
import 'package:sareemart_customer/features/notifications/notifications_screen.dart';

/// Scripted fake: the first call to each endpoint is slow (stale), later
/// calls are immediate (fresh). Overlapping user actions race deterministically.
class _RaceApi extends CustomerApi {
  _RaceApi() : super(baseUrl: 'http://test.invalid');

  int harajCalls = 0;
  int sellersCalls = 0;
  int notificationsCalls = 0;
  int productsCalls = 0;
  // When true, haraj page 1 advertises 3 pages so the footer auto-fires a
  // (slow) load-more, letting a reset race it.
  bool harajMultiPage = false;

  Map<String, dynamic> row(String tag, int n) => {
        'id': n,
        'title': '$tag-$n',
        'name': '$tag-$n',
      };

  @override
  Future<ApiResult> harajPosts(Map<String, dynamic> params) async {
    harajCalls++;
    if (harajMultiPage) {
      if (harajCalls == 1) {
        return ApiResult({
          'status': 1,
          'data': [row('PAGE1', 10)],
          'last_page': 3,
        });
      }
      if (harajCalls == 2) {
        await Future.delayed(const Duration(milliseconds: 800));
        return ApiResult({
          'status': 1,
          'data': [row('PAGE2', 20)],
          'last_page': 3,
        });
      }
      return ApiResult({
        'status': 1,
        'data': [row('FRESH', 2)],
        'last_page': 1,
      });
    }
    if (harajCalls == 1) {
      await Future.delayed(const Duration(milliseconds: 300));
      return ApiResult({
        'status': 1,
        'data': [row('STALE', 1)],
        'last_page': 1,
      });
    }
    return ApiResult({
      'status': 1,
      'data': [row('FRESH', 2)],
      'last_page': 1,
    });
  }

  @override
  Future<ApiResult> harajMyPosts(Map<String, dynamic> params) =>
      harajPosts(params);

  @override
  Future<ApiResult> harajCategories() async =>
      ApiResult({'status': 1, 'data': []});

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
    if (sellersCalls == 1) {
      // Slow enough that the debounced second search finishes first.
      await Future.delayed(const Duration(milliseconds: 800));
      return ApiResult({
        'status': 1,
        'total': 1,
        'data': [row('STALE', 11)],
      });
    }
    return ApiResult({
      'status': 1,
      'total': 1,
      'data': [row('FRESH', 22)],
    });
  }

  @override
  Future<ApiResult> notifications({int limit = 20, int offset = 0}) async {
    notificationsCalls++;
    if (notificationsCalls == 1) {
      await Future.delayed(const Duration(milliseconds: 300));
      return ApiResult({
        'status': 1,
        'total': 9,
        'data': [for (var i = 0; i < 8; i++) row('STALE', 101 + i)],
      });
    }
    if (notificationsCalls == 2) {
      // Slow load-more: a refresh must supersede it.
      await Future.delayed(const Duration(milliseconds: 800));
      return ApiResult({
        'status': 1,
        'total': 9,
        'data': [row('MORE', 109)],
      });
    }
    return ApiResult({
      'status': 1,
      'total': 1,
      'data': [row('FRESH', 202)],
    });
  }

  @override
  Future<ApiResult> products({
    required double latitude,
    required double longitude,
    Map<String, dynamic> filters = const {},
    String tagNames = '',
    String slug = '',
  }) async {
    productsCalls++;
    if (productsCalls == 1) {
      await Future.delayed(const Duration(milliseconds: 300));
      return ApiResult({
        'status': 1,
        'total': 1,
        'data': [row('STALE', 1001)],
      });
    }
    return ApiResult({
      'status': 1,
      'total': 1,
      'data': [row('FRESH', 2002)],
    });
  }
}

Future<void> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  appController.injectForTest(prefs: prefs, testApi: _RaceApi());
  appController.city = {'id': 1, 'latitude': 15.4624, 'longitude': 45.3228};
  headerSearch.productQuery = '';
  headerSearch.harajQuery = '';
  final db = await CatalogDatabase.openMemory();
  appController.setCatalogDbForTest(db);
}

List<String> _names(List items) =>
    items.map((e) => '${e['name'] ?? e['title']}').toList();

void main() {
  testWidgets('haraj: slow first load loses to fast reset', (tester) async {
    await _setup();
    await tester.pumpWidget(const MaterialApp(home: HarajListScreen()));
    await tester.pump(const Duration(milliseconds: 50));
    // initState load is still in flight (slow); a new search supersedes it.
    headerSearch.submitHaraj('fresh');
    await tester.pump(const Duration(milliseconds: 500));
    final st = tester.state(find.byType(HarajListScreen)) as dynamic;
    expect(_names(st.items as List), ['FRESH-2']);
  });

  testWidgets('haraj: stale load-more is dropped after a reset',
      (tester) async {
    await _setup();
    (appController.api as _RaceApi).harajMultiPage = true;
    await tester.pumpWidget(const MaterialApp(home: HarajListScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    // Page 1 painted, footer auto-fired the slow page-2 load; a new search
    // supersedes both.
    headerSearch.submitHaraj('fresh');
    await tester.pump(const Duration(milliseconds: 1000));
    final st = tester.state(find.byType(HarajListScreen)) as dynamic;
    expect(_names(st.items as List), ['FRESH-2']);
    expect(st.page, 1);
  });

  testWidgets('sellers: slow load loses to newer search', (tester) async {
    await _setup();
    await tester.pumpWidget(const MaterialApp(home: SellersScreen()));
    // initState load is in flight (slow 800ms API + location lookup that
    // never answers in tests and falls back after its 8s bound); typing
    // supersedes it via the 450ms debounce, finishing well before the
    // stale response lands.
    await tester.enterText(find.byType(TextField).first, 'ab');
    await tester.pump(const Duration(milliseconds: 9500));
    final st = tester.state(find.byType(SellersScreen)) as dynamic;
    expect(_names(st.items as List), ['FRESH-22']);
  });

  testWidgets('notifications: refresh beats in-flight load-more',
      (tester) async {
    await _setup();
    appController.token = 't';
    await tester.pumpWidget(const MaterialApp(home: NotificationsScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    // First page done (8 rows, total 9 -> trailing spinner below the fold).
    // Infinite scroll (fling to the bottom edge) triggers the slow load-more.
    await tester.fling(find.byType(ListView), const Offset(0, -800), 1000);
    await tester.pump(const Duration(milliseconds: 300));
    // Back to the very top edge (twice: first gesture travels, second
    // overscrolls), then pull the list down to trigger the refresh while
    // the slow load-more is still in flight.
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.fling(find.byType(ListView), const Offset(0, 800), 1000);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.fling(find.byType(ListView), const Offset(0, 800), 1000);
    await tester.pump(const Duration(milliseconds: 1200));
    final st = tester.state(find.byType(NotificationsScreen)) as dynamic;
    expect(_names(st.items as List), ['FRESH-202']);
  });

  testWidgets('search: older query cannot overwrite the latest',
      (tester) async {
    await _setup();
    await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
    await tester.enterText(find.byType(TextField), 'aaa');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'b');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 500));
    final st = tester.state(find.byType(SearchScreen)) as dynamic;
    expect(_names(st.items as List), ['FRESH-2002']);
  });
}
