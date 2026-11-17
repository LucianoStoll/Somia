import 'package:drift/native.dart';
import 'package:finapp/core/allocations/category_allocation.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/dashboard/data/sqlite_dashboard_repository.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/data/transaction_settlements_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('realizado separa pendências, agendamentos, baixas, rateios e cartão',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final accounts = SqliteAccountsRepository(db);
    Future<Account> account(String name,
            {String currency = 'BRL', bool analytics = true}) =>
        accounts.create(AccountDraft(
            name: name,
            type: AccountType.checking,
            currencyCode: currency,
            initialBalanceMinor: 100000,
            includeInAnalytics: analytics));
    final bank = await account('Banco');
    final wallet = await account('Carteira');
    final usd = await account('Exterior', currency: 'USD');
    final hidden = await account('Fora das análises', analytics: false);
    final categories = SqliteCategoriesRepository(db);
    final a = await categories
        .create(const CategoryDraft(name: 'Casa', type: CategoryType.expense));
    final b = await categories.create(
        const CategoryDraft(name: 'Outros', type: CategoryType.expense));
    final tx = SqliteTransactionsRepository(db);
    Future<FinancialTransaction> income(int amount, DateTime due,
            {DateTime? effective, String? accountId}) =>
        tx.create(TransactionDraft(
            description: 'Receita',
            type: TransactionType.income,
            amountMinor: amount,
            date: DateTime.utc(2026, 9, 1),
            dueDate: due,
            effectiveDate: effective,
            isEffective: effective != null,
            accountId: accountId ?? bank.id));
    await income(5000, DateTime.utc(2026, 9, 10),
        effective: DateTime.utc(2026, 9, 10));
    await income(9000, DateTime.utc(2026, 9, 20));
    await income(7000, DateTime.utc(2026, 9, 25),
        effective: DateTime.utc(2026, 9, 25));
    await income(1000, DateTime.utc(2026, 9, 10),
        effective: DateTime.utc(2026, 9, 10), accountId: usd.id);
    await income(500000, DateTime.utc(2026, 9, 10),
        effective: DateTime.utc(2026, 9, 10), accountId: hidden.id);
    final partial = await tx.create(TransactionDraft(
        description: 'Parcial',
        type: TransactionType.expense,
        amountMinor: 10000,
        date: DateTime.utc(2026, 9, 1),
        dueDate: DateTime.utc(2026, 9, 20),
        isEffective: false,
        accountId: bank.id,
        allocations: [
          CategoryAllocation(a.id, 6000),
          CategoryAllocation(b.id, 4000)
        ]));
    await TransactionSettlementsRepository(db).add(partial.id,
        accountId: bank.id, amountMinor: 3000, date: DateTime.utc(2026, 9, 12));
    await tx.create(TransactionDraft(
        description: 'Paga',
        type: TransactionType.expense,
        amountMinor: 2000,
        date: DateTime.utc(2026, 9, 10),
        isEffective: true,
        accountId: bank.id,
        categoryId: a.id));
    await SqliteTransfersRepository(db).create(TransferDraft(
        sourceAccountId: bank.id,
        destinationAccountId: wallet.id,
        amountMinor: 500,
        date: DateTime.utc(2026, 9, 10),
        isEffective: true));
    final cards = CardsRepository(db);
    final cardId = await cards.save(CardDraft(
        name: 'Cartão', paymentAccountId: bank.id, closingDay: 25, dueDay: 5));
    Future<void> purchase(DateTime date) => cards
        .createPurchase(TransactionDraft(
            description: 'Compra',
            type: TransactionType.expense,
            amountMinor: 4000,
            date: date,
            isEffective: true,
            accountId: bank.id,
            cardId: cardId,
            categoryId: a.id))
        .then((_) {});
    await purchase(DateTime.utc(2026, 8, 20));
    await purchase(DateTime.utc(2026, 9, 20));
    final entries = await cards.entries(cardId: cardId);
    final entry = entries.singleWhere((e) => e.invoiceMonth.month == 9);
    await cards.refund(
        entry.id, 1000, entry.invoiceId, DateTime.utc(2026, 9, 10));
    await cards.pay(entry.invoiceId, bank.id, 3000, DateTime.utc(2026, 9, 12));
    final repo = SqliteDashboardRepository(db, asOf: DateTime.utc(2026, 9, 15));
    final result = await repo.load(DateTime(2026, 9));
    final brl = result.currencies.singleWhere((c) => c.currencyCode == 'BRL');
    expect(brl.realizedIncomeMinor, 5000);
    expect(brl.incomeMinor, 21000);
    expect(brl.realizedExpenseMinor, 8000);
    expect(brl.expenseMinor, 15000);
    expect(
        brl.realizedExpensesByCategory
            .singleWhere((c) => c.name == 'Casa')
            .amountMinor,
        6800);
    expect(
        brl.realizedExpensesByCategory
            .singleWhere((c) => c.name == 'Outros')
            .amountMinor,
        1200);
    expect(brl.history.last.realizedIncomeMinor, 5000);
    expect(brl.history.last.realizedExpenseMinor, 8000);
    expect(brl.forAnalysis(realized: true).history.last.expenseMinor, 8000);
    expect(
        result.currencies
            .singleWhere((c) => c.currencyCode == 'USD')
            .realizedIncomeMinor,
        1000);
    final october = (await repo.load(DateTime(2026, 10)))
        .currencies
        .singleWhere((c) => c.currencyCode == 'BRL');
    expect(october.realizedExpenseMinor, 0);
    expect(october.expenseMinor, 4000);
  });
}
