import '../../features/transactions/domain/transaction_tags.dart';
import 'app_database.dart';
import 'debt_integrity.dart';
import 'reimbursement_integrity.dart';
import 'planning_integrity.dart';
import 'settlement_integrity.dart';
import '../allocations/category_allocation.dart';

const financialTables = [
  'accounts',
  'categories',
  'transactions',
  'transfers',
  'credit_cards',
  'card_limit_history',
  'card_invoices',
  'card_entries',
  'card_payments',
  'card_entry_history',
  'investments',
  'assets',
  'asset_valuations',
  'debts',
  'debt_payments',
  'people',
  'reimbursements',
  'reimbursement_receipts',
  'budget_limits',
  'planning_goals',
  'goal_accounts',
  'transaction_settlements',
];
typedef FinancialRows = Map<String, Map<String, Map<String, Object?>>>;

Future<Map<String, Map<String, String>>> financialColumns(
    AppDatabase db) async {
  final result = <String, Map<String, String>>{};
  for (final table in financialTables) {
    result[table] = {
      for (final row
          in await db.customSelect('PRAGMA table_info("$table")').get())
        row.read<String>('name'): row.read<String>('type'),
    };
  }
  return result;
}

Future<FinancialRows> readFinancial(AppDatabase db) async => {
      for (final table in financialTables)
        table: {
          for (final row in await db
              .customSelect('SELECT * FROM "$table" ORDER BY id')
              .get())
            row.read<String>('id'): Map<String, Object?>.from(row.data),
        },
    };

/// Caller owns the transaction. Imports only data, retaining trusted triggers.
Future<void> replaceFinancial(AppDatabase db, FinancialRows rows) async {
  await db.customStatement('PRAGMA defer_foreign_keys=ON');
  final triggers = await db
      .customSelect(
          "SELECT name,sql FROM main.sqlite_master WHERE type='trigger'")
      .get();
  for (final trigger in triggers) {
    final name = trigger.read<String>('name').replaceAll('"', '""');
    await db.customStatement('DROP TRIGGER "$name"');
  }
  for (final table in financialTables) {
    await db.customStatement('DELETE FROM "$table"');
  }
  final columns = await financialColumns(db);
  for (final table in financialTables) {
    final names = columns[table]!.keys.toList();
    final sql = 'INSERT INTO "$table" (${names.map((n) => '"$n"').join(',')}) '
        'VALUES (${List.filled(names.length, '?').join(',')})';
    for (final row in rows[table]!.values) {
      await db.customStatement(sql, names.map((n) => row[n]).toList());
    }
  }
  await validateFinancial(db);
  for (final trigger in triggers) {
    await db.customStatement(trigger.read<String>('sql'));
  }
}

Future<void> validateFinancial(AppDatabase db) async {
  await validateDebtFinancial(db);
  await validateReimbursements(db);
  await validatePlanning(db);
  await validateSettlements(db);
  final now = DateTime.now();
  final today =
      DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch;
  if ((await db.customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
    throw const FormatException(
        'Os dados recebidos contêm vínculos incompletos. Os dados atuais foram preservados.');
  }
  final invalid = await db.customSelect('''SELECT 1 FROM categories c
    JOIN categories p ON p.id=c.parent_id
    WHERE p.parent_id IS NOT NULL OR p.type<>c.type
    UNION ALL SELECT 1 FROM transactions t JOIN categories c ON c.id=t.category_id
    WHERE t.type<>c.type
    UNION ALL SELECT 1 FROM transfers t JOIN accounts a ON a.id=t.source_account_id
    JOIN accounts b ON b.id=t.destination_account_id WHERE a.currency_code<>b.currency_code
    UNION ALL SELECT 1 FROM card_entries e JOIN card_invoices i ON i.id=e.invoice_id
    WHERE e.card_id<>i.card_id
    UNION ALL SELECT 1 FROM card_entries e JOIN categories c ON c.id=e.category_id
    WHERE c.type<>'expense'
    UNION ALL SELECT 1 FROM credit_cards c JOIN accounts a ON a.id=c.payment_account_id
    WHERE a.currency_code<>'BRL'
    UNION ALL SELECT 1 FROM card_payments p JOIN accounts a ON a.id=p.account_id
    WHERE a.currency_code<>'BRL'
    UNION ALL SELECT 1 FROM investments v JOIN accounts a ON a.id=v.account_id
    WHERE a.currency_code<>'BRL' OR (v.deleted_at IS NULL AND a.deleted_at IS NOT NULL)
    UNION ALL SELECT 1 FROM asset_valuations v JOIN assets a ON a.id=v.asset_id
    WHERE v.deleted_at IS NULL AND (a.deleted_at IS NOT NULL OR v.assessed_at<a.acquired_at OR v.assessed_at>$today
      OR (v.debt_minor>0 AND length(trim(v.creditor))=0))
    UNION ALL SELECT 1 FROM assets a WHERE a.deleted_at IS NULL AND (a.acquired_at>$today OR NOT EXISTS
      (SELECT 1 FROM asset_valuations v WHERE v.asset_id=a.id AND v.deleted_at IS NULL))
    UNION ALL SELECT 1 FROM card_entries e
    WHERE (e.kind IN ('purchase','fee') AND e.amount_minor<0)
      OR (e.kind IN ('refund','discount') AND e.amount_minor>0) LIMIT 1''').get();
  final categories = {
    for (final r
        in await db.customSelect('SELECT id,type FROM categories').get())
      r.read<String>('id'): r.read<String>('type'),
  };
  for (final table in ['transactions', 'card_entries']) {
    for (final row
        in await db.customSelect('SELECT tags_json FROM $table').get()) {
      TransactionTags.decode(row.read<String>('tags_json'));
    }
    for (final row in await db.customSelect('SELECT * FROM $table').get()) {
      final parts = CategoryAllocation.decode(
        row.read<String>('allocations_json'),
      );
      final total = row
          .read<int>(
            table == 'transactions' ? 'planned_amount_minor' : 'amount_minor',
          )
          .abs();
      CategoryAllocation.validate(parts, total);
      if (table == 'transactions' &&
          parts.isNotEmpty &&
          row.readNullable<int>('actual_amount_minor') != null &&
          row.read<int>('actual_amount_minor') != total) {
        throw const FormatException(
            'Valor efetivado incompatível com o rateio.');
      }
      final type =
          table == 'transactions' ? row.read<String>('type') : 'expense';
      if ((parts.isNotEmpty &&
              row.readNullable<String>('category_id') != null) ||
          parts.any((p) => categories[p.categoryId] != type)) {
        throw const FormatException('Categorias do rateio incompatíveis.');
      }
    }
  }
  if (invalid.isNotEmpty) {
    throw const FormatException(
        'Os dados recebidos não formam registros financeiros válidos. Os dados atuais foram preservados.');
  }
}

Future<void> installSyncTriggers(AppDatabase db) async {
  final columns = await financialColumns(db);
  for (final table in financialTables) {
    for (final action in ['INSERT', 'UPDATE', 'DELETE']) {
      final isDelete = action == 'DELETE';
      final source = isDelete ? 'OLD' : 'NEW';
      final data = isDelete
          ? 'NULL'
          : 'json_object(${columns[table]!.keys.map((n) => "'$n',NEW.\"$n\"").join(',')})';
      await db.customStatement(
        'DROP TRIGGER IF EXISTS sync_${table}_${action.toLowerCase()}',
      );
      await db.customStatement(
        '''CREATE TRIGGER IF NOT EXISTS sync_${table}_${action.toLowerCase()}
        AFTER $action ON "$table"
        WHEN (SELECT capture_enabled FROM sync_state WHERE id=1)=1
        BEGIN
          UPDATE sync_state SET clock=max(clock+1,
            CAST((julianday('now')-2440587.5)*86400000 AS INTEGER)) WHERE id=1;
          INSERT OR IGNORE INTO sync_history
            SELECT table_name,row_id,clock,device_id,is_deleted,data,'local',
              (SELECT clock FROM sync_state WHERE id=1)
            FROM sync_versions WHERE table_name='$table' AND row_id=$source.id;
          INSERT OR REPLACE INTO sync_versions VALUES ('$table',$source.id,
            (SELECT clock FROM sync_state WHERE id=1),
            (SELECT device_id FROM sync_state WHERE id=1),${isDelete ? 1 : 0},$data);
          INSERT OR REPLACE INTO sync_outbox
            SELECT * FROM sync_versions WHERE table_name='$table' AND row_id=$source.id;
        END''',
      );
    }
  }
}
