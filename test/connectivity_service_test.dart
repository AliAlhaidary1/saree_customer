import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

import 'package:sareemart_customer/core/api/api_errors.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/offline/connectivity_service.dart';
import 'package:sareemart_customer/widgets/connectivity_badge.dart';

class _FakeApi extends CustomerApi {
  _FakeApi() : super(baseUrl: 'http://test.invalid');
}

Future<void> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _FakeApi();
  appController.injectForTest(prefs: prefs, testApi: api);
  appController.overrideConnectivityForTest(true);
  addTearDown(() => appController.overrideConnectivityForTest(true));
}

ApiResult _networkFail() => ApiResult({
  'status': 0,
  'message': 'timeout',
  'error': {'code': 'TIMEOUT', 'httpStatus': 504},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectivityService (library-backed)', () {
    test('defaults to online until a probe says otherwise', () {
      final service = ConnectivityService();
      expect(service.isOnline, isTrue);
    });

    test('init() with a failing probe flips the monitor to offline', () async {
      final service = ConnectivityService(probe: () async => false);
      await service.init();
      expect(service.isOnline, isFalse);
    });

    test('init() with a passing probe keeps the monitor online', () async {
      final service = ConnectivityService(probe: () async => true);
      await service.init();
      expect(service.isOnline, isTrue);
    });

    test('subscribes and reacts to status stream transitions both ways',
        () async {
      final controller = StreamController<InternetStatus>.broadcast();
      addTearDown(controller.close);
      final service = ConnectivityService(
        probe: () async => true,
        statusStream: controller.stream,
      );
      await service.init();
      expect(service.isOnline, isTrue);
      controller.add(InternetStatus.disconnected);
      await Future<void>.delayed(Duration.zero);
      expect(service.isOnline, isFalse);
      controller.add(InternetStatus.connected);
      await Future<void>.delayed(Duration.zero);
      expect(service.isOnline, isTrue);
    });

    test('init() is idempotent (second call does not rewire the stream)',
        () async {
      var probeCalls = 0;
      final controller = StreamController<InternetStatus>.broadcast();
      addTearDown(controller.close);
      final service = ConnectivityService(
        probe: () async {
          probeCalls += 1;
          return true;
        },
        statusStream: controller.stream,
      );
      await service.init();
      await service.init();
      expect(probeCalls, 1);
    });
  });

  group('AppController connectivity wiring', () {
    test('looksOffline is false with a healthy monitor and no failures',
        () async {
      await _setup();
      expect(appController.looksOffline, isFalse);
      expect(appController.isOnline, isTrue);
    });

    test('looksOffline is true when the monitor says offline (no API call needed)',
        () async {
      await _setup();
      appController.overrideConnectivityForTest(false);
      expect(appController.isOnline, isFalse);
      expect(appController.looksOffline, isTrue);
    });

    test('looksOffline is true when the last server call failed with a network class',
        () async {
      await _setup();
      appController.api.recordFailure(_networkFail().classifiedError!);
      expect(appController.looksOffline, isTrue);
      appController.api.recordSuccess();
      expect(appController.looksOffline, isFalse);
    });

    test('looksOffline combines both sources (probe offline + server fine still reads offline)',
        () async {
      await _setup();
      appController.api.recordSuccess();
      appController.overrideConnectivityForTest(false);
      expect(appController.looksOffline, isTrue);
    });
  });

  group('ConnectivityBadge (widget)', () {
    testWidgets('renders wifi icon online and wifi-off icon offline, with NO text',
        (tester) async {
      await _setup();
      addTearDown(() => appController.overrideConnectivityForTest(true));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: ConnectivityBadge()),
          ),
        ),
      );
      expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      expect(find.byType(Text), findsNothing);

      appController.overrideConnectivityForTest(false);
      await tester.pump();
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.wifi_rounded), findsNothing);
      expect(find.byType(Text), findsNothing);

      appController.overrideConnectivityForTest(true);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);
      expect(find.byType(Text), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
