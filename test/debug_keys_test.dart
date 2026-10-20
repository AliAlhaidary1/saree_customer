import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/app.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/json_util.dart';

class _FailingApi extends CustomerApi {
  _FailingApi() : super(baseUrl: 'http://test.invalid');

  @override
  Future<ApiResult> products({
    required double latitude,
    required double longitude,
    Map<String, dynamic> filters = const {},
    String tagNames = '',
    String slug = '',
  }) async =>
      ApiResult({'status': 0, 'message': 'offline'});
}

void main() {
  testWidgets('debug page keys', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    appController.injectForTest(prefs: prefs, testApi: _FailingApi());
    appController.city = {'id': 1, 'latitude': 15.4624, 'longitude': 45.3228};
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(seconds: 1));

    void dumpKeys(String label) {
      for (final nav in find.byType(Navigator).evaluate()) {
        final widget = nav.widget as Navigator;
        // ignore: avoid_print
        print('DEBUG[$label] nav pages: ${widget.pages.map((p) => '${p.key}').toList()}');
      }
    }

    dumpKeys('initial');
    router.push('/product/some-slug');
    await tester.pump(const Duration(seconds: 1));
    dumpKeys('after product push');
    router.go('/cart');
    await tester.pump(const Duration(seconds: 1));
    dumpKeys('after cart push');
  });
}
