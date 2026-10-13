import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../domain/analysis_report.dart';
import 'report_exporter.dart';

class _ExportRequest {
  _ExportRequest(this.report, this.format, this.regular, this.bold);
  final AnalysisReport report;
  final ReportFormat format;
  final Uint8List regular, bold;
}

Future<Uint8List> _encode(_ExportRequest request) async =>
    request.format == ReportFormat.excel
        ? ReportExporter.excel(request.report)
        : ReportExporter.pdf(request.report, request.regular, request.bold);

class ReportExportService {
  Future<Uint8List> generate(AnalysisReport report, ReportFormat format) async {
    var regular = Uint8List(0), bold = Uint8List(0);
    if (format == ReportFormat.pdf) {
      regular = (await rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          .buffer
          .asUint8List();
      bold = (await rootBundle.load('assets/fonts/Roboto-Bold.ttf'))
          .buffer
          .asUint8List();
    }
    return compute(_encode, _ExportRequest(report, format, regular, bold));
  }

  Future<bool> save(
      AnalysisReport report, ReportFormat format, Uint8List bytes) async {
    final extension = format == ReportFormat.excel ? 'xlsx' : 'pdf';
    final period =
        '${report.month.year}-${report.month.month.toString().padLeft(2, '0')}';
    final slug = AnalysisReport.titles.indexOf(report.title);
    final path = await FilePicker.saveFile(
        dialogTitle: 'Salvar relatório',
        fileName:
            'somia-analise-${slug + 1}-$period-${report.currency}.$extension',
        bytes: bytes,
        mimeType: format == ReportFormat.pdf
            ? 'application/pdf'
            : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    return path != null;
  }
}
