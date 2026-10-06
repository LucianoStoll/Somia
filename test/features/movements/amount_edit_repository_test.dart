import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SqliteAccountsRepository accounts;
  late Account source, destination;
  final today = DateTime.now();
  final future = DateTime(today.year, today.month, today.day + 5);
  final past = DateTime(today.year, today.month, today.day - 5);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    accounts = SqliteAccountsRepository(db);
    Future<Account> create(String name) => accounts.create(AccountDraft(
        name: name,
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 10000,
        includeInAnalytics: true));
    source = await create('Origem');
    destination = await create('Destino');
  });
  tearDown(() => db.close());

  for (final type in TransactionType.values) {
    for (final date in [null, today, future]) {
      test('$type valor preserva campos, status e saldos (data=$date)',
          () async {
        final repo = SqliteTransactionsRepository(db);
        final category = await SqliteCategoriesRepository(db).create(
            CategoryDraft(
                name: 'Categoria',
                type: CategoryType.values.byName(type.name)));
        final original = await repo.create(TransactionDraft(
            description: 'Original',
            type: type,
            amountMinor: 12345,
            date: past,
            dueDate: future,
            effectiveDate: date,
            isEffective: date != null,
            accountId: source.id,
            categoryId: category.id));
        // Editar o histórico não deve exigir selecionar outra conta.
        await db.customStatement(
            'UPDATE accounts SET is_archived = 1 WHERE id = ?', [source.id]);
        await db.customStatement(
            'UPDATE categories SET is_archived = 1 WHERE id = ?',
            [category.id]);
        await repo.updateAmount(original.id,
            expectedAmountMinor: 12345, amountMinor: 12445);
        final changed = (await repo.list()).single;
        expect(changed.amountMinor, 12445);
        expect(changed.description, original.description);
        expect(changed.accountId, original.accountId);
        expect(changed.categoryId, original.categoryId);
        expect(changed.type, original.type);
        expect(changed.date, original.date);
        expect(changed.dueDate, original.dueDate);
        expect(changed.effectiveDate, original.effectiveDate);
        expect(changed.isEffective, original.isEffective);
        final row = await db
            .customSelect('SELECT actual_amount_minor FROM transactions')
            .getSingle();
        expect(row.readNullable<int>('actual_amount_minor'),
            date == null ? null : 12445);
        final balances = {
          for (final a in await accounts.list()) a.id: a.currentBalanceMinor
        };
        expect(
            balances[source.id],
            original.isEffective
                ? 10000 + (type == TransactionType.income ? 12445 : -12445)
                : 10000);
        for (final invalid in [0, -1, 9000000000000001]) {
          await expectLater(
              repo.updateAmount(original.id,
                  expectedAmountMinor: 12445, amountMinor: invalid),
              throwsFormatException);
        }
        await expectLater(
            repo.updateAmount(original.id,
                expectedAmountMinor: 12345, amountMinor: 999),
            throwsStateError);
        expect((await repo.list()).single.amountMinor, 12445);
        await repo.delete(original.id);
        await expectLater(
            repo.updateAmount(original.id,
                expectedAmountMinor: 12445, amountMinor: 999),
            throwsStateError);
      });
    }
    test('$type efetivados primeiro; pendentes e agendados não sobem',
        () async {
      final repo = SqliteTransactionsRepository(db);
      Future<FinancialTransaction> create(
              String name, DateTime due, DateTime? effective) =>
          repo.create(TransactionDraft(
              description: name,
              type: type,
              amountMinor: 100,
              date: today,
              dueDate: due,
              effectiveDate: effective,
              isEffective: effective != null,
              accountId: source.id));
      final done = await create('Feito', past, today);
      await create('Pendente', today, null);
      await create('Agendado', future, future);
      expect(
          (await repo.list(TransactionFilter(type: type, accountId: source.id)))
              .first
              .id,
          done.id);
      await repo.changeEffectiveDate(done.id, expectedDate: today);
      expect((await repo.list()).last.id, done.id);
    });
  }
  test('transferência altera os dois saldos e preserva todos os campos',
      () async {
    final repo = SqliteTransfersRepository(db);
    final original = await repo.create(TransferDraft(
        description: 'Reserva',
        sourceAccountId: source.id,
        destinationAccountId: destination.id,
        amountMinor: 2500,
        date: past,
        dueDate: future,
        effectiveDate: today,
        isEffective: true));
    await repo.updateAmount(original.id,
        expectedAmountMinor: 2500, amountMinor: 2750);
    final changed = (await repo.list()).single;
    expect(changed.amountMinor, 2750);
    expect(changed.description, original.description);
    expect(changed.sourceAccountId, original.sourceAccountId);
    expect(changed.destinationAccountId, original.destinationAccountId);
    expect(changed.date, original.date);
    expect(changed.dueDate, original.dueDate);
    expect(changed.effectiveDate, original.effectiveDate);
    expect(changed.isEffective, original.isEffective);
    final balances = {
      for (final a in await accounts.list()) a.id: a.currentBalanceMinor
    };
    expect(balances[source.id], 7250);
    expect(balances[destination.id], 12750);
    for (final invalid in [0, -1, 9000000000000001]) {
      await expectLater(
          repo.updateAmount(original.id,
              expectedAmountMinor: 2750, amountMinor: invalid),
          throwsFormatException);
    }
    await expectLater(
        repo.updateAmount(original.id,
            expectedAmountMinor: 2500, amountMinor: 3000),
        throwsStateError);
    await repo.changeEffectiveDate(original.id,
        expectedDate: today, effectiveDate: future);
    await repo.updateAmount(original.id,
        expectedAmountMinor: 2750, amountMinor: 3000);
    expect((await repo.list()).single.effectiveDate!.day, future.day);
    expect((await accounts.list()).every((a) => a.currentBalanceMinor == 10000),
        true);
    await repo.delete(original.id);
    await expectLater(
        repo.updateAmount(original.id,
            expectedAmountMinor: 3000, amountMinor: 1),
        throwsStateError);
  });
  test('transferências efetivadas primeiro inclusive com filtro de conta',
      () async {
    final repo = SqliteTransfersRepository(db);
    Future<Transfer> create(DateTime due, DateTime? effective) =>
        repo.create(TransferDraft(
            description: 'Reserva',
            sourceAccountId: source.id,
            destinationAccountId: destination.id,
            amountMinor: 100,
            date: today,
            dueDate: due,
            effectiveDate: effective,
            isEffective: effective != null));
    final done = await create(past, today);
    await create(today, null);
    await create(future, future);
    expect((await repo.list()).first.id, done.id);
    expect((await repo.list(accountId: source.id)).first.id, done.id);
    expect((await repo.list(accountId: destination.id)).first.id, done.id);
  });
}
