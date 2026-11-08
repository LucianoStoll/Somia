import 'package:excel/excel.dart' as x;
import 'package:finapp/features/csv_import/domain/csv_import.dart';
import 'package:finapp/features/csv_import/domain/excel_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('XLSX lê datas e valores numéricos sem alterar centavos', () {
    final book = x.Excel.createExcel();
    book['Sheet1'].appendRow([
      x.TextCellValue('Descrição'),
      x.TextCellValue('Valor'),
      x.TextCellValue('Data'),
    ]);
    book['Sheet1'].appendRow([
      x.TextCellValue('Mercado'),
      x.DoubleCellValue(-10.03),
      x.DateCellValue(year: 2026, month: 10, day: 5),
    ]);
    final document = ExcelDocument.read(book.save()!);
    final candidate = CsvMapping.suggest(document.headers)
        .parse(document.rows.single, document.headers.length);
    expect(candidate.description, 'Mercado');
    expect(candidate.amountMinor, 1003);
    expect(candidate.date, DateTime.utc(2026, 10, 5));
  });

  test('XLSX recusa fórmulas; nunca executa nem avalia conteúdo', () {
    final book = x.Excel.createExcel();
    book['Sheet1'].appendRow([
      x.TextCellValue('Descrição'),
      x.TextCellValue('Valor'),
      x.TextCellValue('Data'),
    ]);
    book['Sheet1'].appendRow([
      x.TextCellValue('Teste'),
      x.FormulaCellValue('1+1'),
      x.TextCellValue('05/10/2026'),
    ]);
    expect(() => ExcelDocument.read(book.save()!), throwsFormatException);
  });
}
