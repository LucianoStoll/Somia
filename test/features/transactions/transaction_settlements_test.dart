import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/allocations/category_allocation.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/data/transaction_settlements_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';

import 'package:finapp/features/planning/data/planning_repository.dart';
import 'package:finapp/features/reimbursements/data/reimbursements_repository.dart';
import 'package:finapp/features/reimbursements/domain/reimbursement.dart';

void main() {
  late AppDatabase db;
  late SqliteAccountsRepository accounts;
  late SqliteTransactionsRepository tx;
  late TransactionSettlementsRepository repo;
  late String a, b;
  final past = DateTime.utc(2020, 1, 5), future = DateTime.utc(2190, 1, 5);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    accounts = SqliteAccountsRepository(db);
    tx = SqliteTransactionsRepository(db);
    repo = TransactionSettlementsRepository(db);
    Future<String> account(String name) => accounts
        .create(AccountDraft(
            name: name,
            type: AccountType.checking,
            currencyCode: 'BRL',
            initialBalanceMinor: 10000,
            includeInAnalytics: true))
        .then((v) => v.id);
    a = await account('Original');
    b = await account('Outra');
  });
  tearDown(() => db.close());
  Future<FinancialTransaction> create(
          {TransactionType type = TransactionType.expense,
          List<CategoryAllocation> parts = const []}) =>
      tx.create(TransactionDraft(
          description: 'Teste',
          type: type,
          amountMinor: 1001,
          date: past,
          dueDate: past,
          isEffective: false,
          accountId: a,
          allocations: parts));
  test('partial expense uses its account and only residual remains projected',
      () async {
    final t = await create();
    await repo.add(t.id, accountId: b, amountMinor: 400, date: past);
    final result = await accounts.list();
    expect(result.singleWhere((v) => v.id == a).currentBalanceMinor, 10000);
    expect(result.singleWhere((v) => v.id == a).projectedBalanceMinor, 9399);
    expect(result.singleWhere((v) => v.id == b).currentBalanceMinor, 9600);
    final item = (await tx.list()).single;
    expect(item.amountMinor, 1001);
    expect(item.settledMinor, 400);
    expect(item.remainingMinor, 601);
    expect(item.isEffective, false);
    expect(
        (await tx.list(TransactionFilter(
                dateField: TransactionDateField.effective,
                from: past,
                to: past)))
            .single
            .id,
        t.id);
    expect((await tx.list(TransactionFilter(accountId: b))).single.id, t.id);
    await repo.add(t.id, accountId: a, amountMinor: 601, date: past);
    expect(
        (await tx.list(
                const TransactionFilter(status: TransactionStatus.effective)))
            .single
            .isEffective,
        true);
    expect(
        await tx
            .list(const TransactionFilter(status: TransactionStatus.pending)),
        isEmpty);
    await validateFinancial(db);
  });
  test('future receipt is projected on chosen account without duplicate root',
      () async {
    final t = await create(type: TransactionType.income);
    await repo.add(t.id, accountId: b, amountMinor: 600, date: future);
    final result = await accounts.list();
    expect(result.singleWhere((v) => v.id == a).projectedBalanceMinor, 10401);
    expect(result.singleWhere((v) => v.id == b).currentBalanceMinor, 10000);
    expect(result.singleWhere((v) => v.id == b).projectedBalanceMinor, 10600);
    expect((await tx.list()).single.scheduledSettlementMinor, 600);
  });
  test('undo restores pending and deleting source removes its cash effects',
      () async {
    final t = await create();
    final id = await repo.add(t.id, accountId: b, amountMinor: 400, date: past);
    await repo.remove(t.id, id);
    expect(
        (await accounts.list())
            .singleWhere((v) => v.id == b)
            .currentBalanceMinor,
        10000);
    await repo.add(t.id, accountId: b, amountMinor: 400, date: past);
    await tx.delete(t.id);
    expect(
        (await accounts.list())
            .singleWhere((v) => v.id == b)
            .currentBalanceMinor,
        10000);
    await validateFinancial(db);
  });
  test('excess, currency mismatch and integral effectuation roll back',
      () async {
    final t = await create();
    await repo.add(t.id, accountId: b, amountMinor: 400, date: past);
    await expectLater(
        repo.add(t.id, accountId: b, amountMinor: 602, date: past),
        throwsFormatException);
    await expectLater(
        tx.setEffective(t.id, effective: true), throwsFormatException);
    final other = await accounts.create(const AccountDraft(
        name: 'USD',
        type: AccountType.checking,
        currencyCode: 'USD',
        initialBalanceMinor: 0,
        includeInAnalytics: true));
    await expectLater(
        repo.add(t.id, accountId: other.id, amountMinor: 1, date: past),
        throwsFormatException);
    expect((await repo.list(t.id)).length, 1);
    expect((await tx.list()).single.settledMinor, 400);
  });
  test('rateio preserves exact cents across payments and residual', () async {
    final categories = SqliteCategoriesRepository(db);
    final c = await categories
        .create(const CategoryDraft(name: 'A', type: CategoryType.expense));
    final d = await categories
        .create(const CategoryDraft(name: 'B', type: CategoryType.expense));
    final t = await create(
        parts: [CategoryAllocation(c.id, 501), CategoryAllocation(d.id, 500)]);
    await repo.add(t.id, accountId: b, amountMinor: 333, date: past);
    await repo.add(t.id, accountId: a, amountMinor: 333, date: past);
    final events = await db
        .customSelect(
            'SELECT * FROM transaction_events WHERE deleted_at IS NULL')
        .get();
    final totals = <String, int>{};
    for (final e in events) {
      final parts =
          CategoryAllocation.decode(e.read<String>('allocations_json'));
      CategoryAllocation.validate(parts, e.read<int>('planned_amount_minor'));
      for (final p in parts) {
        totals[p.categoryId] = (totals[p.categoryId] ?? 0) + p.amountMinor;
      }
    }
    expect(totals, {c.id: 501, d.id: 500});
    await validateFinancial(db);
  });
  test('snapshot restore retains history and rejects oversized merged payments',
      () async {
    final t = await create();
    await repo.add(t.id, accountId: b, amountMinor: 400, date: past);
    final rows = await readFinancial(db);
    await db.transaction(() => replaceFinancial(db, rows));
    expect((await repo.list(t.id)).single.amountMinor, 400);
    final invalid = jsonDecode(jsonEncode(rows)) as Map<String, dynamic>;
    final payments = invalid['transaction_settlements'] as Map<String, dynamic>;
    payments.values.first['amount_minor'] = 1002;
    final typed = <String, Map<String, Map<String, Object?>>>{
      for (final entry in invalid.entries)
        entry.key: {
          for (final row in (entry.value as Map).entries)
            row.key as String: Map<String, Object?>.from(row.value as Map)
        }
    };
    await expectLater(db.transaction(() => replaceFinancial(db, typed)),
        throwsFormatException);
    expect((await repo.list(t.id)).single.amountMinor, 400);
  });
  test('planning and reimbursement count actual receipts plus residual once',
      () async {
    final expense = await create();
    final reimbursements = ReimbursementsRepository(db);
    final person = await reimbursements.savePerson('Ana');
    await reimbursements
        .replace(expense.id, [ReimbursementDraft(person, 1001)]);
    final income = await create(type: TransactionType.income);
    final claim = (await reimbursements.load()).single;
    await reimbursements.link(claim.id, income.id);
    await repo.add(income.id, accountId: b, amountMinor: 400, date: past);
    final result = (await reimbursements.load()).single;
    expect(result.received, 400);
    expect(result.scheduled, 601);
    expect(result.available, 0);
    final spending = await PlanningRepository(db).spending(DateTime(2020, 1));
    expect(
        spending
            .where((s) => s.type == 'income')
            .fold(0, (v, s) => v + s.realized),
        400);
    expect(
        spending
            .where((s) => s.type == 'income')
            .fold(0, (v, s) => v + s.projected),
        1001);
  });
}
