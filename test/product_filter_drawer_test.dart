import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/widgets/product_filter_drawer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopApi extends CustomerApi {
  _NoopApi() : super(baseUrl: 'http://test.invalid', token: null);
}

Future<void> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  appController.injectForTest(prefs: prefs, testApi: _NoopApi());
  appController.city = {'id': 1};
}

void main() {
  testWidgets('clear all applies immediately, without show results',
      (tester) async {
    await _setup();

    ProductFilterValue? applied;
    var applyCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductFilterSheet(
            initial: ProductFilterValue(
              sort: 'cheapest',
              categoryId: '3',
              priceMin: '10',
              priceMax: '50',
              inStock: true,
            ),
            categories: const [],
            onApply: (v) {
              applied = v;
              applyCount++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(applied, isNull, reason: 'nothing applied on open');

    await tester.tap(find.text(appController.t('clear_all')));
    await tester.pump();

    expect(applyCount, 1, reason: 'clear is applied on tap, not on dismiss');
    expect(applied, isNotNull);
    expect(applied!.isEmpty, isTrue);
    expect(applied!.sort, isEmpty);
    expect(applied!.categoryId, isNull);
    expect(applied!.inStock, isFalse);

    // The sheet stays open, showing the "show results" action.
    expect(find.text(appController.t('show_results')), findsOneWidget);
  });
}
