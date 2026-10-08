import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';
import '../../../core/database/planning_integrity.dart';
import '../../accounts/data/sqlite_accounts_repository.dart';
import '../domain/planning.dart';

class PlanningRepository {
  PlanningRepository(this.db, {DateTime Function()? now})
      : now = now ?? DateTime.now;
  final AppDatabase db;
  final DateTime Function() now;
  static int day(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch;
  static int month(DateTime d) => day(DateTime(d.year, d.month));
  Future<List<QueryRow>> rows(String sql, [List<Object> args = const []]) => db
      .customSelect(sql,
          variables: args
              .map((a) => a is int
                  ? Variable.withInt(a)
                  : Variable.withString(a as String))
              .toList())
      .get();
  Future<List<MonthlySpend>> spending(DateTime period) async {
    final start = month(period),
        end = month(DateTime(period.year, period.month + 1)),
        today = day(now().add(const Duration(days: 1)));
    final tx = await rows('''WITH allocated AS (
      SELECT t.*,json_extract(p.value,'\$.categoryId') cid,json_extract(p.value,'\$.amountMinor') amount FROM transaction_events t,json_each(t.allocations_json) p
      UNION ALL SELECT t.*,t.category_id,COALESCE(t.actual_amount_minor,t.planned_amount_minor) FROM transaction_events t WHERE json_array_length(t.allocations_json)=0)
      SELECT t.cid,c.parent_id,a.currency_code,t.type,
      SUM(CASE WHEN t.effective_at IS NOT NULL AND t.effective_at<? THEN t.amount ELSE 0 END) realized,SUM(t.amount) projected
      FROM allocated t JOIN accounts a ON a.id=t.account_id LEFT JOIN categories c ON c.id=t.cid
      WHERE t.deleted_at IS NULL AND a.deleted_at IS NULL AND a.include_in_analytics=1 AND t.ignore_analytics=0
      AND COALESCE(t.effective_at,t.due_at)>=? AND COALESCE(t.effective_at,t.due_at)<?
      GROUP BY t.cid,c.parent_id,a.currency_code,t.type''',
        [today, start, end]);
    final card = await rows('''WITH allocated AS (
      SELECT e.*,json_extract(p.value,'\$.categoryId') cid,CASE WHEN e.amount_minor<0 THEN -json_extract(p.value,'\$.amountMinor') ELSE json_extract(p.value,'\$.amountMinor') END amount FROM card_entries e,json_each(e.allocations_json) p
      UNION ALL SELECT e.*,e.category_id,e.amount_minor FROM card_entries e WHERE json_array_length(e.allocations_json)=0)
      SELECT e.cid,c.parent_id,'BRL' currency_code,'expense' type,
      SUM(CASE WHEN e.posted_at<? AND i.month_at<=? THEN e.amount ELSE 0 END) realized,SUM(e.amount) projected
      FROM allocated e JOIN card_invoices i ON i.id=e.invoice_id LEFT JOIN categories c ON c.id=e.cid
      WHERE e.deleted_at IS NULL AND e.kind<>'opening' AND i.due_at>=? AND i.due_at<? GROUP BY e.cid,c.parent_id''',
        [today, month(now()), start, end]);
    return [...tx, ...card]
        .map((r) => MonthlySpend(
            r.readNullable<String>('cid'),
            r.readNullable<String>('parent_id'),
            r.read<String>('currency_code'),
            r.read<String>('type'),
            r.read<int>('realized'),
            r.read<int>('projected')))
        .toList();
  }

  Future<List<BudgetLimit>> budgets(DateTime period) async {
    final spend = await spending(period);
    return (await rows(
            'SELECT b.*,c.name FROM budget_limits b JOIN categories c ON c.id=b.category_id WHERE b.deleted_at IS NULL AND b.month_at=? ORDER BY b.currency_code,lower(c.name)',
            [month(period)]))
        .map((r) {
      final id = r.read<String>('category_id'),
          code = r.read<String>('currency_code');
      final matching = spend.where(
          (s) => s.type == 'expense' && s.currency == code && s.matches(id));
      return BudgetLimit(
          r.read<String>('id'),
          id,
          r.read<String>('name'),
          code,
          r.read<int>('amount_minor'),
          matching.fold(0, (v, s) => v + s.realized),
          matching.fold(0, (v, s) => v + s.projected));
    }).toList();
  }

  Future<void> saveBudget(
          DateTime period, String category, String currency, int amount,
          {String? id}) =>
      db.transaction(() async {
        if (period.year < 2000 ||
            period.year > 2100 ||
            amount <= 0 ||
            amount > 9000000000000000 ||
            !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
          throw const FormatException(
              'Confira mês, moeda e limite do orçamento.');
        }
        if ((await rows(
                "SELECT id FROM categories WHERE id=? AND type='expense' AND is_archived=0 AND deleted_at IS NULL",
                [category]))
            .isEmpty) {
          throw const FormatException(
              'Escolha uma categoria de despesa ativa.');
        }
        final existing = await rows(
            'SELECT id FROM budget_limits WHERE category_id=? AND currency_code=? AND month_at=? AND deleted_at IS NULL',
            [category, currency, month(period)]);
        final key = id ??
            (existing.isEmpty ? null : existing.single.read<String>('id'));
        final at = EntityMetadata.nowUtcMillis();
        if (key == null) {
          await db.customStatement(
              'INSERT INTO budget_limits(id,category_id,month_at,currency_code,amount_minor,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',
              [
                EntityMetadata.newId(),
                category,
                month(period),
                currency,
                amount,
                at,
                at
              ]);
        } else {
          if ((await rows(
                  'SELECT id FROM budget_limits WHERE id=? AND deleted_at IS NULL AND month_at=?',
                  [key, month(period)]))
              .isEmpty) {
            throw const FormatException('Orçamento não encontrado neste mês.');
          }
          await db.customStatement(
              'UPDATE budget_limits SET category_id=?,currency_code=?,amount_minor=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [category, currency, amount, at, key]);
        }
        await validatePlanning(db);
      });
  Future<void> deleteBudget(String id) => db.customStatement(
      'UPDATE budget_limits SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
      [EntityMetadata.nowUtcMillis(), EntityMetadata.nowUtcMillis(), id]);
  Future<void> copyPrevious(DateTime period) => db.transaction(() async {
        final previous = await budgets(DateTime(period.year, period.month - 1));
        for (final b in previous) {
          if ((await rows(
                  'SELECT id FROM budget_limits WHERE deleted_at IS NULL AND month_at=? AND currency_code=? AND category_id=?',
                  [month(period), b.currency, b.categoryId]))
              .isEmpty) {
            await saveBudget(period, b.categoryId, b.currency, b.amount);
          }
        }
      });
  Future<String> saveGoal(GoalDraft draft, {String? id}) =>
      db.transaction(() async {
        if (draft.name.trim().isEmpty ||
            !['goal', 'reserve'].contains(draft.kind) ||
            draft.months < 1 ||
            draft.months > 36 ||
            draft.target < 0 ||
            draft.target > 9000000000000000 ||
            (draft.kind == 'goal' && draft.target == 0) ||
            draft.accounts.isEmpty ||
            draft.accounts.toSet().length != draft.accounts.length ||
            !RegExp(r'^[A-Z]{3}$').hasMatch(draft.currency)) {
          throw const FormatException(
              'Informe nome, objetivo e ao menos uma conta na mesma moeda.');
        }
        for (final account in draft.accounts) {
          if ((await rows(
                  'SELECT id FROM accounts WHERE id=? AND currency_code=? AND deleted_at IS NULL AND (is_archived=0 OR EXISTS(SELECT 1 FROM goal_accounts WHERE goal_id=? AND account_id=accounts.id AND deleted_at IS NULL))',
                  [account, draft.currency, id ?? '']))
              .isEmpty) {
            throw const FormatException(
                'Selecione contas ativas na moeda da meta.');
          }
        }
        final at = EntityMetadata.nowUtcMillis(),
            key = id ?? EntityMetadata.newId();
        final values = [
          draft.name.trim(),
          draft.kind,
          draft.currency,
          draft.target,
          draft.deadline == null ? null : day(draft.deadline!),
          draft.months,
          jsonEncode(draft.essential),
          at
        ];
        if (id == null) {
          await db.customStatement(
              'INSERT INTO planning_goals(name,kind,currency_code,target_minor,target_at,reserve_months,essential_json,updated_at,id,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)',
              [...values, key, at]);
        } else {
          if ((await rows(
                  'SELECT id FROM planning_goals WHERE id=? AND deleted_at IS NULL',
                  [id]))
              .isEmpty) {
            throw StateError('Meta não encontrada.');
          }
          await db.customStatement(
              'UPDATE planning_goals SET name=?,kind=?,currency_code=?,target_minor=?,target_at=?,reserve_months=?,essential_json=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [...values, key]);
        }
        final links = await rows(
            'SELECT * FROM goal_accounts WHERE goal_id=? AND deleted_at IS NULL',
            [key]);
        for (final l in links) {
          if (!draft.accounts.contains(l.read<String>('account_id'))) {
            await db.customStatement(
                'UPDATE goal_accounts SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
                [at, at, l.read<String>('id')]);
          }
        }
        for (final a in draft.accounts) {
          if (!links.any((l) => l.read<String>('account_id') == a)) {
            await db.customStatement(
                'INSERT INTO goal_accounts(id,goal_id,account_id,created_at,updated_at) VALUES(?,?,?,?,?)',
                [EntityMetadata.newId(), key, a, at, at]);
          }
        }
        await validatePlanning(db);
        return key;
      });
  Future<void> archiveGoal(PlanningGoal goal) => db.transaction(() async {
        await db.customStatement(
            'UPDATE planning_goals SET is_archived=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
            [goal.archived ? 0 : 1, EntityMetadata.nowUtcMillis(), goal.id]);
        await validatePlanning(db);
      });
  Future<void> deleteGoal(String id) => db.transaction(() async {
        final at = EntityMetadata.nowUtcMillis();
        await db.customStatement(
            'UPDATE goal_accounts SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE goal_id=? AND deleted_at IS NULL',
            [at, at, id]);
        await db.customStatement(
            'UPDATE planning_goals SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
            [at, at, id]);
      });
  Future<List<PlanningGoal>> goals() async {
    final accounts = await SqliteAccountsRepository(db).list();
    final previous = <MonthlySpend>[];
    for (var i = 1; i <= 3; i++) {
      previous.addAll(await spending(DateTime(now().year, now().month - i)));
    }
    final result = <PlanningGoal>[];
    for (final g in await rows(
        'SELECT * FROM planning_goals WHERE deleted_at IS NULL ORDER BY is_archived,kind,lower(name)')) {
      final ids =
          (jsonDecode(g.read<String>('essential_json')) as List).cast<String>();
      final code = g.read<String>('currency_code'),
          kind = g.read<String>('kind');
      final total = previous
          .where((s) =>
              s.type == 'expense' && s.currency == code && ids.any(s.matches))
          .fold<int>(0, (v, s) => v + s.realized);
      final average = total <= 0 ? 0 : (total + 1) ~/ 3;
      final links = await rows(
          'SELECT account_id FROM goal_accounts WHERE goal_id=? AND deleted_at IS NULL',
          [g.read<String>('id')]);
      final linked = links.map((l) => l.read<String>('account_id')).toList();
      final saved = accounts
          .where((a) => linked.contains(a.id))
          .fold<int>(0, (v, a) => v + a.currentBalanceMinor);
      final deadline = g.readNullable<int>('target_at');
      result.add(PlanningGoal(
          id: g.read<String>('id'),
          name: g.read<String>('name'),
          kind: kind,
          currency: code,
          target: kind == 'reserve'
              ? average * g.read<int>('reserve_months')
              : g.read<int>('target_minor'),
          saved: saved,
          months: g.read<int>('reserve_months'),
          essential: ids,
          accounts: linked,
          archived: g.read<int>('is_archived') == 1,
          deadline: deadline == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(deadline, isUtc: true),
          monthlyEssential: average));
    }
    return result;
  }
}
