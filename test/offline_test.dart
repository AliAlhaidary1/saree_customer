import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/offline/cache_policy.dart';
import 'package:sareemart_customer/core/offline/local_store.dart';
import 'package:sareemart_customer/core/offline/offline_cache.dart';
import 'package:sareemart_customer/core/offline/pending_ops.dart';
import 'package:sareemart_customer/core/offline/sync_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LocalStore> freshStore() async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    return LocalStore(p);
  }

  group('LocalStore', () {
    test('corrupt json is quarantined without touching siblings', () async {
      SharedPreferences.setMockInitialValues({
        'a': 'not-json',
        'b': jsonEncode({'ok': 1}),
      });
      final p = await SharedPreferences.getInstance();
      final s = LocalStore(p);
      expect(s.readJson('a'), isNull);
      expect(s.readJson('b'), {'ok': 1});
    });

    test('writeJson size-guard refuses oversized payload', () async {
      final s = await freshStore();
      final big = List.filled(500 * 1024, 'x').join();
      final ok = await s.writeJson('huge', {'v': big});
      expect(ok, isFalse);
    });

    test('account isolation key scopes', () {
      expect(LocalStore.accountScope('123'), 'u:123');
      expect(LocalStore.accountScope(''), 'guest');
      expect(LocalStore.accountScope(null), 'guest');
    });
  });

  group('OfflineCache', () {
    test('queryHash is stable and bounded', () {
      final a = OfflineCache.queryHash({'b': 2, 'a': 1});
      final b = OfflineCache.queryHash({'a': 1, 'b': 2});
      expect(a, b);
      expect(a.length, lessThan(20));
    });

    test('freshness respects CachePolicy TTL', () async {
      final s = await freshStore();
      final c = OfflineCache(s);
      await c.writeDoc('key', {'x': 1});
      expect(c.fresh('key', CacheEntity.productDetails), isTrue);
      // Artificially backdate by re-writing with old timestamp
      await s.writeJson('key', {
        'v': 1,
        'scope': 'guest',
        'refreshedAt': DateTime.now()
            .subtract(const Duration(minutes: 20))
            .millisecondsSinceEpoch,
        'payload': {'x': 1},
      });
      expect(c.fresh('key', CacheEntity.productDetails), isFalse);
    });

    test('clearAccountDocs removes only scoped docs', () async {
      final s = await freshStore();
      final c = OfflineCache(s);
      await c.writeDoc(OfflineCache.ordersKey('u:1'), ['o1'], scope: 'u:1');
      await c.writeDoc(OfflineCache.ordersKey('guest'), ['o2'], scope: 'guest');
      await c.writeDoc('shop_cache', {'x': 1});
      await c.clearAccountDocs('u:1');
      expect(c.readDoc(OfflineCache.ordersKey('u:1')), isNull);
      expect(c.readDoc(OfflineCache.ordersKey('guest')), isNotNull);
      expect(c.readDoc('shop_cache'), isNotNull);
    });
  });

  group('PendingOutbox', () {
    test('coalesces favorite ops by product id', () async {
      final s = await freshStore();
      final out = PendingOutbox(s, 'u:1');
      final pid = '42';
      await out.enqueue(PendingOp(
        id: 'a',
        type: PendingOpType.favoriteAdd,
        payload: {'product_id': pid},
        createdAt: DateTime.now(),
      ));
      await out.enqueue(PendingOp(
        id: 'b',
        type: PendingOpType.favoriteRemove,
        payload: {'product_id': pid},
        createdAt: DateTime.now(),
      ));
      final ops = out.load();
      expect(ops.length, 1);
      expect(ops.first.type, PendingOpType.favoriteRemove);
    });

    test('backoff grows and caps', () {
      final b = PendingOutbox.backoffForAttempt(0);
      expect(b.inSeconds, greaterThanOrEqualTo(2));
      final big = PendingOutbox.backoffForAttempt(20);
      expect(big.inSeconds, lessThanOrEqualTo(600));
    });
  });

  group('SyncEngine', () {
    test('single-flight: concurrent runs collapse', () async {
      final s = await freshStore();
      final out = PendingOutbox(s, 'u:1');
      await out.enqueue(PendingOp(
        id: 'op',
        type: PendingOpType.favoriteAdd,
        payload: {'product_id': '1'},
        createdAt: DateTime.now(),
      ));
      var calls = 0;
      Future<bool> slowExec(PendingOp op) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return true;
      }

      final engine = SyncEngine(outboxForCurrentScope: () => out);
      // Three overlapping requests should result in a single execution pass.
      await Future.wait([
        engine.run(executor: slowExec),
        Future<void>.delayed(const Duration(milliseconds: 5), engine.run),
        Future<void>.delayed(const Duration(milliseconds: 10), engine.run),
      ]);
      expect(calls, 1);
      expect(out.load().isEmpty, isTrue);
      engine.dispose();
    });
  });

  scopedDraftWriteTests();
}

void scopedDraftWriteTests() {
  group('ScopedDraftWrite (debounce scope guard)', () {
    test('same scope writes captured fields', () {
      final w = ScopedDraftWrite(
        scope: 'u:1',
        fields: {'note': 'hi', 'method': 'COD'},
      );
      expect(w.forScope('u:1'), {'note': 'hi', 'method': 'COD'});
    });

    test('account switch inside the window drops the write', () {
      final w = ScopedDraftWrite(scope: 'u:1', fields: {'note': 'hi'});
      expect(w.forScope('u:2'), isNull);
      expect(w.forScope('guest'), isNull);
    });

    test('fields snapshot is isolated from later mutation', () {
      final fields = {'note': 'a'};
      final w = ScopedDraftWrite(scope: 'u:1', fields: fields);
      fields['note'] = 'mutated';
      expect(w.forScope('u:1'), {'note': 'a'});
    });
  });
}
