import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';
import '../../balances/data/sqlite_balances_repository.dart';
import '../domain/account.dart';
import '../domain/accounts_repository.dart';

class SqliteAccountsRepository implements AccountsRepository {
  const SqliteAccountsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<Account>> list({DateTime? asOf, DateTime? through}) async {
    final rows = await balanceRows(_db, asOf: asOf, through: through);
    return rows.map(_mapAccount).toList();
  }

  @override
  Future<Account> create(AccountDraft draft) async {
    _validate(draft);
    final id = EntityMetadata.newId();
    final now = EntityMetadata.nowUtcMillis();
    await _db.customStatement('''
      INSERT INTO accounts
        (id, name, type, currency_code, initial_balance_minor,
         include_in_analytics, include_in_balance, institution_id, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      id,
      draft.name.trim(),
      draft.type.name,
      draft.currencyCode.toUpperCase(),
      draft.initialBalanceMinor,
      draft.includeInAnalytics ? 1 : 0,
      draft.includeInBalance ? 1 : 0,
      draft.institutionId,
      now,
      now
    ]);
    return _find(id);
  }

  @override
  Future<Account> update(String id, AccountDraft draft) async {
    _validate(draft);
    final current = await _find(id);
    if (current.currencyCode != draft.currencyCode.toUpperCase()) {
      final references = await _db.customSelect('''
        SELECT
          (SELECT COUNT(*) FROM transactions WHERE account_id = ?) +
          (SELECT COUNT(*) FROM transfers WHERE
             (source_account_id = ? OR destination_account_id = ?)) +
          (SELECT COUNT(*) FROM credit_cards WHERE payment_account_id = ?) +
          (SELECT COUNT(*) FROM card_payments WHERE account_id = ?)
          AS total
      ''', variables: [
        Variable.withString(id),
        Variable.withString(id),
        Variable.withString(id),
        Variable.withString(id),
        Variable.withString(id)
      ]).getSingle();
      if (references.read<int>('total') > 0) {
        throw StateError(
            'Não é possível trocar a moeda de uma conta com vínculos financeiros ou histórico.');
      }
    }
    await _db.customStatement('''
      UPDATE accounts SET name = ?, type = ?, currency_code = ?,
        initial_balance_minor = ?, include_in_analytics = ?,
        include_in_balance = ?, institution_id = ?, updated_at = ?,
        sync_version = sync_version + 1
      WHERE id = ? AND deleted_at IS NULL
    ''', [
      draft.name.trim(),
      draft.type.name,
      draft.currencyCode.toUpperCase(),
      draft.initialBalanceMinor,
      draft.includeInAnalytics ? 1 : 0,
      draft.includeInBalance ? 1 : 0,
      draft.institutionId,
      EntityMetadata.nowUtcMillis(),
      id
    ]);
    return _find(id);
  }

  @override
  Future<Account> setArchived(String id, {required bool archived}) async {
    await _find(id);
    await _db.customStatement('''
      UPDATE accounts SET is_archived = ?, updated_at = ?,
        sync_version = sync_version + 1
      WHERE id = ? AND deleted_at IS NULL
    ''', [archived ? 1 : 0, EntityMetadata.nowUtcMillis(), id]);
    return _find(id);
  }

  Future<Account> _find(String id) async {
    final accounts = await list();
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    throw StateError('Conta não encontrada.');
  }

  Account _mapAccount(QueryRow row) => Account(
        id: row.read<String>('id'),
        name: row.read<String>('name'),
        type: AccountType.values.byName(row.read<String>('type')),
        currencyCode: row.read<String>('currency_code'),
        initialBalanceMinor: row.read<int>('initial_balance_minor'),
        currentBalanceMinor: row.read<int>('current_balance_minor'),
        projectedBalanceMinor: row.read<int>('current_balance_minor') +
            row.read<int>('pending_balance_minor'),
        isArchived: row.read<int>('is_archived') == 1,
        includeInAnalytics: row.read<int>('include_in_analytics') == 1,
        includeInBalance: row.read<int>('include_in_balance') == 1,
        institutionId: row.readNullable<String>('institution_id'),
      );

  void _validate(AccountDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw const FormatException('Informe o nome da conta.');
    }
    if (!RegExp(r'^[A-Za-z]{3}$').hasMatch(draft.currencyCode)) {
      throw const FormatException('A moeda deve ter três letras (ex.: BRL).');
    }
  }
}
