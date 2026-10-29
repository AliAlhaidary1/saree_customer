import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/offline/local_store.dart';
import 'package:sareemart_customer/core/offline/pending_ops.dart';
import 'package:sareemart_customer/core/offline/sync_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('account switch during sync never replays the old outbox as new user',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    var scope = 'u:1';
    final oldOutbox = PendingOutbox(store, scope);
    for (final id in ['first', 'second']) {
      await oldOutbox.enqueue(PendingOp(
        id: id,
        type: PendingOpType.favoriteAdd,
        // Deliberately legacy: no account_scope stamp.
        payload: {'product_id': id},
        createdAt: DateTime.now(),
      ));
    }
    final started = Completer<void>();
    final response = Completer<bool>();
    final executed = <String>[];
    final engine = SyncEngine(
      outboxForCurrentScope: () => PendingOutbox(store, scope),
    );
    final running = engine.run(executor: (op) async {
      executed.add('$scope:${op.id}');
      started.complete();
      return response.future;
    });
    await started.future;
    scope = 'u:2';
    response.complete(true);
    await running;
    expect(executed, ['u:1:first']);
    expect(oldOutbox.load().map((op) => op.id), ['second']);
    expect(PendingOutbox(store, scope).load(), isEmpty);
    engine.dispose();
  });
}
