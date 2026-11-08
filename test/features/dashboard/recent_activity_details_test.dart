import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/dashboard/domain/dashboard_repository.dart';
import 'package:finapp/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:finapp/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:finapp/features/dashboard/presentation/widgets/recent_activity_details.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transactions/domain/transactions_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:finapp/features/transfers/domain/transfers_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

DashboardActivity activity(DashboardActivityType type, {String? cardId}) =>
    DashboardActivity(
      id: 'selected',
      type: type,
      description: 'Registro antigo',
      accountLabel: 'Conta antiga',
      currencyCode: 'BRL',
      amountMinor: 100,
      date: DateTime(2026, 9, 10),
      isEffective: false,
      cardId: cardId,
    );

class _Transactions extends Fake implements TransactionsRepository {
  bool fail = false;
  List<FinancialTransaction> items = [];
  @override
  Future<List<FinancialTransaction>> list([TransactionFilter? filter]) async {
    expect(
      filter,
      isNull,
    ); // A different selected month must not hide the item.
    if (fail) throw StateError('read failed');
    return items;
  }
}

class _Transfers extends Fake implements TransfersRepository {
  @override
  Future<List<Transfer>> list({String? accountId}) async => [
        Transfer(
          id: 'selected',
          description: 'Reserva atualizada',
          sourceAccountId: 'a',
          sourceAccountName: 'Banco',
          destinationAccountId: 'b',
          destinationAccountName: 'Reserva',
          currencyCode: 'BRL',
          amountMinor: 25000,
          date: DateTime(2026, 9, 10),
          isEffective: false,
        ),
      ];
}

class _Cards extends Fake implements CardsRepository {
  @override
  Future<List<CreditCard>> list() async => [
        const CreditCard(
          id: 'card',
          name: 'Cartão atual',
          paymentAccountId: 'a',
          closingDay: 25,
          dueDay: 5,
        ),
      ];
  @override
  Future<List<CardEntry>> entries({String? cardId, String? invoiceId}) async {
    expect(cardId, 'card');
    return [
      CardEntry(
        id: 'selected',
        cardId: 'card',
        invoiceId: 'invoice',
        purchaseId: 'purchase',
        index: 0,
        count: 2,
        description: 'Compra atualizada',
        kind: 'purchase',
        amountMinor: 3500,
        postedAt: DateTime(2026, 9, 10),
        dueAt: DateTime(2026, 10, 5),
        invoiceMonth: DateTime(2026, 10),
      ),
    ];
  }
}

class _Dashboard extends Fake implements DashboardRepository {
  _Dashboard(this.item);
  final DashboardActivity item;
  @override
  Future<DashboardSummary> load(DateTime month) async =>
      DashboardSummary(month: month, currencies: const [], recent: [item]);
}

void main() {
  late _Transactions transactions;
  setUp(() async {
    await getIt.reset();
    referenceMonth.select(DateTime(2026, 11));
    transactions = _Transactions();
    getIt.registerSingleton<TransactionsRepository>(transactions);
    getIt.registerSingleton<TransfersRepository>(_Transfers());
    getIt.registerSingleton<CardsRepository>(_Cards());
    transactions.items = [
      FinancialTransaction(
        id: 'selected',
        description: 'Registro atualizado',
        type: TransactionType.income,
        amountMinor: 12345,
        date: DateTime(2026, 9, 10),
        effectiveDate: DateTime(2026, 9, 12),
        isEffective: true,
        accountId: 'a',
        accountName: 'Banco atual',
        categoryId: null,
        categoryName: 'Salário',
        currencyCode: 'BRL',
      ),
    ];
  });
  tearDown(() async {
    await getIt.reset();
    referenceMonth.select(DateTime.now());
  });

  Future<void> mount(WidgetTester tester, DashboardActivity item) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: RecentActivityDetails(activity: item)),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 1200.0]) {
    testWidgets('recentes $width abrem o registro atual sem mudar o mês', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      getIt.registerSingleton<DashboardRepository>(
        _Dashboard(activity(DashboardActivityType.income)),
      );
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const DashboardPage()),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Registro antigo'));
      await tester.tap(find.text('Registro antigo'));
      await tester.pumpAndSettle();
      expect(find.text('Detalhes do lançamento'), findsOneWidget);
      expect(find.text('Registro atualizado'), findsOneWidget);
      expect(find.text('R\$ 123,45'), findsOneWidget);
      expect(find.text('Banco atual'), findsOneWidget);
      expect(find.text('Efetivação: 12/09/2026'), findsOneWidget);
      expect(referenceMonth.value, DateTime(2026, 11));
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.byType(RecentActivityDetails), findsNothing);
      expect(referenceMonth.value, DateTime(2026, 11));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('registro removido não abre outro lançamento', (tester) async {
    transactions.items = [];
    await mount(tester, activity(DashboardActivityType.expense));
    expect(find.textContaining('não está mais disponível'), findsOneWidget);
    expect(find.text('R\$ 1,00'), findsNothing);
    expect(find.text('Ver despesas'), findsNothing);
  });

  testWidgets('erro de leitura permite tentar novamente', (tester) async {
    transactions.fail = true;
    await mount(tester, activity(DashboardActivityType.income));
    expect(
      find.text('Não foi possível carregar este lançamento.'),
      findsOneWidget,
    );
    transactions.fail = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Registro atualizado'), findsOneWidget);
  });

  testWidgets('transferência mostra origem e destino sem alterar mês', (
    tester,
  ) async {
    await mount(tester, activity(DashboardActivityType.transfer));
    expect(find.text('Reserva atualizada'), findsOneWidget);
    expect(find.text('Banco → Reserva'), findsOneWidget);
    expect(find.text('R\$ 250,00'), findsOneWidget);
    expect(referenceMonth.value, DateTime(2026, 11));
  });

  testWidgets('compra abre extrato do cartão e mês da fatura corretos', (
    tester,
  ) async {
    Uri? destination;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRecentActivityDetails(
                  context,
                  activity(DashboardActivityType.expense, cardId: 'card'),
                ),
                child: const Text('Abrir recente'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/cards',
          builder: (context, state) {
            destination = state.uri;
            return const Scaffold(body: Text('Extrato correto'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Abrir recente'));
    await tester.pumpAndSettle();
    expect(find.text('Compra atualizada'), findsOneWidget);
    expect(find.text('Cartão atual'), findsOneWidget);
    expect(find.text('Compra no cartão · Parcela 1/2'), findsOneWidget);
    expect(find.text('Vencimento da fatura: 05/10/2026'), findsOneWidget);
    expect(find.text('Efetivado'), findsNothing);
    await tester.tap(find.text('Ver extrato do cartão'));
    await tester.pumpAndSettle();
    expect(destination?.queryParameters['card'], 'card');
    expect(destination?.queryParameters['view'], 'statement');
    expect(
      DateTime.parse(destination!.queryParameters['month']!),
      DateTime(2026, 10),
    );
    expect(find.byType(RecentActivityDetails), findsNothing);
  });
}
