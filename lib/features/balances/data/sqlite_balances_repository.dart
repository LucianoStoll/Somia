import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/balances_repository.dart';
import '../domain/balances_snapshot.dart';

/// Consulta compartilhada com a listagem de contas para manter a mesma
/// definição de saldo em toda a aplicação.
Future<List<QueryRow>> balanceRows(AppDatabase db,
    {DateTime? asOf, DateTime? through}) {
  final cutoff = asOf ?? DateTime.now();
  final asOfEnd = DateTime.utc(cutoff.year, cutoff.month, cutoff.day + 1)
      .millisecondsSinceEpoch;
  final end = through == null
      ? null
      : DateTime.utc(through.year, through.month, through.day + 1)
          .millisecondsSinceEpoch;
  const txEffectiveUntil = 'AND t.effective_at < ?';
  const transferEffectiveUntil = 'AND f.effective_at < ?';
  const txPending = '(t.effective_at IS NULL OR t.effective_at >= ?)';
  const transferPending = '(f.effective_at IS NULL OR f.effective_at >= ?)';
  final txUntil =
      end == null ? '' : 'AND COALESCE(t.effective_at, t.due_at) < ?';
  final transferUntil =
      end == null ? '' : 'AND COALESCE(f.effective_at, f.due_at) < ?';
  final variables = <Variable>[
    Variable.withInt(asOfEnd),
    Variable.withInt(asOfEnd),
    Variable.withInt(asOfEnd),
    Variable.withInt(asOfEnd),
    if (end != null) Variable.withInt(end),
    Variable.withInt(asOfEnd),
    if (end != null) Variable.withInt(end),
    Variable.withInt(asOfEnd),
    if (end != null) Variable.withInt(end),
    if (end != null) Variable.withInt(end),
    Variable.withInt(asOfEnd),
    if (end != null) Variable.withInt(end),
  ];
  return db.customSelect('''
    SELECT a.*,
      a.initial_balance_minor +
      COALESCE((SELECT SUM(CASE WHEN t.type = 'income'
                      THEN t.actual_amount_minor ELSE -t.actual_amount_minor END)
                FROM transaction_events t
                WHERE t.account_id = a.id AND t.effective_at IS NOT NULL
                  $txEffectiveUntil
                  AND t.actual_amount_minor IS NOT NULL
                  AND t.ignore_balance = 0 AND t.deleted_at IS NULL), 0) +
      COALESCE((SELECT SUM(CASE WHEN f.destination_account_id = a.id
                      THEN f.amount_minor ELSE -f.amount_minor END)
                FROM transfers f
                WHERE (f.source_account_id = a.id OR f.destination_account_id = a.id)
                  AND f.effective_at IS NOT NULL $transferEffectiveUntil
                  AND f.deleted_at IS NULL), 0)
      - COALESCE((SELECT SUM(p.amount_minor) FROM card_payments p
         WHERE p.account_id=a.id AND p.deleted_at IS NULL AND p.effective_at < ?),0)
      AS current_balance_minor,
      COALESCE((SELECT SUM(CASE WHEN t.type = 'income'
                      THEN t.planned_amount_minor ELSE -t.planned_amount_minor END)
                FROM transaction_events t
                WHERE t.account_id = a.id AND $txPending
                  AND t.ignore_balance = 0 AND t.deleted_at IS NULL
                  $txUntil), 0) +
      COALESCE((SELECT SUM(CASE WHEN f.destination_account_id = a.id
                      THEN f.amount_minor ELSE -f.amount_minor END)
                FROM transfers f
                WHERE (f.source_account_id = a.id OR f.destination_account_id = a.id)
                  AND $transferPending AND f.deleted_at IS NULL
                  $transferUntil), 0)
      - COALESCE((SELECT SUM(p.amount_minor) FROM card_payments p
         WHERE p.account_id=a.id AND p.deleted_at IS NULL AND p.effective_at >= ?
         ${end == null ? '' : 'AND p.effective_at < ?'}),0)
      - COALESCE((SELECT SUM(MAX(0,
          COALESCE((SELECT SUM(e.amount_minor) FROM card_entries e JOIN card_invoices i ON i.id=e.invoice_id
            WHERE e.card_id=c.id AND e.deleted_at IS NULL ${end == null ? '' : 'AND i.due_at < ?'}),0)
          - COALESCE((SELECT SUM(p.amount_minor) FROM card_payments p JOIN card_invoices i ON i.id=p.invoice_id
            WHERE i.card_id=c.id AND p.deleted_at IS NULL
            AND (p.effective_at < ? ${end == null ? 'OR 1=1' : 'OR p.effective_at < ?'})),0)))
         FROM credit_cards c WHERE c.payment_account_id=a.id AND c.deleted_at IS NULL),0)
      AS pending_balance_minor
    FROM accounts a
    WHERE a.deleted_at IS NULL
    ORDER BY a.is_archived, lower(a.name), a.id
  ''', variables: variables).get();
}

class SqliteBalancesRepository implements BalancesRepository {
  const SqliteBalancesRepository(this._db);

  final AppDatabase _db;

  @override
  Future<BalancesSnapshot> calculate(
      {DateTime? asOf, DateTime? through}) async {
    final rows = await balanceRows(_db, asOf: asOf, through: through);
    final accounts = <AccountBalance>[];
    final totals = <String, (int, int)>{};
    for (final row in rows) {
      final currency = row.read<String>('currency_code');
      final current = row.read<int>('current_balance_minor');
      final projected = current + row.read<int>('pending_balance_minor');
      accounts.add(AccountBalance(
          accountId: row.read<String>('id'),
          currencyCode: currency,
          currentMinor: current,
          projectedMinor: projected));
      totals.putIfAbsent(currency, () => (0, 0));
      if (row.read<int>('include_in_balance') != 1) continue;
      final previous = totals[currency]!;
      totals[currency] = (previous.$1 + current, previous.$2 + projected);
    }
    final consolidated = totals.entries
        .map((entry) => CurrencyBalance(
            currencyCode: entry.key,
            currentMinor: entry.value.$1,
            projectedMinor: entry.value.$2))
        .toList()
      ..sort((a, b) => a.currencyCode.compareTo(b.currencyCode));
    return BalancesSnapshot(accounts: accounts, consolidated: consolidated);
  }
}
