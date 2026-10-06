import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/series/movement_series.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SqliteAccountsRepository accounts;
  late Account source, destination;
  final date = DateTime(2026, 1, 31);
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

  TransactionDraft draft(
          {TransactionType type = TransactionType.expense,
          SeriesPlan? plan,
          int amount = 10000,
          SeriesScope scope = SeriesScope.onlyThis,
          DateTime? posted,
          DateTime? due,
          String description = 'Compra',
          String? account}) =>
      TransactionDraft(
          description: description,
          type: type,
          amountMinor: amount,
          date: posted ?? date,
          dueDate: due ?? date,
          isEffective: true,
          accountId: account ?? source.id,
          seriesPlan: plan,
          scope: scope);
  const plan = SeriesPlan(kind: SeriesKind.installments, count: 4);

  for (final type in TransactionType.values) {
    test('$type série pendente, centavos e projeção sem alterar saldo atual',
        () async {
      final repo = SqliteTransactionsRepository(db);
      final first =
          await repo.create(draft(type: type, plan: plan, amount: 10001));
      final items = (await repo.list()).toList()
        ..sort((a, b) => a.series!.index.compareTo(b.series!.index));
      expect(items.length, 4);
      expect(items.map((a) => a.amountMinor), [2501, 2500, 2500, 2500]);
      expect(items.map((a) => a.series!.label),
          ['Parcelado 1/4', 'Parcelado 2/4', 'Parcelado 3/4', 'Parcelado 4/4']);
      expect(items.every((a) => a.effectiveDate == null && !a.isEffective),
          isTrue);
      expect(items[1].dueDate, DateTime.utc(2026, 2, 28));
      expect(items[2].dueDate, DateTime.utc(2026, 3, 31));
      expect(first.series!.index, 0);
      final balance = (await accounts.list(through: DateTime(2026, 4, 30)))
          .firstWhere((a) => a.id == source.id);
      expect(balance.currentBalanceMinor, 10000);
      expect(balance.projectedBalanceMinor,
          10000 + (type == TransactionType.income ? 10001 : -10001));
    });
  }
  test(
      'editar/excluir série preserva anteriores, efetivados e agendados; isolado não altera vizinhos',
      () async {
    final repo = SqliteTransactionsRepository(db);
    await repo.create(draft(plan: plan));
    var items = (await repo.list()).toList()
      ..sort((a, b) => a.series!.index.compareTo(b.series!.index));
    await repo.setEffective(items[2].id,
        effective: true, effectiveDate: DateTime(2026, 3, 31));
    await repo.setEffective(items[3].id,
        effective: true, effectiveDate: DateTime(2090, 1, 1));
    await repo.update(
        items[1].id,
        draft(
            amount: 1500,
            posted: items[1].date,
            due: items[1].dueDate,
            scope: SeriesScope.thisAndNext,
            description: 'Alterada'));
    items = (await repo.list()).toList()
      ..sort((a, b) => a.series!.index.compareTo(b.series!.index));
    expect(items.map((a) => a.description),
        ['Compra', 'Alterada', 'Compra', 'Compra']);
    expect(items.map((a) => a.amountMinor), [2500, 1500, 2500, 2500]);
    expect(items[1].effectiveDate, isNull);
    await repo.delete(items[1].id, scope: SeriesScope.thisAndNext);
    expect((await repo.list()).length, 3);
    await repo.updateAmount(items[0].id,
        expectedAmountMinor: 2500, amountMinor: 3500);
    expect((await repo.list()).where((a) => a.amountMinor == 3500).length, 1);
  });
  test(
      'editar fevereiro sem mudar data mantém março 31; data nova reancora próximas',
      () async {
    final repo = SqliteTransactionsRepository(db);
    await repo.create(draft(plan: plan));
    var items = (await repo.list()).toList()
      ..sort((a, b) => a.series!.index.compareTo(b.series!.index));
    await repo.update(
        items[1].id,
        draft(
            posted: items[1].date,
            due: items[1].dueDate,
            scope: SeriesScope.thisAndNext,
            description: 'Sem alterar calendário'));
    items = (await repo.list()).toList()
      ..sort((a, b) => a.series!.index.compareTo(b.series!.index));
    expect(items[2].dueDate, DateTime.utc(2026, 3, 31));
    await repo.update(
        items[1].id,
        draft(
            posted: items[1].date,
            due: DateTime(2026, 2, 10),
            scope: SeriesScope.thisAndNext));
    items = (await repo.list()).toList()
      ..sort((a, b) => a.series!.index.compareTo(b.series!.index));
    expect(items.map((a) => a.dueDate!.day), [31, 10, 10, 10]);
    expect(items[2].date, DateTime.utc(2026, 3, 31));
  });
  test('edição de valor em série protege efetivados e rejeita valor antigo',
      () async {
    final repo = SqliteTransactionsRepository(db);
    await repo.create(draft(plan: plan));
    final items = (await repo.list()).toList()
      ..sort((a, b) => a.series!.index.compareTo(b.series!.index));
    await repo.setEffective(items[2].id, effective: true);
    await repo.updateAmount(items[1].id,
        expectedAmountMinor: 2500,
        amountMinor: 3000,
        scope: SeriesScope.thisAndNext);
    final updated = (await repo.list()).toList()
      ..sort((a, b) => a.series!.index.compareTo(b.series!.index));
    expect(updated.map((a) => a.amountMinor), [2500, 3000, 2500, 3000]);
    await expectLater(
        repo.updateAmount(items[1].id,
            expectedAmountMinor: 2500,
            amountMinor: 4000,
            scope: SeriesScope.thisAndNext),
        throwsStateError);
  });
  test('falhas de criação e edição desfazem a série inteira', () async {
    final repo = SqliteTransactionsRepository(db);
    await expectLater(
        repo.create(draft(
            plan: const SeriesPlan(
                kind: SeriesKind.recurring, count: 3, unit: SeriesUnit.year),
            posted: DateTime(2099, 1, 1),
            due: DateTime(2099, 1, 1))),
        throwsFormatException);
    expect(await repo.list(), isEmpty);
    await expectLater(
        repo.create(draft(plan: plan, account: 'ausente')), throwsStateError);
    expect(await repo.list(), isEmpty);
    final first = await repo.create(draft(plan: plan));
    await expectLater(
        repo.update(first.id,
            draft(account: 'ausente', scope: SeriesScope.thisAndNext)),
        throwsStateError);
    expect(
        (await repo.list())
            .every((a) => a.description == 'Compra' && a.amountMinor == 2500),
        isTrue);
  });
  test(
      'transferências finitas movimentam dois saldos sem duplicação e preservam efetivados',
      () async {
    final repo = SqliteTransfersRepository(db);
    final first = await repo.create(TransferDraft(
        description: 'Reserva',
        sourceAccountId: source.id,
        destinationAccountId: destination.id,
        amountMinor: 10001,
        date: date,
        isEffective: true,
        seriesPlan: plan));
    var items = (await repo.list()).toList()
      ..sort((a, b) => a.series!.index.compareTo(b.series!.index));
    expect(items.map((a) => a.amountMinor), [2501, 2500, 2500, 2500]);
    expect(items.every((a) => a.effectiveDate == null), isTrue);
    var balances = await accounts.list(through: DateTime(2026, 4, 30));
    expect(balances.firstWhere((a) => a.id == source.id).projectedBalanceMinor,
        -1);
    expect(
        balances
            .firstWhere((a) => a.id == destination.id)
            .projectedBalanceMinor,
        20001);
    await repo.setEffective(items[2].id,
        effective: true, effectiveDate: DateTime(2026, 3, 31));
    await repo.update(
        items[1].id,
        TransferDraft(
            description: 'Aplicação',
            sourceAccountId: source.id,
            destinationAccountId: destination.id,
            amountMinor: 3000,
            date: items[1].date,
            dueDate: items[1].dueDate,
            isEffective: true,
            scope: SeriesScope.thisAndNext));
    items = (await repo.list()).toList()
      ..sort((a, b) => a.series!.index.compareTo(b.series!.index));
    expect(items.map((a) => a.amountMinor), [2501, 3000, 2500, 3000]);
    expect(items[2].description, 'Reserva');
    expect(items[3].dueDate, DateTime.utc(2026, 4, 30));
    await repo.updateAmount(items[1].id,
        expectedAmountMinor: 3000,
        amountMinor: 4000,
        scope: SeriesScope.thisAndNext);
    await repo.delete(items[1].id, scope: SeriesScope.thisAndNext);
    expect((await repo.list()).length, 2);
    await repo.delete(first.id);
    expect((await repo.list()).single.isEffective, true);
    balances = await accounts.list();
    expect(balances.firstWhere((a) => a.id == source.id).currentBalanceMinor,
        7500);
    expect(
        balances.firstWhere((a) => a.id == destination.id).currentBalanceMinor,
        12500);
  });
}
