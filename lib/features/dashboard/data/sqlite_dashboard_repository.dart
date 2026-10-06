import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../accounts/domain/account.dart';
import '../../balances/data/sqlite_balance_details.dart';
import '../../balances/data/sqlite_balances_repository.dart';
import '../domain/dashboard_repository.dart';
import '../domain/entities/dashboard_summary.dart';

class SqliteDashboardRepository implements DashboardRepository {
  const SqliteDashboardRepository(this._db);

  final AppDatabase _db;

  @override
  Future<DashboardSummary> load(DateTime month) => _db.transaction(() async {
        final start =
            DateTime.utc(month.year, month.month).millisecondsSinceEpoch;
        final end =
            DateTime.utc(month.year, month.month + 1).millisecondsSinceEpoch;
        final monthEnd = DateTime.utc(month.year, month.month + 1, 0);
        final balances = await SqliteBalancesRepository(_db)
            .calculate(asOf: monthEnd, through: monthEnd);
        final details = await loadBalanceDetails(_db, month, balances);
        // Efetivados pertencem ao mês da efetivação; pendentes, ao vencimento.
        // A data de lançamento não define os totais nem os gráficos.
        final totals = <String, (int, int)>{};
        final period = await _db.customSelect('''
      SELECT a.currency_code, t.type, SUM(COALESCE(t.actual_amount_minor, t.planned_amount_minor)) AS amount_minor
      FROM transactions t JOIN accounts a ON a.id = t.account_id
      WHERE t.deleted_at IS NULL AND t.ignore_analytics = 0
        AND a.deleted_at IS NULL AND a.include_in_analytics = 1
        AND COALESCE(t.effective_at, t.due_at) >= ? AND COALESCE(t.effective_at, t.due_at) < ?
      GROUP BY a.currency_code, t.type
    ''', variables: [Variable.withInt(start), Variable.withInt(end)]).get();
        final cardPeriod = await _db.customSelect('''
          SELECT 'BRL' AS currency_code, 'expense' AS type, SUM(e.amount_minor) AS amount_minor
          FROM card_entries e JOIN card_invoices i ON i.id=e.invoice_id
          WHERE e.deleted_at IS NULL AND e.kind <> 'opening' AND i.due_at >= ? AND i.due_at < ?
          HAVING COUNT(*) > 0
        ''', variables: [Variable.withInt(start), Variable.withInt(end)]).get();
        for (final row in [...period, ...cardPeriod]) {
          final currency = row.read<String>('currency_code');
          final previous = totals[currency] ?? (0, 0);
          final amount = row.read<int>('amount_minor');
          totals[currency] = row.read<String>('type') == 'income'
              ? (previous.$1 + amount, previous.$2)
              : (previous.$1, previous.$2 + amount);
        }
        final categoryRows = await _db.customSelect('''
      WITH allocated AS (SELECT t.*, json_extract(part.value,'\$.categoryId') AS allocation_category, json_extract(part.value,'\$.amountMinor') AS allocation_amount FROM transactions t JOIN json_each(t.allocations_json) part
        UNION ALL SELECT t.*,t.category_id,COALESCE(t.actual_amount_minor,t.planned_amount_minor) FROM transactions t WHERE t.allocations_json='[]')
      SELECT a.currency_code, COALESCE(parent.name, c.name, 'Sem categoria')
        AS category_name, SUM(t.allocation_amount) AS amount_minor
      FROM allocated t JOIN accounts a ON a.id = t.account_id
      LEFT JOIN categories c ON c.id = t.allocation_category
      LEFT JOIN categories parent ON parent.id = c.parent_id
      WHERE t.deleted_at IS NULL AND t.type = 'expense'
        AND t.ignore_analytics = 0 AND a.deleted_at IS NULL
        AND a.include_in_analytics = 1
        AND COALESCE(t.effective_at, t.due_at) >= ? AND COALESCE(t.effective_at, t.due_at) < ?
      GROUP BY a.currency_code, COALESCE(parent.name, c.name, 'Sem categoria')
      ORDER BY amount_minor DESC, category_name
    ''', variables: [Variable.withInt(start), Variable.withInt(end)]).get();
        final categoryTotals = <String, List<DashboardCategoryExpense>>{};
        final cardCategories = await _db.customSelect('''
          WITH allocated AS (SELECT e.*,json_extract(part.value,'\$.categoryId') AS allocation_category,CASE WHEN e.amount_minor<0 THEN -json_extract(part.value,'\$.amountMinor') ELSE json_extract(part.value,'\$.amountMinor') END AS allocation_amount FROM card_entries e JOIN json_each(e.allocations_json) part
            UNION ALL SELECT e.*,e.category_id,e.amount_minor FROM card_entries e WHERE e.allocations_json='[]')
          SELECT 'BRL' AS currency_code, COALESCE(parent.name,c.name,'Sem categoria') AS category_name,
            SUM(e.allocation_amount) AS amount_minor FROM allocated e JOIN card_invoices i ON i.id=e.invoice_id
          LEFT JOIN categories c ON c.id=e.allocation_category LEFT JOIN categories parent ON parent.id=c.parent_id
          WHERE e.deleted_at IS NULL AND e.kind <> 'opening' AND i.due_at >= ? AND i.due_at < ?
          GROUP BY COALESCE(parent.name,c.name,'Sem categoria')
        ''', variables: [Variable.withInt(start), Variable.withInt(end)]).get();
        for (final row in [...categoryRows, ...cardCategories]) {
          categoryTotals
              .putIfAbsent(row.read<String>('currency_code'), () => [])
              .add(DashboardCategoryExpense(row.read<String>('category_name'),
                  row.read<int>('amount_minor')));
        }
        for (final code in categoryTotals.keys.toList()) {
          final grouped = <String, int>{};
          for (final category in categoryTotals[code]!) {
            grouped.update(category.name, (v) => v + category.amountMinor,
                ifAbsent: () => category.amountMinor);
          }
          categoryTotals[code] = [
            for (final e in grouped.entries)
              if (e.value > 0) DashboardCategoryExpense(e.key, e.value)
          ]..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
        }
        final historyStart =
            DateTime.utc(month.year, month.month - 5).millisecondsSinceEpoch;
        final historyRows = await _db.customSelect('''
      SELECT a.currency_code,
        strftime('%Y-%m', COALESCE(t.effective_at, t.due_at) / 1000, 'unixepoch') AS month_key,
        t.type, SUM(COALESCE(t.actual_amount_minor, t.planned_amount_minor)) AS amount_minor
      FROM transactions t JOIN accounts a ON a.id = t.account_id
      WHERE t.deleted_at IS NULL AND t.ignore_analytics = 0
        AND a.deleted_at IS NULL AND a.include_in_analytics = 1
        AND COALESCE(t.effective_at, t.due_at) >= ? AND COALESCE(t.effective_at, t.due_at) < ?
      GROUP BY a.currency_code, month_key, t.type
    ''', variables: [
          Variable.withInt(historyStart),
          Variable.withInt(end)
        ]).get();
        final monthly = <String, Map<String, (int, int)>>{};
        final cardHistory = await _db.customSelect('''
          SELECT 'BRL' AS currency_code, 'expense' AS type,
            strftime('%Y-%m',i.due_at/1000,'unixepoch') AS month_key, SUM(e.amount_minor) AS amount_minor
          FROM card_entries e JOIN card_invoices i ON i.id=e.invoice_id
          WHERE e.deleted_at IS NULL AND e.kind <> 'opening' AND i.due_at >= ? AND i.due_at < ?
          GROUP BY month_key
        ''', variables: [
          Variable.withInt(historyStart),
          Variable.withInt(end)
        ]).get();
        for (final row in [...historyRows, ...cardHistory]) {
          final code = row.read<String>('currency_code');
          final key = row.read<String>('month_key');
          final byMonth = monthly.putIfAbsent(code, () => {});
          final prior = byMonth[key] ?? (0, 0);
          final amount = row.read<int>('amount_minor');
          byMonth[key] = row.read<String>('type') == 'income'
              ? (prior.$1 + amount, prior.$2)
              : (prior.$1, prior.$2 + amount);
        }
        final accountRows = await _db.customSelect('''
      SELECT id, name, type, currency_code FROM accounts
      WHERE deleted_at IS NULL AND is_archived = 0 ORDER BY name
    ''').get();
        final accountBalances = {
          for (final balance in balances.accounts) balance.accountId: balance,
        };
        final accountsByCurrency = <String, List<DashboardAccountBalance>>{};
        for (final row in accountRows) {
          final id = row.read<String>('id');
          final balance = accountBalances[id];
          if (balance == null) continue;
          final code = row.read<String>('currency_code');
          final type = AccountType.values.firstWhere(
              (value) => value.name == row.read<String>('type'),
              orElse: () => AccountType.other);
          accountsByCurrency.putIfAbsent(code, () => []).add(
              DashboardAccountBalance(row.read<String>('name'), type.label,
                  code, balance.currentMinor));
        }
        // Mesmo que não existam contas ativas na moeda, os totais do período
        // permanecem disponíveis enquanto a conta histórica não foi removida.
        final currencies = <String>{
          ...balances.consolidated.map((value) => value.currencyCode),
          ...totals.keys,
        }.toList()
          ..sort();
        final byCurrency = {
          for (final value in balances.consolidated) value.currencyCode: value,
        };
        final summaries = [
          for (final currency in currencies)
            DashboardCurrencySummary(
                currencyCode: currency,
                balanceDetails: details[currency],
                currentBalanceMinor: byCurrency[currency]?.currentMinor ?? 0,
                projectedBalanceMinor:
                    byCurrency[currency]?.projectedMinor ?? 0,
                incomeMinor: totals[currency]?.$1 ?? 0,
                expenseMinor: totals[currency]?.$2 ?? 0,
                expensesByCategory: categoryTotals[currency] ?? const [],
                accounts: accountsByCurrency[currency] ?? const [],
                history: [
                  for (var i = 5; i >= 0; i--)
                    DashboardMonthTotal(
                        DateTime(month.year, month.month - i),
                        (monthly[currency]?[
                                    '${DateTime(month.year, month.month - i).year}-'
                                        '${DateTime(month.year, month.month - i).month.toString().padLeft(2, '0')}'] ??
                                (0, 0))
                            .$1,
                        (monthly[currency]?[
                                    '${DateTime(month.year, month.month - i).year}-'
                                        '${DateTime(month.year, month.month - i).month.toString().padLeft(2, '0')}'] ??
                                (0, 0))
                            .$2)
                ]),
        ];
        final rows = await _db.customSelect('''
      SELECT id, type, description, account_label, currency_code,
        amount_minor, event_at, effective_at, created_at FROM (
        SELECT t.id, t.type, t.description, a.name AS account_label,
          a.currency_code,
          COALESCE(t.actual_amount_minor, t.planned_amount_minor) AS amount_minor,
          t.due_at AS event_at, t.effective_at, t.created_at
        FROM transactions t JOIN accounts a ON a.id = t.account_id
        WHERE t.deleted_at IS NULL AND a.deleted_at IS NULL
        UNION ALL
        SELECT e.id, 'expense', e.description, 'Cartão ' || c.name,
          'BRL', e.amount_minor, i.due_at, NULL, e.created_at
        FROM card_entries e JOIN credit_cards c ON c.id=e.card_id
        JOIN card_invoices i ON i.id=e.invoice_id
        WHERE e.deleted_at IS NULL AND e.kind='purchase'
        UNION ALL
        SELECT f.id, 'transfer' AS type, f.description AS description,
          source.name || ' → ' || destination.name AS account_label,
          source.currency_code, f.amount_minor, f.due_at AS event_at,
          f.effective_at, f.created_at
        FROM transfers f
        JOIN accounts source ON source.id = f.source_account_id
        JOIN accounts destination ON destination.id = f.destination_account_id
        WHERE f.deleted_at IS NULL
          AND source.deleted_at IS NULL AND destination.deleted_at IS NULL
      ) ORDER BY created_at DESC, id DESC LIMIT 5
    ''').get();
        final recent = rows
            .map((row) => DashboardActivity(
                  id: row.read<String>('id'),
                  type: DashboardActivityType.values
                      .byName(row.read<String>('type')),
                  description: row.read<String>('description'),
                  accountLabel: row.read<String>('account_label'),
                  currencyCode: row.read<String>('currency_code'),
                  amountMinor: row.read<int>('amount_minor'),
                  date: DateTime.fromMillisecondsSinceEpoch(
                      row.read<int>('event_at'),
                      isUtc: true),
                  isEffective: row.readNullable<int>('effective_at') != null &&
                      row.read<int>('effective_at') <
                          DateTime.utc(DateTime.now().year,
                                  DateTime.now().month, DateTime.now().day + 1)
                              .millisecondsSinceEpoch,
                ))
            .toList();
        return DashboardSummary(
            month: DateTime(month.year, month.month),
            currencies: summaries,
            recent: recent);
      });
}
