import 'dart:convert';
import 'cashback_calculator.dart';

String encodeCashbackRule(CashbackRule rule) => jsonEncode({
      'rate': rule.rateBasisPoints,
      'tiers': [
        for (final tier in rule.tiers)
          [tier.minimumPaidMinor, tier.rateBasisPoints]
      ],
      'cap': rule.monthlyCapMinor,
      'schedule': rule.schedule.name,
      'day': rule.receiptDay,
    });

CashbackRule decodeCashbackRule(String value) {
  try {
    final map = jsonDecode(value) as Map<String, dynamic>;
    return CashbackRule(
      rateBasisPoints: map['rate'] as int,
      tiers: [
        for (final tier in map['tiers'] as List)
          CashbackTier(tier[0] as int, tier[1] as int)
      ],
      monthlyCapMinor: map['cap'] as int?,
      schedule: CashbackSchedule.values.byName(map['schedule'] as String),
      receiptDay: map['day'] as int,
    );
  } catch (_) {
    throw const FormatException('Regra de cashback inválida.');
  }
}
