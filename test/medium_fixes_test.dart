import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/notification_read.dart';
import 'package:sareemart_customer/features/account/account_screens.dart';
import 'package:sareemart_customer/features/more/more_screens.dart';
import 'package:sareemart_customer/features/notifications/notifications_screen.dart';
import 'package:sareemart_customer/widgets/ui_helpers.dart';

class _MediumApi extends CustomerApi {
  _MediumApi() : super(baseUrl: 'http://test.invalid');

  int notificationTotal = 250;
  int notificationCalls = 0;
  final List<int> notificationOffsets = [];

  @override
  Future<ApiResult> checkoutGroup(dynamic id) async => ApiResult({
    'status': 0,
    'message': 'offline',
    'error': {'code': 'ECONNREFUSED'},
  });

  @override
  Future<ApiResult> orders({
    int limit = 10,
    int offset = 0,
    int type = 1,
    dynamic orderId,
  }) async => ApiResult({
    'status': 0,
    'message': 'offline',
    'error': {'code': 'ECONNREFUSED'},
  });

  @override
  Future<ApiResult> products({
    required double latitude,
    required double longitude,
    Map<String, dynamic> filters = const {},
    String tagNames = '',
    String slug = '',
  }) async => ApiResult({
    'status': 1,
    'data': [
      {'id': 1, 'name': 'Shoe', 'slug': 'shoe', 'price': 10},
    ],
  });

  @override
  Future<ApiResult> notifications({int limit = 20, int offset = 0}) async {
    notificationCalls++;
    notificationOffsets.add(offset);
    final end = (offset + limit).clamp(0, notificationTotal);
    final rows = [
      for (var i = offset; i < end; i++)
        {'id': i + 1, 'title': 'Notification ${i + 1}'},
    ];
    return ApiResult({'status': 1, 'data': rows, 'total': notificationTotal});
  }
}

Future<_MediumApi> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _MediumApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.token = 'token';
  appController.user = {'id': 7};
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.guestCart = [];
  appController.cartProducts = [];
  appController.guestCartTotal = 0;
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('order details leaves the spinner and offers retry on failure', (
    tester,
  ) async {
    await _setup();
    await tester.pumpWidget(
      const MaterialApp(home: OrderDetailsScreen(id: '99')),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent search fills the search field', (tester) async {
    await _setup();
    await appController.addRecentSearch('shoe');
    await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
    await tester.pump();

    expect(find.text('shoe'), findsOneWidget);
    await tester.tap(find.text('shoe'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, 'shoe');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('mark all read covers every page, not just the loaded rows', (
    tester,
  ) async {
    final api = await _setup();
    await tester.pumpWidget(const MaterialApp(home: NotificationsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.done_all), findsOneWidget);
    await tester.tap(find.byIcon(Icons.done_all));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final reads = await NotificationRead.getReadIds(7);
    expect(reads, hasLength(api.notificationTotal));
    expect(api.notificationOffsets, contains(0));
    expect(api.notificationOffsets.any((offset) => offset > 0), isTrue);
  });
}
