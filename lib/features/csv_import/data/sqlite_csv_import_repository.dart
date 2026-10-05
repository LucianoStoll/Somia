import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/backup_manager.dart';
import '../../accounts/data/sqlite_accounts_repository.dart';
import '../../categories/data/sqlite_categories_repository.dart';
import '../../transactions/data/category_history_repository.dart';
import '../../transactions/data/sqlite_transactions_repository.dart';
import '../../transactions/domain/financial_transaction.dart';
import '../domain/csv_document.dart';
import '../domain/csv_import.dart';

class SqliteCsvImportRepository implements CsvImportRepository {
  const SqliteCsvImportRepository(this.db, {this.maintenance});
  final AppDatabase db;
  final BackupManager? maintenance;
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

  @override
  Future<List<CsvPreviewRow>> preview(
      CsvDocument document, CsvMapping mapping, String accountId) async {
    mapping.validate(document.headers.length);
    final refs = await references();
    if (!refs.accounts.any((a) => a.id == accountId)) {
      throw const FormatException('Selecione uma conta ativa.');
    }
    final existing = await _existing(accountId);
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
            warning: warning));
      } on FormatException catch (e) {
        result.add(CsvPreviewRow(line: raw.line, error: e.message));
      }
    }
    return result;
  }

  @override
  Future<CsvImportResult> commit(
      List<CsvPreviewRow> rows, String accountId) async {
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
    Future<CsvImportResult> action() => db.transaction(() async {
          final refs = await references();
          if (!refs.accounts.any((a) => a.id == accountId)) {
            throw const FormatException(
                'A conta foi removida ou arquivada. Gere a prévia novamente.');
          }
          final existing = await _existing(accountId);
          var imported = 0, skipped = 0;
          final repository = SqliteTransactionsRepository(db);
          for (final row in selected) {
            final candidate = row.candidate!;
            final key = candidate.fingerprint(accountId);
            // A duplicate selected explicitly in the preview is intentional. New
            // duplicates appearing after preview are rechecked inside the commit.
            if (existing.contains(key) && !row.duplicate) {
              skipped++;
              continue;
            }
            await repository.create(candidate.draft(accountId, row.categoryId));
            existing.add(key);
            imported++;
          }
          return CsvImportResult(imported, skipped);
        });
    if (maintenance == null) return action();
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
