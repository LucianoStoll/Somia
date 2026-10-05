import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../domain/balance_details.dart';
import '../domain/balances_snapshot.dart';
import 'sqlite_balances_repository.dart';

/// Chamado dentro da transação do dashboard, com o mesmo snapshot e corte.
Future<Map<String, BalanceDetails>> loadBalanceDetails(
    AppDatabase db, DateTime month, BalancesSnapshot snapshot) async {
  final start = DateTime.utc(month.year, month.month).millisecondsSinceEpoch;
  final end = DateTime.utc(month.year, month.month + 1).millisecondsSinceEpoch;
  final previous = await SqliteBalancesRepository(db).calculate(
      asOf: DateTime.utc(month.year, month.month, 0),
      through: DateTime.utc(month.year, month.month, 0));
  final openings = {
    for (final c in previous.consolidated) c.currencyCode: c.currentMinor
  };
  final values = <String, Map<String, int>>{};
  Future<void> collect(String sql, List<int> args) async {
    final rows = await db
        .customSelect(sql, variables: args.map(Variable.withInt).toList())
        .get();
    for (final r in rows) {
      final byKind =
          values.putIfAbsent(r.read<String>('currency_code'), () => {});
      byKind.update(r.read<String>('kind'), (v) => v + r.read<int>('amount'),
          ifAbsent: () => r.read<int>('amount'));
    }
  }

  await collect(
      '''SELECT a.currency_code,t.type AS kind,SUM(t.actual_amount_minor) AS amount
    FROM transactions t JOIN accounts a ON a.id=t.account_id
    WHERE a.deleted_at IS NULL AND a.include_in_balance=1 AND t.deleted_at IS NULL
      AND t.ignore_balance=0 AND t.actual_amount_minor IS NOT NULL
      AND t.effective_at>=? AND t.effective_at<? GROUP BY a.currency_code,t.type''',
      [start, end]);
  await collect(
      '''SELECT a.currency_code,'pending_'||t.type AS kind,SUM(t.planned_amount_minor) AS amount
    FROM transactions t JOIN accounts a ON a.id=t.account_id
    WHERE a.deleted_at IS NULL AND a.include_in_balance=1 AND t.deleted_at IS NULL AND t.ignore_balance=0
      AND (t.effective_at IS NULL OR t.effective_at>=?) AND COALESCE(t.effective_at,t.due_at)<?
    GROUP BY a.currency_code,t.type''', [end, end]);
  // Uma linha por lado incluído. Transferências internas se compensam.
  await collect('''SELECT a.currency_code,
      CASE WHEN f.effective_at IS NULL OR f.effective_at>=? THEN 'pending_' ELSE '' END ||
      CASE WHEN f.destination_account_id=a.id THEN 'transfer_in' ELSE 'transfer_out' END AS kind,
      SUM(f.amount_minor) AS amount
    FROM transfers f JOIN accounts a ON a.id=f.source_account_id OR a.id=f.destination_account_id
    WHERE a.deleted_at IS NULL AND a.include_in_balance=1 AND f.deleted_at IS NULL
      AND ((f.effective_at>=? AND f.effective_at<?) OR
        ((f.effective_at IS NULL OR f.effective_at>=?) AND COALESCE(f.effective_at,f.due_at)<?))
    GROUP BY a.currency_code,kind''', [end, start, end, end, end]);
  await collect(
      '''SELECT a.currency_code,'card_payments' AS kind,SUM(p.amount_minor) AS amount
    FROM card_payments p JOIN accounts a ON a.id=p.account_id
    WHERE a.deleted_at IS NULL AND a.include_in_balance=1 AND p.deleted_at IS NULL
      AND p.effective_at>=? AND p.effective_at<? GROUP BY a.currency_code''',
      [start, end]);
  await collect('''SELECT a.currency_code,'pending_invoices' AS kind,SUM(MAX(0,
      COALESCE((SELECT SUM(e.amount_minor) FROM card_entries e JOIN card_invoices i ON i.id=e.invoice_id
        WHERE e.card_id=c.id AND e.deleted_at IS NULL AND i.due_at<?),0)
      -COALESCE((SELECT SUM(p.amount_minor) FROM card_payments p JOIN card_invoices i ON i.id=p.invoice_id
        WHERE i.card_id=c.id AND p.deleted_at IS NULL AND p.effective_at<?),0))) AS amount
    FROM credit_cards c JOIN accounts a ON a.id=c.payment_account_id
    WHERE a.deleted_at IS NULL AND a.include_in_balance=1 AND c.deleted_at IS NULL GROUP BY a.currency_code''',
      [end, end]);
  final result = <String, BalanceDetails>{};
  for (final c in snapshot.consolidated) {
    final v = values[c.currencyCode] ?? {};
    final details = BalanceDetails(
        openingMinor: openings[c.currencyCode] ?? 0,
        incomeMinor: v['income'] ?? 0,
        expenseMinor: v['expense'] ?? 0,
        transferInMinor: v['transfer_in'] ?? 0,
        transferOutMinor: v['transfer_out'] ?? 0,
        cardPaymentsMinor: v['card_payments'] ?? 0,
        pendingIncomeMinor: v['pending_income'] ?? 0,
        pendingExpenseMinor: v['pending_expense'] ?? 0,
        pendingTransferInMinor: v['pending_transfer_in'] ?? 0,
        pendingTransferOutMinor: v['pending_transfer_out'] ?? 0,
        pendingInvoicesMinor: v['pending_invoices'] ?? 0);
    assert(details.currentMinor == c.currentMinor,
        'Composição do saldo efetivado divergente');
    assert(details.projectedMinor == c.projectedMinor,
        'Composição do saldo previsto divergente');
    result[c.currencyCode] = details;
  }
  return result;
}
