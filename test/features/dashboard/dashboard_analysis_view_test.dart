import 'dart:io';
import 'package:flutter/services.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/dashboard/domain/dashboard_repository.dart';
import 'package:finapp/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:finapp/features/dashboard/presentation/dashboard_cubit.dart';
import 'package:finapp/features/dashboard/presentation/widgets/dashboard_analysis_view.dart';
import 'package:finapp/features/dashboard/presentation/widgets/dashboard_category_chart.dart';
import 'package:finapp/features/dashboard/presentation/widgets/desktop_history_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class Repository implements DashboardRepository {
  int calls = 0;
  @override
  Future<DashboardSummary> load(DateTime month) async {
    calls++;
    return DashboardSummary(
        month: month, currencies: const [], recent: const []);
  }
}

void main() {
  final fixture = DashboardCurrencySummary(
    currencyCode: 'BRL',
    currentBalanceMinor: 100000,
    projectedBalanceMinor: 120000,
    incomeMinor: 50000,
    expenseMinor: 20000,
    realizedIncomeMinor: 30000,
    realizedExpenseMinor: 5000,
    expensesByCategory: const [DashboardCategoryExpense('Casa', 20000)],
    realizedExpensesByCategory: const [DashboardCategoryExpense('Casa', 5000)],
    history: [
      DashboardMonthTotal(DateTime(2026, 11), 50000, 20000,
          realizedIncomeMinor: 30000, realizedExpenseMinor: 5000)
    ],
  );
  for (final width in [320.0, 1200.0]) {
    testWidgets('seleção compartilhada, mês e consultas preservados $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = Repository();
      final cubit = DashboardCubit(repository);
      addTearDown(cubit.close);
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: BlocProvider.value(
                value: cubit,
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (final name in ['categories', 'history'])
                      DashboardAnalysisView(
                          key: ValueKey(name),
                          currency: fixture,
                          builder: (view) => Text(
                              '$name: ${view.incomeMinor}/${view.expenseMinor}')),
                  ]),
                )),
          )));
      await tester.pumpAndSettle();
      expect(find.text('categories: 50000/20000'), findsOneWidget);
      await tester.tap(find.text('Realizado').first);
      await tester.pumpAndSettle();
      expect(find.text('categories: 30000/5000'), findsOneWidget);
      expect(find.text('history: 30000/5000'), findsOneWidget);
      expect(repository.calls, 1);
      await cubit.load(DateTime(2026, 12));
      await tester.pumpAndSettle();
      expect(cubit.state.analysisMode, DashboardAnalysisMode.realized);
      await tester.tap(find.text('Ambos').first);
      await tester.pumpAndSettle();
      expect(find.text('categories: 50000/20000'), findsOneWidget);
      expect(find.text('categories: 30000/5000'), findsOneWidget);
      expect(find.text('history: 50000/20000'), findsOneWidget);
      expect(find.text('history: 30000/5000'), findsOneWidget);
      expect(
          fixture
              .forAnalysis(realized: true, compare: true)
              .historyAxisMaximumMinor,
          50000);
      expect(
          fixture
              .forAnalysis(realized: false, compare: true)
              .historyAxisMaximumMinor,
          50000);
      expect(fixture.currentBalanceMinor, 100000);
      expect(fixture.projectedBalanceMinor, 120000);
      expect(repository.calls, 2);
      expect(tester.takeException(), isNull);
    });
  }

  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    for (final size in [const Size(390, 1000), const Size(1200, 1000)]) {
      testWidgets('prévia da comparação $size', (tester) async {
        final fonts = Directory(
            '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts');
        final font = FontLoader('Roboto'), icons = FontLoader('MaterialIcons');
        for (final file in fonts.listSync().whereType<File>()) {
          if (file.path.endsWith('Roboto-Regular.ttf') ||
              file.path.endsWith('Roboto-Bold.ttf')) {
            font.addFont(
                Future.value(ByteData.sublistView(file.readAsBytesSync())));
          }
          if (file.path.endsWith('MaterialIcons-Regular.otf')) {
            icons.addFont(
                Future.value(ByteData.sublistView(file.readAsBytesSync())));
          }
        }
        await font.load();
        await icons.load();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final cubit = DashboardCubit(Repository());
        addTearDown(cubit.close);
        await cubit.load();
        cubit.selectAnalysisMode(DashboardAnalysisMode.both);
        await tester.pumpWidget(MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: RepaintBoundary(
                  key: const ValueKey('preview'),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: BlocProvider.value(
                        value: cubit,
                        child: DashboardAnalysisView(
                          currency: fixture,
                          builder: (view) => Column(children: [
                            DashboardCategoryChart(currency: view),
                            DesktopHistoryChart(currency: view),
                          ]),
                        )),
                  )),
            )));
        await tester.pumpAndSettle();
        await expectLater(
            find.byKey(const ValueKey('preview')),
            matchesGoldenFile(size.width < 800
                ? 'analysis-mobile-preview.png'
                : 'analysis-desktop-preview.png'));
      });
    }
  }
}
