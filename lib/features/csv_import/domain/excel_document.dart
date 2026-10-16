import 'package:excel/excel.dart' as x;

import 'csv_document.dart';

/// Reads the first nonempty worksheet; formulas are never evaluated or imported.
class ExcelDocument {
  static CsvDocument read(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > CsvDocument.maxBytes) {
      throw const FormatException('Selecione um XLSX de até 2 MB.');
    }
    try {
      final workbook = x.Excel.decodeBytes(bytes);
      final sheets = workbook.tables.values.where((s) => s.rows.isNotEmpty);
      if (sheets.isEmpty) {
        throw const FormatException('Planilha vazia.');
      }
      final sheet = sheets.first;
      if (sheet.rows.length < 2 ||
          sheet.rows.length > CsvDocument.maxRows + 1) {
        throw const FormatException(
            'A planilha precisa de cabeçalho e até 5.000 linhas.');
      }
      final width = sheet.rows.first.length;
      if (width < 2 || width > 50) {
        throw const FormatException('Use de 2 a 50 colunas na planilha.');
      }
      String cell(x.Data? data) {
        final value = data?.value;
        return switch (value) {
          null => '',
          x.TextCellValue() => value.value.toString(),
          x.IntCellValue() => value.value.toString(),
          x.DoubleCellValue() => value.value.toString().replaceAll('.', ','),
          x.DateCellValue() =>
            '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}',
          x.DateTimeCellValue() =>
            '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}',
          x.FormulaCellValue() => throw const FormatException(
              'Substitua fórmulas por valores antes de importar.'),
          _ => throw const FormatException(
              'Há uma célula com tipo não suportado.'),
        };
      }

      final rows = <CsvRawRow>[];
      for (var i = 0; i < sheet.rows.length; i++) {
        final source = sheet.rows[i];
        if (source.length > width &&
            source.skip(width).any((c) => c?.value != null)) {
          throw FormatException('Colunas extras na linha ${i + 1}.');
        }
        final values = [
          for (var n = 0; n < width; n++)
            cell(n < source.length ? source[n] : null)
        ];
        if (values.any((v) => v.trim().isNotEmpty)) {
          if (values.any((v) => v.length > 4096)) {
            throw FormatException('Campo muito longo na linha ${i + 1}.');
          }
          rows.add(CsvRawRow(i + 1, List.unmodifiable(values)));
        }
      }
      if (rows.length < 2 || rows.first.cells.any((c) => c.trim().isEmpty)) {
        throw const FormatException(
            'Informe cabeçalhos e ao menos um lançamento.');
      }
      return CsvDocument(
          rows.first.cells, List.unmodifiable(rows.skip(1)), '', 'XLSX');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('XLSX inválido ou não suportado.');
    }
  }
}
