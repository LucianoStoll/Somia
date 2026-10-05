import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/dashboard/data/sqlite_dashboard_repository.dart';
import 'package:finapp/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SqliteAccountsRepository accounts;
  late Account bank, wallet, excluded, usd;
  late SqliteTransactionsRepository transactions;
  final month = DateTime.utc(2026, 10);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    accounts = SqliteAccountsRepository(db);
    transactions = SqliteTransactionsRepository(db);
    Future<Account> add(String name,
            {String code = 'BRL',
            int initial = 0,
            bool include = true,
            bool analytics = true}) =>
        accounts.create(AccountDraft(
            name: name,
            type: AccountType.checking,
            currencyCode: code,
            initialBalanceMinor: initial,
            includeInAnalytics: analytics,
            includeInBalance: include));
    bank = await add('Banco', initial: 100000, analytics: false);
    wallet = await add('Carteira', initial: 10000);
    excluded = await add('Aplicação', initial: 900000, include: false);
    usd = await add('USD', code: 'USD', initial: 3000);
  });
  tearDown(() => db.close());
  Future<String> tx(String account, int amount, DateTime due,
          {bool effective = false,
          DateTime? at,
          TransactionType type = TransactionType.expense}) async =>
      (await transactions.create(TransactionDraft(
              description: 'Movimento',
              type: type,
              amountMinor: amount,
              date: DateTime.utc(2026, 9, 1),
              dueDate: due,
              isEffective: effective,
              effectiveDate: at,
              accountId: account)))
          .id;
  Future<DashboardCurrencySummary> load(DateTime date,
      {String code = 'BRL'}) async {
    final s = (await SqliteDashboardRepository(db).load(date))
        .currencies
        .singleWhere((c) => c.currencyCode == code);
    expect(s.balanceDetails!.currentMinor, s.currentBalanceMinor);
    expect(s.balanceDetails!.projectedMinor, s.projectedBalanceMinor);
    return s;
  }

  test(
      'consolida por saldo, corte mensal agendado, abertura e pendências anteriores',
      () async {
    await tx(bank.id, 20000, DateTime.utc(2026, 9, 10),
        effective: true,
        at: DateTime.utc(2026, 9, 10),
        type: TransactionType.income);
    await tx(bank.id, 30000, DateTime.utc(2026, 10, 5),
        effective: true,
        at: DateTime.utc(2026, 10, 5),
        type: TransactionType.income);
    final paid = await tx(bank.id, 5000, DateTime.utc(2026, 10, 9),
        effective: true, at: DateTime.utc(2026, 10, 9));
    await db.customStatement(
        'UPDATE transactions SET actual_amount_minor=4500,ignore_analytics=1 WHERE id=?',
        [paid]);
    await tx(bank.id, 7000, DateTime.utc(2026, 9, 20));
    await tx(bank.id, 9000, DateTime.utc(2026, 10, 20),
        type: TransactionType.income);
    await tx(bank.id, 2000, DateTime.utc(2026, 10, 1),
        effective: true, at: DateTime.utc(2026, 10, 28));
    await tx(bank.id, 8000, DateTime.utc(2026, 10, 2),
        effective: true, at: DateTime.utc(2026, 11, 5));
    await tx(excluded.id, 60000, DateTime.utc(2026, 10, 1),
        effective: true, type: TransactionType.income);
    await accounts.setArchived(bank.id, archived: true);
    final oct = (await load(month)).balanceDetails!;
    expect(oct.openingMinor, 130000);
    expect(oct.incomeMinor, 30000);
    expect(oct.expenseMinor, 6500);
    expect(oct.currentMinor, 153500);
    expect(oct.pendingExpenseMinor, 7000);
    expect(oct.pendingIncomeMinor, 9000);
    expect(oct.projectedMinor, 155500);
    final nov = (await load(DateTime.utc(2026, 11))).balanceDetails!;
    expect(nov.openingMinor, oct.currentMinor);
    expect(nov.expenseMinor, 8000);
    expect(nov.currentMinor, 145500);
    expect(nov.projectedMinor, 147500);
    await load(DateTime.utc(2026, 9));
    await load(DateTime.utc(2027, 1));
  });
  test(
      'transferências internas se compensam e externas contam somente o lado incluído',
      () async {
    final transfers = SqliteTransfersRepository(db);
    Future<void> add(
            String from, String to, int amount, bool paid, DateTime date) =>
        transfers
            .create(TransferDraft(
                sourceAccountId: from,
                destinationAccountId: to,
                amountMinor: amount,
                date: date,
                isEffective: paid))
            .then((_) {});
    await add(bank.id, wallet.id, 10000, true, DateTime.utc(2026, 10, 5));
    await add(bank.id, excluded.id, 2000, true, DateTime.utc(2026, 10, 5));
    await add(excluded.id, bank.id, 500, true, DateTime.utc(2026, 10, 5));
    await add(wallet.id, bank.id, 3000, false, DateTime.utc(2026, 10, 15));
    await add(bank.id, excluded.id, 4000, false, DateTime.utc(2026, 9, 15));
    await add(excluded.id, wallet.id, 1000, false, DateTime.utc(2026, 10, 10));
    final s = (await load(month)).balanceDetails!;
    expect(s.transferInMinor, 10500);
    expect(s.transferOutMinor, 12000);
    expect(s.currentMinor, 108500);
    expect(s.pendingTransferInMinor, 4000);
    expect(s.pendingTransferOutMinor, 7000);
    expect(s.projectedMinor, 105500);
  });
  test(
      'moedas separadas, exclusões, saldo negativo, ignorados e atualização offline',
      () async {
    final ignored =
        await tx(bank.id, 70000, DateTime.utc(2026, 10, 5), effective: true);
    await db.customStatement(
        'UPDATE transactions SET ignore_balance=1 WHERE id=?', [ignored]);
    final deleted = await tx(bank.id, 80000, DateTime.utc(2026, 10, 5));
    await transactions.delete(deleted);
    final expense =
        await tx(usd.id, 4000, DateTime.utc(2026, 10, 5), effective: true);
    final dollar = (await load(month, code: 'USD')).balanceDetails!;
    expect(dollar.openingMinor, 3000);
    expect(dollar.currentMinor, -1000);
    expect((await load(month)).balanceDetails!.currentMinor, 110000);
    await transactions.setEffective(expense, effective: false);
    final changed = (await load(month, code: 'USD')).balanceDetails!;
    expect(changed.currentMinor, 3000);
    expect(changed.projectedMinor, -1000);
    await transactions.delete(expense);
    expect(
        (await load(month, code: 'USD')).balanceDetails!.projectedMinor, 3000);
  });
  for (final alternative in [false, true]) {
    test(
        'cartão: previsto líquido e pagamentos parciais, agendados e noutra conta $alternative',
        () async {
      final cards = CardsRepository(db);
      final card = await cards.save(CardDraft(
          name: 'Cartão',
          paymentAccountId: bank.id,
          closingDay: 25,
          dueDay: 5));
      final purchase = await cards.createPurchase(TransactionDraft(
          description: 'Compra',
          type: TransactionType.expense,
          amountMinor: 10000,
          date: DateTime.utc(2026, 9, 10),
          isEffective: true,
          accountId: bank.id,
          cardId: card,
          cardInvoiceMonth: month));
      final bill = (await cards.invoices(card)).single;
      await cards.refund(purchase, 2000, bill.id, DateTime.utc(2026, 10, 5));
      await cards.pay(bill.id, alternative ? excluded.id : bank.id, 3000,
          DateTime.utc(2026, 10, 5));
      await cards.pay(bill.id, bank.id, 2000, DateTime.utc(2026, 10, 28));
      await cards.pay(bill.id, bank.id, 4000, DateTime.utc(2026, 11, 5));
      final oct = (await load(month)).balanceDetails!;
      expect(oct.expenseMinor, 0);
      expect(oct.cardPaymentsMinor, alternative ? 2000 : 5000);
      expect(oct.pendingInvoicesMinor, 3000);
      expect(oct.projectedMinor, alternative ? 105000 : 102000);
      final nov = (await load(DateTime.utc(2026, 11))).balanceDetails!;
      expect(nov.openingMinor, oct.currentMinor);
      expect(nov.cardPaymentsMinor, 4000);
      expect(nov.pendingInvoicesMinor, 0);
    });
  }
  test('mês vazio e conta excluída sem composição inventada', () async {
    final s = (await load(DateTime.utc(2028, 2))).balanceDetails!;
    expect(s.openingMinor, 110000);
    expect(s.currentMinor, 110000);
    expect(s.projectedMinor, 110000);
    expect(s.incomeMinor, 0);
    expect(s.pendingInvoicesMinor, 0);
    await db.customStatement('UPDATE accounts SET include_in_balance=0');
    final empty = (await load(month)).balanceDetails!;
    expect(empty.openingMinor, 0);
    expect(empty.currentMinor, 0);
    expect(empty.projectedMinor, 0);
  });
}
