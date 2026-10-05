import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notificações financeiras aguardam commit e descartam rollback e falhas',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    var events = 0;
    final subscription = db.tableUpdates().listen((_) => events++);
    addTearDown(subscription.cancel);
    Future<void> flush() => Future<void>.delayed(Duration.zero);
    Future<void> insert(String id) => db.customStatement(
        '''INSERT INTO "accounts" (id,name,type,currency_code,initial_balance_minor,created_at,updated_at)
      VALUES (?,'Carteira','cash','BRL',0,1,1)''', [id]);
    await db.transaction(() async {
      await insert('one');
      await db.customStatement(
          'UPDATE accounts SET name=? WHERE id=?', ['Conta', 'one']);
      await flush();
      expect(events, 0);
    });
    await flush();
    expect(events, 1);
    await expectLater(db.transaction(() async {
      await insert('rolled-back');
      await flush();
      expect(events, 1);
      throw StateError('rollback');
    }), throwsStateError);
    await flush();
    expect(events, 1);
    expect(
        await db
            .customSelect("SELECT * FROM accounts WHERE id='rolled-back'")
            .get(),
        isEmpty);
    await expectLater(insert('one'), throwsA(isA<Exception>()));
    await flush();
    expect(events, 1);
    await db.customStatement('DELETE FROM "accounts" WHERE id=?', ['one']);
    await flush();
    expect(events, 2);
    await db.customStatement('UPDATE sync_state SET clock=clock+1 WHERE id=1');
    await flush();
    expect(events, 2);
  });
}
