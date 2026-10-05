import 'dart:convert';

class CsvRawRow {
  const CsvRawRow(this.line, this.cells);
  final int line;
  final List<String> cells;
}

class CsvDocument {
  const CsvDocument(this.headers, this.rows, this.delimiter, this.encoding);
  final List<String> headers;
  final List<CsvRawRow> rows;
  final String delimiter, encoding;
  static const maxBytes = 2 * 1024 * 1024;
  static const maxRows = 5000;

  static CsvDocument read(List<int> bytes, {String? delimiter}) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Selecione um CSV não vazio de até 2 MB.');
    }
    var encoding = 'UTF-8';
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      encoding = 'Windows-1252';
      const replacements = {0x80: 0x20ac, 0x82: 0x201a, 0x83: 0x0192,
        0x84: 0x201e, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021,
        0x88: 0x02c6, 0x89: 0x2030, 0x8a: 0x0160, 0x8b: 0x2039,
        0x8c: 0x0152, 0x8e: 0x017d, 0x91: 0x2018, 0x92: 0x2019,
        0x93: 0x201c, 0x94: 0x201d, 0x95: 0x2022, 0x96: 0x2013,
        0x97: 0x2014, 0x98: 0x02dc, 0x99: 0x2122, 0x9a: 0x0161,
        0x9b: 0x203a, 0x9c: 0x0153, 0x9e: 0x017e, 0x9f: 0x0178};
      text = String.fromCharCodes(bytes.map((b) => replacements[b] ?? b));
    }
    text = text.replaceFirst(RegExp(r'^\uFEFF'), '');
    if (text.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'))) {
      throw const FormatException('O arquivo não contém texto CSV válido.');
    }
    var line = 1;
    final directive = RegExp(r'^sep=([;,\t])\r?\n', caseSensitive: false).firstMatch(text);
    if (directive != null) {
      delimiter ??= directive.group(1);
      text = text.substring(directive.end);
      line++;
    }
    delimiter ??= _detect(text);
    if (![';', ',', '\t'].contains(delimiter)) {
      throw const FormatException('Separador inválido.');
    }
    final records = <CsvRawRow>[];
    var cells = <String>[];
    var field = StringBuffer();
    var quoted = false, closed = false;
    var recordLine = line;
    void endField() {
      cells.add(field.toString());
      if (cells.length > 50) throw const FormatException('O CSV deve ter até 50 colunas.');
      field = StringBuffer();
      closed = false;
    }
    void endRecord() {
      endField();
      if (cells.any((c) => c.trim().isNotEmpty)) {
        records.add(CsvRawRow(recordLine, List.unmodifiable(cells)));
        if (records.length > maxRows + 1) throw const FormatException('Importe até 5.000 linhas por arquivo.');
      }
      cells = [];
    }
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"'); i++;
          } else { quoted = false; closed = true; }
        } else {
          field.write(c);
          if (c == '\n') line++;
        }
      } else if (c == delimiter) {
        endField();
      } else if (c == '\r' || c == '\n') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        endRecord(); line++; recordLine = line;
      } else if (closed) {
        if (c.trim().isNotEmpty) throw FormatException('Aspas inválidas na linha $line.');
      } else if (c == '"') {
        if (field.toString().trim().isNotEmpty) throw FormatException('Aspas inválidas na linha $line.');
        field = StringBuffer(); quoted = true;
      } else { field.write(c); }
      if (field.length > 4096) throw FormatException('Campo muito longo na linha $line.');
    }
    if (quoted) throw FormatException('Aspas não fechadas na linha $recordLine.');
    if (field.isNotEmpty || cells.isNotEmpty || closed) endRecord();
    if (records.length < 2 || records.first.cells.length < 2) {
      throw const FormatException('O CSV precisa de cabeçalho e ao menos um lançamento. Confira o separador.');
    }
    return CsvDocument(records.first.cells, List.unmodifiable(records.skip(1)), delimiter, encoding);
  }

  static String _detect(String text) {
    final counts = {';': 0, ',': 0, '\t': 0};
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '"') {
        if (quoted && i + 1 < text.length && text[i + 1] == '"') { i++; } else { quoted = !quoted; }
      } else if (!quoted) {
        if (c == '\n' || c == '\r') {
          if (counts.values.any((n) => n > 0)) break;
        } else if (counts.containsKey(c)) { counts[c] = counts[c]! + 1; }
      }
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}
