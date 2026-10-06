import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final type in TransactionType.values) {
    test('$type: hoje, ajuste, desfazer e proteção contra ação antiga',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final accounts = SqliteAccountsRepository(db);
      final account = await accounts.create(const AccountDraft(
          name: 'Banco',
          type: AccountType.checking,
          currencyCode: 'BRL',
          initialBalanceMinor: 10000,
          includeInAnalytics: true));
      final repo = SqliteTransactionsRepository(db);
      final today = DateTime.now();
      final posted = DateTime(today.year, today.month, today.day - 5);
      final due = DateTime(today.year, today.month, today.day + 5);
      final item = await repo.create(TransactionDraft(
          description: 'Teste',
          type: type,
          amountMinor: 2500,
          date: posted,
          dueDate: due,
          isEffective: false,
          accountId: account.id));
      await repo.setEffective(item.id, effective: true, effectiveDate: today);
      final changed = (await repo.list()).single;
      expect(changed.description, 'Teste');
      expect(changed.date.day, posted.day);
      expect(changed.dueDate!.day, due.day);
      expect(changed.effectiveDate!.day, today.day);
      expect((await accounts.list()).single.currentBalanceMinor,
          type == TransactionType.income ? 12500 : 7500);
      await expectLater(
          repo.setEffective(item.id, effective: true, effectiveDate: today),
          throwsStateError);
      await repo.changeEffectiveDate(item.id,
          expectedDate: today, effectiveDate: due);
      expect((await repo.list()).single.isEffective, false);
      expect((await accounts.list()).single.currentBalanceMinor, 10000);
      await expectLater(repo.changeEffectiveDate(item.id, expectedDate: today),
          throwsStateError);
      await repo.changeEffectiveDate(item.id, expectedDate: due);
      final undone = (await repo.list()).single;
      expect(undone.effectiveDate, isNull);
      expect(undone.amountMinor, 2500);
      expect(undone.accountId, account.id);
      expect(undone.dueDate, changed.dueDate);
      await expectLater(repo.changeEffectiveDate(item.id, expectedDate: due),
          throwsStateError);
    });
  }
  test(
      'transferência: dois saldos consistentes, restauro de agendamento e exclusão',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final accounts = SqliteAccountsRepository(db);
    Future<Account> account(String name) => accounts.create(AccountDraft(
        name: name,
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 10000,
        includeInAnalytics: true));
    final source = await account('Origem');
    final destination = await account('Destino');
    final repo = SqliteTransfersRepository(db);
    final today = DateTime.now();
    final future = DateTime(today.year, today.month, today.day + 5);
    final item = await repo.create(TransferDraft(
        description: 'Reserva',
        sourceAccountId: source.id,
        destinationAccountId: destination.id,
        amountMinor: 2500,
        date: today,
        dueDate: future,
        effectiveDate: future,
        isEffective: true));
    await repo.setEffective(item.id, effective: true, effectiveDate: today);
    final balances = {
      for (final a in await accounts.list()) a.id: a.currentBalanceMinor
    };
    expect(balances[source.id], 7500);
    expect(balances[destination.id], 12500);
    await expectLater(
        repo.setEffective(item.id, effective: true), throwsStateError);
    await repo.changeEffectiveDate(item.id,
        expectedDate: today, effectiveDate: future);
    expect((await repo.list()).single.effectiveDate!.day, future.day);
    expect((await accounts.list()).every((a) => a.currentBalanceMinor == 10000),
        true);
    await repo.changeEffectiveDate(item.id, expectedDate: future);
    expect((await repo.list()).single.effectiveDate, isNull);
    await repo.setEffective(item.id, effective: true, effectiveDate: today);
    await repo.delete(item.id);
    await expectLater(repo.changeEffectiveDate(item.id, expectedDate: today),
        throwsStateError);
    expect((await accounts.list()).every((a) => a.currentBalanceMinor == 10000),
        true);
  });
}
