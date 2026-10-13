import 'dart:io';

import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/core/routing/somia_shell.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/dashboard/domain/dashboard_repository.dart';
import 'package:finapp/features/balances/domain/balance_details.dart';
import 'package:finapp/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:finapp/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _DashboardStub implements DashboardRepository {
  _DashboardStub({this.emptyCategories = false});
  final bool emptyCategories;
  final requestedMonths = <DateTime>[];

  @override
  Future<DashboardSummary> load(DateTime month) async {
    requestedMonths.add(month);
    return DashboardSummary(month: month, currencies: [
      DashboardCurrencySummary(
        currencyCode: 'BRL',
        balanceDetails: const BalanceDetails(
            openingMinor: 100000,
            incomeMinor: 420000,
            expenseMinor: 200000,
            cardPaymentsMinor: 85000,
            pendingIncomeMinor: 100000,
            pendingExpenseMinor: 45000),
        currentBalanceMinor: 235000,
        projectedBalanceMinor: 290000,
        incomeMinor: 620000,
        expenseMinor: 385000,
        expensesByCategory: emptyCategories
            ? const []
            : const [
                DashboardCategoryExpense('Moradia', 200000),
                DashboardCategoryExpense('Alimentação', 185000),
              ],
        dailyBalances: [
          for (var day = 1; day <= 30; day++)
            DashboardDailyBalance(DateTime(month.year, month.month, day),
                205000 + day * 1000, 245000 + day * 1500)
        ],
        upcoming: [
          DashboardDue(
              id: 'due',
              description: 'Conta de energia',
              date: DateTime(month.year, month.month, 20),
              amountMinor: 12500,
              kind: 'expense')
        ],
        accounts: const [
          DashboardAccountBalance(
              'Conta principal', 'Conta corrente', 'BRL', 235000,
              institutionId: 'banco-do-brasil'),
          DashboardAccountBalance('Carteira zerada', 'Carteira', 'BRL', 0),
          DashboardAccountBalance('Reserva', 'Investimento', 'BRL', 50000,
              isInvestment: true,
              includeInBalance: false,
              institutionId: 'mercado-pago')
        ],
        history: [
          for (var i = 0; i < 6; i++)
            DashboardMonthTotal(
                DateTime(month.year, month.month - 5 + i),
                [400000, 520000, 440000, 560000, 530000, 620000][i],
                [300000, 340000, 350000, 420000, 440000, 385000][i])
        ],
      ),
    ], recent: [
      DashboardActivity(
          id: 'income',
          type: DashboardActivityType.income,
          description: 'Salário',
          accountLabel: 'Conta principal',
          currencyCode: 'BRL',
          amountMinor: 420000,
          date: month,
          isEffective: true),
      DashboardActivity(
          id: 'expense',
          type: DashboardActivityType.expense,
          description: 'Supermercado',
          accountLabel: 'Alimentação',
          currencyCode: 'BRL',
          amountMinor: 32050,
          date: month,
          isEffective: true),
      DashboardActivity(
          id: 'transfer',
          type: DashboardActivityType.transfer,
          description: 'Transferência',
          accountLabel: 'Conta → Carteira',
          currencyCode: 'BRL',
          amountMinor: 20000,
          date: month,
          isEffective: true),
    ]);
  }
}

Future<_DashboardStub> _mount(WidgetTester tester, Size size,
    {double textScale = 1, bool emptyCategories = false}) async {
  referenceMonth.select(DateTime.now());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final repository = _DashboardStub(emptyCategories: emptyCategories);
  getIt.registerSingleton<DashboardRepository>(repository);
  addTearDown(() async {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await getIt.reset();
  });
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const RepaintBoundary(
      key: ValueKey('dashboard-preview'),
      child: SomiaShell(location: '/', child: DashboardPage()),
    ),
  ));
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  for (final width in [360.0, 390.0, 520.0]) {
    testWidgets('mobile $width mantém a ordem e receitas/despesas lado a lado',
        (tester) async {
      await _mount(tester, Size(width, 900));
      expect(find.byTooltip('Entender os saldos'), findsOneWidget);
      expect(find.text('A receber'), findsOneWidget);
      expect(find.text('A pagar'), findsOneWidget);
      final selector = tester
          .getRect(find.byKey(const ValueKey('dashboard-month-selector')));
      final menu = tester.getRect(find.byTooltip('Abrir menu'));
      expect(selector.center.dy, closeTo(menu.center.dy, 2));
      expect(selector.left, greaterThan(menu.right));
      expect(selector.right, lessThanOrEqualTo(width));
      final balance =
          tester.getRect(find.byKey(const ValueKey('mobile-balance-BRL')));
      final income =
          tester.getRect(find.byKey(const ValueKey('mobile-income-BRL')));
      final expense =
          tester.getRect(find.byKey(const ValueKey('mobile-expense-BRL')));
      final history =
          tester.getRect(find.byKey(const ValueKey('mobile-history-BRL')));
      final categories =
          tester.getRect(find.byKey(const ValueKey('mobile-categories-BRL')));
      expect(balance.width, closeTo(width - 32, 0.1));

      expect(expense.top, income.top);

      expect(balance.bottom, lessThan(income.top));
      expect(history.top, greaterThan(income.bottom));
      expect(categories.top, greaterThan(history.bottom));
      expect(find.text('Gastos por categoria'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('mobile-recent')), 250,
          scrollable: find.descendant(
              of: find.byKey(const ValueKey('dashboard-mobile-scroll')),
              matching: find.byType(Scrollable)));
      final recent =
          tester.getRect(find.byKey(const ValueKey('mobile-recent')));
      expect(
          recent.top,
          greaterThan(tester
              .getRect(find.byKey(const ValueKey('mobile-categories-BRL')))
              .bottom));
      expect(find.text('Saldo por conta'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mobile estreito suporta texto ampliado sem overflow',
      (tester) async {
    await _mount(tester, const Size(320, 900), textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('mobile-recent')), 250,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('dashboard-mobile-scroll')),
            matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
        find.byKey(const ValueKey('dashboard-month-selector')), findsOneWidget);
  });

  testWidgets('gráfico mobile sem despesas mostra estado vazio',
      (tester) async {
    await _mount(tester, const Size(390, 900), emptyCategories: true);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('mobile-categories-BRL')), 250,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('dashboard-mobile-scroll')),
            matching: find.byType(Scrollable)));
    expect(find.text('Nenhuma despesa neste mês.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seletor de mês permanece no cabeçalho e atualiza o resumo',
      (tester) async {
    final repository = await _mount(tester, const Size(390, 900));
    final initial = repository.requestedMonths.last;
    await tester.tap(find.byTooltip('Próximo mês'));
    await tester.pumpAndSettle();
    expect(repository.requestedMonths.last,
        DateTime(initial.year, initial.month + 1));
    await tester.tap(find.byTooltip('Mês anterior'));
    await tester.pumpAndSettle();
    expect(repository.requestedMonths.last, initial);
    await tester.tap(find.byKey(const ValueKey('dashboard-month-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dezembro'));
    await tester.pumpAndSettle();
    expect(repository.requestedMonths.last, DateTime(initial.year, 12));
    await tester.tap(find.byTooltip('Abrir menu'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop mantém métricas, categorias e saldo por conta',
      (tester) async {
    await _mount(tester, const Size(1440, 1000));

    expect(find.text('Saldo atual'), findsOneWidget);
    expect(find.text('Saldo previsto no fim do mês'), findsOneWidget);
    expect(find.text('Gastos por categoria'), findsOneWidget);
    expect(find.text('Saldo por conta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vencimento abre detalhes sem alterar mês ao cancelar',
      (tester) async {
    await _mount(tester, const Size(390, 900));
    final initial = referenceMonth.value;
    final button = find.widgetWithText(TextButton, 'Abrir');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Vencimento:'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(referenceMonth.value, initial);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ocultar zeradas preserva investimentos e consulta diária',
      (tester) async {
    await _mount(tester, const Size(1440, 1000));
    final switchFinder =
        find.widgetWithText(SwitchListTile, 'Ocultar contas zeradas');
    await tester.ensureVisible(switchFinder);
    await tester.pumpAndSettle();
    expect(find.text('Carteira zerada'), findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(find.text('Carteira zerada'), findsNothing);
    expect(find.text('Reserva'), findsOneWidget);
    expect(find.text('Fora do saldo principal'), findsOneWidget);
    final slider = find.byType(Slider);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dia 30 •'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    for (final previewSize in [const Size(390, 844), const Size(1920, 1200)]) {
      testWidgets('renderiza resumo $previewSize para inspeção visual',
          (tester) async {
        final root = Platform.environment['FLUTTER_ROOT']!;
        final directory = Directory('$root/bin/cache/artifacts/material_fonts');
        final loader = FontLoader('Roboto');
        for (final file in directory.listSync().whereType<File>()) {
          if (file.path.endsWith('Roboto-Regular.ttf') ||
              file.path.endsWith('Roboto-Bold.ttf')) {
            loader.addFont(
                Future.value(ByteData.sublistView(file.readAsBytesSync())));
          }
        }
        await loader.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(Future.value(File(
                '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
            .readAsBytesSync()
            .buffer
            .asByteData()));
        await icons.load();
        await _mount(tester, previewSize);
        await expectLater(
            find.byKey(const ValueKey('dashboard-preview')),
            matchesGoldenFile(previewSize.width < 800
                ? 'dashboard-mobile-preview.png'
                : 'dashboard-desktop-preview.png'));
        if (previewSize.width < 800) {
          await tester.scrollUntilVisible(
              find.byKey(const ValueKey('mobile-categories-BRL')), 250,
              scrollable: find.descendant(
                  of: find.byKey(const ValueKey('dashboard-mobile-scroll')),
                  matching: find.byType(Scrollable)));
          await tester.pumpAndSettle();
          await expectLater(find.byKey(const ValueKey('dashboard-preview')),
              matchesGoldenFile('dashboard-categories-mobile-preview.png'));
        }
      });
    }
  }
}
