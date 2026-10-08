import '../../reimbursements/data/reimbursements_repository.dart';
import '../../../core/database/reimbursement_integrity.dart';
import '../../../core/allocations/category_allocation.dart';
import '../../../core/allocations/allocation_store.dart';
import '../../cards/data/cards_repository.dart';
import '../../../core/series/series_store.dart';
import '../../../core/series/movement_series.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/debt_integrity.dart';
import '../../../core/database/entity_metadata.dart';
import '../domain/financial_transaction.dart';
import '../domain/transactions_repository.dart';

class SqliteTransactionsRepository implements TransactionsRepository {
  const SqliteTransactionsRepository(this._db);
  final AppDatabase _db;

  Future<T> _checked<T>(Future<T> Function() action) =>
      _db.transaction(() async {
        final result = await action();
        await validateDebtFinancial(_db);
        await validateReimbursements(_db);
        return result;
      });

  static const _select = '''
    SELECT t.id, t.description, t.type, t.planned_amount_minor,
      t.series_id, t.series_index, t.series_kind, t.series_count, t.series_unit, t.series_interval,
      t.posted_at, t.due_at, t.effective_at, t.account_id, t.category_id, t.allocations_json,
      a.name AS account_name, a.currency_code,
      c.name AS category_name
    FROM transactions t
    JOIN accounts a ON a.id = t.account_id
    LEFT JOIN categories c ON c.id = t.category_id
  ''';

  @override
  Future<List<FinancialTransaction>> list([
    TransactionFilter filter = const TransactionFilter(),
  ]) async {
    final where = <String>['t.deleted_at IS NULL'];
    final variables = <Variable>[];
    final todayEnd = _dayMillis(DateTime.now().add(const Duration(days: 1)));
    if (filter.type != null) {
      where.add('t.type = ?');
      variables.add(Variable.withString(filter.type!.name));
    }
    if (filter.accountId != null) {
      where.add('t.account_id = ?');
      variables.add(Variable.withString(filter.accountId!));
    }
    if (filter.categoryId != null) {
      where.add(
        '''(t.category_id = ? OR c.parent_id = ? OR EXISTS (SELECT 1 FROM json_each(t.allocations_json) part JOIN categories ac ON ac.id=json_extract(part.value,'\$.categoryId') WHERE ac.id=? OR ac.parent_id=?))''',
      );
      variables.add(Variable.withString(filter.categoryId!));
      variables.add(Variable.withString(filter.categoryId!));
      variables.add(Variable.withString(filter.categoryId!));
      variables.add(Variable.withString(filter.categoryId!));
    }
    switch (filter.status) {
      case TransactionStatus.effective:
        where.add('t.effective_at IS NOT NULL AND t.effective_at < ?');
        variables.add(Variable.withInt(todayEnd));
      case TransactionStatus.pending:
        where.add('(t.effective_at IS NULL OR t.effective_at >= ?)');
        variables.add(Variable.withInt(todayEnd));
      case TransactionStatus.all:
        break;
    }
    final dateColumn = switch (filter.dateField) {
      TransactionDateField.posted => 't.posted_at',
      TransactionDateField.due => 't.due_at',
      TransactionDateField.effective => 't.effective_at',
    };
    if (filter.from != null) {
      where.add('$dateColumn >= ?');
      variables.add(Variable.withInt(_dayMillis(filter.from!)));
    }
    if (filter.to != null) {
      where.add('$dateColumn < ?');
      final day =
          DateTime.utc(filter.to!.year, filter.to!.month, filter.to!.day + 1);
      variables.add(Variable.withInt(day.millisecondsSinceEpoch));
    }
    variables.add(Variable.withInt(todayEnd));
    final rows = await _db.customSelect('''
      $_select WHERE ${where.join(' AND ')}
      ORDER BY CASE WHEN t.effective_at < ? THEN 0 ELSE 1 END, t.due_at DESC, t.created_at DESC, t.id DESC
    ''', variables: variables).get();
    final items = [
      ...rows.map(_map),
      ...await CardsRepository(_db).movements(filter)
    ];
    items.sort((a, b) {
      if (a.isEffective != b.isEffective) return a.isEffective ? -1 : 1;
      return (b.dueDate ?? b.date).compareTo(a.dueDate ?? a.date);
    });
    return items;
  }

  @override
  Future<FinancialTransaction> create(TransactionDraft draft) async {
    if (draft.cardId != null) {
      final repo = CardsRepository(_db);
      return repo.findMovement(await repo.createPurchase(draft));
    }
    _validateDraft(draft);
    final plan = draft.seriesPlan;
    if (plan == null) return _checked(() => _createSingle(draft));
    if (draft.reimbursements?.isNotEmpty ?? false) {
      throw const FormatException(
          'Crie o lançamento individual antes de vincular reembolsos.');
    }
    plan.validate();
    if (plan.dateAt(draft.date, plan.count - 1).year > 2100 ||
        plan.dateAt(draft.dueDate ?? draft.date, plan.count - 1).year > 2100) {
      throw const FormatException('A série deve terminar até o ano 2100.');
    }
    final id = await SeriesStore(_db, 'transactions')
        .create(plan, draft.amountMinor, (index, amount) async {
      final date = plan.dateAt(draft.date, index);
      final due = plan.dateAt(draft.dueDate ?? draft.date, index);
      if (date.year > 2100 || due.year > 2100) {
        throw const FormatException('A série deve terminar até o ano 2100.');
      }
      return (await _createSingle(TransactionDraft(
              description: draft.description,
              type: draft.type,
              accountId: draft.accountId,
              categoryId: draft.categoryId,
              allocations: CategoryAllocation.distribute(
                draft.allocations,
                amount,
              ),
              amountMinor: amount,
              date: date,
              dueDate: due,
              isEffective: false)))
          .id;
    });
    return _find(id);
  }

  @override
  Future<FinancialTransaction> update(String id, TransactionDraft draft) =>
      _checked(() async {
        if (id.startsWith('invoice:')) {
          throw StateError('Abra a fatura para alterar seus lançamentos.');
        }
        if (id.startsWith('card:')) {
          final repo = CardsRepository(_db);
          await repo.editPurchase(id.substring(5), draft);
          return repo.findMovement(id.substring(5));
        }
        if (draft.cardId != null) {
          throw StateError(
              'Crie uma nova compra para mudar a forma de pagamento.');
        }
        final store = SeriesStore(_db, 'transactions');
        final original = await store.row(id);
        if (draft.scope == SeriesScope.onlyThis ||
            SeriesStore.info(original) == null) {
          return _updateSingle(id, draft);
        }
        if (draft.reimbursements != null) {
          throw const FormatException(
              'Altere o reembolso somente neste lançamento.');
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
              TransactionDraft(
                  description: draft.description,
                  type: draft.type,
                  accountId: draft.accountId,
                  categoryId: draft.categoryId,
                  allocations: draft.allocations,
                  amountMinor: draft.amountMinor,
                  date: date,
                  dueDate: due,
                  isEffective: false));
        }
        return _find(id);
      });

  Future<FinancialTransaction> _createSingle(TransactionDraft draft) async {
    _validateDraft(draft);
    await _validateReferences(draft);
    await validateAllocationReferences(_db, draft.allocations, draft.type.name);
    final id = EntityMetadata.newId();
    final now = EntityMetadata.nowUtcMillis();
    final day = _dayMillis(draft.date);
    final due = _dayMillis(draft.dueDate ?? draft.date);
    final effective = draft.isEffective
        ? _dayMillis(draft.effectiveDate ?? draft.date)
        : null;
    await _db.customStatement('''
      INSERT INTO transactions
        (id, description, type, planned_amount_minor, actual_amount_minor,
         competence_at, posted_at, due_at, effective_at, account_id, category_id,
         created_at, updated_at, allocations_json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      id,
      draft.description.trim(),
      draft.type.name,
      draft.amountMinor,
      draft.isEffective ? draft.amountMinor : null,
      day,
      day,
      due,
      effective,
      draft.accountId,
      draft.categoryId,
      now,
      now,
      CategoryAllocation.encode(draft.allocations),
    ]);
    if (draft.reimbursements != null) {
      await ReimbursementsRepository(_db).replace(id, draft.reimbursements!);
    }
    return _find(id);
  }

  Future<FinancialTransaction> _updateSingle(
      String id, TransactionDraft draft) async {
    _validateDraft(draft);
    final original = await _find(id);
    await validateAllocationReferences(
      _db,
      draft.allocations,
      draft.type.name,
      historicalIds: original.type == draft.type
          ? original.allocations.map((p) => p.categoryId).toSet()
          : {},
    );
    final accountChanged = original.accountId != draft.accountId;
    final categoryChanged = original.categoryId != draft.categoryId;
    final typeChanged = original.type != draft.type;
    if (accountChanged || categoryChanged || typeChanged) {
      await _validateReferences(draft,
          checkAccount: accountChanged,
          checkCategory: categoryChanged || typeChanged);
    }
    // Não revalida conta/categoria arquivada ao editar só descrição, data ou
    // valor de um lançamento histórico; mudar o vínculo exige entidade ativa.
    final fields = <String>[
      'allocations_json = ?',
      'description = ?',
      'planned_amount_minor = ?',
      'actual_amount_minor = ?',
      'competence_at = ?',
      'posted_at = ?',
      'due_at = ?',
      'effective_at = ?',
      'updated_at = ?',
      'sync_version = sync_version + 1',
    ];
    final day = _dayMillis(draft.date);
    final args = <Object?>[
      CategoryAllocation.encode(draft.allocations),
      draft.description.trim(),
      draft.amountMinor,
      draft.isEffective ? draft.amountMinor : null,
      day,
      day,
      _dayMillis(draft.dueDate ?? draft.date),
      draft.isEffective ? _dayMillis(draft.effectiveDate ?? draft.date) : null,
      EntityMetadata.nowUtcMillis(),
    ];
    if (accountChanged) {
      fields.add('account_id = ?');
      args.add(draft.accountId);
    }
    if (categoryChanged) {
      fields.add('category_id = ?');
      args.add(draft.categoryId);
    }
    if (typeChanged) {
      fields.add('type = ?');
      args.add(draft.type.name);
    }
    args.add(id);
    await _db.customStatement('''
      UPDATE transactions SET ${fields.join(', ')}
      WHERE id = ? AND deleted_at IS NULL
    ''', args);
    if (draft.reimbursements != null) {
      await ReimbursementsRepository(_db).replace(id, draft.reimbursements!);
    }
    return _find(id);
  }

  @override
  Future<void> updateAmount(String id,
          {required int expectedAmountMinor,
          required int amountMinor,
          SeriesScope scope = SeriesScope.onlyThis}) =>
      _checked(() async {
        if (id.startsWith('invoice:')) {
          throw StateError('Abra a fatura para alterar seus lançamentos.');
        }
        if (id.startsWith('card:')) {
          return CardsRepository(_db).updateAmount(
              id.substring(5), expectedAmountMinor, amountMinor, scope);
        }
        final store = SeriesStore(_db, 'transactions');
        final original = await store.row(id);
        if (original.read<int>('planned_amount_minor') != expectedAmountMinor) {
          throw StateError(
              'O valor já mudou. Atualize a lista e tente novamente.');
        }
        final targets = await store.targets(id, scope);
        for (final row in targets) {
          await _updateAmountSingle(row.read<String>('id'),
              expectedAmountMinor: row.read<int>('planned_amount_minor'),
              amountMinor: amountMinor);
        }
      });

  Future<void> _updateAmountSingle(String id,
      {required int expectedAmountMinor, required int amountMinor}) async {
    if (amountMinor <= 0 || amountMinor > 9000000000000000) {
      throw const FormatException(
          'Informe um valor maior que zero e dentro do limite.');
    }
    final original = await _find(id);
    final parts = CategoryAllocation.distribute(
      original.allocations,
      amountMinor,
    );
    final changed = await _db.customUpdate('''
      UPDATE transactions SET allocations_json = ?, planned_amount_minor = ?,
        actual_amount_minor = CASE WHEN effective_at IS NULL THEN NULL ELSE ? END,
        updated_at = ?, sync_version = sync_version + 1
      WHERE id = ? AND deleted_at IS NULL AND planned_amount_minor = ?
    ''', variables: [
      Variable.withString(CategoryAllocation.encode(parts)),
      Variable.withInt(amountMinor),
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
  Future<
      void> delete(String id, {SeriesScope scope = SeriesScope.onlyThis}) => id
          .startsWith('invoice:')
      ? Future.error(StateError('Abra a fatura para alterar seus lançamentos.'))
      : id.startsWith('card:')
          ? CardsRepository(_db).deletePurchase(id.substring(5), scope)
          : _checked(() => SeriesStore(_db, 'transactions').delete(id, scope));

  @override
  Future<void> setEffective(String id,
          {required bool effective, DateTime? effectiveDate}) =>
      _checked(() => _setEffective(id,
          effective: effective, effectiveDate: effectiveDate));

  Future<void> _setEffective(String id,
      {required bool effective, DateTime? effectiveDate}) async {
    if (id.startsWith('invoice:')) {
      throw StateError('Pague pela ação da fatura.');
    }
    if (id.startsWith('card:')) {
      throw StateError('Pague pela fatura do cartão.');
    }
    final chosen = _dayMillis(effectiveDate ?? DateTime.now());
    final todayEnd = _dayMillis(DateTime.now().add(const Duration(days: 1)));
    final changed = await _db.customUpdate('''
      UPDATE transactions
      SET effective_at = ${effective ? '?' : 'NULL'},
        actual_amount_minor = ${effective ? 'planned_amount_minor' : 'NULL'},
        updated_at = ?, sync_version = sync_version + 1
      WHERE id = ? AND deleted_at IS NULL
        AND ${effective ? '(effective_at IS NULL OR effective_at >= ?)' : 'effective_at IS NOT NULL'}
    ''', variables: [
      if (effective) Variable.withInt(chosen),
      Variable.withInt(EntityMetadata.nowUtcMillis()),
      Variable.withString(id),
      if (effective) Variable.withInt(todayEnd),
    ]);
    if (changed != 1) {
      throw StateError('O lançamento já mudou de estado. Atualize a lista.');
    }
  }

  @override
  Future<void> changeEffectiveDate(String id,
          {required DateTime expectedDate, DateTime? effectiveDate}) =>
      _checked(() => _changeEffectiveDate(id,
          expectedDate: expectedDate, effectiveDate: effectiveDate));

  Future<void> _changeEffectiveDate(String id,
      {required DateTime expectedDate, DateTime? effectiveDate}) async {
    if (id.startsWith('invoice:')) {
      throw StateError('Pague pela ação da fatura.');
    }
    if (id.startsWith('card:')) {
      throw StateError('Pague pela fatura do cartão.');
    }
    final changed = await _db.customUpdate('''
      UPDATE transactions SET effective_at = ?, actual_amount_minor = ${effectiveDate == null ? 'NULL' : 'planned_amount_minor'},
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

  Future<FinancialTransaction> _find(String id) async {
    final rows = await _db.customSelect('''
      $_select WHERE t.id = ? AND t.deleted_at IS NULL
    ''', variables: [Variable.withString(id)]).get();
    if (rows.isEmpty) throw StateError('Lançamento não encontrado.');
    return _map(rows.single);
  }

  Future<void> _validateReferences(TransactionDraft draft,
      {bool checkAccount = true, bool checkCategory = true}) async {
    if (checkAccount) {
      final account = await _db.customSelect('''
        SELECT id FROM accounts WHERE id = ? AND deleted_at IS NULL
          AND is_archived = 0
      ''', variables: [Variable.withString(draft.accountId)]).get();
      if (account.isEmpty) throw StateError('Selecione uma conta ativa.');
    }
    if (!checkCategory || draft.categoryId == null) return;
    final category = await _db.customSelect('''
      SELECT c.id FROM categories c
      LEFT JOIN categories p ON p.id = c.parent_id
      WHERE c.id = ? AND c.type = ? AND c.deleted_at IS NULL
        AND c.is_archived = 0
        AND (c.parent_id IS NULL OR (p.is_archived = 0 AND p.deleted_at IS NULL))
    ''', variables: [
      Variable.withString(draft.categoryId!),
      Variable.withString(draft.type.name)
    ]).get();
    if (category.isEmpty) {
      throw StateError('Selecione uma categoria ativa do mesmo tipo.');
    }
  }

  void _validateDraft(TransactionDraft draft) {
    CategoryAllocation.validate(draft.allocations, draft.amountMinor);
    if (draft.allocations.isNotEmpty && draft.categoryId != null) {
      throw const FormatException('Use categoria única ou rateio.');
    }
    if (draft.description.trim().isEmpty) {
      throw const FormatException('Informe a descrição.');
    }
    if (draft.amountMinor <= 0) {
      throw const FormatException('O valor deve ser maior que zero.');
    }
    if (draft.amountMinor > 9000000000000000) {
      throw const FormatException('Valor acima do limite permitido.');
    }
    if (draft.accountId.isEmpty) throw StateError('Selecione uma conta.');
  }

  int _dayMillis(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch;

  FinancialTransaction _map(QueryRow row) => FinancialTransaction(
        id: row.read<String>('id'),
        allocations: CategoryAllocation.decode(
          row.read<String>('allocations_json'),
        ),
        series: SeriesStore.info(row),
        description: row.read<String>('description'),
        type: TransactionType.values.byName(row.read<String>('type')),
        amountMinor: row.read<int>('planned_amount_minor'),
        date: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('posted_at'),
          isUtc: true,
        ),
        dueDate: DateTime.fromMillisecondsSinceEpoch(row.read<int>('due_at'),
            isUtc: true),
        effectiveDate: row.readNullable<int>('effective_at') == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row.read<int>('effective_at'),
                isUtc: true),
        isEffective: row.readNullable<int>('effective_at') != null &&
            row.read<int>('effective_at') <
                _dayMillis(DateTime.now().add(const Duration(days: 1))),
        accountId: row.read<String>('account_id'),
        accountName: row.read<String>('account_name'),
        categoryId: row.readNullable<String>('category_id'),
        categoryName: row.readNullable<String>('category_name'),
        currencyCode: row.read<String>('currency_code'),
      );
}
