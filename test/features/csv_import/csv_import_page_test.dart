import 'dart:convert';
import 'dart:typed_data';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/csv_import/domain/csv_document.dart';
import 'package:finapp/features/csv_import/domain/csv_import.dart';
import 'package:finapp/features/csv_import/presentation/csv_import_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class PreviewRepository implements CsvImportRepository {
  int commits = 0;
  List<CsvPreviewRow>? committed;
  final refs = const CsvReferences([
    Account(
        id: 'account',
        name: 'Conta exemplo',
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 0,
        currentBalanceMinor: 0,
        projectedBalanceMinor: 0,
        isArchived: false,
        includeInAnalytics: true)
  ], [
    FinanceCategory(
        id: 'food',
        name: 'Alimentação',
        type: CategoryType.expense,
        parentId: null,
        isArchived: false,
        iconKey: null,
        colorArgb: null)
  ]);
  @override
  Future<CsvReferences> references() async => refs;
  @override
  Future<List<CsvPreviewRow>> preview(
      CsvDocument document, CsvMapping mapping, String accountId) async {
    mapping.validate(document.headers.length);
    return [
      CsvPreviewRow(
          line: 2,
          selected: true,
          candidate: CsvCandidate(
              line: 2,
              description: 'Mercado da semana',
              type: TransactionType.expense,
              amountMinor: 12345,
              date: DateTime.utc(2026, 10, 5),
              dueDate: DateTime.utc(2026, 10, 8)),
          categoryId: 'food',
          warning: 'Categoria sugerida pelo histórico.'),
      CsvPreviewRow(
          line: 3,
          duplicate: true,
          candidate: CsvCandidate(
              line: 3,
              description: 'Possível duplicado',
              type: TransactionType.expense,
              amountMinor: 1000,
              date: DateTime.utc(2026, 10, 5),
              dueDate: DateTime.utc(2026, 10, 5))),
      const CsvPreviewRow(
          line: 4, error: 'Valor inválido. Confira o formato decimal.')
    ];
  }

  @override
  Future<CsvImportResult> commit(
      List<CsvPreviewRow> rows, String accountId) async {
    commits++;
    committed = rows;
    return CsvImportResult(rows.where((r) => r.selected).length, 0);
  }
}

Future<void> openPreview(WidgetTester tester, PreviewRepository repo,
    {Size size = const Size(320, 900), double scale = 1.5}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => RepaintBoundary(
                              key: const Key('csv-preview'),
                              child: CsvImportPage(
                                  repository: repo,
                                  pickFile: () async => CsvPickedFile(
                                      'extrato-exemplo.csv',
                                      Uint8List.fromList(utf8.encode(
                                          'Descrição;Valor;Data\nMercado;-123,45;05/10/2026'))))))),
                  child: const Text('Abrir'))))));
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Selecionar CSV'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Gerar prévia'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Gerar prévia'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('3. Conferir lançamentos'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
  testWidgets(
      'prévia cabe em tela estreita com fonte ampliada e cancelar não grava',
      (tester) async {
    final repo = PreviewRepository();
    await openPreview(tester, repo);
    expect(find.textContaining('1 selecionados'), findsOneWidget);
    await tester.ensureVisible(find.text('Importar 1 lançamentos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar 1 lançamentos'));
    await tester.pumpAndSettle();
    expect(repo.commits, 0);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.commits, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'duplicado exige seleção, mostra confirmação e só importa ao confirmar',
      (tester) async {
    final repo = PreviewRepository();
    await openPreview(tester, repo, size: const Size(1000, 800), scale: 1);
    await tester.scrollUntilVisible(find.text('Possível duplicado'), 200,
        scrollable: find.byType(Scrollable).first);
    final tile = find.widgetWithText(CheckboxListTile, 'Possível duplicado');
    expect(tester.widget<CheckboxListTile>(tile).value, isFalse);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Importar 2 lançamentos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar 2 lançamentos'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Você selecionou 1 possíveis duplicados'),
        findsOneWidget);
    await tester.tap(find.text('Importar'));
    await tester.pumpAndSettle();
    expect(repo.commits, 1);
    expect(repo.committed!.where((r) => r.selected).length, 2);
    expect(find.text('Importar CSV'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'categoria da prévia pode ser removida sem alterar os dados existentes',
      (tester) async {
    final repo = PreviewRepository();
    await openPreview(tester, repo, size: const Size(800, 900), scale: 1);
    await tester.scrollUntilVisible(find.text('Alimentação'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Alimentação'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sem categoria'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Importar 1 lançamentos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar 1 lançamentos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar'));
    await tester.pumpAndSettle();
    expect(repo.committed!.first.categoryId, isNull);
    expect(tester.takeException(), isNull);
  });
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('prévia CSV mobile', (tester) async {
      await openPreview(tester, PreviewRepository(),
          size: const Size(390, 844), scale: 1);
      await expectLater(find.byKey(const Key('csv-preview')),
          matchesGoldenFile('csv-import-mobile-preview.png'));
    });
  }
}
