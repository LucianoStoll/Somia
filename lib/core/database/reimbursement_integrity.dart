import 'app_database.dart';

Future<void> validateReimbursements(AppDatabase db) async {
  final invalid = await db.customSelect('''
    SELECT 1 FROM reimbursements r JOIN people p ON p.id=r.person_id
    LEFT JOIN transactions t ON t.id=r.transaction_id
    WHERE r.deleted_at IS NULL AND (p.deleted_at IS NOT NULL OR
      (r.transaction_id IS NOT NULL AND (t.type<>'expense' OR t.deleted_at IS NOT NULL)) OR
      (r.purchase_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM card_entries e
        WHERE e.purchase_id=r.purchase_id AND e.kind='purchase' AND e.deleted_at IS NULL)))
    UNION ALL SELECT 1 FROM reimbursements r JOIN transactions t ON t.id=r.transaction_id
    WHERE r.deleted_at IS NULL AND t.planned_amount_minor < (SELECT SUM(x.amount_minor)
      FROM reimbursements x WHERE x.transaction_id=r.transaction_id AND x.deleted_at IS NULL)
    UNION ALL SELECT 1 FROM reimbursements r WHERE r.deleted_at IS NULL AND r.purchase_id IS NOT NULL
      AND r.amount_minor > (SELECT COALESCE(SUM(e.amount_minor),0) FROM card_entries e
        WHERE e.purchase_id=r.purchase_id AND e.kind='purchase' AND e.deleted_at IS NULL)
    UNION ALL SELECT 1 FROM reimbursements r WHERE r.deleted_at IS NULL AND r.purchase_id IS NOT NULL
      AND (SELECT SUM(x.amount_minor) FROM reimbursements x WHERE x.purchase_id=r.purchase_id AND x.deleted_at IS NULL)
        > (SELECT COALESCE(SUM(e.amount_minor),0) FROM card_entries e WHERE e.purchase_id=r.purchase_id AND e.kind='purchase' AND e.deleted_at IS NULL)
    UNION ALL SELECT 1 FROM reimbursement_receipts l JOIN reimbursements r ON r.id=l.reimbursement_id
      JOIN transactions t ON t.id=l.transaction_id
    WHERE l.deleted_at IS NULL AND t.deleted_at IS NULL AND (r.deleted_at IS NOT NULL OR t.type<>'income' OR
      (SELECT a.currency_code FROM accounts a WHERE a.id=t.account_id) <> COALESCE(
        (SELECT a.currency_code FROM transactions src JOIN accounts a ON a.id=src.account_id WHERE src.id=r.transaction_id),'BRL'))
    UNION ALL SELECT 1 FROM reimbursements r WHERE r.deleted_at IS NULL AND r.amount_minor <
      (SELECT COALESCE(SUM(t.planned_amount_minor),0) FROM reimbursement_receipts l JOIN transactions t ON t.id=l.transaction_id
       WHERE l.reimbursement_id=r.id AND l.deleted_at IS NULL AND t.deleted_at IS NULL)
    LIMIT 1''').get();
  if (invalid.isNotEmpty) {
    throw const FormatException(
        'Reembolso incompatível. Confira a despesa, a pessoa, a moeda e os recebimentos vinculados. Remova os vínculos antes de excluir a despesa.');
  }
}
