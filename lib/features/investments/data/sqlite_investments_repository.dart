import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';
import '../../accounts/data/sqlite_accounts_repository.dart';
import '../../accounts/domain/account.dart';
import '../../transactions/data/sqlite_transactions_repository.dart';
import '../../transactions/domain/financial_transaction.dart';
import '../../transfers/data/sqlite_transfers_repository.dart';
import '../../transfers/domain/transfer.dart';
import '../domain/investment.dart';

class SqliteInvestmentsRepository implements InvestmentsRepository {
  const SqliteInvestmentsRepository(this.db);
  final AppDatabase db;
  static const maxMinor = 9000000000000000;

  @override
  Future<InvestmentOverview> load({DateTime? date}) => db.transaction(() async {
        final accounts =
            await SqliteAccountsRepository(db).list(asOf: date, through: date);
        final byId = {for (final a in accounts) a.id: a};
        final rows = await db
            .customSelect(
              'SELECT * FROM investments WHERE deleted_at IS NULL ORDER BY lower(name),id',
            )
            .get();
        final items = rows
            .map(
              (r) => Investment(
                id: r.read<String>('id'),
                name: r.read<String>('name'),
                kind: InvestmentKind.values.byName(r.read<String>('kind')),
                institution: r.read<String>('institution'),
                notes: r.read<String>('notes'),
                maturityDate: r.readNullable<int>('maturity_at') == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(
                        r.read<int>('maturity_at'),
                        isUtc: true),
                account: byId[r.read<String>('account_id')] ??
                    (throw StateError('Conta da aplicação indisponível.')),
              ),
            )
            .toList();
        return InvestmentOverview(items, accounts);
      });

  @override
  Future<void> save(
    InvestmentDraft draft, {
    String? id,
  }) =>
      db.transaction(() async {
        if (draft.name.trim().isEmpty) {
          throw const FormatException('Informe o nome da aplicação.');
        }
        if (draft.initialBalanceMinor < 0 ||
            draft.initialBalanceMinor > maxMinor) {
          throw const FormatException('Informe um saldo inicial válido.');
        }
        final maturity = draft.maturityDate;
        if (maturity != null &&
            (maturity.year < 1900 || maturity.year > 2100)) {
          throw const FormatException(
              'Informe um vencimento entre 1900 e 2100.');
        }
        final maturityMillis = maturity == null
            ? null
            : DateTime.utc(maturity.year, maturity.month, maturity.day)
                .millisecondsSinceEpoch;
        final now = EntityMetadata.nowUtcMillis();
        if (id != null) {
          final original = await _find(id);
          if (draft.accountId != null &&
              draft.accountId != original.account.id) {
            throw const FormatException(
              'O vínculo da conta não pode ser alterado.',
            );
          }
          await db.customStatement(
            '''UPDATE investments SET name=?,kind=?,institution=?,
        notes=?,maturity_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?''',
            [
              draft.name.trim(),
              draft.kind.name,
              draft.institution.trim(),
              draft.notes.trim(),
              maturityMillis,
              now,
              id,
            ],
          );
          return;
        }
        var accountId = draft.accountId;
        if (accountId != null) {
          if (draft.initialBalanceMinor != 0) {
            throw const FormatException(
              'A conta existente já possui seu próprio saldo.',
            );
          }
          await _activeAccount(accountId);
          final used = await db.customSelect(
            'SELECT id FROM investments WHERE account_id=?',
            variables: [Variable(accountId)],
          ).get();
          if (used.isNotEmpty) {
            throw const FormatException(
              'Esta conta já está vinculada a uma aplicação.',
            );
          }
        } else {
          accountId = (await SqliteAccountsRepository(db).create(
            AccountDraft(
              name: draft.name.trim(),
              type: draft.kind == InvestmentKind.savings
                  ? AccountType.savings
                  : AccountType.investment,
              currencyCode: 'BRL',
              initialBalanceMinor: draft.initialBalanceMinor,
              includeInAnalytics: true,
              includeInBalance: false,
            ),
          ))
              .id;
        }
        await db.customStatement(
          '''INSERT INTO investments
      (id,account_id,name,kind,institution,notes,maturity_at,created_at,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?)''',
          [
            EntityMetadata.newId(),
            accountId,
            draft.name.trim(),
            draft.kind.name,
            draft.institution.trim(),
            draft.notes.trim(),
            maturityMillis,
            now,
            now,
          ],
        );
      });

  Future<Investment> _find(String id, {DateTime? date}) async {
    final overview = await load(date: date);
    for (final item in overview.investments) {
      if (item.id == id) return item;
    }
    throw StateError('Aplicação não encontrada.');
  }

  void _amount(int amount, {bool zeroAllowed = false}) {
    if (amount < (zeroAllowed ? 0 : 1) || amount > maxMinor) {
      throw const FormatException('Informe um valor válido dentro do limite.');
    }
  }

  void _date(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final now = DateTime.now();
    if (date.year < 1900 ||
        day.isAfter(DateTime.utc(now.year, now.month, now.day))) {
      throw const FormatException(
        'Use a data de uma movimentação já realizada.',
      );
    }
  }

  Future<void> _activeAccount(String id) async {
    final rows = await db.customSelect(
      '''SELECT id FROM accounts WHERE id=?
      AND currency_code='BRL' AND is_archived=0 AND deleted_at IS NULL''',
      variables: [Variable(id)],
    ).get();
    if (rows.isEmpty)
      throw const FormatException('Selecione uma conta ativa em reais.');
  }

  @override
  Future<void> transfer(
    String id, {
    required String otherAccountId,
    required bool deposit,
    required int amountMinor,
    required DateTime date,
  }) =>
      db.transaction(() async {
        _amount(amountMinor);
        _date(date);
        final item = await _find(id, date: date);
        await _activeAccount(item.account.id);
        await _activeAccount(otherAccountId);
        if (otherAccountId == item.account.id) {
          throw const FormatException('Selecione outra conta.');
        }
        if (!deposit && amountMinor > item.account.currentBalanceMinor) {
          throw const FormatException(
            'O resgate supera o saldo disponível nessa data.',
          );
        }
        await SqliteTransfersRepository(db).create(
          TransferDraft(
            description: '${deposit ? 'Aporte' : 'Resgate'} — ${item.name}',
            sourceAccountId: deposit ? otherAccountId : item.account.id,
            destinationAccountId: deposit ? item.account.id : otherAccountId,
            amountMinor: amountMinor,
            date: date,
            dueDate: date,
            effectiveDate: date,
            isEffective: true,
          ),
        );
      });

  @override
  Future<void> recordReturn(
    String id, {
    required int amountMinor,
    required DateTime date,
  }) =>
      db.transaction(() async {
        _amount(amountMinor);
        _date(date);
        final item = await _find(id);
        await _activeAccount(item.account.id);
        await _transaction(item, amountMinor, date, adjustment: false);
      });

  @override
  Future<void> reconcile(
    String id, {
    required int targetMinor,
    required int expectedBalanceMinor,
    required DateTime date,
  }) =>
      db.transaction(() async {
        _amount(targetMinor, zeroAllowed: true);
        _date(date);
        final item = await _find(id, date: date);
        await _activeAccount(item.account.id);
        if (item.account.currentBalanceMinor != expectedBalanceMinor) {
          throw StateError(
              'O saldo mudou. Confira novamente antes de confirmar.');
        }
        final delta = targetMinor - expectedBalanceMinor;
        if (delta == 0) return;
        _amount(delta.abs());
        await _transaction(item, delta, date, adjustment: true);
      });

  Future<void> _transaction(
    Investment item,
    int delta,
    DateTime date, {
    required bool adjustment,
  }) async {
    final tx = await SqliteTransactionsRepository(db).create(
      TransactionDraft(
        description:
            '${adjustment ? 'Ajuste de saldo do banco' : 'Rendimento'} — ${item.name}',
        type: delta > 0 ? TransactionType.income : TransactionType.expense,
        amountMinor: delta.abs(),
        date: date,
        dueDate: date,
        effectiveDate: date,
        isEffective: true,
        accountId: item.account.id,
      ),
    );
    // Reconciliação não presume que toda diferença seja rendimento/gasto.
    if (adjustment)
      await db.customStatement(
        'UPDATE transactions SET ignore_analytics=1 WHERE id=?',
        [tx.id],
      );
  }

  @override
  Future<void> setArchived(String id, bool archived) =>
      db.transaction(() async {
        final item = await _find(id);
        await SqliteAccountsRepository(db)
            .setArchived(item.account.id, archived: archived);
      });
}
