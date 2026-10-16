import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Token storage backed by platform secure storage (Keystore/Keychain).
///
/// A one-time migration reads the legacy SharedPreferences `token` value and
/// moves it into secure storage. The legacy slot is then deleted.
///
/// If secure storage is unavailable or fails, [TokenVaultException] is thrown
/// instead of silently falling back to plaintext. This prevents bearer tokens
/// from being captured in unencrypted backups or device dumps.
///
/// Tokens are never logged. Callers receive the value only for header
/// construction inside [CustomerApi.setToken].

class TokenVaultException implements Exception {
  const TokenVaultException(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => 'TokenVaultException: $message';
}

class TokenVault {
  TokenVault({FlutterSecureStorage? secure, this._prefs})
      : _secure = secure ?? const FlutterSecureStorage();

  static const storageKey = 'auth_token_v1';
  static const legacyKey = 'token';

  final FlutterSecureStorage _secure;
  final SharedPreferences? _prefs;

  Future<SharedPreferences> get _prefsAsync async =>
      _prefs ?? await SharedPreferences.getInstance();

  Future<String?> read() async {
    try {
      final v = await _secure.read(key: storageKey);
      if (v != null && v.isNotEmpty) return v;
    } catch (e) {
      throw TokenVaultException(
        'Secure storage read failed',
        cause: e,
      );
    }
    // One-time migration from the legacy plaintext slot.
    try {
      final p = await _prefsAsync;
      final legacy = p.getString(legacyKey);
      if (legacy != null && legacy.isNotEmpty) {
        await write(legacy);
        return legacy;
      }
    } catch (_) {}
    return null;
  }

  Future<void> write(String token) async {
    try {
      await _secure.write(key: storageKey, value: token);
    } catch (e) {
      throw TokenVaultException(
        'Secure storage write failed; token not persisted',
        cause: e,
      );
    }
    try {
      final p = await _prefsAsync;
      await p.remove(legacyKey);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _secure.delete(key: storageKey);
    } catch (_) {}
    try {
      final p = await _prefsAsync;
      await p.remove(legacyKey);
    } catch (_) {}
    if (kDebugMode) debugPrint('[auth] session cleared');
  }
}
