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
    final subscription = db.financialChanges.listen((_) => events++);
    addTearDown(subscription.cancel);
    Future<void> flush() => Future<void>.delayed(Duration.zero);
    Future<void> insert(String id) => db.customStatement(
        '''INSERT INTO "accounts" (id,name,type,currency_code,initial_balance_minor,created_at,updated_at)
      VALUES (?,'Carteira','cash','BRL',0,1,1)''', [id]);
    await db.transaction(() async {
      await insert('one');
      await db.customUpdate("UPDATE accounts SET name='Conta' WHERE id='one'");
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
    await db.customUpdate("DELETE FROM accounts WHERE id='one'");
    await flush();
    expect(events, 2);
    expect(
        await db.customUpdate(
            "UPDATE accounts SET name='Ausente' WHERE id='missing'"),
        0);
    await db.customStatement('UPDATE sync_state SET clock=clock+1 WHERE id=1');
    await flush();
    expect(events, 2);
  });
  test('savepoint revertido não contamina notificações da transação externa',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    var events = 0;
    final subscription = db.financialChanges.listen((_) => events++);
    addTearDown(subscription.cancel);
    await db.transaction(() async {
      await expectLater(
          db.transaction(() async {
            await db.customStatement('''INSERT INTO accounts
          (id,name,type,currency_code,initial_balance_minor,created_at,updated_at)
          VALUES ('nested','Carteira','cash','BRL',0,1,1)''');
            throw StateError('savepoint rollback');
          }, requireNew: true),
          throwsStateError);
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, 0);
    expect(
        await db.customSelect("SELECT * FROM accounts WHERE id='nested'").get(),
        isEmpty);
    await expectLater(db.transaction(() async {
      await db.transaction(() => db.customStatement('''INSERT INTO accounts
          (id,name,type,currency_code,initial_balance_minor,created_at,updated_at)
          VALUES ('nested','Carteira','cash','BRL',0,1,1)'''),
          requireNew: true);
      throw StateError('outer rollback');
    }), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(events, 0);
  });
}
