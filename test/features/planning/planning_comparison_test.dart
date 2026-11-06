import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/planning/domain/planning.dart';
import 'package:finapp/features/planning/presentation/planning_comparison_panel.dart';

void main() {
  PlanningCategoryComparison compare(
          List<MonthlySpend> now, List<MonthlySpend> before) =>
      PlanningCategoryComparison.fromSpending(
          current: now,
          previous: before,
          categoryId: 'p',
          currency: 'BRL',
          type: 'expense');
  test('compara valores líquidos e ordena contribuições sem duplicar filhas',
      () {
    final c = compare(const [
      MonthlySpend('a', 'p', 'BRL', 'expense', 0, 18000),
      MonthlySpend('a', 'p', 'BRL', 'expense', 0, -1000),
      MonthlySpend('b', 'p', 'BRL', 'expense', 0, 9000),
      MonthlySpend('p', null, 'BRL', 'expense', 0, 1000),
      MonthlySpend('x', null, 'BRL', 'expense', 0, 999999),
      MonthlySpend('a', 'p', 'USD', 'expense', 0, 999999),
      MonthlySpend('a', 'p', 'BRL', 'income', 0, 999999),
    ], const [
      MonthlySpend('a', 'p', 'BRL', 'expense', 0, 10000),
      MonthlySpend('b', 'p', 'BRL', 'expense', 0, 11000),
      MonthlySpend('old', 'p', 'BRL', 'expense', 0, 4000),
    ]);
    expect(c.total.current, 27000);
    expect(c.total.previous, 25000);
    expect(c.total.difference, 2000);
    expect(c.total.percent, 8);
    expect(c.changes.map((v) => v.categoryId), ['a', 'old', 'b', 'p']);
    expect(c.changes.fold<int>(0, (sum, v) => sum + v.difference), 2000);
    expect(c.changes[1].current, 0);
  });
  test('base zero ou negativa não produz percentual enganoso', () {
    expect(const PlanningCategoryChange('p', 1000, 0).percent, isNull);
    expect(const PlanningCategoryChange('p', 1000, -1000).percent, isNull);
    expect(const PlanningCategoryChange('p', 1000, 2000).percent, -50);
    expect(const PlanningCategoryChange('p', 2000, 2000).percent, 0);
  });
  testWidgets('janeiro compara com dezembro do ano anterior', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
            body: SingleChildScrollView(
                child: PlanningComparisonPanel(
                    month: DateTime(2027, 1),
                    currency: 'BRL',
                    type: 'expense',
                    categoryId: 'p',
                    current: const [
              MonthlySpend('a', 'p', 'BRL', 'expense', 0, 12500)
            ],
                    previous: const [
              MonthlySpend('a', 'p', 'BRL', 'expense', 0, 10000)
            ],
                    categories: const [])))));
    await tester.pumpAndSettle();
    expect(find.text('Janeiro 2027'), findsOneWidget);
    expect(find.text('Dezembro 2026'), findsOneWidget);
    expect(find.text('+25,0% em relação ao mês anterior'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('planning-contribution-a')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
