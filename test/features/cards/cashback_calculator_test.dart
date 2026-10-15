import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/features/cards/domain/cashback_calculator.dart';

void main() {
  const calculator = CashbackCalculator();
  final today = DateTime.utc(2026, 10, 31);

  test('payment coverage accepts only selected eligible outstanding items', () {
    expect(
        validatePaymentCoverage(
            paymentMinor: 10000,
            allocationByEntry: {'a': 2000, 'b': 5000},
            availableByEntry: {'a': 3000, 'b': 5000}),
        7000);
    expect(
        validatePaymentCoverage(
            paymentMinor: 10000, allocationByEntry: {}, availableByEntry: {}),
        0);
    expect(
        () => validatePaymentCoverage(
            paymentMinor: 10000,
            allocationByEntry: {'a': 6000, 'b': 5000},
            availableByEntry: {'a': 6000, 'b': 5000}),
        throwsArgumentError);
    expect(
        () => validatePaymentCoverage(
            paymentMinor: 10000,
            allocationByEntry: {'a': 6000},
            availableByEntry: {'a': 5000}),
        throwsArgumentError);
    expect(
        () => validatePaymentCoverage(
            paymentMinor: 10000,
            allocationByEntry: {'another-invoice': 1},
            availableByEntry: {'a': 5000}),
        throwsArgumentError);
  });

  List<CashbackEntitlement> calculate({
    required List<CashbackPurchase> purchases,
    required List<CashbackPayment> payments,
    CashbackRule? rule,
    DateTime? asOf,
  }) =>
      calculator.calculate(
        rule: rule ?? CashbackRule(rateBasisPoints: 100),
        purchases: purchases,
        payments: payments,
        asOf: asOf ?? today,
      );

  test('first partial payment activates the full purchase only once', () {
    final result = calculate(
      purchases: [const CashbackPurchase(id: 'p', totalMinor: 100000)],
      payments: [
        CashbackPayment('p', 10000, DateTime.utc(2026, 10, 2)),
        CashbackPayment('p', 10000, DateTime.utc(2026, 10, 10)),
      ],
    );
    expect(result.single.amountMinor, 1000);
    expect(result.single.firstPayment, DateTime.utc(2026, 10, 2));
  });

  test('tier base uses paid cents rather than the activated purchase', () {
    final rule = CashbackRule(
      rateBasisPoints: 100,
      tiers: [const CashbackTier(50000, 200)],
    );
    final purchases = [const CashbackPurchase(id: 'p', totalMinor: 100000)];
    final payments = [CashbackPayment('p', 10000, DateTime.utc(2026, 10, 2))];
    expect(
        calculate(purchases: purchases, payments: payments, rule: rule)
            .single
            .amountMinor,
        1000);
    payments.add(CashbackPayment('p', 40000, DateTime.utc(2026, 10, 10)));
    expect(
        calculate(purchases: purchases, payments: payments, rule: rule)
            .single
            .amountMinor,
        2000);
  });

  test('later monthly payments do not create another receipt', () {
    final result = calculate(
      purchases: [const CashbackPurchase(id: 'p', totalMinor: 100000)],
      payments: [
        CashbackPayment('p', 10000, DateTime.utc(2026, 9, 2)),
        CashbackPayment('p', 10000, DateTime.utc(2026, 10, 2)),
      ],
      rule: CashbackRule(
          rateBasisPoints: 100,
          schedule: CashbackSchedule.nextMonth,
          receiptDay: 31),
    );
    expect(result, hasLength(1));
    expect(result.single.receiptDate, DateTime.utc(2026, 10, 31));
  });

  test('monthly receipt clamps day 31 and crosses the year boundary', () {
    final rule = CashbackRule(
        rateBasisPoints: 100,
        schedule: CashbackSchedule.nextMonth,
        receiptDay: 31);
    expect(
        rule.receiptFor(DateTime.utc(2028, 1, 31)), DateTime.utc(2028, 2, 29));
    expect(
        rule.receiptFor(DateTime.utc(2026, 12, 31)), DateTime.utc(2027, 1, 31));
  });

  test('scheduled payment is excluded until its effective date', () {
    final purchases = [const CashbackPurchase(id: 'p', totalMinor: 10000)];
    final payments = [CashbackPayment('p', 10000, DateTime.utc(2026, 11, 1))];
    expect(calculate(purchases: purchases, payments: payments), isEmpty);
    expect(
        calculate(
                purchases: purchases,
                payments: payments,
                asOf: DateTime.utc(2026, 11, 1))
            .single
            .amountMinor,
        100);
  });

  test('cap is proportional, stable and separate for each monthly cohort', () {
    final purchases = [
      const CashbackPurchase(id: 'b', totalMinor: 10000),
      const CashbackPurchase(id: 'a', totalMinor: 10000),
      const CashbackPurchase(id: 'c', totalMinor: 10000),
      const CashbackPurchase(id: 'd', totalMinor: 10000),
    ];
    final payments = [
      for (final p in purchases)
        CashbackPayment(
            p.id, 10000, DateTime.utc(2026, p.id == 'd' ? 9 : 10, 1)),
    ];
    final result = calculate(
        purchases: purchases,
        payments: payments,
        rule: CashbackRule(rateBasisPoints: 100, monthlyCapMinor: 100));
    expect({for (final r in result) r.purchaseId: r.amountMinor},
        {'a': 34, 'b': 33, 'c': 33, 'd': 100});
    expect(
        calculate(
                purchases: purchases.reversed.toList(),
                payments: payments.reversed.toList(),
                rule: CashbackRule(rateBasisPoints: 100, monthlyCapMinor: 100))
            .map((r) => r.amountMinor),
        result.map((r) => r.amountMinor));
  });

  test('refund reduces only its purchase while received rate is preserved', () {
    final result = calculate(
      purchases: [
        const CashbackPurchase(
            id: 'a',
            totalMinor: 10000,
            refundedMinor: 5000,
            confirmedRateBasisPoints: 200),
        const CashbackPurchase(
            id: 'b', totalMinor: 10000, confirmedRateBasisPoints: 200),
      ],
      payments: [
        CashbackPayment('a', 10000, DateTime.utc(2026, 10, 1)),
        CashbackPayment('b', 10000, DateTime.utc(2026, 10, 1)),
      ],
    );
    expect(result.map((r) => r.amountMinor), [100, 200]);
  });

  test('higher tier can increase a received purchase entitlement', () {
    final result = calculate(
      purchases: [
        const CashbackPurchase(
            id: 'p', totalMinor: 10000, confirmedRateBasisPoints: 100)
      ],
      payments: [CashbackPayment('p', 10000, DateTime.utc(2026, 10, 1))],
      rule: CashbackRule(
          rateBasisPoints: 100, tiers: [const CashbackTier(10000, 200)]),
    );
    expect(result.single.amountMinor, 200);
  });

  test('batch allocation preserves exact cents including large intermediates',
      () {
    expect(distributeMinor(1001, {'a': 100, 'b': 200}), {'a': 334, 'b': 667});
    expect(
        distributeMinor(
            9000000000000000, {'a': 9000000000000000, 'b': 9000000000000000}),
        {'a': 4500000000000000, 'b': 4500000000000000});
    expect(roundedRatio(9000000000000000, 10000, 10000), 9000000000000000);
    expect(roundedRatio(5, 1000, 10000), 1);
  });

  test('malformed rules, purchases and payment allocations are rejected', () {
    expect(() => CashbackRule(rateBasisPoints: 10001), throwsArgumentError);
    expect(() => CashbackRule(rateBasisPoints: 100, receiptDay: 0),
        throwsArgumentError);
    expect(
        () => CashbackRule(rateBasisPoints: 100, tiers: [
              const CashbackTier(100, 100),
              const CashbackTier(100, 200)
            ]),
        throwsArgumentError);
    expect(() => distributeMinor(1, {'a': 0}), throwsArgumentError);
    expect(
        () => calculate(purchases: [
              const CashbackPurchase(
                  id: 'a', totalMinor: 100, refundedMinor: 101),
            ], payments: []),
        throwsArgumentError);
    expect(
        () => calculate(purchases: [
              const CashbackPurchase(id: 'a', totalMinor: 100),
            ], payments: [
              CashbackPayment('a', 101, today)
            ]),
        throwsArgumentError);
    expect(
        () => calculate(
            purchases: [], payments: [CashbackPayment('unknown', 1, today)]),
        throwsArgumentError);
  });

  test('accepted confirmation difference never regenerates a pending value',
      () {
    final baseline = CashbackConfirmationBaseline(
        theoreticalMinor: 1000, receivedMinor: 800);
    expect(baseline.adjustmentFor(1000), 0);
    expect(baseline.adjustmentFor(2000), 1000);
    expect(baseline.adjustmentFor(900), -100);
    expect(
        baseline.refundFor(refundedMinor: 50000, purchaseMinor: 100000), 400);
    expect(
        baseline.refundFor(refundedMinor: 100000, purchaseMinor: 100000), 800);
  });

  test('refund lowers pending tiers but preserves other received percentages',
      () {
    final result = calculator.calculate(
      rule: CashbackRule(
          rateBasisPoints: 100, tiers: [const CashbackTier(20000, 200)]),
      purchases: [
        const CashbackPurchase(
            id: 'refunded', totalMinor: 10000, refundedMinor: 10000),
        const CashbackPurchase(id: 'pending', totalMinor: 10000),
        const CashbackPurchase(
            id: 'received', totalMinor: 10000, confirmedRateBasisPoints: 200),
      ],
      payments: [
        CashbackPayment('refunded', 10000, today),
        CashbackPayment('pending', 5000, today),
        CashbackPayment('received', 5000, today),
      ],
      tierRefunds: [CashbackTierRefund('refunded', 10000, today)],
      asOf: today,
    );
    expect({for (final r in result) r.purchaseId: r.amountMinor},
        {'pending': 100, 'received': 200, 'refunded': 0});
  });

  test('refund allocations cannot exceed their paid month or purchase', () {
    expect(
        () => calculator.calculate(
              rule: CashbackRule(rateBasisPoints: 100),
              purchases: [
                const CashbackPurchase(
                    id: 'p', totalMinor: 10000, refundedMinor: 1000)
              ],
              payments: [CashbackPayment('p', 1000, today)],
              tierRefunds: [CashbackTierRefund('p', 1001, today)],
              asOf: today,
            ),
        throwsArgumentError);
  });
}
