import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/backup_manager.dart';
import '../../../core/database/local_backup_store.dart';
import '../../accounts/data/sqlite_accounts_repository.dart';
import '../../categories/data/sqlite_categories_repository.dart';
import '../../transactions/data/category_history_repository.dart';
import '../../transactions/data/sqlite_transactions_repository.dart';
import '../../transactions/domain/financial_transaction.dart';
import '../domain/csv_document.dart';
import '../domain/csv_import.dart';
import '../domain/import_history.dart';

class SqliteCsvImportRepository
    implements CsvImportRepository, CsvImportHistory {
  const SqliteCsvImportRepository(this.db, {this.maintenance});
  final AppDatabase db;
  final BackupManager? maintenance;

  @override
  Future<List<ImportBatch>> batches() async => [
        for (final row in await db
            .customSelect('''SELECT id,account_id,source_name,created_at
          FROM import_batches WHERE undone_at IS NULL ORDER BY created_at DESC''').get())
          ImportBatch(
            row.read<String>('id'),
            row.read<String>('source_name'),
            DateTime.fromMillisecondsSinceEpoch(row.read<int>('created_at')),
            row.read<String>('account_id'),
          )
      ];

  @override
  Future<List<ImportUndoEntry>> inspectUndo(String batchId) async {
    final rows = await db.customSelect(
        '''SELECT e.*,t.description,t.updated_at,t.sync_version,t.deleted_at
      FROM import_batch_entries e LEFT JOIN transactions t
        ON e.action='created' AND t.id=e.target_id
      WHERE e.batch_id=? AND e.undone_at IS NULL ORDER BY e.source_line''',
        variables: [Variable.withString(batchId)]).get();
    return [
      for (final row in rows)
        ImportUndoEntry(
          row.read<String>('id'),
          row.read<int>('source_line'),
          row.read<String>('action'),
          row.readNullable<String>('description') ?? 'Vínculo existente',
          row.read<String>('action') == 'linked' ||
              (row.readNullable<int>('deleted_at') == null &&
                  row.readNullable<int>('updated_at') ==
                      row.read<int>('initial_updated_at') &&
                  row.readNullable<int>('sync_version') ==
                      row.read<int>('initial_sync_version')),
          row.read<String>('action') == 'linked' ||
                  (row.readNullable<int>('deleted_at') == null &&
                      row.readNullable<int>('updated_at') ==
                          row.read<int>('initial_updated_at') &&
                      row.readNullable<int>('sync_version') ==
                          row.read<int>('initial_sync_version'))
              ? null
              : 'Lançamento alterado, excluído ou sincronizado; revise manualmente.',
        )
    ];
  }

  @override
  Future<int> undo(String batchId, Set<String> entryIds) async {
    if (entryIds.isEmpty) return 0;
    Future<int> action() => db.transaction(() async {
          final batch = await db.customSelect(
              'SELECT id FROM import_batches WHERE id=? AND undone_at IS NULL',
              variables: [Variable.withString(batchId)]).get();
          if (batch.isEmpty) {
            throw const FormatException(
                'Lote não disponível. Atualize a lista.');
          }
          final entries = await inspectUndo(batchId);
          if (entryIds.length !=
                  entries.where((e) => entryIds.contains(e.id)).length ||
              entries.any((e) => entryIds.contains(e.id) && !e.canUndo)) {
            throw const FormatException(
                'O lote mudou. Revise os conflitos antes de desfazer.');
          }
          final raw = await db.customSelect(
              'SELECT id,target_id,action FROM import_batch_entries WHERE batch_id=? AND undone_at IS NULL',
              variables: [Variable.withString(batchId)]).get();
          for (final entry
              in raw.where((r) => entryIds.contains(r.read<String>('id')))) {
            if (entry.read<String>('action') == 'created') {
              await SqliteTransactionsRepository(db)
                  .delete(entry.read<String>('target_id'));
            }
            await db.customStatement(
                'UPDATE import_batch_entries SET undone_at=? WHERE id=?', [
              DateTime.now().millisecondsSinceEpoch,
              entry.read<String>('id')
            ]);
          }
          final remaining = await db.customSelect(
              'SELECT id FROM import_batch_entries WHERE batch_id=? AND undone_at IS NULL',
              variables: [Variable.withString(batchId)]).get();
          if (remaining.isEmpty) {
            await db.customStatement(
                'UPDATE import_batches SET undone_at=? WHERE id=?',
                [DateTime.now().millisecondsSinceEpoch, batchId]);
          }
          return entryIds.length;
        });
    if (maintenance == null) return action();
    await maintenance!.store.create(db, BackupKind.beforeImport);
    return maintenance!.maintain(action);
  }

  @override
  Future<CsvReferences> references() async {
    final accounts = (await SqliteAccountsRepository(db).list())
        .where((a) => !a.isArchived)
        .toList();
    final all = await SqliteCategoriesRepository(db).list();
    final categories = all
        .where((c) =>
            !c.isArchived &&
            (c.parentId == null ||
                all.any((p) => p.id == c.parentId && !p.isArchived)))
        .toList();
    return CsvReferences(accounts, categories);
  }

  Future<Set<String>> _existing(String accountId) async {
    final rows = await db.customSelect(
        '''SELECT description,type,planned_amount_minor,posted_at,due_at
      FROM transactions WHERE account_id=? AND deleted_at IS NULL''',
        variables: [Variable.withString(accountId)]).get();
    return rows
        .map((r) => CsvCandidate(
                line: 0,
                description: r.read<String>('description'),
                type: TransactionType.values.byName(r.read<String>('type')),
                amountMinor: r.read<int>('planned_amount_minor'),
                date: DateTime.fromMillisecondsSinceEpoch(
                    r.read<int>('posted_at'),
                    isUtc: true),
                dueDate: DateTime.fromMillisecondsSinceEpoch(
                    r.read<int>('due_at'),
                    isUtc: true))
            .fingerprint(accountId))
        .toSet();
  }

  Future<List<QueryRow>> _matchSources(String accountId) async {
    final queries = [
      '''SELECT 'transactions' target_table,id,description,type,
        planned_amount_minor amount_minor,COALESCE(effective_at,due_at) date_at
        FROM transactions WHERE account_id=? AND deleted_at IS NULL
        AND trash_state='active' ''',
      '''SELECT 'transaction_settlements' target_table,s.id,t.description,
        t.type,s.amount_minor,s.effective_at date_at
        FROM transaction_settlements s JOIN transactions t ON t.id=s.transaction_id
        WHERE s.account_id=? AND s.deleted_at IS NULL AND t.deleted_at IS NULL''',
      '''SELECT 'transfers' target_table,id,description,
        CASE WHEN source_account_id=? THEN 'expense' ELSE 'income' END type,
        amount_minor,COALESCE(effective_at,due_at) date_at
        FROM transfers WHERE (source_account_id=? OR destination_account_id=?)
        AND deleted_at IS NULL AND trash_state='active' ''',
      '''SELECT 'card_payments' target_table,id,'Pagamento de fatura' description,
        'expense' type,amount_minor,effective_at date_at
        FROM card_payments WHERE account_id=? AND deleted_at IS NULL''',
    ];
    final result = <QueryRow>[];
    for (var i = 0; i < queries.length; i++) {
      result.addAll(await db.customSelect(queries[i], variables: [
        for (var n = 0; n < (i == 2 ? 3 : 1); n++)
          Variable.withString(accountId)
      ]).get());
    }
    return result;
  }

  List<CsvMatch> _suggest(
      CsvCandidate candidate, List<QueryRow> sources, Set<String> linked) {
    final date = candidate.effectiveDate ?? candidate.dueDate;
    final matches = <CsvMatch>[];
    for (final source in sources) {
      final table = source.read<String>('target_table');
      final id = source.read<String>('id');
      if (linked.contains('$table:$id') ||
          source.read<int>('amount_minor') != candidate.amountMinor ||
          source.read<String>('type') != candidate.type.name) {
        continue;
      }
      final stamp = source.readNullable<int>('date_at');
      if (stamp == null) {
        continue;
      }
      final sourceDate =
          DateTime.fromMillisecondsSinceEpoch(stamp, isUtc: true);
      final days = date.difference(sourceDate).inDays.abs();
      if (days > 3) {
        continue;
      }
      final label = source.read<String>('description');
      final same = csvNormalize(label) == csvNormalize(candidate.description);
      matches.add(CsvMatch(
          table, id, label, sourceDate, (days == 0 ? 2 : 0) + (same ? 3 : 0)));
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.take(4).toList();
  }

  @override
  Future<List<CsvPreviewRow>> preview(
      CsvDocument document, CsvMapping mapping, String accountId) async {
    mapping.validate(document.headers.length);
    final refs = await references();
    if (!refs.accounts.any((a) => a.id == accountId)) {
      throw const FormatException('Selecione uma conta ativa.');
    }
    final existing = await _existing(accountId);
    final sources = await _matchSources(accountId);
    final linked = {
      for (final row in await db
          .customSelect(
              'SELECT target_table,target_id FROM import_batch_entries WHERE undone_at IS NULL')
          .get())
        '${row.read<String>('target_table')}:${row.read<String>('target_id')}'
    };
    final seen = <String>{};
    final history = <TransactionType, Map<String, String>>{};
    for (final type in TransactionType.values) {
      history[type] = await CategoryHistoryRepository(db).load(type);
    }
    final result = <CsvPreviewRow>[];
    for (final raw in document.rows) {
      try {
        final candidate = mapping.parse(raw, document.headers.length);
        final key = candidate.fingerprint(accountId);
        final duplicate = existing.contains(key) || !seen.add(key);
        String? categoryId, warning;
        if (candidate.categoryText.isNotEmpty ||
            candidate.subcategoryText.isNotEmpty) {
          final matches = refs.categories.where((c) {
            if (c.type.name != candidate.type.name) return false;
            if (candidate.subcategoryText.isEmpty) {
              return c.parentId == null &&
                  csvNormalize(c.name) == csvNormalize(candidate.categoryText);
            }
            if (c.parentId == null ||
                csvNormalize(c.name) !=
                    csvNormalize(candidate.subcategoryText)) {
              return false;
            }
            return candidate.categoryText.isEmpty ||
                refs.categories.any((p) =>
                    p.id == c.parentId &&
                    csvNormalize(p.name) ==
                        csvNormalize(candidate.categoryText));
          }).toList();
          if (matches.length == 1) {
            categoryId = matches.single.id;
          } else {
            warning =
                'Categoria não encontrada ou ambígua. Escolha na prévia ou importe sem categoria.';
          }
        } else {
          categoryId = history[candidate.type]![
              CategoryHistoryRepository.normalize(candidate.description)];
          if (categoryId != null) {
            warning = 'Categoria sugerida pelo histórico.';
          }
        }
        result.add(CsvPreviewRow(
            line: raw.line,
            candidate: candidate,
            duplicate: duplicate,
            selected: !duplicate,
            categoryId: categoryId,
            matches: _suggest(candidate, sources, linked),
            warning: warning));
      } on FormatException catch (e) {
        result.add(CsvPreviewRow(line: raw.line, error: e.message));
      }
    }
    return result;
  }

  @override
  Future<CsvImportResult> commit(List<CsvPreviewRow> rows, String accountId,
      {String sourceName = 'Extrato'}) async {
    final selected =
        rows.where((r) => r.selected && r.candidate != null).toList();
    if (selected.isEmpty) {
      throw const FormatException('Selecione ao menos um lançamento válido.');
    }
    if (selected.length > CsvDocument.maxRows ||
        selected.map((r) => r.line).toSet().length != selected.length) {
      throw const FormatException(
          'Seleção de linhas inválida. Gere a prévia novamente.');
    }
    final label = sourceName.trim();
    if (label.isEmpty || label.length > 150) {
      throw const FormatException('Nome do arquivo de origem inválido.');
    }
    Future<CsvImportResult> action() => db.transaction(() async {
          final refs = await references();
          if (!refs.accounts.any((a) => a.id == accountId)) {
            throw const FormatException(
                'A conta foi removida ou arquivada. Gere a prévia novamente.');
          }
          final existing = await _existing(accountId);
          final sources = await _matchSources(accountId);
          final linkedTargets = {
            for (final row in await db
                .customSelect(
                    'SELECT target_table,target_id FROM import_batch_entries WHERE undone_at IS NULL')
                .get())
              '${row.read<String>('target_table')}:${row.read<String>('target_id')}'
          };
          var imported = 0, skipped = 0, linked = 0;
          final batchId = const Uuid().v4();
          await db.customStatement('''INSERT INTO import_batches
                  (id,account_id,source_name,created_at) VALUES(?,?,?,?)''', [
            batchId,
            accountId,
            label,
            DateTime.now().millisecondsSinceEpoch
          ]);
          final repository = SqliteTransactionsRepository(db);
          for (final row in selected) {
            final candidate = row.candidate!;
            final key = candidate.fingerprint(accountId);
            if (row.linkTarget != null) {
              final target = row.linkTarget!;
              final targetKey = '${target.table}:${target.id}';
              if (linkedTargets.contains(targetKey) ||
                  !_suggest(candidate, sources, linkedTargets).any(
                      (m) => m.table == target.table && m.id == target.id)) {
                throw const FormatException(
                    'Um vínculo mudou desde a prévia. Gere a prévia novamente.');
              }
              await db.customStatement('''INSERT INTO import_batch_entries
                  (id,batch_id,target_table,target_id,action,source_line,
                   initial_updated_at,initial_sync_version)
                  VALUES(?,?,?,?,?,?,?,?)''', [
                const Uuid().v4(),
                batchId,
                target.table,
                target.id,
                'linked',
                row.line,
                0,
                0
              ]);
              linkedTargets.add(targetKey);
              linked++;
              continue;
            }
            // A duplicate selected explicitly in the preview is intentional. New
            // duplicates appearing after preview are rechecked inside the commit.
            if (existing.contains(key) && !row.duplicate) {
              skipped++;
              continue;
            }
            final created = await repository
                .create(candidate.draft(accountId, row.categoryId));
            final stored = await db.customSelect(
                'SELECT updated_at,sync_version FROM transactions WHERE id=?',
                variables: [Variable.withString(created.id)]).getSingle();
            await db.customStatement('''INSERT INTO import_batch_entries
                  (id,batch_id,target_table,target_id,action,source_line,
                   initial_updated_at,initial_sync_version)
                  VALUES(?,?,?,?,?,?,?,?)''', [
              const Uuid().v4(),
              batchId,
              'transactions',
              created.id,
              'created',
              row.line,
              stored.read<int>('updated_at'),
              stored.read<int>('sync_version')
            ]);
            existing.add(key);
            imported++;
          }
          if (imported + linked == 0) {
            await db.customStatement(
                'DELETE FROM import_batches WHERE id=?', [batchId]);
          }
          return CsvImportResult(imported, skipped,
              batchId: imported + linked > 0 ? batchId : null, linked: linked);
        });
    if (maintenance == null) return action();
    // A validated recoverable copy must exist before any financial write.
    await maintenance!.store.create(db, BackupKind.beforeImport);
    CsvImportResult? committed;
    try {
      return await maintenance!.maintain(() async {
        committed = await action();
        return committed!;
      }, refreshScreens: false);
    } catch (_) {
      // A failure refreshing backup metadata after commit must not report that
      // the financial import failed, nor invite a duplicate retry.
      if (committed != null) return committed!;
      rethrow;
    }
  }
}
