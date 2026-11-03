import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sareemart_customer/app.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/features/onboarding/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  appController.injectForTest(
    prefs: prefs,
    testApi: CustomerApi(baseUrl: 'http://test.invalid'),
  );
  appController.token = null;
  appController.user = null;
}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('ar'),
  theme: ThemeData(useMaterial3: true),
  home: Directionality(textDirection: TextDirection.rtl, child: home),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('three onboarding pages complete and persist first run', (
    tester,
  ) async {
    await _setup();
    var completed = false;
    await tester.pumpWidget(
      _app(
        OnboardingScreen(
          onComplete: () async {
            await appController.completeOnboarding();
            completed = true;
          },
        ),
      ),
    );

    expect(find.text('onboarding_1_title'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(find.text('onboarding_2_title'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(find.text('onboarding_3_title'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(appController.onboardingCompleted, isTrue);
  });

  testWidgets('skipping onboarding persists completion', (tester) async {
    await _setup();
    await tester.pumpWidget(
      _app(OnboardingScreen(onComplete: appController.completeOnboarding)),
    );

    await tester.tap(find.byKey(const Key('onboarding_skip')));
    await tester.pumpAndSettle();

    expect(appController.onboardingCompleted, isTrue);
  });

  testWidgets('home tutorial covers key actions and never repeats', (
    tester,
  ) async {
    await _setup();
    await appController.completeOnboarding();
    final titles = [
      'tutorial_search_title',
      'tutorial_cart_title',
      'tutorial_assistant_title',
      'tutorial_haraj_title',
      if (appController.akhdimniEnabled) 'tutorial_akhdimni_title',
      'tutorial_orders_title',
    ];

    await tester.pumpWidget(
      _app(const AppShell(location: '/', child: SizedBox.expand())),
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    for (final title in titles) {
      expect(find.text(title), findsOneWidget, reason: title);
      await tester.tap(find.byKey(const Key('tutorial_next')));
      await tester.pumpAndSettle();
    }

    expect(appController.appTutorialCompleted, isTrue);
    expect(find.byKey(const Key('tutorial_next')), findsNothing);

    await tester.pumpWidget(Container());
    await tester.pumpWidget(
      _app(const AppShell(location: '/', child: SizedBox.expand())),
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tutorial_next')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
