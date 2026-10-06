import 'dart:convert';
import 'dart:io';
import 'package:finapp/core/database/backup_manager.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/csv_import/domain/csv_document.dart';
import 'package:finapp/features/csv_import/domain/csv_import.dart';
import 'package:finapp/features/csv_import/data/sqlite_csv_import_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class FailingBackupStore extends LocalBackupStore {
  FailingBackupStore() : super(Directory.systemTemp);
  @override
  Future<List<LocalBackupCopy>> list() async =>
      throw const FileSystemException('list failure');
}

void main() {
  late AppDatabase db;
  late Account account;
  late SqliteCsvImportRepository repo;
  late SqliteTransactionsRepository movements;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    account = await SqliteAccountsRepository(db).create(const AccountDraft(
        name: 'Conta',
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 5000,
        includeInAnalytics: true));
    repo = SqliteCsvImportRepository(db);
    movements = SqliteTransactionsRepository(db);
  });
  tearDown(() => db.close());
  Future<List<CsvPreviewRow>> preview(String csv) async {
    final doc = CsvDocument.read(utf8.encode(csv));
    return repo.preview(doc, CsvMapping.suggest(doc.headers), account.id);
  }

  test(
      'prévia não escreve; lote importa pendências, datas e centavos e entra na fila de sync',
      () async {
    await db.customStatement(
        "UPDATE sync_state SET base_id='base',email='test@example.com',device_id='device',capture_enabled=1 WHERE id=1");
    final rows = await preview(
        'Descrição;Valor;Data;Vencimento;Efetivação\nCompra;-10,03;05/10/2026;10/10/2026;\nRecebimento;30;05/10/2026;;05/10/2026\nErro;abc;05/10/2026;;');
    expect(await movements.list(), isEmpty);
    expect(rows.last.error, isNotNull);
    var events = 0;
    final sub = db.financialChanges.listen((_) => events++);
    addTearDown(sub.cancel);
    final result = await repo.commit(rows, account.id);
    await Future<void>.delayed(Duration.zero);
    expect(result.imported, 2);
    expect(events, 1);
    final all = await movements.list();
    final expense = all.firstWhere((r) => r.type == TransactionType.expense);
    expect(expense.amountMinor, 1003);
    expect(expense.effectiveDate, isNull);
    expect(expense.dueDate, DateTime.utc(2026, 10, 10));
    expect(
        (await SqliteAccountsRepository(db).list()).single.currentBalanceMinor,
        8000);
    expect(
        (await db.customSelect('SELECT * FROM sync_outbox').get()).length, 2);
  });
  test(
      'duplicados no arquivo e no banco ficam desmarcados; repetição não duplica dados',
      () async {
    const csv =
        'Descrição;Valor;Data\nCompra;-10;05/10/2026\nCompra;-10;05/10/2026';
    final rows = await preview(csv);
    expect(rows[0].selected, isTrue);
    expect(rows[1].duplicate, isTrue);
    expect(rows[1].selected, isFalse);
    expect((await repo.commit(rows, account.id)).imported, 1);
    final again = await preview(csv);
    expect(again.every((r) => r.duplicate && !r.selected), isTrue);
    expect(
        (await repo.commit([again[0].select(true)], account.id)).imported, 1);
    expect((await movements.list()).length, 2);
  });
  test(
      'duplicado surgido após prévia é ignorado ao confirmar e categorias não alteram comparação',
      () async {
    final rows = await preview('Descrição;Valor;Data\nCompra;-10;05/10/2026');
    await movements.create(rows.single.candidate!.draft(account.id, null));
    final result = await repo.commit(rows, account.id);
    expect(result.imported, 0);
    expect(result.skipped, 1);
    expect((await movements.list()).length, 1);
  });
  test(
      'categoria/subcategoria pelo nome, sugestão pelo histórico e categoria desconhecida',
      () async {
    final categories = SqliteCategoriesRepository(db);
    final parent = await categories.create(
        const CategoryDraft(name: 'Alimentação', type: CategoryType.expense));
    final child = await categories.create(CategoryDraft(
        name: 'Mercado', type: CategoryType.expense, parentId: parent.id));
    await movements.create(TransactionDraft(
        description: 'Café',
        type: TransactionType.expense,
        amountMinor: 200,
        date: DateTime.utc(2026, 9, 1),
        isEffective: false,
        accountId: account.id,
        categoryId: child.id));
    final rows = await preview(
        'Descrição;Valor;Data;Categoria;Subcategoria\nCompra;-10;05/10/2026;Alimentacao;Mercado\nCafé;-3;05/10/2026;;\nPix;-5;05/10/2026;Não existe;');
    expect(rows[0].categoryId, child.id);
    expect(rows[1].categoryId, child.id);
    expect(rows[1].warning, contains('histórico'));
    expect(rows[2].categoryId, isNull);
    expect(rows[2].warning, isNotNull);
    await categories.setArchived(parent.id, archived: true);
    final updated = await preview('Descrição;Valor;Data\nCafé;-3;05/10/2026');
    expect(updated.single.categoryId, isNull);
  });
  test(
      'categoria arquivada após prévia reverte lote inteiro e não deixa outbox parcial',
      () async {
    final categories = SqliteCategoriesRepository(db);
    final category = await categories.create(
        const CategoryDraft(name: 'Mercado', type: CategoryType.expense));
    final rows = await preview(
        'Descrição;Valor;Data\nPrimeiro;-10;05/10/2026\nSegundo;-20;05/10/2026');
    await categories.setArchived(category.id, archived: true);
    await db.customStatement(
        "UPDATE sync_state SET base_id='base',email='test@example.com',device_id='device',capture_enabled=1 WHERE id=1");
    await expectLater(
        repo.commit([rows[0], rows[1].category(category.id)], account.id),
        throwsStateError);
    expect(await movements.list(), isEmpty);
    expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
  });
  test('conta arquivada após prévia e seleção repetida não são importadas',
      () async {
    final rows = await preview('Descrição;Valor;Data\nCompra;-10;05/10/2026');
    await expectLater(repo.commit([rows.single, rows.single], account.id),
        throwsFormatException);
    await SqliteAccountsRepository(db).setArchived(account.id, archived: true);
    await expectLater(repo.commit(rows, account.id), throwsFormatException);
    expect(await movements.list(), isEmpty);
  });
  test(
      'falha de metadados de backup após commit não transforma importação concluída em erro',
      () async {
    final manager = BackupManager(db, FailingBackupStore());
    addTearDown(manager.dispose);
    final rows = await preview('Descrição;Valor;Data\nCompra;-10;05/10/2026');
    final result = await SqliteCsvImportRepository(db, maintenance: manager)
        .commit(rows, account.id);
    expect(result.imported, 1);
    expect((await movements.list()).length, 1);
    expect(manager.error, isNotNull);
  });
}
