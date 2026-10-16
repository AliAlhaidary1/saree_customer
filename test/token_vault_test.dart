import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/auth/token_vault.dart';

class _FailingStoragePlatform extends TestFlutterSecureStoragePlatform {
  _FailingStoragePlatform(super.data);

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async {
    throw Exception('secure storage unavailable');
  }

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async {
    throw Exception('secure storage unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
  });

  Future<TokenVault> freshVault({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    return TokenVault(prefs: p);
  }

  group('TokenVault', () {
    test('reads secure value when present', () async {
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({
        TokenVault.storageKey: 'secret-token',
      });
      final vault = await freshVault();
      expect(await vault.read(), 'secret-token');
    });

    test('migrates legacy plaintext token and removes legacy slot', () async {
      final vault = await freshVault(prefs: {
        TokenVault.legacyKey: 'legacy-token',
      });
      expect(await vault.read(), 'legacy-token');
      final p = await SharedPreferences.getInstance();
      // Legacy slot should be cleared after migration.
      expect(p.getString(TokenVault.legacyKey), isNull);
      // Secure slot should now hold the migrated value.
      final secure = await const FlutterSecureStorage().read(key: TokenVault.storageKey);
      expect(secure, 'legacy-token');
    });

    test('write throws TokenVaultException instead of plaintext fallback', () async {
      FlutterSecureStoragePlatform.instance = _FailingStoragePlatform({});
      final vault = await freshVault();
      expect(
        () => vault.write('token'),
        throwsA(isA<TokenVaultException>()),
      );
      final p = await SharedPreferences.getInstance();
      expect(p.getString(TokenVault.legacyKey), isNull);
    });

    test('read throws TokenVaultException on secure failure', () async {
      FlutterSecureStoragePlatform.instance = _FailingStoragePlatform({});
      final vault = await freshVault();
      expect(
        () => vault.read(),
        throwsA(isA<TokenVaultException>()),
      );
    });

    test('clear removes secure and legacy tokens', () async {
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({
        TokenVault.storageKey: 'token',
      });
      final vault = await freshVault(prefs: {
        TokenVault.legacyKey: 'token',
      });
      await vault.clear();
      final secure = await const FlutterSecureStorage().read(key: TokenVault.storageKey);
      expect(secure, isNull);
      final p = await SharedPreferences.getInstance();
      expect(p.getString(TokenVault.legacyKey), isNull);
    });
  });
}
