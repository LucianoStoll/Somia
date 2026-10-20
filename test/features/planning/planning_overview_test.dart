import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/widgets/module_surface.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/domain/money_minor.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/planning/domain/planning.dart';
import 'package:finapp/features/planning/presentation/planning_overview.dart';

void main() {
  Account account(String id, String name, int projected) => Account(
      id: id,
      name: name,
      type: AccountType.checking,
      currencyCode: 'BRL',
      initialBalanceMinor: 0,
      currentBalanceMinor: 0,
      projectedBalanceMinor: projected,
      isArchived: false,
      includeInAnalytics: true);

  testWidgets('expandir e rolar após trocar mês não mistura estados',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bucket = PageStorageBucket();
    Future<void> open(int month, {bool loading = false}) async {
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark,
          home: DefaultTabController(
              length: 3,
              child: Scaffold(
                  body: PageStorage(
                      bucket: bucket,
                      child: loading
                          ? const SizedBox()
                          : ModuleSurface(
                              child: PlanningOverview(
                                  month: DateTime(2026, month),
                                  accounts: [
                                    account(
                                        'a', 'Conta principal', month * 1000),
                                    account('b', 'Conta negativa', -1000),
                                  ],
                                  categories: const [],
                                  spending: const [],
                                  budgets: const [],
                                  onRefresh: () async {},
                                  indicators:
                                      const Text('Indicador de teste'))))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    for (final month in [10, 11, 10]) {
      await open(month);
      final accounts = find.text('Ver contas (2)');
      await tester.scrollUntilVisible(accounts, -200);
      final tile = tester.widget<ExpansionTile>(
          find.ancestor(of: accounts, matching: find.byType(ExpansionTile)));
      if (!tile.initiallyExpanded &&
          find.text('Conta principal').evaluate().isEmpty) {
        await tester.tap(accounts);
        await tester.pumpAndSettle();
      }
      expect(find.text('Conta principal'), findsOneWidget);
      expect(find.text('Conta negativa'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Indicadores do mês'), 200);
      await tester.tap(find.text('Indicadores do mês'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await open(month, loading: true);
    }
  });

  FinanceCategory category(String id, String name, {String? parent}) =>
      FinanceCategory(
          id: id,
          name: name,
          type: CategoryType.expense,
          parentId: parent,
          isArchived: false,
          iconKey: null,
          colorArgb: 0xffa5bcd0);

  Future<void> chart(WidgetTester tester, List<MonthlySpend> rows,
      List<FinanceCategory> categories) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
            body: SingleChildScrollView(
                child: PlanningCategoryChart(
                    spending: rows,
                    categories: categories,
                    currency: 'BRL',
                    label: 'Despesas')))));
    await tester.pumpAndSettle();
  }

  testWidgets('categoria abre subcategorias, valor direto e créditos',
      (tester) async {
    await chart(tester, const [
      MonthlySpend('p', null, 'BRL', 'expense', 1000, 1000),
      MonthlySpend('a', 'p', 'BRL', 'expense', 3000, 3000),
      MonthlySpend('a', 'p', 'BRL', 'expense', 1000, 1000),
      MonthlySpend('b', 'p', 'BRL', 'expense', -500, -500),
    ], [
      category('p', 'Alimentação'),
      category('a', 'Mercado', parent: 'p'),
      category('b', 'Restaurante', parent: 'p'),
    ]);
    await tester.tap(find.byKey(const ValueKey('planning-category-p')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('planning-subcategories'));
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Sem subcategoria')),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Mercado')),
        findsOneWidget);
    expect(
        find.descendant(
            of: sheet, matching: find.text(MoneyMinor.display(4000, 'BRL'))),
        findsOneWidget);
    expect(
        find.descendant(
            of: sheet, matching: find.text(MoneyMinor.display(-500, 'BRL'))),
        findsOneWidget);
    expect(
        find.descendant(
            of: sheet, matching: find.text(MoneyMinor.display(4500, 'BRL'))),
        findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver categorias'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planning-category-detail-p')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('planning-subcategories')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Outras abre categorias reais e permite chegar à subcategoria',
      (tester) async {
    await chart(tester, const [
      MonthlySpend('a', null, 'BRL', 'expense', 5000, 5000),
      MonthlySpend('b', null, 'BRL', 'expense', 4000, 4000),
      MonthlySpend('c', null, 'BRL', 'expense', 3000, 3000),
      MonthlySpend('d', null, 'BRL', 'expense', 2000, 2000),
      MonthlySpend('sub', 'e', 'BRL', 'expense', 1000, 1000),
    ], [
      category('a', 'Moradia'),
      category('b', 'Transporte'),
      category('c', 'Saúde'),
      category('d', 'Lazer'),
      category('e', 'Alimentação'),
      category('sub', 'Mercado', parent: 'e'),
    ]);
    await tester.tap(find.byKey(const ValueKey('planning-category-other')));
    await tester.pumpAndSettle();
    expect(find.text('Lazer'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('planning-category-detail-e')));
    await tester.pumpAndSettle();
    expect(find.text('Mercado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
