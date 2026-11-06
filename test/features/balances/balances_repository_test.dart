import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/balances/data/sqlite_balances_repository.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('três datas controlam saldo realizado, projeção e ambas as contas',
      () async {
    // O reagendamento exige que as efetivações iniciais ainda estejam no futuro.
    final year = DateTime.now().year + 1;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final accounts = SqliteAccountsRepository(db);
    final a = await accounts.create(const AccountDraft(
        name: 'Origem',
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 10000,
        includeInAnalytics: true));
    final b = await accounts.create(const AccountDraft(
        name: 'Destino',
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 0,
        includeInAnalytics: true));
    final transactions = SqliteTransactionsRepository(db);
    final transfers = SqliteTransfersRepository(db);
    final expense = await transactions.create(TransactionDraft(
        description: 'Conta futura',
        type: TransactionType.expense,
        amountMinor: 2000,
        date: DateTime.utc(year, 9, 1),
        dueDate: DateTime.utc(year, 10, 10),
        effectiveDate: DateTime.utc(year, 11, 1),
        isEffective: true,
        accountId: a.id));
    final transfer = await transfers.create(TransferDraft(
        sourceAccountId: a.id,
        destinationAccountId: b.id,
        amountMinor: 1000,
        date: DateTime.utc(year, 9, 2),
        dueDate: DateTime.utc(year, 10, 15),
        effectiveDate: DateTime.utc(year, 11, 5),
        isEffective: true));
    await transactions.create(TransactionDraft(
        description: 'Outra pendência',
        type: TransactionType.expense,
        amountMinor: 500,
        date: DateTime.utc(year, 9, 3),
        dueDate: DateTime.utc(year, 10, 20),
        isEffective: false,
        accountId: a.id));

    final repo = SqliteBalancesRepository(db);
    final september = await repo.calculate(
        asOf: DateTime.utc(year, 9, 30), through: DateTime.utc(year, 9, 30));
    expect(
        september.accounts
            .firstWhere((x) => x.accountId == a.id)
            .projectedMinor,
        10000);
    final october = await repo.calculate(
        asOf: DateTime.utc(year, 10, 31), through: DateTime.utc(year, 10, 31));
    expect(october.accounts.firstWhere((x) => x.accountId == a.id).currentMinor,
        10000);
    expect(
        october.accounts.firstWhere((x) => x.accountId == a.id).projectedMinor,
        9500);
    expect(
        october.accounts.firstWhere((x) => x.accountId == b.id).projectedMinor,
        0);
    final november = await repo.calculate(
        asOf: DateTime.utc(year, 11, 30), through: DateTime.utc(year, 11, 30));
    expect(
        november.accounts.firstWhere((x) => x.accountId == a.id).currentMinor,
        7000);
    expect(
        november.accounts.firstWhere((x) => x.accountId == b.id).currentMinor,
        1000);
    expect(
        november.accounts.firstWhere((x) => x.accountId == a.id).projectedMinor,
        6500);

    // A opção "Contabilizar hoje" antecipa o corte; a outra mantém o prazo.
    await transactions.setEffective(expense.id,
        effective: true, effectiveDate: DateTime.utc(year, 9, 29));
    await transfers.setEffective(transfer.id,
        effective: true, effectiveDate: DateTime.utc(year, 10, 15));
    final updated = await repo.calculate(
        asOf: DateTime.utc(year, 9, 30), through: DateTime.utc(year, 9, 30));
    expect(updated.accounts.firstWhere((x) => x.accountId == a.id).currentMinor,
        8000);
    expect(updated.accounts.firstWhere((x) => x.accountId == b.id).currentMinor,
        0);
    final txByDue = await transactions.list(TransactionFilter(
        from: DateTime.utc(year, 10, 10), to: DateTime.utc(year, 10, 10)));
    expect(txByDue.single.id, expense.id);
    final txByPosted = await transactions.list(TransactionFilter(
        dateField: TransactionDateField.posted,
        from: DateTime.utc(year, 9, 1),
        to: DateTime.utc(year, 9, 1)));
    expect(txByPosted.single.id, expense.id);
  });

  test('saldo por conta e consolidado considera efetivos, pendentes e prazo',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final accounts = SqliteAccountsRepository(db);
    Future<Account> add(String name, String currency, int initial) =>
        accounts.create(AccountDraft(
            name: name,
            type: AccountType.checking,
            currencyCode: currency,
            initialBalanceMinor: initial,
            includeInAnalytics: true));
    final bank = await add('Banco', 'BRL', 10000);
    final cash = await add('Carteira', 'BRL', 2000);
    final dollar = await add('Dólar', 'USD', 500);
    final transactions = SqliteTransactionsRepository(db);
    final transfers = SqliteTransfersRepository(db);
    final today = DateTime.utc(2026, 9, 29);
    final future = DateTime.utc(2026, 10, 15);
    TransactionDraft draft(String account, TransactionType type, int amount,
            DateTime date, bool effective) =>
        TransactionDraft(
            description: 'Movimento',
            type: type,
            amountMinor: amount,
            date: date,
            isEffective: effective,
            accountId: account);

    await transactions
        .create(draft(bank.id, TransactionType.income, 4000, today, true));
    final expense = await transactions
        .create(draft(bank.id, TransactionType.expense, 1000, today, true));
    await transactions
        .create(draft(bank.id, TransactionType.expense, 1500, future, false));
    await transactions
        .create(draft(cash.id, TransactionType.income, 300, today, false));
    final paidTransfer = await transfers.create(TransferDraft(
        sourceAccountId: bank.id,
        destinationAccountId: cash.id,
        amountMinor: 2000,
        date: today,
        isEffective: true));
    await transfers.create(TransferDraft(
        sourceAccountId: cash.id,
        destinationAccountId: bank.id,
        amountMinor: 500,
        date: future,
        isEffective: false));

    final repo = SqliteBalancesRepository(db);
    final todaySnapshot = await repo.calculate(through: today);
    final todayById = {for (final a in todaySnapshot.accounts) a.accountId: a};
    expect(todayById[bank.id]!.currentMinor, 11000);
    expect(todayById[bank.id]!.projectedMinor, 11000);
    expect(todayById[cash.id]!.currentMinor, 4000);
    expect(todayById[cash.id]!.projectedMinor, 4300);
    expect(
        todaySnapshot.consolidated
            .singleWhere((a) => a.currencyCode == 'BRL')
            .currentMinor,
        15000);

    final all = await repo.calculate();
    final byId = {for (final a in all.accounts) a.accountId: a};
    expect(byId[bank.id]!.projectedMinor, 10000);
    expect(byId[cash.id]!.projectedMinor, 3800);
    expect(
        all.consolidated
            .singleWhere((a) => a.currencyCode == 'BRL')
            .projectedMinor,
        13800);
    expect(
        all.consolidated
            .singleWhere((a) => a.currencyCode == 'USD')
            .projectedMinor,
        500);
    expect(byId[dollar.id]!.currentMinor, 500);
    expect(
        (await accounts.list())
            .firstWhere((a) => a.id == bank.id)
            .projectedBalanceMinor,
        10000);

    // A flag de saldo independe da flag de análises.
    await db.customStatement(
        'UPDATE transactions SET ignore_balance = 1 WHERE id = ?',
        [expense.id]);
    expect(
        (await repo.calculate())
            .consolidated
            .singleWhere((a) => a.currencyCode == 'BRL')
            .currentMinor,
        16000);
    await transfers.delete(paidTransfer.id);
    final afterDelete = await repo.calculate();
    expect(
        afterDelete.accounts
            .firstWhere((a) => a.accountId == bank.id)
            .currentMinor,
        14000);
    expect(
        afterDelete.consolidated
            .singleWhere((a) => a.currencyCode == 'BRL')
            .currentMinor,
        16000);
    await accounts.setArchived(cash.id, archived: true);
    expect(
        (await repo.calculate())
            .consolidated
            .singleWhere((a) => a.currencyCode == 'BRL')
            .currentMinor,
        16000);
    expect(
        (await db
                .customSelect('SELECT COUNT(*) AS count FROM transactions')
                .getSingle())
            .read<int>('count'),
        4);
  });

  test('liquidação posterior pertence ao mês agendado na projeção', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final accounts = SqliteAccountsRepository(db);
    Future<Account> add(String name, int initial) =>
        accounts.create(AccountDraft(
            name: name,
            type: AccountType.cash,
            currencyCode: 'BRL',
            initialBalanceMinor: initial,
            includeInAnalytics: true));
    final source = await add('Origem', 10000);
    final destination = await add('Destino', 0);
    final october = DateTime.utc(2026, 10, 10);
    final december = DateTime.utc(2026, 12, 5);
    final expense = await SqliteTransactionsRepository(db).create(
        TransactionDraft(
            description: 'Compra',
            type: TransactionType.expense,
            amountMinor: 2000,
            date: october,
            isEffective: true,
            accountId: source.id));
    final transfer = await SqliteTransfersRepository(db).create(TransferDraft(
        sourceAccountId: source.id,
        destinationAccountId: destination.id,
        amountMinor: 1000,
        date: october,
        isEffective: true));
    await db.customStatement(
        'UPDATE transactions SET effective_at = ? WHERE id = ?',
        [december.millisecondsSinceEpoch, expense.id]);
    await db.customStatement(
        'UPDATE transfers SET effective_at = ? WHERE id = ?',
        [december.millisecondsSinceEpoch, transfer.id]);

    final snapshot = await SqliteBalancesRepository(db).calculate(
        asOf: DateTime.utc(2026, 10, 31), through: DateTime.utc(2026, 10, 31));
    final byId = {
      for (final account in snapshot.accounts) account.accountId: account
    };
    expect(byId[source.id]!.currentMinor, 10000);
    expect(byId[source.id]!.projectedMinor, 10000);
    expect(byId[destination.id]!.currentMinor, 0);
    expect(byId[destination.id]!.projectedMinor, 0);
    expect(snapshot.consolidated.single.projectedMinor, 10000);
  });
}
