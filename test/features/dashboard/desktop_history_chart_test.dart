import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:finapp/features/dashboard/presentation/widgets/desktop_history_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('escala cobre zero, centavos e valores grandes com intervalos inteiros',
      () {
    for (final maximum in [
      0,
      1,
      3,
      9,
      99,
      100,
      12500,
      99999999,
      9000000000000000
    ]) {
      final step = historyAxisStep(maximum);
      expect(step, greaterThan(0));
      expect(step * 4, greaterThanOrEqualTo(maximum));
      expect(
          {for (var i = 0; i < 5; i++) historyAxisLabel(i * step)}.length, 5);
    }
    expect(historyAxisLabel(1), '0,01');
    expect(historyAxisLabel(100000), '1 mil');
    expect(historyAxisLabel(100000000), '1 mi');
  });
  for (final config in [
    (600.0, 1.0, 12500),
    (240.0, 2.0, 1),
    (360.0, 2.0, 99999999),
    (400.0, 1.0, 0)
  ]) {
    testWidgets('escala/barras alinhadas e sem overflow $config',
        (tester) async {
      final data = DashboardCurrencySummary(
          currencyCode: 'USD',
          currentBalanceMinor: 0,
          projectedBalanceMinor: 0,
          incomeMinor: 0,
          expenseMinor: 0,
          history: [
            for (var i = 0; i < 6; i++)
              DashboardMonthTotal(DateTime(2026, i + 1), i == 0 ? 0 : config.$3,
                  i == 0 ? 0 : config.$3 ~/ 2)
          ]);
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: config.$1,
                      child: MediaQuery(
                          data: MediaQueryData(
                              textScaler: TextScaler.linear(config.$2)),
                          child: DesktopHistoryChart(currency: data)))))));
      await tester.pumpAndSettle();
      expect(find.text('USD'), findsOneWidget);
      final step = historyAxisStep(config.$3);
      for (var i = 0; i < 5; i++) {
        final axis =
            tester.getRect(find.byKey(ValueKey('history-axis-${step * i}')));
        final grid =
            tester.getRect(find.byKey(ValueKey('history-grid-${step * i}')));
        expect(axis.center.dy, closeTo(grid.top, 0.01));
      }
      final bottom =
          tester.getRect(find.byKey(const ValueKey('history-grid-0'))).top;
      final top =
          tester.getRect(find.byKey(ValueKey('history-grid-${step * 4}'))).top;
      expect(
          tester
              .getSize(find.byKey(const ValueKey('history-bar-income-1')))
              .height,
          0);
      final bar =
          tester.getRect(find.byKey(const ValueKey('history-bar-income-2')));
      expect(bar.bottom, closeTo(bottom, 0.01));
      expect(
          bar.height, closeTo((bottom - top) * config.$3 / (step * 4), 0.01));
      expect(tester.takeException(), isNull);
    });
  }
}
