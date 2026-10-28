import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/domain/account_statement.dart';
import 'package:finapp/features/accounts/presentation/account_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const account = Account(
    id: 'a',
    name: 'Banco do Brasil — Investimentos',
    type: AccountType.investment,
    currencyCode: 'BRL',
    initialBalanceMinor: 0,
    currentBalanceMinor: -5000,
    projectedBalanceMinor: 15000,
    isArchived: false,
    includeInAnalytics: false,
    includeInBalance: false);

StatementSection section(int closing) => StatementSection(
        openingMinor: 10000,
        closingMinor: closing,
        dailyBalances: const [],
        days: [
          StatementDay(
              date: DateTime.utc(2026, 9, 10),
              closingMinor: closing,
              entries: [
                for (final (kind, amount) in [
                  (StatementKind.income, 5000),
                  (StatementKind.transferIn, 2000),
                  (StatementKind.transferOut, -3000),
                  (StatementKind.expense, -15000),
                  (StatementKind.cardPayment, -4000),
                ])
                  StatementEntry(
                      id: kind.name,
                      description: kind.name,
                      date: DateTime.utc(2026, 9, 10),
                      amountMinor: amount,
                      kind: kind,
                      effective: true),
              ])
        ]);

void main() {
  for (final (width, scale) in [(390.0, 1.0), (320.0, 1.8), (1000.0, 1.0)]) {
    testWidgets('card preserves ledger and actions at $width with text $scale',
        (tester) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var opened = 0, added = 0;
      String? action;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 1600), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: SingleChildScrollView(
                  child: RepaintBoundary(
            key: const ValueKey('preview'),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: AccountSummaryCard(
                  account: account,
                  statement: AccountStatement(
                      account: account,
                      month: DateTime(2026, 9),
                      realized: section(-5000),
                      projected: section(15000)),
                  onOpen: () => opened++,
                  onAdd: () => added++,
                  onAction: (value) => action = value,
                )),
          ))),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Saldo inicial do mês'), findsOneWidget);
      expect(find.textContaining('190,00'),
          findsOneWidget); // Expenses include invoice payments.
      expect(find.textContaining('R\$ -50,00'), findsOneWidget);
      expect(find.text('Fora das análises'), findsOneWidget);
      expect(find.text('Fora do saldo consolidado'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('account-add-a')));
      await tester.tap(find.byKey(const ValueKey('account-statement-a')));
      expect(added, 1);
      expect(opened, 1);
      await tester.tap(find.byKey(const ValueKey('account-menu-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(action, 'edit');
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW') && width == 390) {
        await expectLater(find.byKey(const ValueKey('preview')),
            matchesGoldenFile('accounts-card-mobile-preview.png'));
      }
    });
  }
}
