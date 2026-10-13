import 'package:flutter/material.dart';
import 'package:finapp/app/app.dart';
import 'package:finapp/core/widgets/somia_brand.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/features/dashboard/domain/dashboard_repository.dart';
import 'package:finapp/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:flutter_test/flutter_test.dart';

class _DashboardStub implements DashboardRepository {
  _DashboardStub({this.withDetails = false});
  final bool withDetails;

  @override
  Future<DashboardSummary> load(DateTime month) async => DashboardSummary(
        month: month,
        currencies: [
          DashboardCurrencySummary(
              currencyCode: 'BRL',
              currentBalanceMinor: 12000,
              projectedBalanceMinor: 13000,
              incomeMinor: 4000,
              expenseMinor: 2000,
              expensesByCategory: withDetails
                  ? const [
                      DashboardCategoryExpense(
                          'Uma categoria com nome bastante longo', 2000),
                    ]
                  : const [])
        ],
        recent: withDetails
            ? [
                DashboardActivity(
                  id: 'long',
                  type: DashboardActivityType.expense,
                  description:
                      'Lançamento de mercado com uma descrição muito extensa',
                  accountLabel: 'Conta corrente com nome longo',
                  currencyCode: 'BRL',
                  amountMinor: 2000,
                  date: month,
                  isEffective: true,
                )
              ]
            : const [],
      );
}

void main() {
  testWidgets('exibe o resumo financeiro na tela inicial', (tester) async {
    getIt.registerSingleton<DashboardRepository>(_DashboardStub());
    addTearDown(getIt.reset);
    await tester.pumpWidget(const FinApp());
    await tester.pumpAndSettle();

    expect(find.byType(SomiaBrand), findsWidgets);
    expect(find.text('Saldo atual'), findsOneWidget);
    expect(find.text('R\$ 120,00'), findsOneWidget);
    expect(find.textContaining('Resultado do mês:'), findsOneWidget);
    expect(find.textContaining('R\$ 20,00'), findsWidgets);
    expect(find.text('Receitas'), findsWidgets);
    expect(
        tester.getTopLeft(find.text('Saldo atual')).dy,
        lessThan(
            tester.getTopLeft(find.textContaining('Resultado do mês:')).dy));

    await tester.tap(find.byTooltip('Próximo mês'));
    await tester.pumpAndSettle();
    expect(find.text('Saldo previsto'), findsOneWidget);
    expect(find.text('R\$ 130,00'), findsWidgets);

    expect(find.text('Saldo atual'), findsNothing);

    await tester.tap(find.byTooltip('Mês anterior'));
    await tester.pumpAndSettle();
    expect(find.text('Saldo atual'), findsOneWidget);
    expect(find.text('R\$ 120,00'), findsOneWidget);
  });

  testWidgets('resumo permanece legível em tela estreita com texto ampliado',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await getIt.reset();
    });
    getIt.registerSingleton<DashboardRepository>(
        _DashboardStub(withDetails: true));
    await tester.pumpWidget(const FinApp());
    await tester.pumpAndSettle();

    expect(find.text('Saldo atual'), findsOneWidget);
    expect(find.text('Gastos por categoria'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('mobile-recent')), 250,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('dashboard-mobile-scroll')),
            matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
    expect(find.text('Lançamento de mercado com uma descrição muito extensa'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
