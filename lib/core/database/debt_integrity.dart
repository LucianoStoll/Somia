import 'app_database.dart';

/// Shared by local transaction edits and snapshot/sync imports. Deleted expenses
/// keep their link for history but neither reserve nor amortize principal.
Future<void> validateDebtFinancial(AppDatabase db) async {
  final now = DateTime.now();
  final today =
      DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch;
  final invalid = await db.customSelect('''
    SELECT 1 FROM debts d LEFT JOIN assets a ON a.id=d.asset_id
    WHERE d.deleted_at IS NULL AND (d.reference_at>$today OR
      (d.asset_id IS NOT NULL AND (a.id IS NULL OR a.deleted_at IS NOT NULL)))
    UNION ALL SELECT 1 FROM debt_payments p
    JOIN debts d ON d.id=p.debt_id JOIN transactions t ON t.id=p.transaction_id
    JOIN accounts a ON a.id=t.account_id
    WHERE p.deleted_at IS NULL AND (d.deleted_at IS NOT NULL OR
      (t.deleted_at IS NULL AND (t.type<>'expense' OR a.currency_code<>'BRL'
       OR EXISTS(SELECT 1 FROM transaction_settlements s WHERE s.transaction_id=t.id AND s.deleted_at IS NULL)
       OR p.principal_minor>t.planned_amount_minor
       OR (t.actual_amount_minor IS NOT NULL AND p.principal_minor>t.actual_amount_minor)
       OR COALESCE(t.effective_at,t.due_at,t.posted_at)<d.reference_at)))
    UNION ALL SELECT 1 FROM debts d WHERE d.deleted_at IS NULL AND d.balance_minor<
      (SELECT COALESCE(SUM(p.principal_minor),0) FROM debt_payments p
       JOIN transactions t ON t.id=p.transaction_id
       WHERE p.debt_id=d.id AND p.deleted_at IS NULL AND t.deleted_at IS NULL)
    LIMIT 1
  ''').get();
  if (invalid.isNotEmpty) {
    throw const FormatException(
        'Vínculo de dívida incompatível. Confira amortização, valor, data, conta e saldo inicial; desvincule a parcela antes de alterar esses dados.');
  }
}
