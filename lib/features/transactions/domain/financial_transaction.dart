import '../../../core/series/movement_series.dart';

enum TransactionType {
  expense('Despesa'),
  income('Receita');

  const TransactionType(this.label);
  final String label;
}

enum TransactionStatus { all, effective, pending }

enum TransactionDateField { posted, due, effective }

class FinancialTransaction {
  const FinancialTransaction({
    required this.id,
    this.series,
    this.cardId,
    this.cardInvoiceMonth,
    this.cardInvoiceId,
    this.cardBalanceMinor = 0,
    this.cardScheduledMinor = 0,
    this.cardEntryCount = 0,
    this.cardLastPaymentId,
    this.cardPaymentSignature = '',
    required this.description,
    required this.type,
    required this.amountMinor,
    required this.date,
    this.dueDate,
    this.effectiveDate,
    required this.isEffective,
    required this.accountId,
    required this.accountName,
    required this.categoryId,
    required this.categoryName,
    required this.currencyCode,
  });

  final String id;
  final SeriesInfo? series;
  final String? cardId;
  final DateTime? cardInvoiceMonth;
  final String? cardInvoiceId, cardLastPaymentId;
  final int cardBalanceMinor, cardScheduledMinor, cardEntryCount;
  final String cardPaymentSignature;
  final String description;
  final TransactionType type;
  final int amountMinor;

  /// Data de lançamento, independente de `created_at`.
  final DateTime date;
  final DateTime? dueDate;
  final DateTime? effectiveDate;
  final bool isEffective;
  final String accountId;
  final String accountName;
  final String? categoryId;
  final String? categoryName;
  final String currencyCode;
}

class TransactionDraft {
  const TransactionDraft({
    required this.description,
    required this.type,
    required this.amountMinor,
    required this.date,
    this.dueDate,
    this.effectiveDate,
    required this.isEffective,
    this.seriesPlan,
    this.cardId,
    this.cardInvoiceMonth,
    this.cardFirstInstallment = 1,
    this.scope = SeriesScope.onlyThis,
    required this.accountId,
    this.categoryId,
  });

  final String description;
  final TransactionType type;
  final int amountMinor;
  final DateTime date;
  final DateTime? dueDate;
  final DateTime? effectiveDate;
  final bool isEffective;
  final SeriesPlan? seriesPlan;
  final String? cardId;
  final DateTime? cardInvoiceMonth;
  final int cardFirstInstallment;
  final SeriesScope scope;
  final String accountId;
  final String? categoryId;
}

class TransactionFilter {
  const TransactionFilter(
      {this.type,
      this.accountId,
      this.categoryId,
      this.status = TransactionStatus.all,
      this.from,
      this.to,
      this.dateField = TransactionDateField.due});

  final TransactionType? type;
  final String? accountId;
  final String? categoryId;
  final TransactionStatus status;
  final DateTime? from;
  final DateTime? to;
  final TransactionDateField dateField;
}
