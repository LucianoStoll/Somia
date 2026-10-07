import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';
import '../../../core/database/debt_integrity.dart';
import '../domain/debt.dart';

class SqliteDebtsRepository implements DebtsRepository {
  const SqliteDebtsRepository(this.db);
  final AppDatabase db;
  static int day(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch;
  static DateTime date(int d) =>
      DateTime.fromMillisecondsSinceEpoch(d, isUtc: true);
  Future<QueryRow> _find(String id) =>
      db.customSelect('SELECT * FROM debts WHERE id=? AND deleted_at IS NULL',
          variables: [Variable(id)]).getSingle();
  @override
  Future<List<Debt>> load() => db.transaction(() async {
        final debts = await db
            .customSelect(
                'SELECT * FROM debts WHERE deleted_at IS NULL ORDER BY lower(name),id')
            .get();
        final result = <Debt>[];
        final tomorrow = day(DateTime.now().add(const Duration(days: 1)));
        for (final d in debts) {
          final rows = await db.customSelect(
              '''SELECT p.*,t.description,t.planned_amount_minor,t.actual_amount_minor,t.effective_at,
        COALESCE(t.effective_at,t.due_at,t.posted_at) AS date,t.deleted_at AS transaction_deleted
        FROM debt_payments p JOIN transactions t ON t.id=p.transaction_id
        WHERE p.debt_id=? ORDER BY date DESC,p.created_at DESC,p.id DESC''',
              variables: [Variable(d.read<String>('id'))]).get();
          result.add(Debt(
              id: d.read<String>('id'),
              name: d.read<String>('name'),
              creditor: d.read<String>('creditor'),
              kind: DebtKind.values.byName(d.read<String>('kind')),
              initialMinor: d.read<int>('balance_minor'),
              referenceAt: date(d.read<int>('reference_at')),
              assetId: d.readNullable<String>('asset_id'),
              notes: d.read<String>('notes'),
              payments: rows
                  .map((p) => DebtPayment(
                      id: p.read<String>('id'),
                      transactionId: p.read<String>('transaction_id'),
                      description: (p.readNullable<int>('deleted_at') != null ||
                              p.readNullable<int>('transaction_deleted') !=
                                  null)
                          ? p.read<String>('linked_description')
                          : p.read<String>('description'),
                      amountMinor: (p.readNullable<int>('deleted_at') != null ||
                              p.readNullable<int>('transaction_deleted') !=
                                  null)
                          ? p.read<int>('linked_amount_minor')
                          : p.readNullable<int>('actual_amount_minor') ??
                              p.read<int>('planned_amount_minor'),
                      principalMinor: p.read<int>('principal_minor'),
                      date: date(p
                          .read<int>((p.readNullable<int>('deleted_at') != null || p.readNullable<int>('transaction_deleted') != null) ? 'linked_at' : 'date')),
                      effective: p.readNullable<int>('effective_at') != null && p.read<int>('effective_at') < tomorrow,
                      deleted: p.readNullable<int>('transaction_deleted') != null,
                      unlinked: p.readNullable<int>('deleted_at') != null))
                  .toList()));
        }
        return result;
      });
  @override
  Future<String> save(DebtDraft draft, {String? id}) =>
      db.transaction(() async {
        if (draft.name.trim().isEmpty || draft.creditor.trim().isEmpty) {
          throw const FormatException('Informe nome e credor.');
        }
        if (draft.balanceMinor < 0 || draft.balanceMinor > 9000000000000000) {
          throw const FormatException('Saldo inicial fora do limite.');
        }
        if (draft.referenceAt.year < 1900 ||
            day(draft.referenceAt) > day(DateTime.now())) {
          throw const FormatException(
              'A referência deve estar entre 1900 e hoje.');
        }
        if (draft.assetId != null) {
          final asset = await db.customSelect(
              'SELECT id FROM assets WHERE id=? AND deleted_at IS NULL',
              variables: [Variable(draft.assetId!)]).get();
          if (asset.isEmpty) {
            throw const FormatException('Selecione um bem cadastrado.');
          }
          final duplicate = await db.customSelect(
              'SELECT id FROM debts WHERE asset_id=? AND deleted_at IS NULL AND id<>?',
              variables: [Variable(draft.assetId!), Variable(id ?? '')]).get();
          if (duplicate.isNotEmpty) {
            throw const FormatException(
                'O bem já possui um financiamento vinculado.');
          }
        }
        final now = EntityMetadata.nowUtcMillis();
        final debtId = id ?? EntityMetadata.newId();
        if (id != null) {
          final old = await _find(debtId);
          if (old.readNullable<String>('asset_id') != draft.assetId) {
            throw const FormatException(
                'O vínculo com o bem é definido no cadastro e preservado no histórico.');
          }
          final links = await db.customSelect(
              'SELECT id FROM debt_payments WHERE debt_id=?',
              variables: [Variable(id)]).get();
          if (links.isNotEmpty &&
              (old.read<int>('balance_minor') != draft.balanceMinor ||
                  old.read<int>('reference_at') != day(draft.referenceAt))) {
            throw const FormatException(
                'Saldo inicial e referência ficam preservados após vincular parcelas.');
          }
          await db.customStatement(
              'UPDATE debts SET name=?,creditor=?,kind=?,balance_minor=?,reference_at=?,notes=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [
                draft.name.trim(),
                draft.creditor.trim(),
                draft.kind.name,
                draft.balanceMinor,
                day(draft.referenceAt),
                draft.notes.trim(),
                now,
                id
              ]);
        } else {
          await db.customStatement(
              'INSERT INTO debts(id,name,creditor,kind,balance_minor,reference_at,asset_id,notes,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)',
              [
                debtId,
                draft.name.trim(),
                draft.creditor.trim(),
                draft.kind.name,
                draft.balanceMinor,
                day(draft.referenceAt),
                draft.assetId,
                draft.notes.trim(),
                now,
                now
              ]);
        }
        await validateDebtFinancial(db);
        return debtId;
      });
  @override
  Future<List<DebtExpense>> expenses(String debtId) async {
    final debt = await _find(debtId);
    final tomorrow = day(DateTime.now().add(const Duration(days: 1)));
    final rows = await db.customSelect(
        '''SELECT t.id,t.description,t.planned_amount_minor,t.effective_at,COALESCE(t.effective_at,t.due_at,t.posted_at) AS date
      FROM transactions t JOIN accounts a ON a.id=t.account_id WHERE t.deleted_at IS NULL AND t.type='expense' AND a.currency_code='BRL'
      AND COALESCE(t.effective_at,t.due_at,t.posted_at)>=?
      AND NOT EXISTS(SELECT 1 FROM debt_payments p WHERE p.transaction_id=t.id AND p.deleted_at IS NULL)
      ORDER BY date,t.description,t.id''',
        variables: [Variable(debt.read<int>('reference_at'))]).get();
    return rows
        .map((r) => DebtExpense(
            id: r.read<String>('id'),
            description: r.read<String>('description'),
            amountMinor: r.read<int>('planned_amount_minor'),
            date: date(r.read<int>('date')),
            effective: r.readNullable<int>('effective_at') != null &&
                r.read<int>('effective_at') < tomorrow))
        .toList();
  }

  @override
  Future<void> link(String debtId, String transactionId, int principalMinor) =>
      db.transaction(() async {
        await _find(debtId);
        if (principalMinor < 0 || principalMinor > 9000000000000000) {
          throw const FormatException('Amortização fora do limite.');
        }
        final expense = (await expenses(debtId))
            .where((t) => t.id == transactionId)
            .firstOrNull;
        if (expense == null) {
          throw const FormatException(
              'Despesa indisponível ou já vinculada. Atualize a lista.');
        }
        if (principalMinor > expense.amountMinor) {
          throw const FormatException(
              'A amortização não pode superar o valor da parcela.');
        }
        final now = EntityMetadata.nowUtcMillis();
        await db.customStatement(
            'INSERT INTO debt_payments(id,debt_id,transaction_id,principal_minor,linked_amount_minor,linked_description,linked_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)',
            [
              EntityMetadata.newId(),
              debtId,
              transactionId,
              principalMinor,
              expense.amountMinor,
              expense.description,
              day(expense.date),
              now,
              now
            ]);
        await validateDebtFinancial(db);
      });
  @override
  Future<void> unlink(String paymentId) => db.transaction(() async {
        final n = await db.customUpdate(
            'UPDATE debt_payments SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=? AND deleted_at IS NULL',
            variables: [
              Variable(EntityMetadata.nowUtcMillis()),
              Variable(EntityMetadata.nowUtcMillis()),
              Variable(paymentId)
            ]);
        if (n != 1) throw StateError('O vínculo já mudou. Atualize a tela.');
      });
}
