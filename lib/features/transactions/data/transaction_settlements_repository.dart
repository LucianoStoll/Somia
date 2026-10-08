import 'package:drift/drift.dart';
import '../../../core/allocations/category_allocation.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';
import '../../../core/database/settlement_integrity.dart';

class TransactionSettlement {
  const TransactionSettlement(
      this.id, this.accountId, this.accountName, this.amountMinor, this.date);
  final String id, accountId, accountName;
  final int amountMinor;
  final DateTime date;
}

class TransactionSettlementsRepository {
  const TransactionSettlementsRepository(this.db);
  final AppDatabase db;
  Future<List<TransactionSettlement>> list(String id) async => [
        for (final r in await db.customSelect(
            '''SELECT s.*,a.name FROM transaction_settlements s
      JOIN accounts a ON a.id=s.account_id WHERE s.transaction_id=? AND s.deleted_at IS NULL
      ORDER BY s.effective_at,s.created_at,s.id''',
            variables: [Variable.withString(id)]).get())
          TransactionSettlement(
              r.read<String>('id'),
              r.read<String>('account_id'),
              r.read<String>('name'),
              r.read<int>('amount_minor'),
              DateTime.fromMillisecondsSinceEpoch(r.read<int>('effective_at'),
                  isUtc: true))
      ];
  Future<String> add(String transactionId,
          {required String accountId,
          required int amountMinor,
          required DateTime date}) =>
      db.transaction(() async {
        final t = await db.customSelect(
            '''SELECT t.*,a.currency_code FROM transactions t JOIN accounts a ON a.id=t.account_id
      WHERE t.id=? AND t.deleted_at IS NULL''',
            variables: [Variable.withString(transactionId)]).getSingleOrNull();
        final a = await db.customSelect(
            'SELECT * FROM accounts WHERE id=? AND deleted_at IS NULL AND is_archived=0',
            variables: [Variable.withString(accountId)]).getSingleOrNull();
        if (t == null ||
            a == null ||
            a.read<String>('currency_code') !=
                t.read<String>('currency_code') ||
            amountMinor <= 0 ||
            amountMinor > 9000000000000000) {
          throw const FormatException(
              'Informe valor positivo e uma conta ativa da mesma moeda.');
        }
        final previous = await list(transactionId);
        final sum = previous.fold(0, (v, s) => v + s.amountMinor);
        if (t.readNullable<int>('effective_at') != null ||
            sum + amountMinor > t.read<int>('planned_amount_minor')) {
          throw const FormatException(
              'A baixa excede o saldo pendente. Desfaça a efetivação integral antes de registrar baixas.');
        }
        final parts =
            CategoryAllocation.decode(t.read<String>('allocations_json'));
        final used = <String, int>{};
        for (final r in await db.customSelect(
            'SELECT allocations_json FROM transaction_settlements WHERE transaction_id=? AND deleted_at IS NULL',
            variables: [Variable.withString(transactionId)]).get()) {
          for (final p in CategoryAllocation.decode(
              r.read<String>('allocations_json'))) {
            used[p.categoryId] = (used[p.categoryId] ?? 0) + p.amountMinor;
          }
        }
        final allocation = CategoryAllocation.distribute([
          for (final p in parts)
            CategoryAllocation(
                p.categoryId, p.amountMinor - (used[p.categoryId] ?? 0))
        ], amountMinor);
        final id = EntityMetadata.newId(), now = EntityMetadata.nowUtcMillis();
        await db.customStatement(
            '''INSERT INTO transaction_settlements(id,transaction_id,account_id,amount_minor,effective_at,allocations_json,created_at,updated_at)
      VALUES(?,?,?,?,?,?,?,?)''',
            [
              id,
              transactionId,
              accountId,
              amountMinor,
              DateTime.utc(date.year, date.month, date.day)
                  .millisecondsSinceEpoch,
              CategoryAllocation.encode(allocation),
              now,
              now
            ]);
        await validateSettlements(db);
        return id;
      });
  Future<void> remove(String transactionId, String id) =>
      db.transaction(() async {
        final n = await db.customUpdate(
            'UPDATE transaction_settlements SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=? AND transaction_id=? AND deleted_at IS NULL',
            variables: [
              Variable.withInt(EntityMetadata.nowUtcMillis()),
              Variable.withInt(EntityMetadata.nowUtcMillis()),
              Variable.withString(id),
              Variable.withString(transactionId)
            ]);
        if (n != 1)
          throw const FormatException(
              'A baixa já foi alterada. Atualize o histórico.');
        await validateSettlements(db);
      });
}
