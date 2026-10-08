import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_controller.dart';

/// Real push notifications (FCM) — parity with front `NotificationBootstrap.jsx`.
///
/// Front reads the Firebase web config from backend `settings.firebase` and
/// registers `saree_fcm_token`. Mobile does the same: Firebase is initialized
/// from backend `settings['firebase']` when native `google-services.json` /
/// `GoogleService-Info.plist` files are absent, the real FCM token is sent to
/// the backend (`fcm_token`), and messages are shown + routed whether the app
/// is in foreground, background, or fully terminated.
///
/// Without any Firebase config the service disables itself gracefully and the
/// app keeps working with in-app notification polling.

/// Background isolate entry-point. Must stay top-level.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    final ok = await PushNotifications.ensureInitialized();
    if (!ok) return;
    await PushNotifications.showFromMessage(message);
  } catch (_) {}
}

class PushNotifications {
  PushNotifications._();

  static const channelId = 'saree_high_importance';
  static const channelName = 'تنبيهات سريع ماركت';
  static const _optionsCacheKey = 'saree_firebase_options';

  static bool enabled = false;
  static bool _listenersAttached = false;
  static GoRouter? _router;
  static String? _pendingRoute;

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  // ---------- Firebase init (default files -> backend settings -> cache) ----------

  static String _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && '$v'.isNotEmpty && '$v' != 'null') return '$v';
    }
    return '';
  }

  static FirebaseOptions? optionsFromSettings(Map<String, dynamic>? settings) {
    if (settings == null || settings.isEmpty) return null;
    final apiKey = _pick(settings, ['apiKey', 'api_key']);
    // Android needs its own appId (1:...:android:...). The shared web `appId`
    // does NOT work on Android — it is kept last and fails closed (disabled
    // gracefully) when no Android key exists. Per-app keys are served by the
    // backend settings table (see SettingApiController firebase merge).
    final appId = _pick(settings, [
      'customerAndroidAppId',
      'androidAppIdCustomer',
      'androidAppId',
      'android_app_id',
      'mobileAppId',
      'mobile_app_id',
      'appId',
      'app_id',
    ]);
    final senderId = _pick(settings, [
      'messagingSenderId',
      'messaging_sender_id',
      'senderId',
      'sender_id',
    ]);
    final projectId = _pick(settings, ['projectId', 'project_id']);
    if (apiKey.isEmpty || appId.isEmpty || senderId.isEmpty || projectId.isEmpty) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
      storageBucket: _pick(settings, ['storageBucket', 'storage_bucket']).isNotEmpty
          ? _pick(settings, ['storageBucket', 'storage_bucket'])
          : null,
      authDomain: _pick(settings, ['authDomain', 'auth_domain']).isNotEmpty
          ? _pick(settings, ['authDomain', 'auth_domain'])
          : null,
    );
  }

  static Future<void> _cacheOptions(FirebaseOptions options) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _optionsCacheKey,
        jsonEncode({
          'apiKey': options.apiKey,
          'appId': options.appId,
          'messagingSenderId': options.messagingSenderId,
          'projectId': options.projectId,
          if (options.storageBucket != null) 'storageBucket': options.storageBucket,
          if (options.authDomain != null) 'authDomain': options.authDomain,
        }),
      );
    } catch (_) {}
  }

  static Future<FirebaseOptions?> _cachedOptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_optionsCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return optionsFromSettings(map);
    } catch (_) {
      return null;
    }
  }

  /// Ensures Firebase is initialized. Safe to call from main() and from the
  /// background isolate. Returns false when no config is available at all.
  static Future<bool> ensureInitialized({Map<String, dynamic>? settings}) async {
    try {
      if (Firebase.apps.isNotEmpty) return true;
      try {
        await Firebase.initializeApp();
        return true;
      } catch (_) {}
      final opts = optionsFromSettings(settings) ?? await _cachedOptions();
      if (opts == null) return false;
      await Firebase.initializeApp(options: opts);
      await _cacheOptions(opts);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- Full setup (call after appController.bootstrap) ----------

  static Future<bool> init({Map<String, dynamic>? firebaseSettings}) async {
    try {
      final ok = await ensureInitialized(settings: firebaseSettings);
      if (!ok) {
        enabled = false;
        return false;
      }
      final messaging = FirebaseMessaging.instance;

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // iOS permission dialog.
      try {
        await messaging.requestPermission(alert: true, badge: true, sound: true);
      } catch (_) {}
      // iOS: wait for APNs token (best effort).
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          await messaging.getAPNSToken();
        } catch (_) {}
      }

      // Local notifications (foreground display + tap routing).
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        iOS: DarwinInitializationSettings(),
      );
      await _local.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          final route = _routeFromPayload(response.payload);
          _go(route);
        },
      );
      try {
        await _local
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } catch (_) {}
      try {
        await _local
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                channelId,
                channelName,
                description: 'Order updates and store notifications',
                importance: Importance.max,
              ),
            );
      } catch (_) {}
      try {
        await _local
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      } catch (_) {}

      // Real device token -> backend (replaces the stub token).
      try {
        final token = await messaging.getToken();
        if (token != null && token.isNotEmpty) {
          await appController.setFcmToken(token);
        }
      } catch (_) {}
      try {
        messaging.onTokenRefresh.listen((token) {
          appController.setFcmToken(token);
        });
      } catch (_) {}

      if (!_listenersAttached) {
        _listenersAttached = true;
        FirebaseMessaging.onMessage.listen((message) {
          showFromMessage(message);
        });
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          _go(_routeFromMessage(message.data));
        });
        try {
          FirebaseMessaging.instance.getInitialMessage().then((message) {
            if (message != null) {
              _go(_routeFromMessage(message.data));
            }
          });
        } catch (_) {}
      }

      enabled = true;
      return true;
    } catch (_) {
      enabled = false;
      return false;
    }
  }

  static void attachRouter(GoRouter router) {
    _router = router;
    if (_pendingRoute != null) {
      final next = _pendingRoute!;
      _pendingRoute = null;
      try {
        router.push(next);
      } catch (_) {}
    }
  }

  // ---------- Display + routing ----------

  static Future<void> showFromMessage(RemoteMessage message) async {
    try {
      final title = message.notification?.title ??
          message.data['title'] ??
          channelName;
      final body = message.notification?.body ??
          message.data['body'] ??
          message.data['message'] ??
          '';
      if (title.isEmpty && body.isEmpty) return;
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _local.show(
        id: message.hashCode,
        title: title,
        body: body,
        notificationDetails: details,
        payload: jsonEncode(message.data),
      );
    } catch (_) {}
  }

  static String _routeFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return '/notifications';
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        return _routeFromMessage(decoded);
      }
    } catch (_) {}
    return '/notifications';
  }

  /// Backend payload -> app route. Order-ish payloads land on the unified
  /// order details screen (which resolves checkout-groups first, like web).
  static String _routeFromMessage(Map data) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = ('${data[k] ?? ''}').trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final link = pick(['link', 'link_url', 'url', 'click_action']);
    if (link.startsWith('/')) return link;

    final groupId = pick(['checkout_group_id', 'checkoutGroupId', 'group_id']);
    if (groupId.isNotEmpty) return '/orders/$groupId';

    final orderId = pick(['order_id', 'orderId', 'order_item_id', 'id']);
    final type = pick(['type', 'notification_type']).toLowerCase();
    if (orderId.isNotEmpty &&
        (type.contains('order') ||
            type.contains('checkout') ||
            type.contains('deliver') ||
            type.isEmpty)) {
      return '/orders/$orderId';
    }
    return '/notifications';
  }

  static void _go(String route) {
    try {
      final router = _router;
      if (router == null) {
        _pendingRoute = route;
        return;
      }
      router.push(route);
    } catch (_) {
      _pendingRoute = route;
    }
  }
}
