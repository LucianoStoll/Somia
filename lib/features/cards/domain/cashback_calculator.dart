/// Monetary calculations use cents and rates in basis points (100 = 1%).
/// This module has no database or clock dependency; callers supply the facts.
class CashbackTier {
  const CashbackTier(this.minimumPaidMinor, this.rateBasisPoints);
  final int minimumPaidMinor;
  final int rateBasisPoints;
}

enum CashbackSchedule { firstPayment, nextMonth }

class CashbackRule {
  CashbackRule({
    required this.rateBasisPoints,
    List<CashbackTier> tiers = const [],
    this.monthlyCapMinor,
    this.schedule = CashbackSchedule.firstPayment,
    this.receiptDay = 1,
  }) : tiers = List.unmodifiable(tiers) {
    _rate(rateBasisPoints);
    if (monthlyCapMinor != null) _money(monthlyCapMinor!);
    if (receiptDay < 1 || receiptDay > 31) {
      throw ArgumentError('Dia de recebimento inválido.');
    }
    var previous = -1;
    for (final tier in tiers) {
      _money(tier.minimumPaidMinor);
      _rate(tier.rateBasisPoints);
      if (tier.minimumPaidMinor <= previous) {
        throw ArgumentError('Faixas devem ter limites crescentes e únicos.');
      }
      previous = tier.minimumPaidMinor;
    }
  }

  final int rateBasisPoints;
  final List<CashbackTier> tiers;
  final int? monthlyCapMinor;
  final CashbackSchedule schedule;
  final int receiptDay;

  int rateFor(int paidMinor) {
    _money(paidMinor);
    var result = rateBasisPoints;
    for (final tier in tiers) {
      if (paidMinor < tier.minimumPaidMinor) break;
      result = tier.rateBasisPoints;
    }
    return result;
  }

  DateTime receiptFor(DateTime firstPayment) {
    if (schedule == CashbackSchedule.firstPayment) {
      return DateTime.utc(
          firstPayment.year, firstPayment.month, firstPayment.day);
    }
    final next = DateTime.utc(firstPayment.year, firstPayment.month + 1);
    final lastDay = DateTime.utc(next.year, next.month + 1, 0).day;
    return DateTime.utc(
        next.year, next.month, receiptDay > lastDay ? lastDay : receiptDay);
  }
}

/// A payment allocation is the amount actually covered by one payment.
/// Later allocations affect monthly tiers but do not activate the purchase again.
class CashbackPayment {
  const CashbackPayment(this.purchaseId, this.amountMinor, this.date);
  final String purchaseId;
  final int amountMinor;
  final DateTime date;
}

/// Refund value attributed to paid spending in a particular month. The caller
/// resolves installment/payment coverage before invoking the calculator.
class CashbackTierRefund {
  const CashbackTierRefund(this.purchaseId, this.amountMinor, this.paidMonth);
  final String purchaseId;
  final int amountMinor;
  final DateTime paidMonth;
}

class CashbackPurchase {
  const CashbackPurchase({
    required this.id,
    required this.totalMinor,
    this.refundedMinor = 0,
    this.confirmedRateBasisPoints,
  });
  final String id;
  final int totalMinor;
  final int refundedMinor;

  /// A received purchase retains its percentage when refunds lower the tier.
  /// Higher tiers may still generate a complement.
  final int? confirmedRateBasisPoints;
}

class CashbackEntitlement {
  const CashbackEntitlement({
    required this.purchaseId,
    required this.firstPayment,
    required this.receiptDate,
    required this.rateBasisPoints,
    required this.amountMinor,
  });
  final String purchaseId;
  final DateTime firstPayment;
  final DateTime receiptDate;
  final int rateBasisPoints;
  final int amountMinor;
}

class CashbackCalculator {
  const CashbackCalculator();

  /// Calculates one purchase cohort per month of first payment.
  /// Scheduled payments do not count before their effective day.
  List<CashbackEntitlement> calculate({
    required CashbackRule rule,
    required List<CashbackPurchase> purchases,
    required List<CashbackPayment> payments,
    List<CashbackTierRefund> tierRefunds = const [],
    required DateTime asOf,
  }) {
    final byId = <String, CashbackPurchase>{};
    for (final purchase in purchases) {
      _money(purchase.totalMinor);
      _money(purchase.refundedMinor);
      if (purchase.id.isEmpty ||
          purchase.totalMinor == 0 ||
          purchase.refundedMinor > purchase.totalMinor ||
          byId.containsKey(purchase.id)) {
        throw ArgumentError('Compra inválida ou duplicada.');
      }
      if (purchase.confirmedRateBasisPoints != null) {
        _rate(purchase.confirmedRateBasisPoints!);
      }
      byId[purchase.id] = purchase;
    }
    final first = <String, DateTime>{};
    final monthlyPaid = <int, int>{};
    final paidPerPurchase = <String, int>{};
    final paidByPurchaseMonth = <String, Map<int, int>>{};
    final cutoff = _day(asOf);
    for (final payment in payments) {
      _money(payment.amountMinor);
      final purchase = byId[payment.purchaseId];
      if (purchase == null || payment.amountMinor == 0) {
        throw ArgumentError('Pagamento sem compra ou valor válido.');
      }
      final day = _day(payment.date);
      if (day.isAfter(cutoff)) continue;
      final paid = (paidPerPurchase[purchase.id] ?? 0) + payment.amountMinor;
      if (paid > purchase.totalMinor) {
        throw ArgumentError('Pagamento excede o valor da compra.');
      }
      paidPerPurchase[purchase.id] = paid;
      final old = first[purchase.id];
      if (old == null || day.isBefore(old)) first[purchase.id] = day;
      final key = _month(day);
      monthlyPaid[key] = (monthlyPaid[key] ?? 0) + payment.amountMinor;
      _money(monthlyPaid[key]!);
      final months = paidByPurchaseMonth[purchase.id] ??= {};
      months[key] = (months[key] ?? 0) + payment.amountMinor;
    }
    final refundedPaidByPurchase = <String, int>{};
    for (final refund in tierRefunds) {
      _money(refund.amountMinor);
      final purchase = byId[refund.purchaseId];
      final month = _month(refund.paidMonth);
      final months = paidByPurchaseMonth[refund.purchaseId];
      final paid = months?[month] ?? 0;
      final refunded =
          (refundedPaidByPurchase[refund.purchaseId] ?? 0) + refund.amountMinor;
      if (purchase == null ||
          refund.amountMinor > paid ||
          refunded > purchase.refundedMinor) {
        throw ArgumentError('Estorno excede a compra ou o pagamento coberto.');
      }
      refundedPaidByPurchase[refund.purchaseId] = refunded;
      if (months != null) months[month] = paid - refund.amountMinor;
      monthlyPaid[month] = (monthlyPaid[month] ?? 0) - refund.amountMinor;
    }
    final result = <CashbackEntitlement>[];
    final cohorts = <int, List<CashbackPurchase>>{};
    for (final purchase in purchases) {
      final date = first[purchase.id];
      if (date == null) continue;
      (cohorts[_month(date)] ??= []).add(purchase);
    }
    for (final cohort in cohorts.entries) {
      final rate = rule.rateFor(monthlyPaid[cohort.key] ?? 0);
      final amounts = <String, int>{};
      final rates = <String, int>{};
      for (final purchase in cohort.value) {
        final locked = purchase.confirmedRateBasisPoints ?? 0;
        final effectiveRate = locked > rate ? locked : rate;
        rates[purchase.id] = effectiveRate;
        amounts[purchase.id] = roundedRatio(
            purchase.totalMinor - purchase.refundedMinor, effectiveRate, 10000);
      }
      final total =
          amounts.values.fold(BigInt.zero, (a, b) => a + BigInt.from(b));
      final cap = rule.monthlyCapMinor;
      final capped = cap != null && total > BigInt.from(cap)
          ? distributeMinor(cap, amounts)
          : amounts;
      for (final purchase in cohort.value) {
        final date = first[purchase.id]!;
        result.add(CashbackEntitlement(
          purchaseId: purchase.id,
          firstPayment: date,
          receiptDate: rule.receiptFor(date),
          rateBasisPoints: rates[purchase.id]!,
          amountMinor: capped[purchase.id]!,
        ));
      }
    }
    result.sort((a, b) => a.purchaseId.compareTo(b.purchaseId));
    return result;
  }
}

/// Captures the theoretical value accepted at confirmation separately from
/// the actual deposit. Repeating a calculation never restores an accepted
/// difference. Persistence must update this snapshot when an adjustment is
/// confirmed and retain the original receipt as history.
class CashbackConfirmationBaseline {
  CashbackConfirmationBaseline({
    required this.theoreticalMinor,
    required this.receivedMinor,
  }) {
    _money(theoreticalMinor);
    _money(receivedMinor);
  }
  final int theoreticalMinor;
  final int receivedMinor;

  int adjustmentFor(int newTheoreticalMinor) {
    _money(newTheoreticalMinor);
    return newTheoreticalMinor - theoreticalMinor;
  }

  /// Returns the actual received value proportional to the refunded purchase,
  /// rather than replacing a user's accepted deposit with a calculated one.
  int refundFor({required int refundedMinor, required int purchaseMinor}) {
    _money(refundedMinor);
    _money(purchaseMinor);
    if (purchaseMinor == 0 || refundedMinor > purchaseMinor) {
      throw ArgumentError('Valor de estorno inválido.');
    }
    return roundedRatio(receivedMinor, refundedMinor, purchaseMinor);
  }
}

/// Half-up rounding with arbitrary-precision intermediates, including on web.
int roundedRatio(int amount, int numerator, int denominator) {
  _money(amount);
  if (numerator < 0 || denominator <= 0) {
    throw ArgumentError('Proporção inválida.');
  }
  final product = BigInt.from(amount) * BigInt.from(numerator);
  final divisor = BigInt.from(denominator);
  final result = (product * BigInt.two + divisor) ~/ (divisor * BigInt.two);
  if (result > BigInt.from(_maximumMinor)) {
    throw ArgumentError('Valor monetário fora do limite.');
  }
  return result.toInt();
}

/// Largest-remainder allocation, ties broken by stable identity rather than
/// input order. The allocated amounts always sum exactly to [totalMinor].
Map<String, int> distributeMinor(int totalMinor, Map<String, int> weights) {
  _money(totalMinor);
  var sum = BigInt.zero;
  for (final entry in weights.entries) {
    if (entry.key.isEmpty) throw ArgumentError('Identificador vazio.');
    _money(entry.value);
    sum += BigInt.from(entry.value);
  }
  if (sum == BigInt.zero) {
    if (totalMinor != 0) throw ArgumentError('Rateio sem base positiva.');
    return {for (final id in weights.keys) id: 0};
  }
  final result = <String, int>{};
  final remainders = <(String, BigInt)>[];
  var allocated = 0;
  for (final entry in weights.entries) {
    final product = BigInt.from(totalMinor) * BigInt.from(entry.value);
    final value = (product ~/ sum).toInt();
    result[entry.key] = value;
    allocated += value;
    remainders.add((entry.key, product % sum));
  }
  remainders.sort((a, b) {
    final byRemainder = b.$2.compareTo(a.$2);
    return byRemainder == 0 ? a.$1.compareTo(b.$1) : byRemainder;
  });
  for (var i = 0; i < totalMinor - allocated; i++) {
    final id = remainders[i].$1;
    result[id] = result[id]! + 1;
  }
  return result;
}

const _maximumMinor = 9000000000000000;
void _money(int value) {
  if (value < 0 || value > _maximumMinor) {
    throw ArgumentError('Valor monetário fora do limite.');
  }
}

void _rate(int value) {
  if (value < 0 || value > 10000) {
    throw ArgumentError('Percentual deve estar entre 0% e 100%.');
  }
}

DateTime _day(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
int _month(DateTime value) => value.year * 12 + value.month;
