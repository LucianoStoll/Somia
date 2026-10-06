import 'dart:math' as math;

int cardDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch;
DateTime cardDate(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
DateTime calendarDay(int year, int month, int day) => DateTime.utc(
    year, month, math.min(day, DateTime.utc(year, month + 1, 0).day));

class CreditCard {
  const CreditCard(
      {required this.id,
      required this.name,
      required this.paymentAccountId,
      required this.closingDay,
      required this.dueDay,
      this.institutionId,
      this.limitMinor,
      this.isArchived = false,
      this.committedMinor = 0,
      this.creditMinor = 0});
  final String id, name, paymentAccountId;
  final String? institutionId;
  final int closingDay, dueDay;
  final int? limitMinor;
  final bool isArchived;
  final int committedMinor, creditMinor;
  int? get availableMinor =>
      limitMinor == null ? null : limitMinor! - committedMinor;

  /// A chave é o mês do vencimento, mesmo quando fecha no mês anterior.
  DateTime closingFor(DateTime month) => calendarDay(
      month.year, month.month - (dueDay <= closingDay ? 1 : 0), closingDay);
  DateTime dueFor(DateTime month) =>
      calendarDay(month.year, month.month, dueDay);
  DateTime invoiceMonthFor(DateTime purchaseDate) {
    var month = DateTime.utc(purchaseDate.year, purchaseDate.month);
    while (cardDay(closingFor(month)) <= cardDay(purchaseDate)) {
      month = DateTime.utc(month.year, month.month + 1);
    }
    return month;
  }
}

class CardDraft {
  const CardDraft(
      {required this.name,
      required this.paymentAccountId,
      required this.closingDay,
      required this.dueDay,
      this.limitMinor,
      this.institutionId});
  final String name, paymentAccountId;
  final int closingDay, dueDay;
  final int? limitMinor;
  final String? institutionId;
}

class CardEntry {
  const CardEntry(
      {required this.id,
      required this.cardId,
      required this.invoiceId,
      required this.purchaseId,
      required this.index,
      required this.count,
      required this.description,
      required this.kind,
      required this.amountMinor,
      required this.postedAt,
      required this.dueAt,
      required this.invoiceMonth,
      this.categoryId,
      this.categoryName,
      this.sourceId});
  final String id, cardId, invoiceId, purchaseId, description, kind;
  final int index, count, amountMinor;
  final DateTime postedAt, dueAt, invoiceMonth;
  final String? categoryId, categoryName, sourceId;
  String get label => count > 1
      ? 'Parcela ${index + 1}/$count'
      : switch (kind) {
          'opening' => 'Saldo inicial',
          'refund' => 'Estorno',
          'fee' => 'Encargo',
          'discount' => 'Desconto',
          _ => 'Compra',
        };
}

class CardPayment {
  const CardPayment(
      {required this.id,
      required this.amountMinor,
      required this.date,
      required this.accountName});
  final String id, accountName;
  final int amountMinor;
  final DateTime date;
}

class CardInvoice {
  const CardInvoice(
      {required this.id,
      required this.cardId,
      required this.month,
      required this.closingAt,
      required this.dueAt,
      required this.previousMinor,
      required this.chargesMinor,
      required this.paidMinor,
      required this.scheduledMinor,
      this.entries = const [],
      this.payments = const []});
  final String id, cardId;
  final DateTime month, closingAt, dueAt;
  final int previousMinor, chargesMinor, paidMinor, scheduledMinor;
  final List<CardEntry> entries;
  final List<CardPayment> payments;
  int get balanceMinor => previousMinor + chargesMinor - paidMinor;
  int get projectedMinor => balanceMinor - scheduledMinor;
  String get status {
    if (balanceMinor < 0) return 'Crédito';
    if (balanceMinor == 0 &&
        (paidMinor > 0 || entries.isNotEmpty || previousMinor != 0)) {
      return 'Paga';
    }
    if (cardDay(dueAt) < cardDay(DateTime.now()) && balanceMinor > 0) {
      return 'Atrasada';
    }
    if (paidMinor > 0 && balanceMinor > 0) return 'Parcial';
    return cardDay(closingAt) <= cardDay(DateTime.now()) ? 'Fechada' : 'Aberta';
  }
}

/// Desfazer restaura apenas os pagamentos tocados por esta ação.
class CardSettlement {
  const CardSettlement(
      {required this.invoiceId,
      required this.date,
      required this.shifted,
      this.newPaymentId,
      this.newAmountMinor = 0});
  final String invoiceId;
  final DateTime date;
  final List<(String, DateTime, int)> shifted;
  final String? newPaymentId;
  final int newAmountMinor;
}
