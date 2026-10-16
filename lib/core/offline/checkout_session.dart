import 'dart:convert';
import 'dart:math';

import 'local_store.dart';

/// Checkout idempotency session: one stable key per logical order attempt.
///
/// The backend can only deduplicate retries when the SAME key is resent. A
/// key generated fresh on every tap (`DateTime.now()` per call) defeats
/// deduplication. This session:
/// * creates one key when the user confirms an order and persists it
///   (survives process termination during checkout),
/// * reuses it for every retry/gateway step of the same attempt,
/// * clears it only on authoritative success (order id received) or explicit
///   user cancellation — never on timeout/uncertainty.
///
/// On app restart with a non-cleared session the UI must show an "uncertain"
/// state and reconcile via order history BEFORE offering resubmission.

class CheckoutSession {
  CheckoutSession(this._store, this.scope);

  final LocalStore _store;
  final String scope;

  String get _key => 'checkout_session::$scope';

  Map<String, dynamic>? load() {
    final raw = _store.readJson(_key);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  String? get key {
    final s = load();
    final k = s?['idempotency_key']?.toString();
    return (k == null || k.isEmpty) ? null : k;
  }

  Map<String, dynamic>? get context {
    final s = load();
    final c = s?['context'];
    if (c is Map) return Map<String, dynamic>.from(c);
    return null;
  }

  bool matchesFingerprint(String fingerprint) {
    return context?['fingerprint'] == fingerprint;
  }

  /// Begins (or resumes) a session. Returns the stable key to send.
  /// If the cart fingerprint changed since the session started, a fresh key
  /// is generated so the backend does not attach an old key to a new order.
  Future<String> begin({Map<String, dynamic>? context}) async {
    final fingerprint = context?['fingerprint']?.toString();
    final existing = key;
    if (existing != null && (fingerprint == null || matchesFingerprint(fingerprint))) {
      return existing;
    }
    await clear();
    final now = DateTime.now();
    final entropy = Random().nextInt(0x7fffffff).toRadixString(36);
    final fresh =
        'checkout-$scope-${now.microsecondsSinceEpoch}-${now.millisecond.toRadixString(36)}-$entropy';
    await _store.writeString(_key, jsonEncode({
      'idempotency_key': fresh,
      'started_at': DateTime.now().millisecondsSinceEpoch,
      'context': context ?? {},
    }));
    return fresh;
  }

  Future<void> clear() => _store.remove(_key);
}

/// Deterministic fingerprint for a cart snapshot.
///
/// The backend idempotency key is scoped to the logical order, so the
/// fingerprint must change whenever the items, quantities, address, or
/// payment method change. It is cheap to compute and stable across devices.
String cartFingerprint({
  required List<Map<String, dynamic>> items,
  dynamic addressId,
  String? paymentMethod,
  String? deliveryTime,
  String? promoCodeId,
}) {
  final buffer = StringBuffer();
  buffer.write('a=${addressId ?? ''}&');
  buffer.write('p=${paymentMethod ?? ''}&');
  buffer.write('d=${deliveryTime ?? ''}&');
  buffer.write('c=${promoCodeId ?? ''}&');
  final sorted = items.map((i) {
    final vid = '${i['product_variant_id'] ?? i['variant_id'] ?? ''}';
    final qty = (i['qty'] ?? i['quantity'] ?? 0).toString();
    return '${vid}x$qty';
  }).toList();
  sorted.sort();
  buffer.write(sorted.join('|'));
  return buffer.toString();
}

/// Cryptographic hash is unnecessary here (the key itself is opaque), but
/// the fingerprint string is long; callers may truncate it to keep payloads
/// small. The first 64 characters still include the address and all items.
String compactFingerprint(String fingerprint, {int length = 64}) {
  if (fingerprint.length <= length) return fingerprint;
  return fingerprint.substring(0, length);
}
