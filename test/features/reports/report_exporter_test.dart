import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' as x;
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/analysis/domain/expense_analysis.dart';
import 'package:finapp/features/reports/domain/analysis_report.dart';
import 'package:finapp/features/reports/data/report_exporter.dart';

AnalysisExpense expense(String id, int amount, int month,
        {String currency = 'BRL', String? description}) =>
    AnalysisExpense(
        id: id,
        description: description ?? 'Alimentação São João',
        source: 'Conta corrente',
        currency: currency,
        date: DateTime(2026, month, 15),
        category: 'Alimentação',
        subcategory: 'Mercado',
        amount: amount);

ExpenseAnalysis fixture({int count = 1}) =>
    ExpenseAnalysis(DateTime(2026, 10), [
      expense('rateio', 101, 10, description: '=SUM(A1:A3)'),
      expense('rateio', 202, 10),
      expense('estorno', -100, 10),
      expense('set', 100, 9),
      expense('ago', 101, 8),
      expense('usd', 99999, 10, currency: 'USD'),
      for (var i = 1; i < count; i++)
        expense('extra-$i', 0, 10,
            description:
                'Descrição longa ${'São João com acentuação e detalhes. ' * 20}')
    ], {
      'BRL': [
        FutureCommitment(DateTime(2026, 11), [expense('parcela', 500, 11)],
            [expense('fatura', 700, 11)]),
        FutureCommitment(DateTime(2026, 12), [], [])
      ]
    }, [
      const Account(
          id: 'cc',
          name: 'Banco São João',
          type: AccountType.checking,
          currencyCode: 'BRL',
          initialBalanceMinor: 0,
          currentBalanceMinor: -123,
          projectedBalanceMinor: 0,
          isArchived: false,
          includeInAnalytics: true),
      const Account(
          id: 'invest',
          name: 'CDB',
          type: AccountType.investment,
          currencyCode: 'BRL',
          initialBalanceMinor: 0,
          currentBalanceMinor: 200,
          projectedBalanceMinor: 0,
          isArchived: false,
          includeInAnalytics: false,
          includeInBalance: false),
      const Account(
          id: 'archive',
          name: 'Arquivada',
          type: AccountType.cash,
          currencyCode: 'BRL',
          initialBalanceMinor: 0,
          currentBalanceMinor: 99999,
          projectedBalanceMinor: 0,
          isArchived: true,
          includeInAnalytics: true)
    ]);

void main() {
  AnalysisReport report(int view, {int count = 1}) =>
      AnalysisReport.fromAnalysis(fixture(count: count), 'BRL', view,
          generatedAt: DateTime(2026, 10, 13, 11, 30));
  test('categorias preservam rateios/estornos e não somam outra moeda', () {
    final r = report(0);
    expect((r.sections.first.rows.last[1] as ReportMoney).minor, 203);
    expect(r.sections.last.rows.length, 3);
    expect(r.sections.last.rows.map((row) => row.last),
        containsAll(['rateio', 'estorno']));
  });
  test('média global arredonda uma vez e inclui meses vazios', () {
    final r = report(1);
    expect((r.sections.first.rows.last[3] as ReportMoney).minor, 67);
    expect(r.sections.last.rows.length, 5);
  });
  test('compromissos e contas conservam a base financeira das telas', () {
    final future = report(2);
    expect((future.sections.first.rows.last[3] as ReportMoney).minor, 1200);
    expect(future.sections.last.rows.length, 2);
    final accounts = report(3);
    expect((accounts.sections.first.rows.last[1] as ReportMoney).minor, 77);
    expect(accounts.sections.last.rows.length, 2);
    expect(accounts.sections.last.rows.last[2], 'Não');
  });
  test('XLSX reabre com valores numéricos, datas e descrição como texto', () {
    final book = x.Excel.decodeBytes(ReportExporter.excel(report(0)));
    expect(book.tables.keys, ['Informações', 'Categorias', 'Lançamentos']);
    final detail = book['Lançamentos'].rows;
    final formulaRow = detail.firstWhere((row) =>
        row[1]?.value is x.TextCellValue &&
        (row[1]!.value as x.TextCellValue).value.toString() == '=SUM(A1:A3)');
    expect(detail[1][0]!.value, isA<x.DateCellValue>());
    expect(formulaRow[1]!.value, isA<x.TextCellValue>());
    expect((formulaRow[1]!.value as x.TextCellValue).value.toString(),
        '=SUM(A1:A3)');
    expect((formulaRow[5]!.value as x.DoubleCellValue).value, 1.01);
    expect((book['Categorias'].rows.last[1]!.value as x.DoubleCellValue).value,
        2.03);
  });
  test('PDF gera todas as análises offline com fonte incorporada', () async {
    final regular = File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync();
    final bold = File('assets/fonts/Roboto-Bold.ttf').readAsBytesSync();
    for (var view = 0; view < 4; view++) {
      final bytes = await ReportExporter.pdf(report(view), regular, bold);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(3000));
    }
  });
  test('PDF pagina mais de 20 páginas sem truncar descrições longas', () async {
    final bytes = await ReportExporter.pdf(
        report(0, count: 220),
        File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync(),
        File('assets/fonts/Roboto-Bold.ttf').readAsBytesSync());
    expect(bytes, isA<Uint8List>());
    expect(bytes.length, greaterThan(10000));
  });
  test('moeda inexistente e análise inválida são rejeitadas', () {
    expect(() => AnalysisReport.fromAnalysis(fixture(), 'EUR', 0),
        throwsArgumentError);
    expect(() => AnalysisReport.fromAnalysis(fixture(), 'BRL', 4),
        throwsArgumentError);
  });
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    test('arquivos para inspeção visual e compatibilidade externa', () async {
      final folder = Directory('test/features/reports/samples')
        ..createSync(recursive: true);
      for (var view = 0; view < 4; view++) {
        final r = report(view);
        File('${folder.path}/analysis-$view.xlsx')
            .writeAsBytesSync(ReportExporter.excel(r));
        File('${folder.path}/analysis-$view.pdf').writeAsBytesSync(
            await ReportExporter.pdf(
                r,
                File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync(),
                File('assets/fonts/Roboto-Bold.ttf').readAsBytesSync()));
      }
      File('${folder.path}/large.pdf').writeAsBytesSync(
          await ReportExporter.pdf(
              report(0, count: 220),
              File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync(),
              File('assets/fonts/Roboto-Bold.ttf').readAsBytesSync()));
    });
  }
}
