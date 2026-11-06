import 'package:firebase_core/firebase_core.dart';

/// إعدادات Android العامة لتطبيق العميل في مشروع Firebase saree-market.
/// تُستخدم كخيار احتياطي عندما لا تكون إعدادات الخادم قد حُمّلت بعد.
class FirebaseConfig {
  static const String apiKey = 'AIzaSyCk-izCfnQbJvzteb2Uw8twDAylfe0m2JI';
  static const String appId = '1:615854672127:android:4751dc09d8349c6cb824ca';
  static const String messagingSenderId = '615854672127';
  static const String projectId = 'saree-market';
  static const String storageBucket = 'saree-market.firebasestorage.app';
  static const String authDomain = 'saree-market.firebaseapp.com';

  static const FirebaseOptions options = FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: storageBucket,
    authDomain: authDomain,
  );
}
