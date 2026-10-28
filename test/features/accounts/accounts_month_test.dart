import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/data/account_statement_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/domain/accounts_repository.dart';
import 'package:finapp/features/accounts/presentation/accounts_page.dart';
import 'package:finapp/features/balances/data/sqlite_balances_repository.dart';
import 'package:finapp/features/dashboard/data/sqlite_dashboard_repository.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contas por mês preservam aplicações fora do saldo consolidado',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = SqliteAccountsRepository(db);
    final bank = await repo.create(const AccountDraft(
        name: 'Corrente',
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 10000,
        includeInAnalytics: true));
    final investment = await repo.create(const AccountDraft(
        name: 'Aplicação',
        type: AccountType.investment,
        currencyCode: 'BRL',
        initialBalanceMinor: 50000,
        includeInAnalytics: true,
        includeInBalance: false));
    final transactions = SqliteTransactionsRepository(db);
    Future<void> add(TransactionType type, int amount, DateTime date,
        {bool effective = true}) async {
      await transactions.create(TransactionDraft(
          description: 'Teste',
          type: type,
          amountMinor: amount,
          date: date,
          isEffective: effective,
          accountId: bank.id));
    }

    await add(TransactionType.income, 5000, DateTime.utc(2026, 1, 10));
    await add(TransactionType.expense, 1000, DateTime.utc(2026, 2, 1));
    await add(TransactionType.expense, 700, DateTime.utc(2026, 1, 31),
        effective: false);
    await add(TransactionType.expense, 900, DateTime.utc(2026, 2, 1),
        effective: false);
    await SqliteTransfersRepository(db).create(TransferDraft(
        sourceAccountId: bank.id,
        destinationAccountId: investment.id,
        amountMinor: 2000,
        date: DateTime.utc(2026, 1, 15),
        isEffective: true));
    final january = await repo.list(
        asOf: DateTime.utc(2026, 1, 31), through: DateTime.utc(2026, 1, 31));
    final current = january.firstWhere((a) => a.id == bank.id);
    final applied = january.firstWhere((a) => a.id == investment.id);
    expect(current.currentBalanceMinor, 13000);
    expect(current.projectedBalanceMinor, 12300);
    expect(applied.currentBalanceMinor, 52000);
    expect(applied.includeInBalance, false);
    expect(applied.includeInAnalytics, true);
    final dashboard = SqliteDashboardRepository(db, asOf: DateTime.utc(2030));
    final summary = (await dashboard.load(DateTime(2026, 1))).currencies.single;
    expect(summary.currentBalanceMinor, 13000);
    expect(summary.projectedBalanceMinor, 12300);
    expect(summary.incomeMinor, 5000);
    expect(summary.expenseMinor, 700);
    expect(summary.accounts.length, 2);
    final february = await repo.list(
        asOf: DateTime.utc(2026, 2, 28), through: DateTime.utc(2026, 2, 28));
    expect(
        february.firstWhere((a) => a.id == bank.id).currentBalanceMinor, 12000);
    expect(february.firstWhere((a) => a.id == bank.id).projectedBalanceMinor,
        10400);
    await repo.update(
        investment.id,
        const AccountDraft(
            name: 'Aplicação',
            type: AccountType.investment,
            currencyCode: 'BRL',
            initialBalanceMinor: 50000,
            includeInAnalytics: true));
    expect(
        (await dashboard.load(DateTime(2026, 1)))
            .currencies
            .single
            .currentBalanceMinor,
        65000);
    await repo.update(
        bank.id,
        const AccountDraft(
            name: 'Corrente',
            type: AccountType.checking,
            currencyCode: 'BRL',
            initialBalanceMinor: 10000,
            includeInAnalytics: true,
            includeInBalance: false));
    await repo.update(
        investment.id,
        const AccountDraft(
            name: 'Aplicação',
            type: AccountType.investment,
            currencyCode: 'BRL',
            initialBalanceMinor: 50000,
            includeInAnalytics: true,
            includeInBalance: false));
    final balances = await SqliteBalancesRepository(db).calculate(
        asOf: DateTime.utc(2026, 1, 31), through: DateTime.utc(2026, 1, 31));
    expect(balances.accounts.length, 2);
    expect(balances.consolidated.single.currentMinor, 0);
    expect(balances.consolidated.single.projectedMinor, 0);
  });

  testWidgets(
      'Contas compartilha mês e menu alterna inclusão sem esconder conta',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final db = AppDatabase(NativeDatabase.memory());
    final repo = SqliteAccountsRepository(db);
    final account = await repo.create(const AccountDraft(
        name: 'Aplicação',
        type: AccountType.investment,
        currencyCode: 'BRL',
        initialBalanceMinor: 50000,
        includeInAnalytics: true));
    getIt.registerSingleton<AccountsRepository>(repo);
    getIt.registerSingleton<AccountStatementRepository>(
        AccountStatementRepository(db));
    referenceMonth.select(DateTime(2026, 1));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      referenceMonth.select(DateTime.now());
      await getIt.reset();
      await db.close();
    });
    await tester.pumpWidget(const MaterialApp(home: AccountsPage()));
    await tester.pumpAndSettle();
    expect(find.text('Janeiro 2026'), findsOneWidget);
    expect(find.text('Saldos no fim do mês'), findsNothing);
    expect(find.text('Saldo consolidado'), findsNothing);
    expect(find.text('Saldo inicial do mês'), findsOneWidget);
    expect(find.text('Receitas'), findsOneWidget);
    expect(find.text('Saldo atual'), findsOneWidget);
    expect(find.text('Saldo previsto'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('account-add-${account.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Transferência'), findsOneWidget);
    expect(find.text('Receita'), findsOneWidget);
    expect(find.text('Despesa'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Buscar contas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'inexistente');
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma conta encontrada.'), findsOneWidget);
    await tester.tap(find.byTooltip('Fechar busca'));
    await tester.pumpAndSettle();
    expect(find.text('Aplicação'), findsOneWidget);
    await tester.tap(find.byTooltip('Próximo mês'));
    await tester.pumpAndSettle();
    expect(referenceMonth.value, DateTime(2026, 2));
    expect(find.text('Fevereiro 2026'), findsOneWidget);
    await tester.tap(find.text('Fevereiro 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dezembro'));
    await tester.pumpAndSettle();
    expect(referenceMonth.value, DateTime(2026, 12));
    await tester.tap(find.byKey(ValueKey('account-menu-${account.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir do saldo do mês'));
    await tester.pumpAndSettle();
    expect((await repo.list()).single.includeInBalance, false);
    expect(find.text('Aplicação'), findsOneWidget);
    expect(find.textContaining('Fora do saldo consolidado'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('account-menu-${account.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Incluir no saldo do mês'));
    await tester.pumpAndSettle();
    expect((await repo.list()).single.includeInBalance, true);
    expect((await repo.list()).single.includeInAnalytics, true);
    expect(tester.takeException(), isNull);
  });
}
