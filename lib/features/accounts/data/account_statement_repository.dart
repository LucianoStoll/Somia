import 'dart:math' as math;
import 'package:drift/drift.dart';
import '../../../core/allocations/category_allocation.dart';
import '../../../core/database/app_database.dart';
import '../../cards/domain/credit_card.dart';
import '../domain/account_statement.dart';
import 'sqlite_accounts_repository.dart';

class AccountStatementRepository {
  const AccountStatementRepository(this.db);
  final AppDatabase db;
  Future<List<QueryRow>> _rows(String sql, List<Object> values) => db
      .customSelect(sql,
          variables: values
              .map((v) => v is int
                  ? Variable.withInt(v)
                  : Variable.withString(v as String))
              .toList())
      .get();

  Future<AccountStatement> load(String accountId, DateTime month,
          {DateTime? today}) =>
      db.transaction(() async {
        final first = DateTime.utc(month.year, month.month);
        final last = DateTime.utc(month.year, month.month + 1, 0);
        final now = cardDate(cardDay(today ?? DateTime.now()));
        final cutoff = now.isBefore(last) ? now : last;
        final end = cardDay(DateTime.utc(month.year, month.month + 1));
        final accounts = await SqliteAccountsRepository(db)
            .list(asOf: cutoff, through: last);
        final account = accounts.where((a) => a.id == accountId).firstOrNull;
        if (account == null) throw StateError('Conta não encontrada.');
        final actual = <StatementEntry>[], forecast = <StatementEntry>[];
        final tx = await _rows(
            '''SELECT t.*,c.name AS category_name,p.name AS parent_name
      FROM transactions t LEFT JOIN categories c ON c.id=t.category_id
      LEFT JOIN categories p ON p.id=c.parent_id
      WHERE t.account_id=? AND t.deleted_at IS NULL AND t.ignore_balance=0
      AND COALESCE(t.effective_at,t.due_at,t.posted_at)<?''', [accountId, end]);
        for (final r in tx) {
          final effectiveAt = r.readNullable<int>('effective_at');
          final date = cardDate(effectiveAt ??
              r.readNullable<int>('due_at') ??
              r.read<int>('posted_at'));
          final effective =
              effectiveAt != null && cardDay(date) <= cardDay(cutoff);
          final amount = !effective
              ? r.read<int>('planned_amount_minor')
              : r.readNullable<int>('actual_amount_minor') ??
                  r.read<int>('planned_amount_minor');
          final income = r.read<String>('type') == 'income';
          final e = StatementEntry(
              id: r.read<String>('id'),
              description: r.read<String>('description'),
              date: date,
              amountMinor: income ? amount : -amount,
              kind: income ? StatementKind.income : StatementKind.expense,
              effective: effective,
              detail:
                  CategoryAllocation.decode(r.read<String>('allocations_json'))
                          .isNotEmpty
                      ? 'Rateio entre categorias'
                      : [
                          r.readNullable<String>('parent_name'),
                          r.readNullable<String>('category_name')
                        ].whereType<String>().join(' / '));
          forecast.add(e);
          if (effective) actual.add(e);
        }
        final transfers = await _rows(
            '''SELECT f.*,a.name AS source_name,b.name AS destination_name FROM transfers f
      JOIN accounts a ON a.id=f.source_account_id JOIN accounts b ON b.id=f.destination_account_id
      WHERE (f.source_account_id=? OR f.destination_account_id=?) AND f.deleted_at IS NULL
      AND COALESCE(f.effective_at,f.due_at,f.posted_at)<?''',
            [accountId, accountId, end]);
        for (final r in transfers) {
          final incoming =
              r.read<String>('destination_account_id') == accountId;
          final at = r.readNullable<int>('effective_at');
          final date = cardDate(
              at ?? r.readNullable<int>('due_at') ?? r.read<int>('posted_at'));
          final effective = at != null && cardDay(date) <= cardDay(cutoff);
          final other =
              r.read<String>(incoming ? 'source_name' : 'destination_name');
          final e = StatementEntry(
              id: r.read<String>('id'),
              description: r.read<String>('description'),
              date: date,
              amountMinor: r.read<int>('amount_minor') * (incoming ? 1 : -1),
              kind: incoming
                  ? StatementKind.transferIn
                  : StatementKind.transferOut,
              effective: effective,
              detail: incoming
                  ? 'Transferência de $other'
                  : 'Transferência para $other');
          forecast.add(e);
          if (effective) actual.add(e);
        }
        final payments = await _rows(
            '''SELECT p.*,c.name AS card_name FROM card_payments p
      JOIN card_invoices i ON i.id=p.invoice_id JOIN credit_cards c ON c.id=i.card_id
      WHERE p.account_id=? AND p.deleted_at IS NULL AND p.effective_at<?''',
            [accountId, end]);
        for (final r in payments) {
          final date = cardDate(r.read<int>('effective_at'));
          final effective = cardDay(date) <= cardDay(cutoff);
          final e = StatementEntry(
              id: 'payment:${r.read<String>('id')}',
              description:
                  'Pagamento de fatura • ${r.read<String>('card_name')}',
              date: date,
              amountMinor: -r.read<int>('amount_minor'),
              kind: StatementKind.cardPayment,
              effective: effective);
          forecast.add(e);
          if (effective) actual.add(e);
        }
        // Variação da dívida prevista por cartão. Liquidações em qualquer conta
        // compensam a previsão na conta padrão, sem gerar uma receita bancária.
        final cards = await _rows(
            'SELECT id,name FROM credit_cards WHERE payment_account_id=? AND deleted_at IS NULL',
            [accountId]);
        for (final card in cards) {
          final id = card.read<String>('id'), name = card.read<String>('name');
          final events = await _rows(
              '''SELECT i.due_at AS day,SUM(e.amount_minor) AS charges,0 AS paid
        FROM card_entries e JOIN card_invoices i ON i.id=e.invoice_id
        WHERE e.card_id=? AND e.deleted_at IS NULL AND i.due_at<? GROUP BY i.due_at
        UNION ALL
        SELECT p.effective_at AS day,0,SUM(p.amount_minor) FROM card_payments p JOIN card_invoices i ON i.id=p.invoice_id
        WHERE i.card_id=? AND p.deleted_at IS NULL AND p.effective_at<? GROUP BY p.effective_at''',
              [id, end, id, end]);
          final days = <int, (int, int)>{};
          for (final r in events) {
            final date = r.read<int>('day'),
                before = days[r.read<int>('day')] ?? (0, 0);
            days[date] = (
              before.$1 + r.read<int>('charges'),
              before.$2 + r.read<int>('paid')
            );
          }
          var charges = 0, paid = 0, residual = 0;
          for (final day in days.keys.toList()..sort()) {
            charges += days[day]!.$1;
            paid += days[day]!.$2;
            final next = math.max(0, charges - paid), delta = residual - next;
            residual = next;
            if (delta == 0) continue;
            forecast.add(StatementEntry(
                id: 'forecast:$id:$day',
                description: delta < 0
                    ? 'Fatura prevista • $name'
                    : 'Compensação de fatura prevista • $name',
                date: cardDate(day),
                amountMinor: delta,
                kind: delta < 0
                    ? StatementKind.invoice
                    : StatementKind.adjustment,
                effective: false,
                detail: delta > 0
                    ? 'Ajuste da previsão; não é uma receita na conta.'
                    : null));
          }
        }
        StatementSection section(List<StatementEntry> entries) {
          entries.sort((a, b) {
            final d = a.date.compareTo(b.date);
            return d != 0 ? d : a.id.compareTo(b.id);
          });
          var balance = account.initialBalanceMinor;
          for (final e in entries.where((e) => e.date.isBefore(first))) {
            balance += e.amountMinor;
          }
          final opening = balance, days = <StatementDay>[], points = <int>[];
          for (var day = 1; day <= last.day; day++) {
            final date = DateTime.utc(first.year, first.month, day);
            final lines = entries.where((e) => e.date == date).toList();
            balance += lines.fold(0, (a, e) => a + e.amountMinor);
            points.add(balance);
            if (lines.isNotEmpty) {
              days.add(StatementDay(
                  date: date,
                  entries: List.unmodifiable(lines),
                  closingMinor: balance));
            }
          }
          return StatementSection(
              openingMinor: opening,
              closingMinor: balance,
              days: List.unmodifiable(days),
              dailyBalances: List.unmodifiable(points));
        }

        return AccountStatement(
            account: account,
            month: first,
            realized: section(actual),
            projected: section(forecast));
      });
}
