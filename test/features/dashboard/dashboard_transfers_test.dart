import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/dashboard/data/sqlite_dashboard_repository.dart';
import 'package:finapp/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:finapp/features/dashboard/presentation/widgets/dashboard_transfers_card.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';

void main() {
  test('card mensal conta uma vez, separa moedas, situação e data de atividade',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final accounts = SqliteAccountsRepository(db);
    final transfers = SqliteTransfersRepository(db);
    Future<Account> account(String name, String code) =>
        accounts.create(AccountDraft(
            name: name,
            type: AccountType.checking,
            currencyCode: code,
            initialBalanceMinor: 0,
            includeInBalance: code != 'USD',
            includeInAnalytics: true));
    final a = await account('A', 'BRL'), b = await account('B', 'BRL');
    Future<Transfer> move(int amount, DateTime due, [DateTime? effective]) =>
        transfers.create(TransferDraft(
            sourceAccountId: a.id,
            destinationAccountId: b.id,
            amountMinor: amount,
            date: due,
            dueDate: due,
            effectiveDate: effective,
            isEffective: effective != null));
    await move(9000, DateTime(2026, 1, 3), DateTime(2025, 12, 31));
    await move(10000, DateTime(2025, 12, 30), DateTime(2026, 1, 12));
    await move(3000, DateTime(2026, 1, 20), DateTime(2026, 1, 20));
    await move(2000, DateTime(2026, 1, 25));
    await move(5000, DateTime(2026, 2, 5));
    final deleted = await move(99999, DateTime(2026, 1, 8));
    await transfers.delete(deleted.id);
    final u = await account('U', 'USD'), v = await account('V', 'USD');
    await transfers.create(TransferDraft(
        sourceAccountId: u.id,
        destinationAccountId: v.id,
        amountMinor: 700,
        date: DateTime(2026, 1, 9),
        isEffective: false));
    final repo = SqliteDashboardRepository(db, asOf: DateTime(2026, 1, 15));
    final january = await repo.load(DateTime(2026, 1));
    final brl = january.currencies.singleWhere((c) => c.currencyCode == 'BRL');
    expect(brl.transferCount, 3);
    expect(brl.transferredMinor, 10000);
    expect(brl.pendingTransferMinor, 5000);
    expect(brl.incomeMinor, 0);
    expect(brl.expenseMinor, 0);
    expect(brl.currentBalanceMinor, 0);
    expect(brl.projectedBalanceMinor, 0);
    final usd = january.currencies.singleWhere((c) => c.currencyCode == 'USD');
    expect(usd.transferCount, 1);
    expect(usd.pendingTransferMinor, 700);
    final february = await repo.load(DateTime(2026, 2));
    final next =
        february.currencies.singleWhere((c) => c.currencyCode == 'BRL');
    expect(next.transferCount, 1);
    expect(next.pendingTransferMinor, 5000);
  });

  for (final create in [false, true]) {
    testWidgets(
        'atalho mantém mês e abre ${create ? 'cadastro' : 'transferências'}',
        (tester) async {
      final month = DateTime(2026, 11);
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
                body: SingleChildScrollView(
                    child: DashboardTransfersCard(
                        month: month,
                        currency: const DashboardCurrencySummary(
                            currencyCode: 'BRL',
                            currentBalanceMinor: 0,
                            projectedBalanceMinor: 0,
                            incomeMinor: 0,
                            expenseMinor: 0))))),
        GoRoute(
            path: '/transfers',
            builder: (_, state) =>
                Scaffold(body: Text('Destino: ${state.uri}'))),
      ]);
      addTearDown(router.dispose);
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!)));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma transferência neste mês.'), findsOneWidget);
      await tester.tap(create
          ? find.byTooltip('Nova transferência')
          : find.text('Ver transferências'));
      await tester.pumpAndSettle();
      expect(find.text('Destino: /transfers${create ? '?create=1' : ''}'),
          findsOneWidget);
      expect(referenceMonth.value, month);
      expect(tester.takeException(), isNull);
    });
  }
}
