import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'app.dart';
import 'core/app_controller.dart';
import 'core/app_theme.dart';
import 'core/push_notifications.dart';
import 'widgets/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Device-safe image cache: bounded RAM usage, avoids OOM on long browsing.
  try {
    PaintingBinding.instance.imageCache.maximumSize = 200;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 80 << 20; // 80MB
  } catch (_) {}
  // Background handler registered unconditionally (before runApp) so the OS
  // can wake the app for data-only pushes when fully closed. The handler
  // self-initializes Firebase from native files or cached backend options
  // and no-ops gracefully when no config exists yet (first install).
  try {
    FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler,
    );
  } catch (_) {}
  // Best-effort Firebase init so background/terminated notifications can wake
  // the app. Uses native google-services files when present, otherwise the
  // cached backend-provided options from the last successful run.
  try {
    await PushNotifications.ensureInitialized();
  } catch (_) {}
  runApp(const ProviderScope(child: BootstrapApp()));
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  GoRouter? router;
  final apiUrl = TextEditingController();
  bool _showSplash = true;
  bool _bootstrapDone = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    apiUrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final splashMin = Future<void>.delayed(
      // مدة أنيميشن السبلاش المبسط (1400ms) — سريع بدون انتظار زائد
      const Duration(milliseconds: 1500),
    );
    await appController.bootstrap();
    // Real FCM token (backend settings.firebase -> Firebase -> fcm_token sync).
    // Gracefully disabled when no Firebase config exists anywhere.
    try {
      final fb = appController.settings['firebase'];
      await PushNotifications.init(
        firebaseSettings: fb is Map<String, dynamic>
            ? fb
            : (fb is Map ? Map<String, dynamic>.from(fb) : null),
      );
    } catch (_) {}
    apiUrl.text = appController.apiUrl;
    if (!mounted) return;
    final failed =
        appController.bootstrapError != null && appController.cities.isEmpty;
    _bootstrapDone = true;
    if (!failed) {
      router = buildRouter();
      PushNotifications.attachRouter(router!);
    }
    setState(() {});
    // انتظر اكتمال الأنيميشن + انتهاء التحميل، ثم خروج واحد سلس (لا واجهتين)
    await splashMin;
    if (mounted) setState(() => _showSplash = false);
  }

  @override
  Widget build(BuildContext context) {
    // انتقال واحد متلاشي: سبلاش -> تطبيق (بدون قفزة بين واجهتين)
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: _child(),
    );
  }

  Widget _child() {
    if (_showSplash || !_bootstrapDone) {
      return const MaterialApp(
        key: ValueKey('splash'),
        debugShowCheckedModeBanner: false,
        home: BrandSplashScreen(),
      );
    }

    if (router == null) {
      return MaterialApp(
        key: const ValueKey('error'),
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.build(locale: const Locale('ar')),
        home: Scaffold(
          backgroundColor: AppTheme.primaryNavy,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_outlined,
                  color: AppTheme.accentOrange,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  AppTheme.brandNameAr,
                  style: const TextStyle(
                    color: AppTheme.backgroundWhite,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (appController.bootstrapError != null) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      appController.t('network_error'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.backgroundWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      '${appController.apiUrl}\n${appController.bootstrapError}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.backgroundWhite.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (kDebugMode) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: TextField(
                        controller: apiUrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'API URL',
                          labelStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: BrandedButton(
                      onPressed: () async {
                        if (kDebugMode) {
                          await appController.setApiUrl(apiUrl.text);
                        }
                        setState(() {
                          _showSplash = true;
                          _bootstrapDone = false;
                          router = null;
                        });
                        await _start();
                      },
                      label: appController.t('retry'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return SareemartCustomerApp(router: router!);
  }
}
