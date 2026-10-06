import '../../../core/series/movement_series.dart';

class Transfer {
  const Transfer({
    required this.id,
    this.series,
    this.description = 'Transferência',
    required this.sourceAccountId,
    required this.sourceAccountName,
    required this.destinationAccountId,
    required this.destinationAccountName,
    required this.currencyCode,
    required this.amountMinor,
    required this.date,
    this.dueDate,
    this.effectiveDate,
    required this.isEffective,
  });

  final String id;
  final SeriesInfo? series;
  final String description;
  final String sourceAccountId;
  final String sourceAccountName;
  final String destinationAccountId;
  final String destinationAccountName;
  final String currencyCode;
  final int amountMinor;
  final DateTime date;
  final DateTime? dueDate;
  final DateTime? effectiveDate;
  final bool isEffective;
}

class TransferDraft {
  const TransferDraft({
    this.description = 'Transferência',
    required this.sourceAccountId,
    required this.destinationAccountId,
    required this.amountMinor,
    required this.date,
    this.dueDate,
    this.effectiveDate,
    required this.isEffective,
    this.seriesPlan,
    this.scope = SeriesScope.onlyThis,
  });

  final String description;
  final String sourceAccountId;
  final String destinationAccountId;
  final int amountMinor;
  final DateTime date;
  final DateTime? dueDate;
  final DateTime? effectiveDate;
  final bool isEffective;
  final SeriesPlan? seriesPlan;
  final SeriesScope scope;
}

enum TransferDateField { posted, due, effective }

class TransferFilter {
  const TransferFilter(
      {this.from,
      this.to,
      this.accountId,
      this.effective,
      this.dateField = TransferDateField.due});
  final DateTime? from;
  final DateTime? to;
  final String? accountId;
  final bool? effective;
  final TransferDateField dateField;

  bool matches(Transfer item) {
    final date = switch (dateField) {
      TransferDateField.posted => item.date,
      TransferDateField.due => item.dueDate ?? item.date,
      TransferDateField.effective => item.effectiveDate,
    };
    return (accountId == null ||
            item.sourceAccountId == accountId ||
            item.destinationAccountId == accountId) &&
        (effective == null || item.isEffective == effective) &&
        ((from == null && to == null) ||
            date != null &&
                (from == null ||
                    !DateTime(date.year, date.month, date.day)
                        .isBefore(from!)) &&
                (to == null ||
                    !DateTime(date.year, date.month, date.day).isAfter(to!)));
  }
}
