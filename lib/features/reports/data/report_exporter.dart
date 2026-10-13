import 'dart:typed_data';
import 'package:excel/excel.dart' as x;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/analysis_report.dart';

enum ReportFormat { excel, pdf }

class ReportExporter {
  static Uint8List excel(AnalysisReport report) {
    final book = x.Excel.createExcel();
    final info = book['Informações'];
    for (final row in [
      ['Somia', report.title],
      ['Mês selecionado', AnalysisReport.period(report.month)],
      ['Moeda', report.currency],
      [
        'Gerado em',
        '${AnalysisReport.date(report.generatedAt)} ${report.generatedAt.hour.toString().padLeft(2, '0')}:${report.generatedAt.minute.toString().padLeft(2, '0')}'
      ],
      ['Critérios', report.note]
    ]) {
      info.appendRow(row.map(x.TextCellValue.new).toList());
    }
    info.setColumnWidth(0, 24);
    info.setColumnWidth(1, 80);
    book.setDefaultSheet('Informações');
    book.delete('Sheet1');
    for (final section in report.sections) {
      final sheet = book[section.title];
      sheet.appendRow(section.headers.map(x.TextCellValue.new).toList());
      for (final row in section.rows) {
        sheet.appendRow(row
            .map<x.CellValue>((value) => switch (value) {
                  ReportMoney() => x.DoubleCellValue(value.minor / 100),
                  DateTime() => x.DateCellValue(
                      year: value.year, month: value.month, day: value.day),
                  // Always text, including strings starting with =, +, - or @.
                  _ => x.TextCellValue(value.toString())
                })
            .toList());
      }
      for (var col = 0; col < section.headers.length; col++) {
        sheet.setColumnWidth(col, col == 1 ? 42 : 24);
        sheet
                .cell(x.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
                .cellStyle =
            x.CellStyle(bold: true, textWrapping: x.TextWrapping.WrapText);
      }
      for (var row = 0; row < section.rows.length; row++) {
        for (var col = 0; col < section.rows[row].length; col++) {
          final value = section.rows[row][col];
          final cell = sheet.cell(x.CellIndex.indexByColumnRow(
              columnIndex: col, rowIndex: row + 1));
          if (value is ReportMoney) {
            cell.cellStyle = x.CellStyle(
                numberFormat: x.CustomNumericNumFormat(formatCode: '#,##0.00'));
          } else if (value is DateTime) {
            cell.cellStyle = x.CellStyle(
                numberFormat:
                    x.CustomDateTimeNumFormat(formatCode: 'dd/mm/yyyy'));
          } else {
            cell.cellStyle = x.CellStyle(textWrapping: x.TextWrapping.WrapText);
          }
        }
      }
    }
    return Uint8List.fromList(book.encode()!);
  }

  static Future<Uint8List> pdf(
      AnalysisReport report, Uint8List regular, Uint8List bold) async {
    final doc = pw.Document(title: report.title, author: 'Somia');
    final theme = pw.ThemeData.withFont(
        base: pw.Font.ttf(ByteData.sublistView(regular)),
        bold: pw.Font.ttf(ByteData.sublistView(bold)));
    for (final section in report.sections) {
      // A row must fit on a page. Continuation rows retain every character of
      // long descriptions/identifiers, without hiding or truncating data.
      final rows = <List<String>>[];
      for (final row in section.rows) {
        final cells = row.map(report.display).toList();
        final chunks = cells
            .map((text) => [
                  if (text.isEmpty) '',
                  for (var i = 0; i < text.length; i += 100)
                    text.substring(
                        i, i + 100 > text.length ? text.length : i + 100)
                ])
            .toList();
        final count =
            chunks.fold<int>(1, (s, c) => c.length > s ? c.length : s);
        for (var i = 0; i < count; i++) {
          rows.add([for (final cell in chunks) i < cell.length ? cell[i] : '']);
        }
      }
      doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(28),
          theme: theme,
          maxPages: 10000,
          header: (_) => pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Somia | ${report.title}',
                        style: pw.TextStyle(
                            fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 5),
                    pw.Text(
                        '${AnalysisReport.period(report.month)} | ${report.currency} | Gerado em ${AnalysisReport.date(report.generatedAt)}',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 10)
                  ]),
          footer: (context) => pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                  'Página ${context.pageNumber} de ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8))),
          build: (_) => [
                pw.Text(section.title,
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text(report.note, style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 12),
                if (rows.isEmpty)
                  pw.Text('Nenhum registro neste período.')
                else
                  pw.TableHelper.fromTextArray(
                      headers: section.headers,
                      data: rows,
                      headerStyle: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold),
                      cellStyle: const pw.TextStyle(fontSize: 8),
                      headerDecoration:
                          const pw.BoxDecoration(color: PdfColors.blueGrey100),
                      cellPadding: const pw.EdgeInsets.all(5))
              ]));
    }
    return doc.save();
  }
}
