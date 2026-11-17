import 'dart:math' as math;
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../domain/monthly_cash_flow.dart';

/// Fonte única dos recebimentos/pagamentos do Resumo e de Movimentos.
class SqliteMonthlyCashFlowRepository implements MonthlyCashFlowRepository {
  const SqliteMonthlyCashFlowRepository(this.db, {this.asOf});
  final AppDatabase db;
  final DateTime? asOf;

  @override
  Future<Map<String, MonthlyCashFlow>> load(DateTime month) async {
    final today = asOf ?? DateTime.now();
    final start = DateTime.utc(month.year, month.month).millisecondsSinceEpoch;
    final end = math.min(
        DateTime.utc(month.year, month.month + 1).millisecondsSinceEpoch,
        DateTime.utc(today.year, today.month, today.day + 1)
            .millisecondsSinceEpoch);
    final rows = await db.customSelect('''
      WITH events AS (
        SELECT a.currency_code,t.type AS kind,t.actual_amount_minor AS amount
        FROM transaction_events t JOIN accounts a ON a.id=t.account_id
        WHERE a.deleted_at IS NULL AND a.include_in_balance=1
          AND t.deleted_at IS NULL AND t.ignore_balance=0
          AND t.actual_amount_minor IS NOT NULL
          AND t.effective_at>=? AND t.effective_at<?
        UNION ALL
        SELECT a.currency_code,'card_payment',p.amount_minor
        FROM card_payments p JOIN accounts a ON a.id=p.account_id
        WHERE a.deleted_at IS NULL AND a.include_in_balance=1
          AND p.deleted_at IS NULL AND p.effective_at>=? AND p.effective_at<?
      )
      SELECT codes.currency_code,
        COALESCE(SUM(CASE WHEN e.kind='income' THEN e.amount ELSE 0 END),0) AS income,
        COALESCE(SUM(CASE WHEN e.kind='expense' THEN e.amount ELSE 0 END),0) AS expense,
        COALESCE(SUM(CASE WHEN e.kind='card_payment' THEN e.amount ELSE 0 END),0) AS card_payments
      FROM (SELECT DISTINCT currency_code FROM accounts WHERE deleted_at IS NULL) codes
      LEFT JOIN events e ON e.currency_code=codes.currency_code
      GROUP BY codes.currency_code ORDER BY codes.currency_code
    ''', variables: [
      Variable.withInt(start),
      Variable.withInt(end),
      Variable.withInt(start),
      Variable.withInt(end)
    ]).get();
    return {
      for (final row in rows)
        row.read<String>('currency_code'): MonthlyCashFlow(
            incomeMinor: row.read<int>('income'),
            expenseMinor: row.read<int>('expense'),
            cardPaymentsMinor: row.read<int>('card_payments'))
    };
  }
}
