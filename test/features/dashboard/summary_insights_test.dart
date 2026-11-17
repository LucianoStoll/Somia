import 'package:finapp/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:finapp/features/dashboard/presentation/widgets/summary_insights.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compromissos respeitam datas, tipo e fim do período',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    DashboardDue due(String id, int day, String kind) => DashboardDue(
        id: id,
        description: id,
        date: DateTime(2026, 11, day),
        amountMinor: 10000,
        kind: kind);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SummaryInsights(
      month: DateTime(2026, 11),
      referenceDate: DateTime(2026, 11, 10),
      currency: DashboardCurrencySummary(
          currencyCode: 'BRL',
          currentBalanceMinor: 0,
          projectedBalanceMinor: 0,
          incomeMinor: 0,
          expenseMinor: 0,
          upcoming: [
            due('atraso', 9, 'expense'),
            due('hoje', 10, 'expense'),
            due('limite', 17, 'invoice'),
            due('depois', 18, 'expense'),
            due('receita', 9, 'income'),
            due('outro-mes', 31, 'expense')
          ],
          expensesByCategory: const [
            DashboardCategoryExpense('Menor', 10000),
            DashboardCategoryExpense('Maior', 30000)
          ]),
    )))));
    expect(find.text('Vencidas · 1'), findsOneWidget);
    expect(find.text('Hoje e próximos 7 dias · 2'), findsOneWidget);
    expect(find.text('Mais adiante · 1'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Maior')).dy,
        lessThan(tester.getTopLeft(find.text('Menor')).dy));
    expect(find.textContaining('75,0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
