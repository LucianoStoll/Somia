import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/planning/domain/planning.dart';
import 'package:finapp/features/planning/presentation/planning_indicators.dart';

void main() {
  const rows = [
    MonthlySpend('salary', null, 'BRL', 'income', 10000, 20000),
    MonthlySpend('food', null, 'BRL', 'expense', 7000, 12000),
    MonthlySpend('refund', null, 'BRL', 'expense', -1000, -2000),
    MonthlySpend(null, null, 'USD', 'income', 99999, 99999),
    MonthlySpend(null, null, 'BRL', 'transfer', 99999, 99999),
  ];
  test('separa moeda, realizado e previsto com despesas líquidas', () {
    final actual = PlanningMonthIndicators.fromSpending(rows,
        currency: 'BRL', projected: false);
    final forecast = PlanningMonthIndicators.fromSpending(rows,
        currency: 'BRL', projected: true);
    expect(actual.income, 10000);
    expect(actual.expense, 6000);
    expect(actual.result, 4000);
    expect(actual.savingRate, 40);
    expect(forecast.result, 10000);
    expect(forecast.savingRate, 50);
  });
  test('sem renda positiva não inventa taxa; déficit não é limitado a zero',
      () {
    expect(const PlanningMonthIndicators(0, 5000).savingRate, isNull);
    expect(const PlanningMonthIndicators(-100, 0).savingRate, isNull);
    expect(const PlanningMonthIndicators(1000, 2500).savingRate, -150);
    final empty = PlanningMonthIndicators.fromSpending(rows,
        currency: 'EUR', projected: true);
    expect(empty.result, 0);
    expect(empty.savingRate, isNull);
  });

  Future<void> open(WidgetTester tester,
      {String currency = 'BRL',
      List<MonthlySpend> spending = rows,
      int month = 10,
      double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
            body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: SingleChildScrollView(
                    child: PlanningIndicators(
                        month: DateTime(2026, month),
                        currency: currency,
                        spending: spending))))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'alternância recalcula e atualização de mês/moeda usa novos dados',
      (tester) async {
    await open(tester);
    expect(find.text('40,0%'), findsOneWidget);
    await tester.tap(find.text('Previsto'));
    await tester.pumpAndSettle();
    expect(find.text('50,0%'), findsOneWidget);
    await open(tester, month: 11, currency: 'USD', spending: const [
      MonthlySpend(null, null, 'USD', 'income', 0, 10000),
      MonthlySpend(null, null, 'USD', 'expense', 0, 25000),
    ]);
    expect(find.text('Novembro 2026 · USD'), findsOneWidget);
    expect(find.text('-150,0%'), findsOneWidget);
    expect(find.text('Despesas previstas acima das receitas.'), findsOneWidget);
    expect(find.text('50,0%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('estado vazio e ajuda em tela estreita com texto ampliado',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, spending: const [], scale: 1.5);
    expect(
        find.text('Sem movimentos nesta moeda e neste mês.'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    await tester.tap(find.byTooltip('Como os indicadores são calculados'));
    await tester.pumpAndSettle();
    expect(find.text('Sobre os indicadores'), findsOneWidget);
    await tester.tap(find.text('Entendi'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
