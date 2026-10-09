import 'dart:math' as math;
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../accounts/data/sqlite_accounts_repository.dart';
import '../domain/expense_analysis.dart';

class ExpenseAnalysisRepository {
  ExpenseAnalysisRepository(this.db, {DateTime Function()? now})
      : now = now ?? DateTime.now;
  final AppDatabase db;
  final DateTime Function() now;
  int day(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch;
  Future<ExpenseAnalysis> load(DateTime selected) => db.transaction(() async {
        final month = DateTime(selected.year, selected.month);
        final start = day(DateTime(month.year, month.month - 3)),
            end = day(DateTime(month.year, month.month + 1));
        // Same financial basis as Resumo: effective date, or due date if pending.
        // Split allocations retain the source identity for the detail list.
        final rows = await db.customSelect(r'''
      WITH allocated AS (
        SELECT t.*, json_extract(p.value,'$.categoryId') cid, json_extract(p.value,'$.amountMinor') amount
        FROM transaction_events t,json_each(t.allocations_json) p
        UNION ALL SELECT t.*,t.category_id,COALESCE(t.actual_amount_minor,t.planned_amount_minor)
        FROM transaction_events t WHERE json_array_length(t.allocations_json)=0)
      SELECT t.id,t.description,a.name source,a.currency_code currency,
        COALESCE(t.effective_at,t.due_at) date,COALESCE(parent.name,c.name,'Sem categoria') category,
        CASE WHEN c.parent_id IS NOT NULL THEN c.name ELSE 'Sem subcategoria' END subcategory,t.amount
      FROM allocated t JOIN accounts a ON a.id=t.account_id
      LEFT JOIN categories c ON c.id=t.cid LEFT JOIN categories parent ON parent.id=c.parent_id
      WHERE t.type='expense' AND t.deleted_at IS NULL AND t.ignore_analytics=0
        AND a.deleted_at IS NULL AND a.include_in_analytics=1
        AND COALESCE(t.effective_at,t.due_at)>=? AND COALESCE(t.effective_at,t.due_at)<?
      UNION ALL
      SELECT e.id,e.description,'Cartão '||cc.name,'BRL',i.due_at,
        COALESCE(parent.name,c.name,'Sem categoria'),
        CASE WHEN c.parent_id IS NOT NULL THEN c.name ELSE 'Sem subcategoria' END,
        CASE WHEN p.value IS NULL THEN e.amount_minor
          WHEN e.amount_minor<0 THEN -json_extract(p.value,'$.amountMinor') ELSE json_extract(p.value,'$.amountMinor') END
      FROM card_entries e JOIN card_invoices i ON i.id=e.invoice_id JOIN credit_cards cc ON cc.id=e.card_id
      LEFT JOIN json_each(e.allocations_json) p ON 1=1
      LEFT JOIN categories c ON c.id=COALESCE(json_extract(p.value,'$.categoryId'),e.category_id)
      LEFT JOIN categories parent ON parent.id=c.parent_id
      WHERE e.deleted_at IS NULL AND cc.deleted_at IS NULL AND e.kind<>'opening' AND i.due_at>=? AND i.due_at<?
    ''', variables: [
          Variable.withInt(start),
          Variable.withInt(end),
          Variable.withInt(start),
          Variable.withInt(end)
        ]).get();
        AnalysisExpense map(QueryRow r) => AnalysisExpense(
            id: r.read<String>('id'),
            description: r.read<String>('description'),
            source: r.read<String>('source'),
            currency: r.read<String>('currency'),
            date: DateTime.fromMillisecondsSinceEpoch(r.read<int>('date'),
                isUtc: true),
            category: r.read<String>('category'),
            subcategory: r.read<String>('subcategory'),
            amount: r.read<int>('amount'));
        final futureStart = day(DateTime(month.year, month.month + 1)),
            futureEnd = day(DateTime(month.year, month.month + 7));
        final tomorrow = day(DateTime(now().year, now().month, now().day + 1));
        final pending = await db.customSelect('''
      SELECT t.id,t.description,a.name source,a.currency_code currency,COALESCE(t.effective_at,t.due_at) date,
        'Despesa' category,'Pendente' subcategory,COALESCE(t.actual_amount_minor,t.planned_amount_minor) amount
      FROM transaction_events t JOIN accounts a ON a.id=t.account_id
      WHERE t.type='expense' AND t.deleted_at IS NULL AND t.ignore_balance=0
        AND t.ignore_analytics=0 AND a.deleted_at IS NULL AND a.include_in_analytics=1
        AND (t.effective_at IS NULL OR t.effective_at>=?)
        AND COALESCE(t.effective_at,t.due_at)>=? AND COALESCE(t.effective_at,t.due_at)<?
    ''', variables: [
          Variable.withInt(tomorrow),
          Variable.withInt(futureStart),
          Variable.withInt(futureEnd)
        ]).get();
        final cardRows = await db.customSelect('''
      SELECT i.id,i.card_id,i.due_at,c.name,
        COALESCE((SELECT SUM(e.amount_minor) FROM card_entries e WHERE e.invoice_id=i.id AND e.deleted_at IS NULL),0)
        -COALESCE((SELECT SUM(p.amount_minor) FROM card_payments p WHERE p.invoice_id=i.id AND p.deleted_at IS NULL AND p.effective_at<?),0) amount
      FROM card_invoices i JOIN credit_cards c ON c.id=i.card_id
      WHERE c.deleted_at IS NULL AND i.due_at<? ORDER BY i.card_id,i.month_at
    ''', variables: [
          Variable.withInt(tomorrow),
          Variable.withInt(futureEnd)
        ]).get();
        final cardPending = <AnalysisExpense>[];
        final credits = <String, int>{};
        for (final r in cardRows) {
          final id = r.read<String>('card_id'), date = r.read<int>('due_at');
          final net = r.read<int>('amount') + (credits[id] ?? 0);
          credits[id] = math.min(0, net);
          // Each invoice's unpaid charges once; never repeat overdue carry-over.
          if (date >= futureStart && net > 0)
            cardPending.add(AnalysisExpense(
                id: r.read<String>('id'),
                description: 'Fatura — ${r.read<String>('name')}',
                source: 'Cartão',
                currency: 'BRL',
                date: DateTime.fromMillisecondsSinceEpoch(date, isUtc: true),
                category: 'Cartão',
                subcategory: 'Fatura',
                amount: net));
        }
        final expenses = pending.map(map).toList();
        final accounts = await SqliteAccountsRepository(db)
            .list(asOf: DateTime(month.year, month.month + 1, 0));
        final codes = {
          ...accounts.map((a) => a.currencyCode),
          ...expenses.map((e) => e.currency),
          if (cardPending.isNotEmpty) 'BRL'
        };
        final commitments = <String, List<FutureCommitment>>{};
        for (final code in codes) {
          commitments[code] = [
            for (var i = 1; i <= 6; i++)
              FutureCommitment(
                  DateTime(month.year, month.month + i),
                  expenses
                      .where((e) =>
                          e.currency == code &&
                          e.date.year ==
                              DateTime(month.year, month.month + i).year &&
                          e.date.month ==
                              DateTime(month.year, month.month + i).month)
                      .toList(),
                  cardPending
                      .where((e) =>
                          e.currency == code &&
                          e.date.year ==
                              DateTime(month.year, month.month + i).year &&
                          e.date.month ==
                              DateTime(month.year, month.month + i).month)
                      .toList())
          ];
        }
        return ExpenseAnalysis(
            month, rows.map(map).toList(), commitments, accounts);
      });
}
