import 'dart:convert';
import '../../accounts/domain/account.dart';
import '../../categories/domain/category.dart';
import '../../transactions/domain/financial_transaction.dart';
import 'csv_document.dart';

enum CsvDateFormat { dayFirst, iso, monthFirst }

enum CsvAmountFormat { comma, dot }

enum CsvDirection { signed, income, expense }

String csvNormalize(String text) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const to = 'aaaaaeeeeiiiiooooouuuuc';
  var value = text.trim().toLowerCase();
  for (var i = 0; i < from.length; i++) {
    value = value.replaceAll(from[i], to[i]);
  }
  return value.replaceAll(RegExp(r'\s+'), ' ');
}

class CsvMapping {
  CsvMapping(
      {this.description,
      this.amount,
      this.date,
      this.due,
      this.effective,
      this.type,
      this.category,
      this.subcategory,
      this.dateFormat = CsvDateFormat.dayFirst,
      this.amountFormat = CsvAmountFormat.comma,
      this.direction = CsvDirection.signed});
  int? description, amount, date, due, effective, type, category, subcategory;
  CsvDateFormat dateFormat;
  CsvAmountFormat amountFormat;
  CsvDirection direction;
  factory CsvMapping.suggest(List<String> headers) {
    int? find(List<String> names) {
      final i = headers.indexWhere((h) => names.contains(csvNormalize(h)));
      return i < 0 ? null : i;
    }

    return CsvMapping(
        description: find(['descricao', 'historico', 'description', 'memo']),
        amount: find(['valor', 'amount', 'valor do lancamento']),
        date: find([
          'data',
          'data de lancamento',
          'data do lancamento',
          'lancamento',
          'date'
        ]),
        due: find(['vencimento', 'data de vencimento', 'due date']),
        effective: find([
          'efetivacao',
          'data de efetivacao',
          'data de pagamento',
          'effective date'
        ]),
        type: find(['tipo', 'type', 'natureza']),
        category: find(['categoria', 'category']),
        subcategory: find(['subcategoria', 'subcategory']));
  }
  void validate(int columns) {
    if (description == null || amount == null || date == null) {
      throw const FormatException(
          'Escolha as colunas de descrição, valor e data.');
    }
    final selected = [
      description,
      amount,
      date,
      due,
      effective,
      type,
      category,
      subcategory
    ].whereType<int>().toList();
    if (selected.any((i) => i < 0 || i >= columns) ||
        selected.toSet().length != selected.length) {
      throw const FormatException('Use uma coluna diferente para cada campo.');
    }
  }

  CsvCandidate parse(CsvRawRow row, int columns) {
    if (row.cells.length != columns) {
      throw const FormatException(
          'Quantidade de colunas diferente do cabeçalho.');
    }
    String value(int? i) => i == null ? '' : row.cells[i].trim();
    final history = value(description);
    if (history.isEmpty) throw const FormatException('Descrição vazia.');
    final signedAmount = parseAmount(value(amount), amountFormat);
    if (signedAmount == 0) {
      throw const FormatException('Valor deve ser diferente de zero.');
    }
    TransactionType movement;
    if (type != null) {
      movement = switch (csvNormalize(value(type))) {
        'receita' ||
        'income' ||
        'credito' ||
        'credit' ||
        'entrada' ||
        'c' =>
          TransactionType.income,
        'despesa' ||
        'expense' ||
        'debito' ||
        'debit' ||
        'saida' ||
        'd' =>
          TransactionType.expense,
        _ => throw const FormatException(
            'Tipo desconhecido; informe receita ou despesa.'),
      };
    } else {
      movement = switch (direction) {
        CsvDirection.income => TransactionType.income,
        CsvDirection.expense => TransactionType.expense,
        CsvDirection.signed =>
          signedAmount < 0 ? TransactionType.expense : TransactionType.income,
      };
    }
    if (signedAmount < 0 && movement == TransactionType.income) {
      throw const FormatException('Valor negativo não pode ser receita.');
    }
    final posted = parseDate(value(date), dateFormat);
    final dueDate =
        value(due).isEmpty ? posted : parseDate(value(due), dateFormat);
    final effectiveDate = value(effective).isEmpty
        ? null
        : parseDate(value(effective), dateFormat);
    return CsvCandidate(
        line: row.line,
        description: history,
        type: movement,
        amountMinor: signedAmount.abs(),
        date: posted,
        dueDate: dueDate,
        effectiveDate: effectiveDate,
        categoryText: value(category),
        subcategoryText: value(subcategory));
  }

  static int parseAmount(String text, CsvAmountFormat format) {
    var value = text
        .trim()
        .replaceFirst(RegExp(r'^R\$\s*', caseSensitive: false), '')
        .trim();
    var negative = false;
    if (value.startsWith('(') && value.endsWith(')')) {
      negative = true;
      value = value.substring(1, value.length - 1);
    }
    if (value.startsWith('-') || value.startsWith('+')) {
      if (negative) throw const FormatException('Sinal do valor inválido.');
      negative = value.startsWith('-');
      value = value.substring(1);
    }
    final pattern = format == CsvAmountFormat.comma
        ? r'^(?:\d+|\d{1,3}(?:\.\d{3})+)(?:,\d{1,2})?$'
        : r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$';
    if (!RegExp(pattern).hasMatch(value)) {
      throw const FormatException('Valor inválido. Confira o formato decimal.');
    }
    value = format == CsvAmountFormat.comma
        ? value.replaceAll('.', '').replaceAll(',', '.')
        : value.replaceAll(',', '');
    final parts = value.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null || whole > 90000000000000) {
      throw const FormatException('Valor acima do limite.');
    }
    final minor = whole * 100 +
        (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
    if (minor > 9000000000000000) {
      throw const FormatException('Valor acima do limite.');
    }
    return negative ? -minor : minor;
  }

  static DateTime parseDate(String text, CsvDateFormat format) {
    final match = (format == CsvDateFormat.iso
            ? RegExp(r'^(\d{4})-(\d{2})-(\d{2})$')
            : RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$'))
        .firstMatch(text);
    if (match == null) {
      throw const FormatException(
          'Data inválida. Confira o formato escolhido.');
    }
    final a = int.parse(match.group(1)!),
        b = int.parse(match.group(2)!),
        c = int.parse(match.group(3)!);
    final (year, month, day) = switch (format) {
      CsvDateFormat.dayFirst => (c, b, a),
      CsvDateFormat.iso => (a, b, c),
      CsvDateFormat.monthFirst => (c, a, b),
    };
    final result = DateTime.utc(year, month, day);
    if (year < 1900 ||
        year > 2100 ||
        result.year != year ||
        result.month != month ||
        result.day != day) {
      throw const FormatException('Data inexistente ou fora de 1900–2100.');
    }
    return result;
  }
}

class CsvCandidate {
  const CsvCandidate(
      {required this.line,
      required this.description,
      required this.type,
      required this.amountMinor,
      required this.date,
      required this.dueDate,
      this.effectiveDate,
      this.categoryText = '',
      this.subcategoryText = ''});
  final int line, amountMinor;
  final String description, categoryText, subcategoryText;
  final TransactionType type;
  final DateTime date, dueDate;
  final DateTime? effectiveDate;
  // Ignore category and effectuation when spotting an already-entered movement.
  String fingerprint(String accountId) => jsonEncode([
        accountId,
        csvNormalize(description),
        type.name,
        amountMinor,
        date.millisecondsSinceEpoch,
        dueDate.millisecondsSinceEpoch
      ]);
  TransactionDraft draft(String accountId, String? categoryId) =>
      TransactionDraft(
          description: description,
          type: type,
          amountMinor: amountMinor,
          date: date,
          dueDate: dueDate,
          effectiveDate: effectiveDate,
          isEffective: effectiveDate != null,
          accountId: accountId,
          categoryId: categoryId);
}

class CsvPreviewRow {
  const CsvPreviewRow(
      {required this.line,
      this.candidate,
      this.error,
      this.warning,
      this.duplicate = false,
      this.selected = false,
      this.categoryId});
  final int line;
  final CsvCandidate? candidate;
  final String? error, warning, categoryId;
  final bool duplicate, selected;
  CsvPreviewRow select(bool value) => CsvPreviewRow(
      line: line,
      candidate: candidate,
      error: error,
      warning: warning,
      duplicate: duplicate,
      selected: value && candidate != null,
      categoryId: categoryId);
  CsvPreviewRow category(String? value) => CsvPreviewRow(
      line: line,
      candidate: candidate,
      error: error,
      warning: warning,
      duplicate: duplicate,
      selected: selected,
      categoryId: value);
}

class CsvReferences {
  const CsvReferences(this.accounts, this.categories);
  final List<Account> accounts;
  final List<FinanceCategory> categories;
}

class CsvImportResult {
  const CsvImportResult(this.imported, this.skipped);
  final int imported, skipped;
}

abstract interface class CsvImportRepository {
  Future<CsvReferences> references();
  Future<List<CsvPreviewRow>> preview(
      CsvDocument document, CsvMapping mapping, String accountId);
  Future<CsvImportResult> commit(List<CsvPreviewRow> rows, String accountId);
}
