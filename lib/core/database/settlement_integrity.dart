import '../allocations/category_allocation.dart';
import 'app_database.dart';

/// Also runs on restore and sync: partial payments must never duplicate a full
/// effectuation or exceed the original transaction, even across devices.
Future<void> validateSettlements(AppDatabase db) async {
  final invalid =
      await db.customSelect('''SELECT 1 FROM transaction_settlements s
    JOIN transactions t ON t.id=s.transaction_id
    JOIN accounts a ON a.id=s.account_id JOIN accounts original ON original.id=t.account_id
    WHERE s.deleted_at IS NULL AND (
      a.currency_code<>original.currency_code OR a.deleted_at IS NOT NULL OR
      t.effective_at IS NOT NULL OR t.actual_amount_minor IS NOT NULL OR
      EXISTS(SELECT 1 FROM debt_payments p WHERE p.transaction_id=t.id AND p.deleted_at IS NULL))
    UNION ALL SELECT 1 FROM transactions t WHERE t.planned_amount_minor<
      (SELECT COALESCE(SUM(s.amount_minor),0) FROM transaction_settlements s WHERE s.transaction_id=t.id AND s.deleted_at IS NULL)
    LIMIT 1''').get();
  if (invalid.isNotEmpty) {
    throw const FormatException(
        'Baixa incompatível. Confira valor, moeda e vínculos; desfaça a efetivação integral ou desvincule a amortização antes de registrar baixas parciais.');
  }
  final rows =
      await db.customSelect('''SELECT s.*,t.allocations_json AS original_parts
    FROM transaction_settlements s JOIN transactions t ON t.id=s.transaction_id
    WHERE s.deleted_at IS NULL''').get();
  final sums = <String, Map<String, int>>{};
  final originals = <String, List<CategoryAllocation>>{};
  for (final r in rows) {
    final id = r.read<String>('transaction_id');
    final parts = CategoryAllocation.decode(r.read<String>('allocations_json'));
    final original =
        CategoryAllocation.decode(r.read<String>('original_parts'));
    originals[id] = original;
    CategoryAllocation.validate(parts, r.read<int>('amount_minor'));
    if (parts.isEmpty != original.isEmpty ||
        parts.any((p) => !original.any((o) => o.categoryId == p.categoryId))) {
      throw const FormatException(
          'Rateio da baixa incompatível com o lançamento.');
    }
    final sum = sums.putIfAbsent(id, () => {});
    for (final p in parts) {
      sum[p.categoryId] = (sum[p.categoryId] ?? 0) + p.amountMinor;
    }
  }
  for (final id in sums.keys) {
    if (originals[id]!
        .any((p) => (sums[id]![p.categoryId] ?? 0) > p.amountMinor)) {
      throw const FormatException('As baixas excedem uma categoria do rateio.');
    }
  }
}
