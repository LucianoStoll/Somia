import '../../../core/series/series_store.dart';
import '../../../core/series/movement_series.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';
import '../domain/transfer.dart';
import '../domain/transfers_repository.dart';

class SqliteTransfersRepository implements TransfersRepository {
  const SqliteTransfersRepository(this._db);

  final AppDatabase _db;

  static const _select = '''
    SELECT f.id, f.description, f.source_account_id, f.destination_account_id,
      f.series_id, f.series_index, f.series_kind, f.series_count, f.series_unit, f.series_interval,
      f.amount_minor, f.posted_at, f.due_at, f.effective_at,
      source.name AS source_name, destination.name AS destination_name,
      source.currency_code AS currency_code
    FROM transfers f
    JOIN accounts source ON source.id = f.source_account_id
    JOIN accounts destination ON destination.id = f.destination_account_id
  ''';

  @override
  Future<List<Transfer>> list({String? accountId}) async {
    final rows = await _db.customSelect('''
      $_select WHERE f.deleted_at IS NULL
      ${accountId == null ? '' : 'AND (f.source_account_id = ? OR f.destination_account_id = ?)'}
      ORDER BY CASE WHEN f.effective_at < ? THEN 0 ELSE 1 END, f.due_at DESC, f.id DESC
    ''', variables: [
      if (accountId != null) ...[
        Variable.withString(accountId),
        Variable.withString(accountId),
      ],
      Variable.withInt(_dayMillis(DateTime.now().add(const Duration(days: 1)))),
    ]).get();
    return rows.map(_map).toList();
  }

  @override
  Future<Transfer> create(TransferDraft draft) async {
    final plan = draft.seriesPlan;
    if (plan == null) return _createSingle(draft);
    plan.validate();
    if (plan.dateAt(draft.date, plan.count - 1).year > 2100 ||
        plan.dateAt(draft.dueDate ?? draft.date, plan.count - 1).year > 2100) {
      throw const FormatException('A série deve terminar até o ano 2100.');
    }
    final id = await SeriesStore(_db, 'transfers')
        .create(plan, draft.amountMinor, (index, amount) async {
      final date = plan.dateAt(draft.date, index);
      final due = plan.dateAt(draft.dueDate ?? draft.date, index);
      if (date.year > 2100 || due.year > 2100) {
        throw const FormatException('A série deve terminar até o ano 2100.');
      }
      return (await _createSingle(TransferDraft(
              description: draft.description,
              sourceAccountId: draft.sourceAccountId,
              destinationAccountId: draft.destinationAccountId,
              amountMinor: amount,
              date: date,
              dueDate: due,
              isEffective: false)))
          .id;
    });
    return _find(id);
  }

  @override
  Future<Transfer> update(String id, TransferDraft draft) =>
      _db.transaction(() async {
        final store = SeriesStore(_db, 'transfers');
        final original = await store.row(id);
        if (draft.scope == SeriesScope.onlyThis ||
            SeriesStore.info(original) == null) {
          return _updateSingle(id, draft);
        }
        final targets = await store.targets(id, draft.scope);
        for (final row in targets) {
          final date =
              SeriesStore.shiftedDate(row, original, 'posted_at', draft.date);
          final due = SeriesStore.shiftedDate(
              row, original, 'due_at', draft.dueDate ?? draft.date);
          if (date.year > 2100 || due.year > 2100) {
            throw const FormatException(
                'A série deve terminar até o ano 2100.');
          }
          await _updateSingle(
              row.read<String>('id'),
              TransferDraft(
                  description: draft.description,
                  sourceAccountId: draft.sourceAccountId,
                  destinationAccountId: draft.destinationAccountId,
                  amountMinor: draft.amountMinor,
                  date: date,
                  dueDate: due,
                  isEffective: false));
        }
        return _find(id);
      });

  Future<Transfer> _createSingle(TransferDraft draft) =>
      _db.transaction(() async {
        _validateDraft(draft);
        await _validateAccounts(draft);
        final id = EntityMetadata.newId();
        final now = EntityMetadata.nowUtcMillis();
        await _db.customStatement('''
      INSERT INTO transfers (id, source_account_id, destination_account_id,
        amount_minor, planned_at, posted_at, due_at, effective_at,
        created_at, updated_at, description)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
          id,
          draft.sourceAccountId,
          draft.destinationAccountId,
          draft.amountMinor,
          _dayMillis(draft.date),
          _dayMillis(draft.date),
          _dayMillis(draft.dueDate ?? draft.date),
          draft.isEffective
              ? _dayMillis(draft.effectiveDate ?? draft.date)
              : null,
          now,
          now,
          draft.description.trim()
        ]);
        return _find(id);
      });

  Future<Transfer> _updateSingle(String id, TransferDraft draft) =>
      _db.transaction(() async {
        _validateDraft(draft);
        final current = await _find(id);
        final sourceChanged = current.sourceAccountId != draft.sourceAccountId;
        final destinationChanged =
            current.destinationAccountId != draft.destinationAccountId;
        await _validateAccounts(draft,
            checkSource: sourceChanged, checkDestination: destinationChanged);
        final fields = <String>[
          'description = ?',
          'amount_minor = ?',
          'planned_at = ?',
          'posted_at = ?',
          'due_at = ?',
          'effective_at = ?',
          'updated_at = ?',
          'sync_version = sync_version + 1'
        ];
        final values = <Object?>[
          draft.description.trim(),
          draft.amountMinor,
          _dayMillis(draft.date),
          _dayMillis(draft.date),
          _dayMillis(draft.dueDate ?? draft.date),
          draft.isEffective
              ? _dayMillis(draft.effectiveDate ?? draft.date)
              : null,
          EntityMetadata.nowUtcMillis()
        ];
        if (sourceChanged) {
          fields.add('source_account_id = ?');
          values.add(draft.sourceAccountId);
        }
        if (destinationChanged) {
          fields.add('destination_account_id = ?');
          values.add(draft.destinationAccountId);
        }
        values.add(id);
        await _db.customStatement('''
      UPDATE transfers SET ${fields.join(', ')}
      WHERE id = ? AND deleted_at IS NULL
    ''', values);
        return _find(id);
      });

  @override
  Future<void> updateAmount(String id,
          {required int expectedAmountMinor,
          required int amountMinor,
          SeriesScope scope = SeriesScope.onlyThis}) =>
      _db.transaction(() async {
        final store = SeriesStore(_db, 'transfers');
        final original = await store.row(id);
        if (original.read<int>('amount_minor') != expectedAmountMinor) {
          throw StateError(
              'O valor já mudou. Atualize a lista e tente novamente.');
        }
        final targets = await store.targets(id, scope);
        for (final row in targets) {
          await _updateAmountSingle(row.read<String>('id'),
              expectedAmountMinor: row.read<int>('amount_minor'),
              amountMinor: amountMinor);
        }
      });

  Future<void> _updateAmountSingle(String id,
      {required int expectedAmountMinor, required int amountMinor}) async {
    if (amountMinor <= 0 || amountMinor > 9000000000000000) {
      throw const FormatException(
          'Informe um valor maior que zero e dentro do limite.');
    }
    final changed = await _db.customUpdate('''
      UPDATE transfers SET amount_minor = ?,
        updated_at = ?, sync_version = sync_version + 1
      WHERE id = ? AND deleted_at IS NULL AND amount_minor = ?
    ''', variables: [
      Variable.withInt(amountMinor),
      Variable.withInt(EntityMetadata.nowUtcMillis()),
      Variable.withString(id),
      Variable.withInt(expectedAmountMinor),
    ]);
    if (changed != 1) {
      throw StateError('O valor já mudou. Atualize a lista e tente novamente.');
    }
  }

  @override
  Future<void> delete(String id, {SeriesScope scope = SeriesScope.onlyThis}) =>
      SeriesStore(_db, 'transfers').delete(id, scope);

  @override
  Future<void> setEffective(String id,
      {required bool effective, DateTime? effectiveDate}) async {
    final todayEnd = _dayMillis(DateTime.now().add(const Duration(days: 1)));
    final changed = await _db.customUpdate('''
      UPDATE transfers SET effective_at = ${effective ? '?' : 'NULL'},
        updated_at = ?, sync_version = sync_version + 1
      WHERE id = ? AND deleted_at IS NULL
        AND ${effective ? '(effective_at IS NULL OR effective_at >= ?)' : 'effective_at IS NOT NULL'}
    ''', variables: [
      if (effective)
        Variable.withInt(_dayMillis(effectiveDate ?? DateTime.now())),
      Variable.withInt(EntityMetadata.nowUtcMillis()),
      Variable.withString(id),
      if (effective) Variable.withInt(todayEnd),
    ]);
    if (changed != 1) {
      throw StateError('A transferência já mudou de estado. Atualize a lista.');
    }
  }

  @override
  Future<void> changeEffectiveDate(String id,
      {required DateTime expectedDate, DateTime? effectiveDate}) async {
    final changed = await _db.customUpdate('''
      UPDATE transfers SET effective_at = ?,
        updated_at = ?, sync_version = sync_version + 1
      WHERE id = ? AND deleted_at IS NULL AND effective_at = ?
    ''', variables: [
      effectiveDate == null
          ? const Variable<int>(null)
          : Variable.withInt(_dayMillis(effectiveDate)),
      Variable.withInt(EntityMetadata.nowUtcMillis()),
      Variable.withString(id),
      Variable.withInt(_dayMillis(expectedDate)),
    ]);
    if (changed != 1) {
      throw StateError(
          'O movimento já mudou. Atualize a lista antes de tentar novamente.');
    }
  }

  Future<Transfer> _find(String id) async {
    final rows = await _db.customSelect('''
      $_select WHERE f.id = ? AND f.deleted_at IS NULL
    ''', variables: [Variable.withString(id)]).get();
    if (rows.isEmpty) throw StateError('Transferência não encontrada.');
    return _map(rows.single);
  }

  void _validateDraft(TransferDraft draft) {
    if (draft.description.trim().isEmpty) {
      throw const FormatException('Informe a descrição.');
    }
    if (draft.sourceAccountId.isEmpty || draft.destinationAccountId.isEmpty) {
      throw StateError('Selecione as contas de origem e destino.');
    }
    if (draft.sourceAccountId == draft.destinationAccountId) {
      throw StateError('Selecione contas diferentes.');
    }
    if (draft.amountMinor <= 0 || draft.amountMinor > 9000000000000000) {
      throw const FormatException(
          'Informe um valor maior que zero e dentro do limite.');
    }
  }

  Future<void> _validateAccounts(TransferDraft draft,
      {bool checkSource = true, bool checkDestination = true}) async {
    final rows = await _db.customSelect('''
      SELECT id, currency_code, is_archived, deleted_at FROM accounts
      WHERE id IN (?, ?)
    ''', variables: [
      Variable.withString(draft.sourceAccountId),
      Variable.withString(draft.destinationAccountId)
    ]).get();
    if (rows.length != 2) throw StateError('Conta não encontrada.');
    final byId = {for (final row in rows) row.read<String>('id'): row};
    final source = byId[draft.sourceAccountId]!;
    final destination = byId[draft.destinationAccountId]!;
    if (checkSource &&
        (source.read<int>('is_archived') == 1 ||
            source.readNullable<int>('deleted_at') != null)) {
      throw StateError('Selecione uma conta de origem ativa.');
    }
    if (checkDestination &&
        (destination.read<int>('is_archived') == 1 ||
            destination.readNullable<int>('deleted_at') != null)) {
      throw StateError('Selecione uma conta de destino ativa.');
    }
    if (source.read<String>('currency_code') !=
        destination.read<String>('currency_code')) {
      throw StateError('As contas precisam ter a mesma moeda.');
    }
  }

  int _dayMillis(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch;

  Transfer _map(QueryRow row) => Transfer(
        id: row.read<String>('id'),
        series: SeriesStore.info(row),
        description: row.read<String>('description'),
        sourceAccountId: row.read<String>('source_account_id'),
        sourceAccountName: row.read<String>('source_name'),
        destinationAccountId: row.read<String>('destination_account_id'),
        destinationAccountName: row.read<String>('destination_name'),
        currencyCode: row.read<String>('currency_code'),
        amountMinor: row.read<int>('amount_minor'),
        date: DateTime.fromMillisecondsSinceEpoch(row.read<int>('posted_at'),
            isUtc: true),
        dueDate: DateTime.fromMillisecondsSinceEpoch(row.read<int>('due_at'),
            isUtc: true),
        effectiveDate: row.readNullable<int>('effective_at') == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row.read<int>('effective_at'),
                isUtc: true),
        isEffective: row.readNullable<int>('effective_at') != null &&
            row.read<int>('effective_at') <
                _dayMillis(DateTime.now().add(const Duration(days: 1))),
      );
}
