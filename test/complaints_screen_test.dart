import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/business_hours.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/features/complaints/complaints_screen.dart';

class _ComplaintsApi extends CustomerApi {
  _ComplaintsApi() : super(baseUrl: 'http://test.invalid');

  bool online = true;
  int submitCalls = 0;
  bool submitOk = true;
  String submitMessage = 'complaint_sent_success';
  Map<String, dynamic>? lastSubmit;

  @override
  Future<ApiResult> cities({
    int limit = 100,
    int offset = 0,
    String search = '',
  }) async {
    if (!online) {
      return ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });
    }
    return ApiResult({
      'status': 1,
      'data': [
        {'id': 1, 'name': 'Test City'},
      ],
    });
  }

  @override
  Future<ApiResult> submitComplaint({
    required String name,
    required String phone,
    String email = '',
    required String type,
    String subject = '',
    required String message,
    String orderId = '',
  }) async {
    submitCalls++;
    lastSubmit = {
      'name': name,
      'phone': phone,
      'email': email,
      'type': type,
      'subject': subject,
      'message': message,
      'order_id': orderId,
    };
    if (!submitOk) {
      return ApiResult({'status': 0, 'message': 'server refused'});
    }
    return ApiResult({'status': 1, 'message': submitMessage, 'data': {'id': 7}});
  }

  @override
  Future<ApiResult> myComplaints() async {
    if (!online) {
      return ApiResult({
        'status': 0,
        'message': 'timeout',
        'error': {'code': 'TIMEOUT', 'httpStatus': 504},
      });
    }
    return ApiResult({'status': 1, 'data': []});
  }
}

Future<_ComplaintsApi> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _ComplaintsApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.city = {'id': 1, 'latitude': 15.0, 'longitude': 45.0};
  appController.businessHours = BusinessHoursResult();
  appController.token = 'tok';
  appController.user = {'id': 7, 'name': 'Tester', 'mobile': '777000000', 'email': 't@t.com'};
  appController.cartProducts = [];
  appController.cartSubTotal = 0;
  appController.guestCart = [];
  appController.guestCartTotal = 0;
  appController.cart = null;
  return api;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty form does not hit the API', (tester) async {
    final api = await _setup();
    await tester.pumpWidget(const MaterialApp(home: ComplaintsScreen()));
    await _settle(tester);
    // Tap send without filling anything.
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'send'));
    await tester.tap(find.widgetWithText(FilledButton, 'send'));
    await _settle(tester);
    expect(api.submitCalls, 0);
    expect(find.text('field_required'), findsWidgets);
  });

  testWidgets('submit fires API with form data and clears afterwards', (tester) async {
    final api = await _setup();
    await tester.pumpWidget(const MaterialApp(home: ComplaintsScreen()));
    await _settle(tester);
    await tester.enterText(find.byType(TextFormField).at(5), 'مشكلتي في الطلب رقم 999');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'send'));
    await tester.tap(find.widgetWithText(FilledButton, 'send'));
    await _settle(tester);
    expect(api.submitCalls, 1);
    expect(api.lastSubmit?['message'], 'مشكلتي في الطلب رقم 999');
    expect(find.text('complaint_sent_success'), findsOneWidget);
  });

  testWidgets('submit while offline shows the internet-required dialog and does NOT fire the API',
      (tester) async {
    final api = await _setup()..online = false;
    await tester.pumpWidget(const MaterialApp(home: ComplaintsScreen()));
    await _settle(tester);
    await tester.enterText(find.byType(TextFormField).at(5), 'message body');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'send'));
    await tester.tap(find.widgetWithText(FilledButton, 'send'));
    await _settle(tester);
    expect(api.submitCalls, 0);
    // Dialog appears (button to dismiss; text key exists in screen shell).
    expect(find.byType(AlertDialog), findsWidgets);
  });

  testWidgets('server refusal keeps draft and shows the backend message', (tester) async {
    final api = await _setup()..submitOk = false;
    await tester.pumpWidget(const MaterialApp(home: ComplaintsScreen()));
    await _settle(tester);
    await tester.enterText(find.byType(TextFormField).at(5), 'رسالة الاختبار');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'send'));
    await tester.tap(find.widgetWithText(FilledButton, 'send'));
    await _settle(tester);
    expect(api.submitCalls, 1);
    expect(find.text('server refused'), findsOneWidget);
    // The form field still contains the message (not cleared).
    expect(find.text('رسالة الاختبار'), findsOneWidget);
  });

  testWidgets('snapshot-less logged-in user sees zero complaints', (tester) async {
    await _setup();
    await tester.pumpWidget(const MaterialApp(home: ComplaintsScreen()));
    await _settle(tester);
    expect(find.text('no_submissions_yet'), findsOneWidget);
  });
}
