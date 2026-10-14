import 'package:drift/native.dart';
import 'package:finapp/core/series/movement_series.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/data/card_payment_coverage_repository.dart';
import 'package:finapp/features/cards/data/debit_cards_repository.dart';
import 'package:finapp/features/cards/data/cashback_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/cards/domain/cashback_calculator.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/data/transaction_settlements_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';

void main() {
  late AppDatabase db;
  late CashbackRepository cashback;
  late DebitCardsRepository debit;
  late CardsRepository credit;
  late SqliteTransactionsRepository transactions;
  late Account source, destination;
  late String debitId, creditId, incomeCategory, returnCategory;
  final today = DateTime.now();
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    cashback = CashbackRepository(db);
    debit = DebitCardsRepository(db);
    credit = CardsRepository(db);
    transactions = SqliteTransactionsRepository(db);
    final accounts = SqliteAccountsRepository(db);
    source = await accounts.create(const AccountDraft(
        name: 'Pagamento',
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 1000000,
        includeInAnalytics: true));
    destination = await accounts.create(const AccountDraft(
        name: 'Cashback',
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 0,
        includeInAnalytics: true));
    debitId = await debit.save(name: 'Débito', accountId: source.id);
    creditId = await credit.save(CardDraft(
        name: 'Crédito',
        paymentAccountId: source.id,
        closingDay: 25,
        dueDay: 5));
    final cats = SqliteCategoriesRepository(db);
    incomeCategory = (await cats.create(
            const CategoryDraft(name: 'Cashback', type: CategoryType.income)))
        .id;
    returnCategory = (await cats.create(
            const CategoryDraft(name: 'Devolução', type: CategoryType.expense)))
        .id;
  });
  tearDown(() => db.close());
  Future<void> configure({
    String kind = 'debit',
    CashbackRule? rule,
    bool enabled = true,
  }) =>
      cashback.saveSettings(
          kind: kind,
          cardId: kind == 'debit' ? debitId : creditId,
          enabled: enabled,
          accountId: destination.id,
          categoryId: incomeCategory,
          returnCategoryId: returnCategory,
          rule: rule ?? CashbackRule(rateBasisPoints: 100));
  Future<FinancialTransaction> buy(
    int amount, {
    bool effective = true,
    DateTime? date,
  }) =>
      transactions.create(TransactionDraft(
          description: 'Compra',
          type: TransactionType.expense,
          amountMinor: amount,
          date: date ?? today,
          isEffective: effective,
          accountId: source.id,
          debitCardId: debitId));
  Future<void> receive(CashbackReceipt r, int amount) => cashback.confirm([r],
      totalMinor: amount,
      accountId: destination.id,
      date: today,
      categoryId: r.kind == 'return' ? returnCategory : incomeCategory);

  test('deleting a pending complement accepts removal without recreating it',
      () async {
    await configure(
        rule: CashbackRule(
            rateBasisPoints: 100, tiers: [const CashbackTier(20000, 200)]));
    await buy(10000);
    await receive((await cashback.list()).single, 100);
    await buy(10000);
    final complement =
        (await cashback.list()).singleWhere((r) => r.kind == 'complement');
    await cashback.delete(complement);
    expect(
        (await cashback.list()).where((r) => r.kind == 'complement'), isEmpty);
    await validateFinancial(db);
  });

  test('legacy installment receipts consolidate without erasing received money',
      () async {
    await configure();
    final purchase = await transactions.create(TransactionDraft(
        description: 'Legada',
        type: TransactionType.expense,
        amountMinor: 90000,
        date: today,
        isEffective: false,
        accountId: source.id,
        debitCardId: debitId,
        seriesPlan: const SeriesPlan(kind: SeriesKind.installments, count: 3)));
    final series = await db
        .customSelect(
            'SELECT * FROM transactions WHERE series_id IS NOT NULL ORDER BY series_index')
        .get();
    // Simulate the pre-fix calculation, where every installment was independent.
    await db.customStatement(
        "UPDATE transactions SET series_kind='recurring' WHERE series_id IS NOT NULL");
    for (final row in series.take(2)) {
      await transactions.setEffective(row.read<String>('id'),
          effective: true, effectiveDate: today);
      await receive(
          (await cashback.list()).singleWhere((r) => r.confirmed == 0), 300);
    }
    await db.customStatement(
        "UPDATE transactions SET series_kind='installments' WHERE series_id IS NOT NULL");
    final receipts = await cashback.list();
    expect(
        receipts
            .where((r) => r.confirmed == 1)
            .fold<int>(0, (v, r) => v + r.amountMinor),
        600);
    expect(receipts.singleWhere((r) => r.confirmed == 0).amountMinor, 300);
    await receive(receipts.singleWhere((r) => r.confirmed == 0), 300);
    await transactions.setEffective(series.last.read<String>('id'),
        effective: true, effectiveDate: today);
    expect((await cashback.list()).where((r) => r.confirmed == 0), isEmpty);
    expect(
        (await cashback.list()).every((r) => r.claimId.contains(purchase.id)),
        isTrue);
    await validateFinancial(db);
  });

  test('manual CRUD persists across reconciliation and backup', () async {
    await cashback.create(
        kind: 'debit',
        cardId: debitId,
        amountMinor: 450,
        accountId: destination.id,
        categoryId: incomeCategory,
        date: today);
    var receipt = (await cashback.list()).single;
    expect(receipt.confirmed, 0);
    await cashback.edit(receipt,
        amountMinor: 555,
        accountId: source.id,
        categoryId: incomeCategory,
        date: today);
    receipt = (await cashback.list()).single;
    expect(receipt.amountMinor, 555);
    expect(receipt.accountId, source.id);
    await receive(receipt, 555);
    receipt = (await cashback.list()).single;
    await cashback.edit(receipt,
        amountMinor: 600,
        accountId: destination.id,
        categoryId: incomeCategory,
        date: today);
    receipt = (await cashback.list()).single;
    expect(receipt.amountMinor, 600);
    expect(receipt.confirmed, 1);
    await validateFinancial(db);
    final snapshot = await readFinancial(db);
    await db.transaction(() => replaceFinancial(db, snapshot));
    expect((await cashback.list()).single.amountMinor, 600);
    await cashback.delete((await cashback.list()).single);
    expect(await cashback.list(), isEmpty);
    await validateFinancial(db);
  });

  test('automatic forecasts can be edited and deleted without regeneration',
      () async {
    await configure();
    await buy(100000);
    var receipt = (await cashback.list()).single;
    await cashback.edit(receipt,
        amountMinor: 777,
        accountId: destination.id,
        categoryId: incomeCategory,
        date: today);
    receipt = (await cashback.list()).single;
    expect(receipt.amountMinor, 777);
    await expectLater(
        cashback.edit(receipt,
            amountMinor: -1, accountId: destination.id, date: today),
        throwsFormatException);
    await cashback.delete(receipt);
    expect(await cashback.list(), isEmpty);
    expect(await cashback.list(), isEmpty);
    await validateFinancial(db);
  });

  test('received automatic cashback can be edited then deleted', () async {
    await configure();
    await buy(100000);
    await receive((await cashback.list()).single, 1000);
    await cashback.edit((await cashback.list()).single,
        amountMinor: 850,
        accountId: destination.id,
        categoryId: incomeCategory,
        date: today);
    expect((await cashback.list()).single.amountMinor, 850);
    await cashback.delete((await cashback.list()).single);
    expect(await cashback.list(), isEmpty);
    await validateFinancial(db);
  });

  test('debit installments receive the full cashback only once', () async {
    await configure();
    final purchase = await transactions.create(TransactionDraft(
        description: 'Parcelada débito',
        type: TransactionType.expense,
        amountMinor: 100001,
        date: today,
        isEffective: false,
        accountId: source.id,
        debitCardId: debitId,
        seriesPlan: const SeriesPlan(kind: SeriesKind.installments, count: 3)));
    await transactions.setEffective(purchase.id,
        effective: true, effectiveDate: today);
    var receipt = (await cashback.list()).single;
    expect(receipt.amountMinor, 1000);
    await receive(receipt, 1000);
    final installments = (await transactions.list())
        .where((t) => t.debitCardId == debitId && t.id != purchase.id);
    for (final installment in installments) {
      await transactions.setEffective(installment.id,
          effective: true, effectiveDate: today);
    }
    receipt = (await cashback.list()).single;
    expect(receipt.amountMinor, 1000);
    expect(receipt.confirmed, 1);
    await validateFinancial(db);
  });

  test('credit installments activate total at first installment payment',
      () async {
    await configure(kind: 'credit');
    final id = await credit.createPurchase(TransactionDraft(
        description: 'Parcelada crédito',
        type: TransactionType.expense,
        amountMinor: 100001,
        date: today,
        isEffective: false,
        accountId: creditId,
        cardId: creditId,
        seriesPlan: const SeriesPlan(kind: SeriesKind.installments, count: 3)));
    final entry = await credit.entry(id);
    await credit.pay(entry.invoiceId, source.id, entry.amountMinor, today);
    expect((await cashback.list()).single.amountMinor, 1000);
    await receive((await cashback.list()).single, 1000);
    final entries = await db
        .customSelect(
            "SELECT * FROM card_entries WHERE kind='purchase' ORDER BY installment_index")
        .get();
    for (final row in entries.skip(1)) {
      await credit.pay(row.read<String>('invoice_id'), source.id,
          row.read<int>('amount_minor'), today);
    }
    expect(await cashback.list(), hasLength(1));
    await validateFinancial(db);
  });
  test(
      'debit is one account expense, never a credit invoice; edits preserve history',
      () async {
    final purchase = await buy(10000);
    expect(purchase.debitCardId, debitId);
    expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM card_entries')
                .getSingle())
            .read<int>('n'),
        0);
    await debit.save(id: debitId, name: 'Corrigido', accountId: destination.id);
    expect((await transactions.list()).single.accountId, source.id);
    await debit.delete(debitId);
    expect(await debit.list(), isEmpty);
    expect((await transactions.list()).single.accountId, source.id);
    await validateFinancial(db);
  });
  test(
      'debit first partial settlement activates total and scheduled expenses do not',
      () async {
    await configure();
    final purchase = await buy(100000, effective: false);
    expect(await cashback.list(), isEmpty);
    await TransactionSettlementsRepository(db).add(purchase.id,
        accountId: source.id, amountMinor: 10000, date: today);
    expect((await cashback.list()).single.amountMinor, 1000);
    await TransactionSettlementsRepository(db).add(purchase.id,
        accountId: source.id, amountMinor: 10000, date: today);
    expect((await cashback.list()).single.amountMinor, 1000);
    await buy(10000, date: today.add(const Duration(days: 1)));
    expect(await cashback.list(), hasLength(1));
  });
  test(
      'credit partial coverage uses full purchase base and actual paid tier base',
      () async {
    await configure(
        kind: 'credit',
        rule: CashbackRule(
            rateBasisPoints: 100, tiers: [const CashbackTier(50000, 200)]));
    final id = await credit.createPurchase(TransactionDraft(
        description: 'Parcelada',
        type: TransactionType.expense,
        amountMinor: 100000,
        date: today,
        isEffective: false,
        accountId: creditId,
        cardId: creditId));
    final entry = await credit.entry(id);
    await expectLater(
        credit.pay(entry.invoiceId, source.id, 10000, today), throwsStateError);
    expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM card_payments')
                .getSingle())
            .read<int>('n'),
        0);
    await credit.pay(entry.invoiceId, source.id, 10000, today,
        coverage: {entry.id: 10000});
    final original = (await cashback.list()).single;
    expect(original.amountMinor, 1000);
    await receive(original, 800);
    await credit.pay(entry.invoiceId, source.id, 40000, today,
        coverage: {entry.id: 40000});
    final complement =
        (await cashback.list()).singleWhere((r) => r.confirmed == 0);
    expect(complement.kind, 'complement');
    expect(complement.amountMinor, 1000);
    await receive(complement, 1000);
    expect((await cashback.list()).where((r) => r.confirmed == 0), isEmpty);
    await validateFinancial(db);
  });
  test('historical payment coverage can be corrected without changing cash',
      () async {
    final id = await credit.createPurchase(TransactionDraft(
        description: 'Antiga',
        type: TransactionType.expense,
        amountMinor: 100000,
        date: today,
        isEffective: false,
        accountId: creditId,
        cardId: creditId));
    final entry = await credit.entry(id);
    await credit.pay(entry.invoiceId, source.id, 10000, today);
    final payment =
        (await db.customSelect('SELECT * FROM card_payments').getSingle()).data;
    final paymentId = payment['id'] as String;
    await configure(kind: 'credit');
    expect(await cashback.list(), isEmpty);
    final coverage = CardPaymentCoverageRepository(db);
    await coverage.replace(paymentId, {entry.id: 10000});
    expect((await cashback.list()).single.amountMinor, 1000);
    await expectLater(
        coverage.replace(paymentId, {entry.id: 20000}), throwsArgumentError);
    expect((await coverage.forPayment(paymentId)).selected, {
      entry.id: 10000,
    });
    await coverage.replace(paymentId, {});
    expect(await cashback.list(), isEmpty);
    await coverage.replace(paymentId, {entry.id: 10000});
    expect((await cashback.list()).single.amountMinor, 1000);
    expect(
        (await db.customSelect('SELECT * FROM card_payments').getSingle()).data,
        payment);
    expect(
        (await db
                .customSelect(
                    'SELECT COUNT(*) AS n FROM card_payment_allocations')
                .getSingle())
            .read<int>('n'),
        1);
    await validateFinancial(db);
  });
  test(
      'accepted actual amount is final through repeated reconciliation and zero confirmations',
      () async {
    await configure();
    await buy(100000);
    final original = (await cashback.list()).single;
    await receive(original, 800);
    for (var i = 0; i < 3; i++) {
      await cashback.reconcile();
    }
    expect((await cashback.list()).single.amountMinor, 800);
    await buy(10000);
    final next = (await cashback.list()).singleWhere((r) => r.confirmed == 0);
    await receive(next, 0);
    expect((await cashback.list()).where((r) => r.confirmed == 0), isEmpty);
    expect(
        (await cashback.list()).singleWhere((r) => r.id == next.id).amountMinor,
        0);
    await validateFinancial(db);
  });
  test(
      'batch confirmation preserves exact cents, rejects stale reads and is atomic',
      () async {
    await configure();
    await buy(10000);
    await buy(20000);
    final receipts = await cashback.list();
    await cashback.confirm(receipts,
        totalMinor: 1001,
        accountId: destination.id,
        categoryId: incomeCategory,
        date: today);
    expect((await cashback.list()).fold(0, (v, r) => v + r.amountMinor), 1001);
    await expectLater(
        cashback.confirm(receipts,
            totalMinor: 1001, accountId: destination.id, date: today),
        throwsStateError);
    expect((await cashback.list()).where((r) => r.confirmed == 0), isEmpty);
    await validateFinancial(db);
  });
  test('new purchases redistribute cap without mutating deposits', () async {
    await configure(
        rule: CashbackRule(rateBasisPoints: 100, monthlyCapMinor: 100));
    await buy(10000);
    await receive((await cashback.list()).single, 100);
    await buy(10000);
    final receipts = await cashback.list();
    expect(receipts.singleWhere((r) => r.confirmed == 1).amountMinor, 100);
    expect(receipts.singleWhere((r) => r.kind == 'return').amountMinor, 50);
    expect(
        receipts
            .singleWhere((r) => r.kind == 'original' && r.confirmed == 0)
            .amountMinor,
        50);
    await receive(receipts.singleWhere((r) => r.kind == 'return'), 50);
    expect(
        (await cashback.list())
            .where((r) => r.kind == 'return' && r.confirmed == 0),
        isEmpty);
  });
  test(
      'refund returns only actually received amount; confirmation has expense category',
      () async {
    await configure(kind: 'credit');
    final id = await credit.createPurchase(TransactionDraft(
        description: 'Compra',
        type: TransactionType.expense,
        amountMinor: 100000,
        date: today,
        isEffective: false,
        accountId: creditId,
        cardId: creditId));
    final entry = await credit.entry(id);
    await credit.pay(entry.invoiceId, source.id, 100000, today);
    await receive((await cashback.list()).single, 800);
    await credit.refund(entry.id, 50000, entry.invoiceId, today);
    var pending = (await cashback.list()).singleWhere((r) => r.confirmed == 0);
    expect(pending.kind, 'return');
    expect(pending.amountMinor, 400);
    await expectLater(
        cashback.confirm([pending],
            totalMinor: 400,
            accountId: destination.id,
            date: today,
            categoryId: incomeCategory),
        throwsStateError);
    await receive(pending, 400);
    await credit.refund(entry.id, 50000, entry.invoiceId, today);
    pending = (await cashback.list()).singleWhere((r) => r.confirmed == 0);
    expect(pending.amountMinor, 400);
    await receive(pending, 400);
    expect((await cashback.list()).where((r) => r.confirmed == 0), isEmpty);
    await validateFinancial(db);
  });
  test(
      'rule edits affect pending current month, retain received snapshots, disable cancels pending',
      () async {
    await configure();
    await buy(10000);
    await receive((await cashback.list()).single, 80);
    await buy(10000);
    await configure(rule: CashbackRule(rateBasisPoints: 200));
    final receipts = await cashback.list();
    expect(receipts.singleWhere((r) => r.confirmed != 0).amountMinor, 80);
    expect(receipts.singleWhere((r) => r.confirmed == 0).amountMinor, 200);
    await configure(enabled: false);
    expect((await cashback.list()).where((r) => r.confirmed == 0), isEmpty);
    await configure();
    expect(
        (await cashback.list()).where((r) => r.confirmed == 0), hasLength(1));
  });
  test(
      'receipt undo and account income shortcut respect ledger and accepted difference',
      () async {
    await configure();
    await buy(10000);
    final original = (await cashback.list()).single;
    await transactions.setEffective(original.id,
        effective: true, effectiveDate: today);
    expect((await cashback.list()).single.confirmed, 1);
    await transactions.setEffective(original.id, effective: false);
    expect((await cashback.list()).single.confirmed, 0);
    await receive((await cashback.list()).single, 80);
    expect((await cashback.list()).where((r) => r.confirmed == 0), isEmpty);
  });
  test(
      'backup financial snapshot resumes without duplicate receipts; partial sync corruption rejects',
      () async {
    await configure();
    await buy(10000);
    await receive((await cashback.list()).single, 80);
    final snapshot = await readFinancial(db);
    final copy = AppDatabase(NativeDatabase.memory());
    try {
      await copy.customSelect('SELECT 1').get();
      await copy.transaction(() => replaceFinancial(copy, snapshot));
      final restored = CashbackRepository(copy);
      expect((await restored.list()).single.amountMinor, 80);
      await restored.reconcile();
      expect(await restored.list(), hasLength(1));
      final broken = await readFinancial(copy);
      final receipt = (await restored.list()).single;
      broken['transactions']![receipt.id]!['actual_amount_minor'] = 81;
      await expectLater(copy.transaction(() => replaceFinancial(copy, broken)),
          throwsStateError);
      expect((await restored.list()).single.amountMinor, 80);
    } finally {
      await copy.close();
    }
  });
}
