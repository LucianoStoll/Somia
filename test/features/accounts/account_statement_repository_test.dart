import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/features/accounts/data/account_statement_repository.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/domain/account_statement.dart';
import 'package:finapp/features/balances/data/sqlite_balances_repository.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SqliteAccountsRepository accounts;
  late Account a, b;
  late AccountStatementRepository repo;
  final month = DateTime.utc(2026, 2);
  final today = DateTime.utc(2026, 2, 10);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    accounts = SqliteAccountsRepository(db);
    repo = AccountStatementRepository(db);
    Future<Account> add(String name, {bool included = true}) =>
        accounts.create(AccountDraft(
            name: name,
            type: AccountType.checking,
            currencyCode: 'BRL',
            initialBalanceMinor: 100000,
            includeInAnalytics: true,
            includeInBalance: included));
    a = await add('Principal', included: false);
    b = await add('Outra');
  });
  tearDown(() => db.close());
  Future<String> tx(String description, int amount, DateTime due,
          {bool effective = false,
          DateTime? at,
          TransactionType type = TransactionType.expense,
          String? account}) async =>
      (await SqliteTransactionsRepository(db).create(TransactionDraft(
              description: description,
              type: type,
              amountMinor: amount,
              date: DateTime.utc(2026, 1, 1),
              dueDate: due,
              effectiveDate: at,
              isEffective: effective,
              accountId: account ?? a.id)))
          .id;
  Future<void> checkDaily(String id, AccountStatement s) async {
    for (var day = 1; day <= s.projected.dailyBalances.length; day++) {
      final snapshot = await SqliteBalancesRepository(db).calculate(
          asOf: DateTime.utc(s.month.year, s.month.month, day),
          through: DateTime.utc(s.month.year, s.month.month, day));
      expect(s.projected.dailyBalances[day - 1],
          snapshot.accounts.firstWhere((x) => x.accountId == id).projectedMinor,
          reason: 'Saldo previsto do dia $day');
    }
    expect(s.realized.closingMinor, s.account.currentBalanceMinor);
    expect(s.projected.closingMinor, s.account.projectedBalanceMinor);
  }

  test(
      'saldo inicial, agrupamento diário, efetivação e vencimento independentes',
      () async {
    await tx('Anterior', 20000, DateTime.utc(2026, 1, 20),
        effective: true,
        at: DateTime.utc(2026, 1, 20),
        type: TransactionType.income);
    await tx('Salário', 30000, DateTime.utc(2026, 2, 8),
        effective: true,
        at: DateTime.utc(2026, 2, 5),
        type: TransactionType.income);
    await tx('Mercado', 5000, DateTime.utc(2026, 2, 7),
        effective: true, at: DateTime.utc(2026, 2, 5));
    await tx('Pendente', 7000, DateTime.utc(2026, 2, 12));
    await tx('Agendado', 4000, DateTime.utc(2026, 2, 6),
        effective: true, at: DateTime.utc(2026, 2, 20));
    final s = await repo.load(a.id, month, today: today);
    expect(s.realized.openingMinor, 120000);
    expect(s.realized.days.single.entries.length, 2);
    expect(s.realized.days.single.date, DateTime.utc(2026, 2, 5));
    expect(s.realized.days.single.closingMinor, 145000);
    expect(s.realized.closingMinor, 145000);
    expect(s.projected.closingMinor, 134000);
    expect(s.projected.days.map((x) => x.date.day), [5, 12, 20]);
    await checkDaily(a.id, s);
  });
  test('transferências isoladas, conta arquivada e fora do consolidado',
      () async {
    final transfers = SqliteTransfersRepository(db);
    await transfers.create(TransferDraft(
        sourceAccountId: a.id,
        destinationAccountId: b.id,
        amountMinor: 2000,
        date: DateTime.utc(2026, 2, 5),
        isEffective: true));
    await transfers.create(TransferDraft(
        sourceAccountId: b.id,
        destinationAccountId: a.id,
        amountMinor: 1000,
        date: DateTime.utc(2026, 2, 15),
        isEffective: false));
    await accounts.setArchived(a.id, archived: true);
    await tx('Outra conta', 8000, DateTime.utc(2026, 2, 7),
        effective: true, account: b.id);
    final source = await repo.load(a.id, month, today: today);
    final destination = await repo.load(b.id, month, today: today);
    expect(source.account.isArchived, true);
    expect(source.account.includeInBalance, false);
    expect(source.realized.total(StatementKind.transferOut), 2000);
    expect(source.projected.total(StatementKind.transferIn), 1000);
    expect(source.projected.closingMinor, 99000);
    expect(destination.projected.closingMinor, 93000);
    await checkDaily(a.id, source);
    await checkDaily(b.id, destination);
  });
  test('exclui apagados e ignorados, mês vazio e ano bissexto', () async {
    final ignored = await tx('Ignorado', 3000, DateTime.utc(2026, 2, 1));
    await db.customStatement(
        'UPDATE transactions SET ignore_balance=1 WHERE id=?', [ignored]);
    final removed = await tx('Apagado', 2000, DateTime.utc(2026, 2, 2));
    await SqliteTransactionsRepository(db).delete(removed);
    final s = await repo.load(a.id, month, today: today);
    expect(s.realized.days, isEmpty);
    expect(s.projected.days, isEmpty);
    expect(s.projected.dailyBalances.length, 28);
    expect(s.projected.closingMinor, 100000);
    final leap = await repo.load(a.id, DateTime.utc(2028, 2),
        today: DateTime.utc(2028, 3));
    expect(leap.projected.dailyBalances.length, 29);
    await checkDaily(a.id, s);
    expect(repo.load('missing', month), throwsStateError);
  });
  test('valor realizado difere do planejado e agendamento usa planejado',
      () async {
    final actual = await tx('Pago', 1000, DateTime.utc(2026, 2, 5),
        effective: true, at: DateTime.utc(2026, 2, 5));
    final scheduled = await tx('Futuro', 2000, DateTime.utc(2026, 2, 15),
        effective: true, at: DateTime.utc(2026, 2, 15));
    await db.customStatement(
        'UPDATE transactions SET actual_amount_minor=500 WHERE id=?', [actual]);
    await db.customStatement(
        'UPDATE transactions SET actual_amount_minor=1500 WHERE id=?',
        [scheduled]);
    final s = await repo.load(a.id, month, today: today);
    expect(s.realized.closingMinor, 99500);
    expect(s.projected.closingMinor, 97500);
    // Projeção no corte de hoje conserva o valor planejado de agendamentos.
    expect(s.projected.closingMinor, s.account.projectedBalanceMinor);
  });
  for (final otherAccount in [false, true]) {
    test(
        'cartão: compensação de fatura e pagamento ${otherAccount ? 'noutra conta' : 'na conta padrão'}',
        () async {
      final cards = CardsRepository(db);
      final card = await cards.save(CardDraft(
          name: 'Cartão',
          paymentAccountId: a.id,
          closingDay: 25,
          dueDay: 5,
          limitMinor: 50000));
      await cards.createPurchase(TransactionDraft(
          description: 'Compra individual',
          type: TransactionType.expense,
          amountMinor: 10000,
          date: DateTime.utc(2026, 1, 10),
          isEffective: true,
          accountId: a.id,
          cardId: card,
          cardInvoiceMonth: month));
      final bill = (await cards.invoices(card)).single;
      await cards.pay(
          bill.id, otherAccount ? b.id : a.id, 4000, DateTime.utc(2026, 2, 8));
      await cards.pay(
          bill.id, otherAccount ? b.id : a.id, 6000, DateTime.utc(2026, 2, 20));
      final s = await repo.load(a.id, month, today: today);
      expect(
          s.realized.entries.any((x) => x.description == 'Compra individual'),
          false);
      expect(s.realized.closingMinor, otherAccount ? 100000 : 96000);
      expect(s.projected.closingMinor, otherAccount ? 100000 : 90000);
      expect(s.projected.adjustmentsMinor, 10000);
      expect(s.projected.total(StatementKind.income), 0);
      await checkDaily(a.id, s);
      final other = await repo.load(b.id, month, today: today);
      await checkDaily(b.id, other);
    });
  }
  test('cartão: atraso muda abertura, estorno e saldo credor não viram receita',
      () async {
    final cards = CardsRepository(db);
    final card = await cards.save(CardDraft(
        name: 'Cartão', paymentAccountId: a.id, closingDay: 25, dueDay: 5));
    final purchase = await cards.createPurchase(TransactionDraft(
        description: 'Compra',
        type: TransactionType.expense,
        amountMinor: 10000,
        date: DateTime.utc(2026, 1, 10),
        isEffective: true,
        accountId: a.id,
        cardId: card,
        cardInvoiceMonth: month));
    final bill = (await cards.invoices(card)).single;
    await cards.refund(purchase, 2000, bill.id, DateTime.utc(2026, 2, 10));
    await cards.pay(bill.id, a.id, 9000, DateTime.utc(2026, 3, 10));
    final feb = await repo.load(a.id, month, today: today);
    expect(feb.projected.closingMinor, 92000);
    await checkDaily(a.id, feb);
    final march = await repo.load(a.id, DateTime.utc(2026, 3),
        today: DateTime.utc(2026, 3, 31));
    expect(march.projected.openingMinor, 92000);
    expect(march.projected.closingMinor, 91000);
    expect(march.projected.adjustmentsMinor, 8000);
    expect(march.projected.total(StatementKind.income), 0);
    await checkDaily(a.id, march);
  });
}
