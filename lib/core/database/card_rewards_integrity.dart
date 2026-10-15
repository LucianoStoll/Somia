import 'dart:convert';
import '../../features/cards/domain/cashback_rule_codec.dart';
import 'app_database.dart';
import 'package:drift/drift.dart';

Future<void> validateCardRewards(AppDatabase db) async {
  final bad = await db.customSelect('''
    SELECT 1 FROM debit_cards d JOIN accounts a ON a.id=d.account_id
      WHERE a.currency_code<>'BRL'
    UNION ALL SELECT 1 FROM debit_card_links l JOIN transactions t ON t.id=l.id
      JOIN accounts a ON a.id=t.account_id WHERE l.deleted_at IS NULL
      AND (t.type<>'expense' OR a.currency_code<>'BRL')
    UNION ALL SELECT 1 FROM card_payment_allocations a JOIN card_payments p ON p.id=a.payment_id
      WHERE a.deleted_at IS NULL AND p.deleted_at IS NULL AND
      (a.amount_minor>9000000000000000 OR p.amount_minor<(SELECT SUM(x.amount_minor)
        FROM card_payment_allocations x WHERE x.payment_id=p.id AND x.deleted_at IS NULL))
    UNION ALL SELECT 1 FROM card_payment_allocations a JOIN card_entries e ON e.id=a.entry_id
      JOIN card_payments p ON p.id=a.payment_id WHERE a.deleted_at IS NULL AND p.deleted_at IS NULL
      AND (e.kind<>'purchase' OR (e.invoice_id<>p.invoice_id AND NOT EXISTS(
        SELECT 1 FROM card_entry_history h WHERE h.entry_id=e.id AND h.previous_invoice_id=p.invoice_id)))
    UNION ALL SELECT 1 FROM card_entries e WHERE e.kind='purchase' AND
      (SELECT COALESCE(SUM(a.amount_minor),0) FROM card_payment_allocations a JOIN card_payments p ON p.id=a.payment_id WHERE a.entry_id=e.id AND a.deleted_at IS NULL AND p.deleted_at IS NULL)>
      MAX(e.amount_minor,COALESCE((SELECT MAX(MAX(COALESCE(h.previous_amount_minor,0),COALESCE(h.amount_minor,0))) FROM card_entry_history h WHERE h.entry_id=e.id),0))
    UNION ALL SELECT 1 FROM cashback_rules r JOIN accounts a ON a.id=r.account_id
      LEFT JOIN categories c ON c.id=r.category_id LEFT JOIN categories x ON x.id=r.return_category_id
      WHERE a.currency_code<>'BRL' OR (c.id IS NOT NULL AND c.type<>'income')
      OR (x.id IS NOT NULL AND x.type<>'expense')
      OR (r.card_kind='credit' AND NOT EXISTS(SELECT 1 FROM credit_cards k WHERE k.id=r.card_id))
      OR (r.card_kind='debit' AND NOT EXISTS(SELECT 1 FROM debit_cards k WHERE k.id=r.card_id))
    UNION ALL SELECT 1 FROM cashback_receipts r JOIN transactions t ON t.id=r.id
      JOIN accounts a ON a.id=t.account_id WHERE r.deleted_at IS NULL AND
      (a.currency_code<>'BRL' OR (r.kind='return' AND t.type<>'expense')
       OR (r.kind<>'return' AND t.type<>'income')
       OR (r.confirmed=1 AND (t.effective_at IS NULL OR t.deleted_at IS NOT NULL))
       OR (r.confirmed=0 AND (t.effective_at IS NOT NULL OR t.deleted_at IS NOT NULL OR t.actual_amount_minor IS NOT NULL))
       OR (r.confirmed=2 AND (t.deleted_at IS NULL OR t.effective_at IS NOT NULL OR t.actual_amount_minor IS NOT NULL)))
    LIMIT 1
  ''').get();
  if (bad.isNotEmpty) {
    throw StateError('Vínculos de cartão ou cashback inconsistentes.');
  }
  for (final row in await db
      .customSelect(
          'SELECT r.*,t.actual_amount_minor,t.effective_at,t.account_id,t.category_id FROM cashback_receipts r JOIN transactions t ON t.id=r.id WHERE r.deleted_at IS NULL')
      .get()) {
    final state = row.read<int>('confirmed');
    final raw = row.readNullable<String>('confirmation_json');
    if (state == 0) {
      if (raw != null) throw StateError('Confirmação pendente inconsistente.');
      continue;
    }
    if (raw == null) throw StateError('Histórico de cashback incompleto.');
    final snapshot = jsonDecode(raw);
    if (snapshot is! Map ||
        snapshot['amount'] is! int ||
        snapshot['date'] is! int) {
      throw StateError('Histórico de cashback inválido.');
    }
    if (snapshot['account'] != row.read<String>('account_id') ||
        snapshot['category'] != row.readNullable<String>('category_id') ||
        (state == 1 &&
            (snapshot['amount'] !=
                    row.readNullable<int>('actual_amount_minor') ||
                snapshot['date'] != row.readNullable<int>('effective_at'))) ||
        (state == 2 && snapshot['amount'] != 0)) {
      throw StateError(
          'Recebimento confirmado não pode ser alterado por edição ou sync parcial.');
    }
  }
  for (final claim in await db
      .customSelect('SELECT * FROM cashback_claims WHERE deleted_at IS NULL')
      .get()) {
    final receipts = await db.customSelect(
        'SELECT r.*,t.actual_amount_minor FROM cashback_receipts r JOIN transactions t ON t.id=r.id WHERE r.claim_id=? AND r.confirmed<>0 AND r.deleted_at IS NULL ORDER BY r.updated_at DESC,r.id DESC',
        variables: [Variable.withString(claim.read<String>('id'))]).get();
    if (receipts.isEmpty) continue;
    var net = 0;
    for (final r in receipts) {
      if (r.read<int>('confirmed') == 1) {
        net += (r.read<String>('kind') == 'return' ? -1 : 1) *
            r.read<int>('actual_amount_minor');
      }
    }
    final last = receipts.first;
    if (claim.read<int>('confirmed_theory_minor') !=
            last.read<int>('theory_minor') ||
        claim.read<int>('accepted_base_minor') !=
            last.read<int>('base_minor') ||
        claim.read<int>('accepted_difference_minor') !=
            net - last.read<int>('theory_minor')) {
      throw StateError(
          'Conflito na confirmação de cashback. Revise as alterações antes de sincronizar.');
    }
  }
  for (final row in await db
      .customSelect(
          'SELECT rule_json FROM cashback_rules UNION ALL SELECT rule_json FROM cashback_claims')
      .get()) {
    decodeCashbackRule(row.read<String>('rule_json'));
  }
}
