import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/planning/domain/planning.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/planning/presentation/planning_overview.dart';
import 'package:finapp/features/planning/presentation/planning_entries_sheet.dart';

void main() {
  final entry = PlanningEntry(
      id: '1',
      description: 'Peças para o carro',
      source: 'Cartão Mercado Pago',
      date: DateTime(2026, 11, 10),
      amount: 4000,
      fullAmount: 10000,
      isCard: true);
  testWidgets(
      'subcategoria abre lançamentos com mês, tipo e moeda selecionados',
      (tester) async {
    (DateTime, String, String, String?)? query;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
            body: PlanningOverview(
                month: DateTime(2026, 11),
                accounts: const [],
                categories: const [
                  FinanceCategory(
                      id: 'p',
                      name: 'Transporte',
                      type: CategoryType.expense,
                      parentId: null,
                      isArchived: false,
                      iconKey: null,
                      colorArgb: null),
                  FinanceCategory(
                      id: 's',
                      name: 'Manutenção',
                      type: CategoryType.expense,
                      parentId: 'p',
                      isArchived: false,
                      iconKey: null,
                      colorArgb: null),
                ],
                spending: const [
                  MonthlySpend('s', 'p', 'BRL', 'expense', 0, 4000)
                ],
                budgets: const [],
                onRefresh: () async {},
                loadEntries: (month, type, currency, categoryId) async {
                  query = (month, type, currency, categoryId);
                  return [entry];
                }))));
    await tester.pumpAndSettle();
    final category = find.byKey(const ValueKey('planning-category-p'));
    await tester.scrollUntilVisible(category, 200);
    await tester.tap(category);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planning-subcategory-s')));
    await tester.pumpAndSettle();
    expect(query, (DateTime(2026, 11), 'expense', 'BRL', 's'));
    final sheet = find.byKey(const ValueKey('planning-entries'));
    expect(sheet, findsOneWidget);
    expect(
        find.descendant(of: sheet, matching: find.text('Peças para o carro')),
        findsOneWidget);
    expect(
        find.descendant(
            of: sheet, matching: find.text('Cartão Mercado Pago · 10/11/2026')),
        findsOneWidget);
    expect(
        find.descendant(
            of: sheet,
            matching: find.textContaining('Parte nesta subcategoria')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falha pode ser repetida sem fechar o detalhe', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
            body: PlanningEntriesSheet(
                title: 'Manutenção',
                month: DateTime(2026, 11),
                currency: 'BRL',
                type: 'expense',
                load: () async {
                  calls++;
                  if (calls == 1) throw StateError('Falha de leitura');
                  return [entry];
                }))));
    await tester.pumpAndSettle();
    expect(
        find.text('Não foi possível carregar os lançamentos.'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Peças para o carro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
