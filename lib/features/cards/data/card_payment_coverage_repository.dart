import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';
import '../domain/cashback_calculator.dart';

class CardPaymentCoverageRepository {
  const CardPaymentCoverageRepository(this.db);
  final AppDatabase db;
  Future<Map<String, int>> available(String invoiceId,
          {String? exceptPayment}) async =>
      {
        for (final row in await db
            .customSelect('''SELECT e.id,MAX(0,e.amount_minor-COALESCE((
      SELECT SUM(a.amount_minor) FROM card_payment_allocations a JOIN card_payments p ON p.id=a.payment_id
      WHERE a.entry_id=e.id AND a.deleted_at IS NULL AND p.deleted_at IS NULL AND p.id<>?),0)) AS remaining
      FROM card_entries e WHERE e.invoice_id=? AND e.kind='purchase' AND e.deleted_at IS NULL''',
                variables: [
              Variable.withString(exceptPayment ?? ''),
              Variable.withString(invoiceId)
            ]).get())
          row.read<String>('id'): row.read<int>('remaining')
      };
  Future<void> allocate(String paymentId, Map<String, int>? chosen) async {
    final p = await db.customSelect(
        'SELECT * FROM card_payments WHERE id=? AND deleted_at IS NULL',
        variables: [Variable.withString(paymentId)]).getSingle();
    final availableItems =
        await available(p.read<String>('invoice_id'), exceptPayment: paymentId);
    final amount = p.read<int>('amount_minor');
    final total = availableItems.values.fold(0, (a, b) => a + b);
    final items = chosen ??
        (amount >= total
            ? {
                for (final e in availableItems.entries)
                  if (e.value > 0) e.key: e.value
              }
            : <String, int>{});
    if (chosen == null && amount < total) {
      final rules = await db.customSelect(
          '''SELECT r.id FROM cashback_rules r JOIN card_invoices i ON i.card_id=r.card_id
        WHERE i.id=? AND r.card_kind='credit' AND r.enabled=1 AND r.deleted_at IS NULL''',
          variables: [Variable.withString(p.read<String>('invoice_id'))]).get();
      if (rules.isNotEmpty) {
        throw StateError(
            'Pagamento parcial: abra a fatura e escolha as compras cobertas para calcular o cashback.');
      }
    }
    validatePaymentCoverage(
        paymentMinor: amount,
        allocationByEntry: items,
        availableByEntry: availableItems);
    final now = EntityMetadata.nowUtcMillis();
    for (final e in items.entries) {
      await db.customStatement(
          'INSERT INTO card_payment_allocations(id,payment_id,entry_id,amount_minor,created_at,updated_at) VALUES(?,?,?,?,?,?)',
          [
            'coverage-$paymentId-${e.key}',
            paymentId,
            e.key,
            e.value,
            now,
            now
          ]);
    }
  }
}
