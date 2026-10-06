import 'package:drift/native.dart';
import 'package:finapp/core/series/movement_series.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/transactions/data/category_history_repository.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CategoryHistoryRepository history;
  late SqliteTransactionsRepository transactions;
  late String account, root, child, other, income;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    history = CategoryHistoryRepository(db);
    transactions = SqliteTransactionsRepository(db);
    account = (await SqliteAccountsRepository(db).create(const AccountDraft(
            name: 'Banco',
            type: AccountType.checking,
            currencyCode: 'BRL',
            initialBalanceMinor: 0,
            includeInAnalytics: true)))
        .id;
    final cats = SqliteCategoriesRepository(db);
    root = (await cats.create(const CategoryDraft(
            name: 'Alimentação', type: CategoryType.expense)))
        .id;
    child = (await cats.create(CategoryDraft(
            name: 'Restaurante', type: CategoryType.expense, parentId: root)))
        .id;
    other = (await cats.create(
            const CategoryDraft(name: 'Lazer', type: CategoryType.expense)))
        .id;
    income = (await cats.create(
            const CategoryDraft(name: 'Salário', type: CategoryType.income)))
        .id;
  });
  tearDown(() => db.close());
  Future<String> add(String description, String? category, int recent,
      {TransactionType type = TransactionType.expense}) async {
    final t = await transactions.create(TransactionDraft(
        description: description,
        type: type,
        amountMinor: 1000,
        date: DateTime(2025, 1),
        isEffective: false,
        accountId: account,
        categoryId: category));
    await db.customStatement(
        'UPDATE transactions SET updated_at=? WHERE id=?', [recent, t.id]);
    return t.id;
  }

  test('normaliza texto completo, usa classificação mais recente e separa tipo',
      () async {
    await add('Jantar', root, 1);
    await add(' JANTAR  ', child, 2);
    await add('Jantar', income, 3, type: TransactionType.income);
    final expense = await history.load(TransactionType.expense);
    expect(expense['jantar'], child);
    expect(expense['jan'], isNull);
    expect((await history.load(TransactionType.income))['jantar'], income);
    expect(CategoryHistoryRepository.normalize('  Jantar   fora  '),
        'jantar fora');
  });
  test('ignora excluídos, categoria ou pai arquivado e aceita histórico antigo',
      () async {
    await add('Jantar', other, 1);
    await add('Jantar', child, 2);
    final deleted = await add('Jantar', root, 3);
    await db.customStatement(
        'UPDATE transactions SET deleted_at=1 WHERE id=?', [deleted]);
    await db.customStatement(
        'UPDATE categories SET is_archived=1 WHERE id=?', [root]);
    expect((await history.load(TransactionType.expense))['jantar'], other);
    await db.customStatement(
        'UPDATE categories SET deleted_at=1 WHERE id=?', [other]);
    expect(await history.load(TransactionType.expense), isEmpty);
  });
  test('cartão e conta compartilham histórico, sem faturas ou ajustes',
      () async {
    await add('Jantar', root, 1);
    final cards = CardsRepository(db);
    final card = await cards.save(CardDraft(
        name: 'Nu', paymentAccountId: account, closingDay: 25, dueDay: 5));
    final purchase = await cards.createPurchase(TransactionDraft(
        description: 'Jantar',
        type: TransactionType.expense,
        amountMinor: 1500,
        date: DateTime(2026, 1),
        isEffective: false,
        accountId: account,
        cardId: card,
        categoryId: child));
    await db.customStatement(
        'UPDATE card_entries SET updated_at=2 WHERE id=?', [purchase]);
    expect((await history.load(TransactionType.expense))['jantar'], child);
    await add('Jantar', other, 3);
    expect((await history.load(TransactionType.expense))['jantar'], other);
    await cards.opening(card, DateTime(2026, 2), 1000);
    expect(
        (await history.load(TransactionType.expense))
            .containsKey('saldo inicial'),
        false);
    await cards.deletePurchase(purchase, SeriesScope.onlyThis);
    expect((await history.load(TransactionType.expense))['jantar'], other);
  });
  test('sem classificação recente usa anterior válida; só lê os dados',
      () async {
    await add('Jantar', child, 1);
    await add('Jantar', null, 2);
    final before = await transactions.list();
    expect((await history.load(TransactionType.expense))['jantar'], child);
    final after = await transactions.list();
    expect(after.map((e) => e.amountMinor), before.map((e) => e.amountMinor));
    expect(after.map((e) => e.categoryId), before.map((e) => e.categoryId));
  });
  test('sugestões distinguem contas e deduplicam descrição na mesma conta',
      () async {
    final bank = SqliteAccountsRepository(db);
    final second = (await bank.create(const AccountDraft(
            name: 'Reserva',
            type: AccountType.savings,
            currencyCode: 'BRL',
            initialBalanceMinor: 0,
            includeInAnalytics: true)))
        .id;
    await add('Rendimento CDI', income, 1, type: TransactionType.income);
    await add(' RENDIMENTO CDI ', income, 2, type: TransactionType.income);
    await transactions.create(TransactionDraft(
        description: 'Rendimento CDI',
        type: TransactionType.income,
        amountMinor: 25,
        date: DateTime(2026, 1),
        isEffective: false,
        accountId: second,
        categoryId: income));
    final suggestions = await history.suggestions(TransactionType.income);
    expect(suggestions, hasLength(2));
    expect(suggestions.first.accountId, second);
    expect(suggestions.first.amountMinor, 25);
    expect(suggestions.last.description, 'RENDIMENTO CDI');
    await db.customStatement(
        'UPDATE accounts SET is_archived=1 WHERE id=?', [second]);
    expect(await history.suggestions(TransactionType.income), hasLength(1));
    expect(await history.suggestions(TransactionType.expense), isEmpty);
  });
}
