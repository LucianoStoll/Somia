import 'dart:convert';
import 'dart:io';

import 'csv_import.dart';

/// A device-local parsing preference. Column labels, rather than positions,
/// prevent a reordered bank export from silently importing the wrong values.
class CsvProfile {
  const CsvProfile(
    this.name,
    this.delimiter,
    this.columns,
    this.dateFormat,
    this.amountFormat,
    this.direction,
  );

  final String name;
  final String? delimiter;
  final Map<String, String> columns;
  final CsvDateFormat dateFormat;
  final CsvAmountFormat amountFormat;
  final CsvDirection direction;

  static const fields = [
    'description',
    'amount',
    'date',
    'due',
    'effective',
    'type',
    'category',
    'subcategory',
  ];

  factory CsvProfile.capture(
    String name,
    String? delimiter,
    List<String> headers,
    CsvMapping mapping,
  ) {
    mapping.validate(headers.length);
    final indexes = [
      mapping.description,
      mapping.amount,
      mapping.date,
      mapping.due,
      mapping.effective,
      mapping.type,
      mapping.category,
      mapping.subcategory,
    ];
    final columns = <String, String>{};
    for (var i = 0; i < fields.length; i++) {
      final index = indexes[i];
      if (index == null) continue;
      final header = headers[index].trim();
      if (header.isEmpty ||
          headers
                  .where((h) => csvNormalize(h) == csvNormalize(header))
                  .length !=
              1) {
        throw const FormatException(
          'O perfil precisa de nomes de colunas únicos e não vazios.',
        );
      }
      columns[fields[i]] = header;
    }
    return CsvProfile(
      name.trim(),
      delimiter,
      columns,
      mapping.dateFormat,
      mapping.amountFormat,
      mapping.direction,
    );
  }

  CsvMapping apply(List<String> headers) {
    int? find(String field) {
      final label = columns[field];
      if (label == null) return null;
      final matches = <int>[];
      for (var i = 0; i < headers.length; i++) {
        if (csvNormalize(headers[i]) == csvNormalize(label)) matches.add(i);
      }
      if (matches.length != 1) {
        throw FormatException(
          'Coluna "$label" do perfil "$name" ausente ou ambígua. Ajuste as colunas antes de importar.',
        );
      }
      return matches.single;
    }

    final mapping = CsvMapping(
      description: find('description'),
      amount: find('amount'),
      date: find('date'),
      due: find('due'),
      effective: find('effective'),
      type: find('type'),
      category: find('category'),
      subcategory: find('subcategory'),
      dateFormat: dateFormat,
      amountFormat: amountFormat,
      direction: direction,
    );
    mapping.validate(headers.length);
    return mapping;
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'delimiter': delimiter,
        'columns': columns,
        'dateFormat': dateFormat.name,
        'amountFormat': amountFormat.name,
        'direction': direction.name,
      };

  factory CsvProfile.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    if (name.trim().isEmpty || name.length > 80) {
      throw const FormatException('Nome de perfil inválido.');
    }
    final delimiter = json['delimiter'] as String?;
    if (delimiter != null && ![';', ',', '\t'].contains(delimiter)) {
      throw const FormatException('Separador de perfil inválido.');
    }
    final raw = json['columns'] as Map<String, dynamic>;
    final columns = <String, String>{};
    for (final entry in raw.entries) {
      if (!fields.contains(entry.key) || entry.value is! String) {
        throw const FormatException('Coluna de perfil inválida.');
      }
      columns[entry.key] = entry.value as String;
    }
    return CsvProfile(
      name.trim(),
      delimiter,
      columns,
      CsvDateFormat.values.byName(json['dateFormat'] as String),
      CsvAmountFormat.values.byName(json['amountFormat'] as String),
      CsvDirection.values.byName(json['direction'] as String),
    );
  }
}

class CsvProfileStore {
  CsvProfileStore(this.file);
  final File file;
  Future<void> _pending = Future.value();

  Future<List<CsvProfile>> load() async {
    await _pending;
    return _read();
  }

  Future<List<CsvProfile>> _read() async {
    if (!await file.exists()) return [];
    try {
      final json = jsonDecode(await file.readAsString()) as List<dynamic>;
      return json
          .map((v) => CsvProfile.fromJson(v as Map<String, dynamic>))
          .toList();
    } on FormatException {
      throw const FormatException(
        'Perfis de importação inválidos. O arquivo foi preservado.',
      );
    } on TypeError {
      throw const FormatException(
        'Perfis de importação inválidos. O arquivo foi preservado.',
      );
    } on ArgumentError {
      throw const FormatException(
        'Perfis de importação inválidos. O arquivo foi preservado.',
      );
    }
  }

  Future<void> save(CsvProfile profile) async {
    final operation = _pending.then((_) async {
      final profiles = await _read();
      profiles.removeWhere(
        (p) => csvNormalize(p.name) == csvNormalize(profile.name),
      );
      profiles.add(profile);
      profiles.sort((a, b) => a.name.compareTo(b.name));
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode(profiles.map((p) => p.toJson()).toList()),
        flush: true,
      );
      await temporary.rename(file.path);
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
