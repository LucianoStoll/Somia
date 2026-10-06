import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/allocations/category_allocation.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/core/series/movement_series.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/balances/data/sqlite_balances_repository.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/dashboard/data/sqlite_dashboard_repository.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CardsRepository cards;
  late SqliteAccountsRepository accounts;
  late Account account, other;
  late String cardId;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    cards = CardsRepository(db);
    accounts = SqliteAccountsRepository(db);
    Future<Account> add(String name) => accounts.create(AccountDraft(
        name: name,
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 100000,
        includeInAnalytics: true));
    account = await add('Principal');
    other = await add('Outra');
    cardId = await cards.save(CardDraft(
        name: 'Nu',
        paymentAccountId: account.id,
        closingDay: 25,
        dueDay: 5,
        limitMinor: 50000,
        institutionId: 'nubank'));
  });
  tearDown(() => db.close());
  TransactionDraft draft(
          {int amount = 10000,
          int count = 1,
          DateTime? date,
          DateTime? month,
          String? selectedCard,
          int first = 1,
          SeriesScope scope = SeriesScope.onlyThis}) =>
      TransactionDraft(
          description: 'Mercado',
          type: TransactionType.expense,
          amountMinor: amount,
          date: date ?? DateTime(2026, 1, 10),
          isEffective: true,
          accountId: account.id,
          cardId: selectedCard ?? cardId,
          cardInvoiceMonth: month,
          cardFirstInstallment: first,
          scope: scope,
          seriesPlan: count == 1
              ? null
              : SeriesPlan(kind: SeriesKind.installments, count: count));
  Future<Account> balance(
      {DateTime? asOf, DateTime? through, String? id}) async {
    final snapshot = await SqliteBalancesRepository(db).calculate(
        asOf: asOf ?? DateTime(2026, 1, 31),
        through: through ?? DateTime(2026, 12, 31));
    final b =
        snapshot.accounts.firstWhere((a) => a.accountId == (id ?? account.id));
    return Account(
        id: '',
        name: '',
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 0,
        isArchived: false,
        includeInAnalytics: true,
        currentBalanceMinor: b.currentMinor,
        projectedBalanceMinor: b.projectedMinor);
  }

  test('fechamento inclusivo próxima, último dia, mensal âncora e manual',
      () async {
    final before =
        await cards.createPurchase(draft(date: DateTime(2026, 1, 24)));
    final on = await cards.createPurchase(draft(date: DateTime(2026, 1, 25)));
    expect((await cards.entry(before)).invoiceMonth, DateTime.utc(2026, 2));
    expect((await cards.entry(on)).invoiceMonth, DateTime.utc(2026, 3));
    final manual = await cards.createPurchase(
        draft(month: DateTime(2026, 5), date: DateTime(2026, 1, 2)));
    expect((await cards.entry(manual)).invoiceMonth, DateTime.utc(2026, 5));
    final c = CreditCard(
        id: 'x', name: 'x', paymentAccountId: 'a', closingDay: 31, dueDay: 5);
    expect(c.closingFor(DateTime(2026, 3)), DateTime.utc(2026, 2, 28));
    expect(c.invoiceMonthFor(DateTime(2026, 2, 28)), DateTime.utc(2026, 4));
    expect(c.closingFor(DateTime(2028, 3)), DateTime.utc(2028, 2, 29));
  });
  test(
      'parcelas centavos, limite total, saldo conta só paga e analytics uma vez',
      () async {
    final tx = SqliteTransactionsRepository(db);
    final movement = await tx.create(draft(amount: 10001, count: 3));
    final all = await cards.entries(cardId: cardId);
    expect(all.map((e) => e.amountMinor), [3334, 3334, 3333]);
    expect(all.map((e) => e.dueAt), [
      DateTime.utc(2026, 2, 5),
      DateTime.utc(2026, 3, 5),
      DateTime.utc(2026, 4, 5)
    ]);
    expect((await cards.find(cardId)).committedMinor, 10001);
    expect((await balance()).currentBalanceMinor, 100000);
    expect((await balance()).projectedBalanceMinor, 89999);
    final invoice = await cards.invoice(all.first.invoiceId);
    await cards.pay(invoice.id, account.id, 3334, DateTime(2026, 2, 5));
    final b = await balance(asOf: DateTime(2026, 2, 28));
    expect(b.currentBalanceMinor, 96666);
    expect(b.projectedBalanceMinor, 89999);
    expect((await cards.find(cardId)).committedMinor, 6667);
    final dash = await SqliteDashboardRepository(db).load(DateTime(2026, 2));
    expect(dash.currencies.single.expenseMinor, 3334);
    expect((await tx.list()).length, 3);
    expect(movement.cardId, cardId);
    expect(await tx.list(const TransactionFilter(type: TransactionType.income)),
        isEmpty);
    expect(
        await tx.list(TransactionFilter(accountId: account.id)), hasLength(3));
    expect(
        await tx
            .list(const TransactionFilter(status: TransactionStatus.effective)),
        hasLength(1));
    await expectLater(
        tx.setEffective(movement.id, effective: true), throwsStateError);
  });
  test(
      'parcial carry histórico sem copiar dívida, juros desconto, conta alternativa e desfazer',
      () async {
    final id = await cards.createPurchase(draft());
    final entry = await cards.entry(id);
    await cards.pay(entry.invoiceId, other.id, 4000, DateTime(2026, 2, 5),
        fee: 500, discount: 200);
    final invoices = await cards.invoices(cardId, selected: DateTime(2026, 3));
    final feb = invoices.firstWhere((i) => i.month == DateTime.utc(2026, 2));
    final mar = invoices.firstWhere((i) => i.month == DateTime.utc(2026, 3));
    expect(feb.balanceMinor, 6300);
    expect(mar.previousMinor, 6300);
    expect(mar.chargesMinor, 0);
    expect((await balance(asOf: DateTime(2026, 2, 28))).projectedBalanceMinor,
        93700);
    expect(
        (await balance(asOf: DateTime(2026, 2, 28), id: other.id))
            .currentBalanceMinor,
        96000);
    expect(
        (await SqliteDashboardRepository(db).load(DateTime(2026, 2)))
            .currencies
            .single
            .expenseMinor,
        10300);
    await cards.pay(mar.id, account.id, 6300, DateTime(2026, 3, 5));
    expect((await cards.invoice(feb.id)).balanceMinor, 6300);
    expect((await cards.invoice(mar.id)).balanceMinor, 0);
    expect((await cards.find(cardId)).committedMinor, 0);
    await cards.undoPayment(feb.payments.single.id);
    expect((await cards.invoice(feb.id)).balanceMinor, 10000);
    expect(
        (await balance(asOf: DateTime(2026, 2, 28), id: other.id))
            .currentBalanceMinor,
        100000);
  });
  test('agendamento não libera limite atual; previsão desconta só uma vez',
      () async {
    final first = await cards.createPurchase(
        draft(date: DateTime(2090, 1, 1), month: DateTime(2090, 2)));
    final e = await cards.entry(first);
    await cards.pay(e.invoiceId, account.id, 4000, DateTime(2090, 2, 5));
    expect((await cards.find(cardId)).committedMinor, 10000);
    final b = await balance(
        asOf: DateTime(2026, 1, 31), through: DateTime(2090, 2, 28));
    expect(b.currentBalanceMinor, 100000);
    expect(b.projectedBalanceMinor, 90000);
    final inv = await cards.invoice(e.invoiceId);
    expect(inv.paidMinor, 0);
    expect(inv.scheduledMinor, 4000);
    expect(
        (await balance(
                asOf: DateTime(2026, 1, 31), through: DateTime(2089, 12, 31)))
            .projectedBalanceMinor,
        100000);
  });
  test(
      'antecipação selecionada com desconto, estorno e crédito sem duplicar saldo',
      () async {
    await cards.createPurchase(draft(amount: 30000, count: 3));
    final entries = await cards.entries(cardId: cardId);
    await cards.anticipate([entries.last.id], entries.first.invoiceId, 1000);
    final invoice = await cards.invoice(entries.first.invoiceId);
    expect(invoice.chargesMinor, 19000);
    expect((await cards.entry(entries.last.id)).invoiceMonth,
        entries.first.invoiceMonth);
    expect(await cards.entryHistory(entries.last.id), hasLength(1));
    expect((await cards.find(cardId)).committedMinor, 29000);
    await cards.refund(
        entries.first.id, 5000, invoice.id, DateTime(2026, 2, 6));
    expect((await cards.find(cardId)).committedMinor, 24000);
    await expectLater(
        cards.refund(entries.first.id, 26000, invoice.id, DateTime(2026, 2, 6)),
        throwsStateError);
    await cards.pay(invoice.id, account.id, 30000, DateTime(2026, 2, 7));
    final card = await cards.find(cardId);
    expect(card.committedMinor, 0);
    expect(card.creditMinor, 6000);
    expect(card.availableMinor, 50000);
    expect((await balance(asOf: DateTime(2026, 2, 28))).projectedBalanceMinor,
        70000);
  });
  test(
      'edição de próximas inclui agendadas, preservando anteriores e pagamentos',
      () async {
    final repo = SqliteTransactionsRepository(db);
    await repo.create(draft(amount: 30000, count: 3));
    final entries = await cards.entries(cardId: cardId);
    await cards.pay(
        entries.last.invoiceId, account.id, 1000, DateTime(2090, 1, 1));
    await repo.updateAmount('card:${entries[1].id}',
        expectedAmountMinor: 10000,
        amountMinor: 12000,
        scope: SeriesScope.thisAndNext);
    expect((await cards.entry(entries.first.id)).amountMinor, 10000);
    expect((await cards.entry(entries[1].id)).amountMinor, 12000);
    expect((await cards.entry(entries.last.id)).amountMinor, 12000);
    await repo.updateAmount('card:${entries.last.id}',
        expectedAmountMinor: 12000, amountMinor: 11000);
    expect(
        (await cards.invoice(entries.last.invoiceId))
            .payments
            .single
            .amountMinor,
        1000);
    await repo.update('card:${entries[1].id}',
        draft(amount: 12000, month: DateTime(2026, 5)));
    expect(
        (await cards.entry(entries[1].id)).invoiceMonth, DateTime.utc(2026, 5));
    expect(await cards.entryHistory(entries[1].id), hasLength(2));
    await repo.delete('card:${entries[1].id}');
    expect(await cards.entries(cardId: cardId), hasLength(2));
  });
  test(
      'compra incorreta em fatura paga: editar data, rateio e mover para destino pago',
      () async {
    final original = await cards.createPurchase(draft());
    final feb = (await cards.entry(original)).invoiceId;
    await cards.pay(feb, account.id, 10000, DateTime(2026, 2, 5));
    final wrong = await cards.createPurchase(draft(amount: 2000));
    final mar = await cards.ensureInvoice(cardId, DateTime(2026, 3));
    await cards.pay(mar, account.id, 1000, DateTime(2026, 3, 5));
    final payments = (await readFinancial(db))['card_payments'];
    final cats = SqliteCategoriesRepository(db);
    final a = await cats
        .create(const CategoryDraft(name: 'Casa', type: CategoryType.expense));
    final b = await cats.create(
        const CategoryDraft(name: 'Mercado', type: CategoryType.expense));
    expect(
        await cards.purchaseHasPayments(wrong, SeriesScope.onlyThis,
            invoiceMonth: DateTime(2026, 3)),
        isTrue);
    await SqliteTransactionsRepository(db).update(
        'card:$wrong',
        TransactionDraft(
            description: 'Compra corrigida',
            type: TransactionType.expense,
            amountMinor: 2500,
            date: DateTime(2026, 1, 20),
            isEffective: false,
            accountId: account.id,
            cardId: cardId,
            cardInvoiceMonth: DateTime(2026, 3),
            allocations: [
              CategoryAllocation(a.id, 1000),
              CategoryAllocation(b.id, 1500)
            ]));
    final edited = await cards.entry(wrong);
    expect(edited.description, 'Compra corrigida');
    expect(edited.postedAt, DateTime.utc(2026, 1, 20));
    expect(edited.invoiceId, mar);
    expect(edited.allocations.map((p) => p.amountMinor), [1000, 1500]);
    expect((await readFinancial(db))['card_payments'], payments);
    expect((await cards.invoice(feb)).balanceMinor, 0);
    expect((await cards.invoice(mar)).balanceMinor, 1500);
    expect((await balance(asOf: DateTime(2026, 4))).currentBalanceMinor, 89000);
    expect((await cards.find(cardId)).committedMinor, 1500);
    final dashboard =
        (await SqliteDashboardRepository(db).load(DateTime(2026, 3)))
            .currencies
            .single;
    expect(dashboard.expenseMinor, 2500);
    expect(dashboard.expensesByCategory.fold(0, (s, p) => s + p.amountMinor),
        2500);
    expect(await cards.entryHistory(wrong), hasLength(1));
    await validateFinancial(db);
  });
  test(
      'excluir compra de fatura paga preserva caixa, crédito, histórico e backup',
      () async {
    final id = await cards.createPurchase(draft());
    final e = await cards.entry(id);
    await cards.pay(e.invoiceId, account.id, 10000, DateTime(2026, 2, 5));
    final payments = (await readFinancial(db))['card_payments'];
    await SqliteTransactionsRepository(db).delete('card:$id');
    expect(await cards.entries(cardId: cardId), isEmpty);
    expect((await readFinancial(db))['card_payments'], payments);
    expect((await balance(asOf: DateTime(2026, 3))).currentBalanceMinor, 90000);
    expect((await cards.find(cardId)).creditMinor, 10000);
    expect((await cards.invoice(e.invoiceId)).balanceMinor, -10000);
    expect(
        (await SqliteDashboardRepository(db).load(DateTime(2026, 2)))
            .currencies
            .single
            .expenseMinor,
        0);
    expect((await cards.entryHistory(id)).single, contains('Exclusão'));
    final rows = await readFinancial(db);
    expect(rows['card_entries']![id]!['deleted_at'], isNotNull);
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await restored.transaction(() => replaceFinancial(restored, rows));
    expect((await readFinancial(restored))['card_payments'], payments);
    expect((await CardsRepository(restored).entryHistory(id)).single,
        contains('Exclusão'));
    await validateFinancial(restored);
  });
  test('excluir próximas inclui pagamentos agendados sem mexer no agendamento',
      () async {
    await cards.createPurchase(draft(amount: 30000, count: 3));
    final entries = await cards.entries(cardId: cardId);
    await cards.pay(
        entries.last.invoiceId, account.id, 1000, DateTime(2090, 1, 1));
    final payments = (await readFinancial(db))['card_payments'];
    expect(
        await cards.purchaseHasPayments(entries.first.id, SeriesScope.onlyThis),
        isFalse);
    expect(
        await cards.purchaseHasPayments(entries.first.id, SeriesScope.onlyThis,
            purchaseDate: DateTime(2026, 3, 10)),
        isTrue);
    await cards.deletePurchase(entries[1].id, SeriesScope.thisAndNext);
    expect((await cards.entries(cardId: cardId)).single.id, entries.first.id);
    expect((await readFinancial(db))['card_payments'], payments);
    expect((await cards.invoice(entries.last.invoiceId)).scheduledMinor, 1000);
    await validateFinancial(db);
  });
  test(
      'correção não reduz compra abaixo dos estornos e exclusão mantém vínculo',
      () async {
    final id = await cards.createPurchase(draft());
    final e = await cards.entry(id);
    await cards.refund(id, 4000, e.invoiceId, DateTime(2026, 2, 3));
    await cards.pay(e.invoiceId, account.id, 6000, DateTime(2026, 2, 5));
    await expectLater(cards.updateAmount(id, 10000, 3000, SeriesScope.onlyThis),
        throwsStateError);
    await expectLater(
        cards.editPurchase(id, draft(amount: 3000)), throwsStateError);
    await expectLater(
        cards.deletePurchase(id, SeriesScope.onlyThis), throwsStateError);
    expect((await cards.entry(id)).amountMinor, 10000);
    expect(await cards.entryHistory(id), isEmpty);
    await validateFinancial(db);
  });
  test(
      'datas reais alteradas, histórico de limite, arquivar e saldo inicial não vira gasto',
      () async {
    final feb = await cards.ensureInvoice(cardId, DateTime(2026, 2));
    await cards.adjustDates(feb, DateTime(2026, 1, 27), DateTime(2026, 2, 6));
    final e = await cards.createPurchase(draft(date: DateTime(2026, 1, 26)));
    expect((await cards.entry(e)).invoiceId, feb);
    await cards.opening(cardId, DateTime(2026, 2), 5000);
    final dash = await SqliteDashboardRepository(db).load(DateTime(2026, 2));
    expect(dash.currencies.single.expenseMinor, 10000);
    expect((await cards.invoice(feb)).balanceMinor, 15000);
    await cards.save(
        CardDraft(
            name: 'Nu',
            paymentAccountId: account.id,
            closingDay: 24,
            dueDay: 6,
            limitMinor: 60000),
        id: cardId);
    expect(await cards.limitHistory(cardId), hasLength(2));
    expect((await cards.invoice(feb)).closingAt, DateTime.utc(2026, 1, 27));
    await cards.archive(cardId, true);
    await expectLater(cards.createPurchase(draft()), throwsStateError);
    await cards.pay(feb, account.id, 1000, DateTime(2026, 2, 6));
    await cards.archive(cardId, false);
    expect((await cards.find(cardId)).isArchived, isFalse);
  });
  test(
      'falha atômica em limites, quantidade, fatura de outro cartão e final fora da faixa',
      () async {
    await expectLater(
        cards.createPurchase(draft(count: 1000, month: DateTime(2099, 12))),
        throwsFormatException);
    expect(await cards.entries(cardId: cardId), isEmpty);
    await expectLater(
        cards.createPurchase(draft(first: 1001)), throwsFormatException);
    expect(await cards.entries(cardId: cardId), isEmpty);
    final id = await cards.createPurchase(draft());
    final e = await cards.entry(id);
    final otherCard = await cards.save(CardDraft(
        name: 'Outro cartão',
        paymentAccountId: account.id,
        closingDay: 20,
        dueDay: 2));
    final otherInvoice =
        await cards.ensureInvoice(otherCard, DateTime(2026, 2));
    await expectLater(
        cards.refund(id, 1000, otherInvoice, DateTime(2026, 2, 1)),
        throwsStateError);
    expect((await cards.invoice(e.invoiceId)).chargesMinor, 10000);
  });
  test('parcelas restantes iniciam na numeração informada, sem recriar antigas',
      () async {
    await cards.createPurchase(
        draft(amount: 9000, count: 3, first: 4, month: DateTime(2026, 6)));
    final entries = await cards.entries(cardId: cardId);
    expect(entries.map((e) => e.label),
        ['Parcela 4/6', 'Parcela 5/6', 'Parcela 6/6']);
    expect(entries.map((e) => e.amountMinor), [3000, 3000, 3000]);
    expect((await cards.find(cardId)).committedMinor, 9000);
    final last = await cards.createPurchase(
        draft(amount: 1500, first: 6, month: DateTime(2026, 9)));
    expect((await cards.entry(last)).label, 'Parcela 6/6');
    expect((await cards.find(cardId)).committedMinor, 10500);
  });
  Future<CardSettlement> settle(CardInvoice bill) =>
      cards.settleInvoice(bill.id,
          expectedBalance: bill.balanceMinor,
          expectedScheduled: bill.scheduledMinor,
          expectedSignature: CardsRepository.paymentSignature(bill),
          expectedAccountId: account.id,
          date: DateTime.now());

  test('corrige compra na fatura paga sem alterar pagamentos ou saldo da conta',
      () async {
    final tx = SqliteTransactionsRepository(db);
    final correctId = await cards.createPurchase(draft(amount: 10000));
    final old = await cards.entry(correctId);
    await cards.pay(old.invoiceId, account.id, 10000, DateTime(2026, 2, 5));
    final before = await balance(asOf: DateTime(2026, 2, 28));
    final wrongId = await cards.createPurchase(draft(amount: 2500));
    final payment = (await cards.invoice(old.invoiceId)).payments.single;
    await tx.update(
        'card:$wrongId',
        draft(
            amount: 3000,
            date: DateTime(2026, 2, 12),
            month: DateTime(2026, 3)));
    final moved = await cards.entry(wrongId);
    expect(moved.postedAt, DateTime.utc(2026, 2, 12));
    expect(moved.invoiceMonth, DateTime.utc(2026, 3));
    expect(moved.amountMinor, 3000);
    final previous = await cards.invoice(old.invoiceId);
    expect(previous.balanceMinor, 0);
    expect(previous.payments.single.id, payment.id);
    expect(previous.payments.single.amountMinor, 10000);
    expect((await balance(asOf: DateTime(2026, 2, 28))).currentBalanceMinor,
        before.currentBalanceMinor);
    expect(await cards.entryHistory(wrongId), hasLength(1));
    final anotherWrong = await cards.createPurchase(draft(amount: 1500));
    await tx.delete('card:$anotherWrong');
    expect((await cards.invoice(old.invoiceId)).balanceMinor, 0);
    expect((await cards.invoice(old.invoiceId)).payments.single.id, payment.id);
    expect(
        (await cards.entryHistory(anotherWrong)).single, contains('Exclusão'));
  });
  test('fatura mensal não acumula anteriores na virada do ano', () async {
    final tx = SqliteTransactionsRepository(db);
    await cards.createPurchase(draft(amount: 50000, month: DateTime(2026, 12)));
    final id = await cards
        .createPurchase(draft(amount: 30000, month: DateTime(2027, 1)));
    final invoiceId = (await cards.entry(id)).invoiceId;
    Future<FinancialTransaction> row(int month) async =>
        (await tx.list(TransactionFilter(
                from: DateTime(2027, month), to: DateTime(2027, month + 1, 0))))
            .single;
    final january = await row(1);
    expect(january.amountMinor, 30000);
    expect(january.cardPreviousMinor, 50000);
    expect(january.cardBalanceMinor, 80000);
    // Janeiro preserva o pagamento da própria fatura e o saldo total,
    // mas seu valor principal continua sendo a competência mensal.
    await cards.pay(invoiceId, account.id, 10000, DateTime(2026, 10, 1));
    final partial = await row(1);
    expect(partial.amountMinor, 30000);
    expect(partial.cardBalanceMinor, 70000);
    final empty = await row(2);
    expect(empty.amountMinor, 0);
    expect(empty.cardPreviousMinor, 70000);
    expect(empty.cardBalanceMinor, 70000);
    expect((await cards.invoice(invoiceId)).paidMinor, 10000);
    expect((await balance(asOf: DateTime.now())).currentBalanceMinor, 90000);
  });

  test('lista agrupa compras e mantém total após pagamento parcial', () async {
    final tx = SqliteTransactionsRepository(db);
    final first = await cards.createPurchase(draft(amount: 10000));
    await cards.createPurchase(draft(amount: 5000));
    final e = await cards.entry(first);
    await cards.pay(e.invoiceId, other.id, 4000, DateTime(2026, 2, 5));
    final filter =
        TransactionFilter(from: DateTime(2026, 2), to: DateTime(2026, 2, 28));
    final row = (await tx.list(filter)).single;
    expect(row.id, 'invoice:${e.invoiceId}');
    expect(row.cardEntryCount, 2);
    expect(row.amountMinor, 15000);
    expect(row.cardBalanceMinor, 11000);
    expect(row.isEffective, false);
    expect((await cards.invoice(e.invoiceId)).entries, hasLength(2));
    await expectLater(
        tx.updateAmount(row.id, expectedAmountMinor: 15000, amountMinor: 1),
        throwsStateError);
    await expectLater(tx.delete(row.id), throwsStateError);
    final action = await settle(await cards.invoice(e.invoiceId));
    expect(action.newAmountMinor, 11000);
    final paid = (await tx.list(filter)).single;
    expect(paid.isEffective, true);
    expect(paid.amountMinor, 15000);
    expect(
        (await SqliteDashboardRepository(db).load(DateTime(2026, 2)))
            .currencies
            .single
            .expenseMinor,
        15000);
    expect(
        (await balance(asOf: DateTime.now(), id: other.id)).currentBalanceMinor,
        96000);
    expect((await balance(asOf: DateTime.now())).currentBalanceMinor, 89000);
    await cards.undoSettlement(action);
    expect((await cards.invoice(e.invoiceId)).balanceMinor, 11000);
    expect((await cards.invoice(e.invoiceId)).payments, hasLength(1));
  });

  for (final scheduled in [4000, 10000]) {
    test('quitar agenda $scheduled sem duplicar e desfazer restaura data',
        () async {
      final e = await cards.entry(await cards.createPurchase(draft()));
      final future = DateTime(2090, 2, 5);
      await cards.pay(e.invoiceId, other.id, scheduled, future);
      final bill = await cards.invoice(e.invoiceId);
      final action = await settle(bill);
      final paid = await cards.invoice(bill.id);
      expect(paid.balanceMinor, 0);
      expect(paid.scheduledMinor, 0);
      expect(paid.payments, hasLength(scheduled == 10000 ? 1 : 2));
      expect(action.newAmountMinor, 10000 - scheduled);
      await expectLater(settle(bill), throwsStateError);
      await cards.undoSettlement(action);
      final undone = await cards.invoice(bill.id);
      expect(undone.balanceMinor, 10000);
      expect(undone.scheduledMinor, scheduled);
      expect(undone.payments.single.date, DateTime.utc(2090, 2, 5));
      await expectLater(cards.undoSettlement(action), throwsStateError);
    });
  }

  test('ajustar data agenda a quitação e rejeita desfazer obsoleto', () async {
    final e = await cards.entry(await cards.createPurchase(draft()));
    final action = await settle(await cards.invoice(e.invoiceId));
    await cards.changeSettlementDate(action, DateTime(2090, 2, 5));
    final bill = await cards.invoice(e.invoiceId);
    expect(bill.balanceMinor, 10000);
    expect(bill.scheduledMinor, 10000);
    await expectLater(cards.undoSettlement(action), throwsStateError);
  });

  test('conta arquivada falha atomicamente e saldo anterior fica separado',
      () async {
    final e = await cards.entry(await cards.createPurchase(draft()));
    await cards.pay(e.invoiceId, other.id, 4000, DateTime(2090, 2, 5));
    await db.customStatement(
        'UPDATE accounts SET is_archived=1 WHERE id=?', [account.id]);
    await expectLater(
        settle(await cards.invoice(e.invoiceId)), throwsStateError);
    final bill = await cards.invoice(e.invoiceId);
    expect(bill.payments.single.date, DateTime.utc(2090, 2, 5));
    expect(bill.balanceMinor, 10000);
    final rows = await SqliteTransactionsRepository(db).list(TransactionFilter(
        from: DateTime(2026, 10), to: DateTime(2026, 10, 31)));
    expect(rows.single.amountMinor, 0);
    expect(rows.single.cardPreviousMinor, 10000);
    expect(rows.single.cardBalanceMinor, 10000);
    expect(rows.single.cardEntryCount, 0);
  });

  test(
      'desfazer último pagamento preserva anteriores e rejeita assinatura antiga',
      () async {
    final e = await cards.entry(await cards.createPurchase(draft()));
    await cards.pay(e.invoiceId, other.id, 4000, DateTime(2026, 2, 5));
    final action = await settle(await cards.invoice(e.invoiceId));
    final bill = await cards.invoice(e.invoiceId);
    await cards.undoInvoicePayment(
        bill.id, action.newPaymentId!, CardsRepository.paymentSignature(bill));
    expect((await cards.invoice(bill.id)).balanceMinor, 6000);
    expect((await cards.invoice(bill.id)).payments.single.amountMinor, 4000);
    await expectLater(
        cards.undoInvoicePayment(bill.id, action.newPaymentId!,
            CardsRepository.paymentSignature(bill)),
        throwsStateError);
  });
  test('duas compras mp em novembro aparecem só como fatura de 242 reais',
      () async {
    final id = await cards.save(CardDraft(
        name: 'mp', paymentAccountId: account.id, closingDay: 25, dueDay: 5));
    await cards.createPurchase(
        draft(amount: 22200, selectedCard: id, month: DateTime(2026, 11)));
    await cards.createPurchase(
        draft(amount: 2000, selectedCard: id, month: DateTime(2026, 11)));
    final rows = await SqliteTransactionsRepository(db).list(TransactionFilter(
        from: DateTime(2026, 11), to: DateTime(2026, 11, 30)));
    expect(rows, hasLength(1));
    expect(rows.single.description, 'Cartão - mp');
    expect(rows.single.amountMinor, 24200);
    expect(rows.single.cardEntryCount, 2);
    expect(rows.single.date, DateTime.utc(2026, 10, 25));
    expect(rows.single.dueDate, DateTime.utc(2026, 11, 5));
    expect(
        (await cards.invoice(rows.single.cardInvoiceId!))
            .entries
            .map((e) => e.amountMinor),
        unorderedEquals([22200, 2000]));
  });
}
