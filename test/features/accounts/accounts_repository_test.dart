import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/schema_v1.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/domain/money_minor.dart';
import 'package:flutter_test/flutter_test.dart';

class _LegacyV1 extends GeneratedDatabase {
  _LegacyV1(super.executor);

  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (_) async {
          for (final statement in schemaV1) {
            await customStatement(statement);
          }
        },
      );
}

void main() {
  const draft = AccountDraft(
    name: 'Carteira',
    type: AccountType.cash,
    currencyCode: 'BRL',
    initialBalanceMinor: 12345,
    includeInAnalytics: true,
  );

  test('converte dinheiro sem ponto flutuante', () {
    expect(MoneyMinor.parse('123,45'), 12345);
    expect(MoneyMinor.parse('-1.2'), -120);
    expect(MoneyMinor.plain(-120), '-1,20');
    expect(() => MoneyMinor.parse('1,234'), throwsFormatException);
  });

  test('CRUD offline, saldo efetivo, arquivamento e bloqueio no banco',
      () async {
    final directory = await Directory.systemTemp.createTemp('finapp-accounts-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/finapp.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    var repo = SqliteAccountsRepository(db);
    final account = await repo.create(draft);
    expect(account.currentBalanceMinor, 12345);
    expect(account.type, AccountType.cash);

    final updated = await repo.update(
        account.id,
        const AccountDraft(
          name: 'Dinheiro',
          type: AccountType.cash,
          currencyCode: 'BRL',
          initialBalanceMinor: 15000,
          includeInAnalytics: false,
        ));
    expect(updated.name, 'Dinheiro');
    expect(updated.includeInAnalytics, false);

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.customStatement('''INSERT INTO transactions
      (id, description, type, planned_amount_minor, actual_amount_minor,
       competence_at, effective_at, account_id, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''', [
      'expense-1',
      'Pago',
      'expense',
      3000,
      2500,
      now,
      now,
      account.id,
      now,
      now
    ]);
    await db.customStatement('''INSERT INTO transactions
      (id, description, type, planned_amount_minor, competence_at,
       account_id, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
        ['pending-1', 'Pendente', 'expense', 9000, now, account.id, now, now]);
    expect((await repo.list()).single.currentBalanceMinor, 12500);

    await repo.setArchived(account.id, archived: true);
    expect((await repo.list()).single.isArchived, true);
    await expectLater(
      db.customStatement('''INSERT INTO transactions
        (id, description, type, planned_amount_minor, competence_at,
         account_id, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
          ['blocked', 'Não pode', 'expense', 100, now, account.id, now, now]),
      throwsA(isA<Exception>()),
    );
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    repo = SqliteAccountsRepository(db);
    expect((await repo.list()).single.currentBalanceMinor, 12500);
    await repo.setArchived(account.id, archived: false);
    expect((await repo.list()).single.isArchived, false);
  });

  test('migra v1 para v6 sem perder contas existentes', () async {
    final directory =
        await Directory.systemTemp.createTemp('finapp-migration-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/finapp.sqlite');
    final old = _LegacyV1(NativeDatabase(file));
    await old.customStatement('''INSERT INTO accounts
      (id, name, type, currency_code, initial_balance_minor,
       created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)''',
        ['legacy', 'Legada', 'cash', 'BRL', 730, 1, 1]);
    await old.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), AppDatabase.currentSchemaVersion);
    final accounts = await SqliteAccountsRepository(db).list();
    expect(accounts.single.currentBalanceMinor, 730);
  });

  for (final reference in ['card', 'payment', 'deletedTransaction']) {
    test('moeda preservada com vínculo financeiro: $reference', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = SqliteAccountsRepository(db);
      final account = await repo.create(draft);
      if (reference == 'deletedTransaction') {
        await db.customStatement(
          """INSERT INTO transactions
          (id,description,type,planned_amount_minor,competence_at,account_id,
           created_at,updated_at,deleted_at)
          VALUES ('old','Histórico','expense',100,1,?,1,1,2)""",
          [account.id],
        );
      } else {
        final other = await repo.create(draft);
        await db.customStatement(
          """INSERT INTO credit_cards
          (id,name,payment_account_id,closing_day,due_day,created_at,updated_at)
          VALUES ('card','Cartão',?,25,5,1,1)""",
          [reference == 'card' ? account.id : other.id],
        );
        if (reference == 'payment') {
          await db.customStatement("""INSERT INTO card_invoices
            (id,card_id,month_at,closing_at,due_at,created_at,updated_at)
            VALUES ('invoice','card',1,1,2,1,1)""");
          await db.customStatement(
            """INSERT INTO card_payments
            (id,invoice_id,account_id,amount_minor,effective_at,created_at,updated_at)
            VALUES ('payment','invoice',?,100,1,1,1)""",
            [account.id],
          );
        }
      }
      await expectLater(
        repo.update(
          account.id,
          const AccountDraft(
            name: 'Outra moeda',
            type: AccountType.cash,
            currencyCode: 'USD',
            initialBalanceMinor: 12345,
            includeInAnalytics: true,
          ),
        ),
        throwsStateError,
      );
      final preserved = (await repo.list()).singleWhere(
        (a) => a.id == account.id,
      );
      expect(preserved.currencyCode, 'BRL');
      expect(preserved.name, draft.name);
      await repo.update(account.id, draft);
    });
  }
}
