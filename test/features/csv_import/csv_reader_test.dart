import 'dart:convert';
import 'package:finapp/features/csv_import/domain/csv_document.dart';
import 'package:finapp/features/csv_import/domain/csv_import.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'BOM, diretiva, aspas escapadas, separador em descrição e campo multilinha',
      () {
    final doc = CsvDocument.read(utf8.encode(
        '\uFEFFsep=;\r\nDescrição;Valor;Data\r\n"Café; ""Centro""\nPix";-1.234,56;05/10/2026\r\n'));
    expect(doc.delimiter, ';');
    expect(doc.rows.single.line, 3);
    expect(doc.rows.single.cells.first, 'Café; "Centro"\nPix');
    final row = CsvMapping.suggest(doc.headers).parse(doc.rows.single, 3);
    expect(row.amountMinor, 123456);
    expect(row.type, TransactionType.expense);
    expect(row.date, DateTime.utc(2026, 10, 5));
    expect(row.effectiveDate, isNull);
  });
  test('Windows-1252 e tabulação mantêm acentos e caracteres especiais', () {
    final bytes = latin1.encode('Descrição\tValor\tData\nPão ') +
        [0x96] +
        latin1.encode(' Pix\t12,03\t05/10/2026');
    final doc = CsvDocument.read(bytes);
    expect(doc.encoding, 'Windows-1252');
    expect(doc.delimiter, '\t');
    expect(doc.rows.single.cells.first, 'Pão – Pix');
  });
  test('separador vírgula com valor decimal entre aspas', () {
    final doc = CsvDocument.read(
        utf8.encode('Data,Descrição,Valor\n05/10/2026,Compra,"-10,20"\n'));
    expect(doc.delimiter, ',');
    expect(
        CsvMapping.suggest(doc.headers).parse(doc.rows.single, 3).amountMinor,
        1020);
  });
  test('dinheiro é exato, com agrupamento, sinais e limites estritos', () {
    expect(
        CsvMapping.parseAmount('R\$ 1.234,56', CsvAmountFormat.comma), 123456);
    expect(CsvMapping.parseAmount('(1,234.56)', CsvAmountFormat.dot), -123456);
    expect(CsvMapping.parseAmount('+0,03', CsvAmountFormat.comma), 3);
    expect(CsvMapping.parseAmount('90000000000000', CsvAmountFormat.comma),
        9000000000000000);
    for (final text in [
      '1,234',
      '12.34,56',
      '1e3',
      'NaN',
      '--1',
      '90000000000000,01'
    ]) {
      expect(() => CsvMapping.parseAmount(text, CsvAmountFormat.comma),
          throwsFormatException);
    }
  });
  test('datas não normalizam silenciosamente datas impossíveis ou ambíguas',
      () {
    expect(CsvMapping.parseDate('29/02/2028', CsvDateFormat.dayFirst),
        DateTime.utc(2028, 2, 29));
    expect(CsvMapping.parseDate('2026-10-05', CsvDateFormat.iso),
        DateTime.utc(2026, 10, 5));
    expect(CsvMapping.parseDate('10/05/2026', CsvDateFormat.monthFirst),
        DateTime.utc(2026, 10, 5));
    for (final text in [
      '29/02/2026',
      '31/04/2026',
      '01/13/2026',
      '01/01/2101',
      '05/10/26'
    ]) {
      expect(() => CsvMapping.parseDate(text, CsvDateFormat.dayFirst),
          throwsFormatException);
    }
  });
  test('tipo fixo, tipo por coluna, pendência e efetivação explícita', () {
    final doc = CsvDocument.read(utf8.encode(
        'Descrição;Valor;Data;Efetivação;Tipo\nCompra;10,20;05/10/2026;;Despesa\nSalário;100;05/10/2026;06/10/2026;Receita'));
    final map = CsvMapping.suggest(doc.headers);
    expect(map.parse(doc.rows[0], 5).type, TransactionType.expense);
    expect(map.parse(doc.rows[0], 5).effectiveDate, isNull);
    expect(map.parse(doc.rows[1], 5).effectiveDate, DateTime.utc(2026, 10, 6));
    map.type = null;
    map.direction = CsvDirection.expense;
    expect(map.parse(doc.rows[1], 5).type, TransactionType.expense);
  });
  test(
      'mapeamento duplicado, tipos desconhecidos, valores zero e linhas incompletas são rejeitados',
      () {
    final map = CsvMapping(description: 0, amount: 1, date: 2, type: 3);
    expect(
        () => map.parse(
            const CsvRawRow(2, ['Compra', '10', '05/10/2026', 'Transferência']),
            4),
        throwsFormatException);
    expect(
        () => map.parse(
            const CsvRawRow(3, ['Compra', '0', '05/10/2026', 'Despesa']), 4),
        throwsFormatException);
    expect(() => map.parse(const CsvRawRow(4, ['Compra', '10']), 4),
        throwsFormatException);
    map.amount = 0;
    expect(() => map.validate(4), throwsFormatException);
  });
  test('arquivos vazios, binários, excessivos e aspas inválidas são rejeitados',
      () {
    for (final bytes in [
      <int>[],
      [0, 1, 2],
      utf8.encode('Descrição;Valor'),
      utf8.encode('A;B\n"ab;10'),
      utf8.encode('A;B\n"ab"x;10'),
      List.filled(CsvDocument.maxBytes + 1, 32)
    ]) {
      expect(() => CsvDocument.read(bytes), throwsFormatException);
    }
    final large = 'A;B\n${List.filled(5001, 'x;1').join('\n')}';
    expect(() => CsvDocument.read(utf8.encode(large)), throwsFormatException);
  });
}
