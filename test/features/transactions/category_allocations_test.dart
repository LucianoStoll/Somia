import 'dart:convert';
import 'dart:io';
import 'package:finapp/core/database/local_backup_store.dart';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/allocations/category_allocation.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/series/movement_series.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:finapp/core/sync/sync_store.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/dashboard/data/sqlite_dashboard_repository.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';

void main() {
  late AppDatabase db;
  late Directory folder;
  SyncStore sync(AppDatabase value) => SyncStore(
      value,
      LocalBackupStore(Directory(
          '${folder.path}/${identical(value, db) ? "first" : "second"}')));
  late SqliteTransactionsRepository repo;
  late SqliteCategoriesRepository categories;
  late String account, first, second;
  final date = DateTime.utc(2026, 9, 1);
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('allocation-test-');
    db = AppDatabase(NativeDatabase.memory());
    repo = SqliteTransactionsRepository(db);
    categories = SqliteCategoriesRepository(db);
    account = (await SqliteAccountsRepository(db).create(const AccountDraft(
            name: 'Conta',
            type: AccountType.checking,
            currencyCode: 'BRL',
            initialBalanceMinor: 50000,
            includeInAnalytics: true)))
        .id;
    first = (await categories.create(
            const CategoryDraft(name: 'Mercado', type: CategoryType.expense)))
        .id;
    second = (await categories.create(
            const CategoryDraft(name: 'Casa', type: CategoryType.expense)))
        .id;
  });
  tearDown(() async {
    await db.close();
    await folder.delete(recursive: true);
  });
  TransactionDraft draft(
          {int total = 10001,
          bool paid = false,
          SeriesPlan? plan,
          String? card,
          List<CategoryAllocation>? parts}) =>
      TransactionDraft(
          description: 'Rateada',
          type: TransactionType.expense,
          accountId: account,
          amountMinor: total,
          date: date,
          isEffective: paid,
          effectiveDate: paid ? date : null,
          seriesPlan: plan,
          cardId: card,
          allocations: parts ??
              [
                CategoryAllocation(first, 6001),
                CategoryAllocation(second, 4000)
              ]);

  test('centavos determinísticos e ausência de overflow', () {
    final parts = CategoryAllocation.distribute(const [
      CategoryAllocation('a', 1),
      CategoryAllocation('b', 1),
      CategoryAllocation('c', 1)
    ], 100);
    expect(parts.map((p) => p.amountMinor), [34, 33, 33]);
    final large = CategoryAllocation.distribute(const [
      CategoryAllocation('a', 6000000000000000),
      CategoryAllocation('b', 3000000000000000)
    ], 9000000000000000);
    expect(
        large.map((p) => p.amountMinor), [6000000000000000, 3000000000000000]);
    expect(
        CategoryAllocation.distribute(
                const [CategoryAllocation('a', 1), CategoryAllocation('b', 1)],
                1)
            .map((p) => p.amountMinor),
        [1, 0]);
    expect(
        () => CategoryAllocation.distribute(
            const [CategoryAllocation('a', 0), CategoryAllocation('b', 0)], 1),
        throwsFormatException);
  });
  test('percentuais são preservados ao alterar valor e reabrir rateio',
      () async {
    final parts = CategoryAllocation.distribute([
      CategoryAllocation(first, 6000, percentageBasisPoints: 6000),
      CategoryAllocation(second, 4000, percentageBasisPoints: 4000)
    ], 10001);
    final item = await repo.create(draft(parts: parts));
    await repo.updateAmount(item.id,
        expectedAmountMinor: 10001, amountMinor: 20002);
    final changed = (await repo.list()).single;
    expect(changed.allocations.map((p) => p.amountMinor), [12001, 8001]);
    expect(
        changed.allocations.map((p) => p.percentageBasisPoints), [6000, 4000]);
  });
  test('saldo e total únicos, gráfico distribuído, filtros e edição rápida',
      () async {
    final item = await repo.create(draft(paid: true));
    expect((await repo.list()).length, 1);
    expect(
        (await SqliteAccountsRepository(db).list()).single.currentBalanceMinor,
        39999);
    final summary =
        (await SqliteDashboardRepository(db).load(date)).currencies.single;
    expect(summary.expenseMinor, 10001);
    expect({for (final c in summary.expensesByCategory) c.name: c.amountMinor},
        {'Mercado': 6001, 'Casa': 4000});
    expect((await repo.list(TransactionFilter(categoryId: second))).single.id,
        item.id);
    await repo.updateAmount(item.id,
        expectedAmountMinor: 10001, amountMinor: 10002);
    expect(
        (await repo.list())
            .single
            .allocations
            .fold(0, (s, p) => s + p.amountMinor),
        10002);
    await repo.setEffective(item.id, effective: false);
    expect(
        (await SqliteAccountsRepository(db).list()).single.currentBalanceMinor,
        50000);
    await repo.delete(item.id);
    expect(await repo.list(), isEmpty);
  });
  test('soma, duplicação e categoria de outro tipo rejeitadas atomicamente',
      () async {
    await expectLater(
        repo.create(draft(parts: [
          CategoryAllocation(first, 1),
          CategoryAllocation(second, 2)
        ])),
        throwsFormatException);
    await expectLater(
        repo.create(draft(parts: [
          CategoryAllocation(first, 6001),
          CategoryAllocation(first, 4000)
        ])),
        throwsFormatException);
    final income = (await categories.create(
            const CategoryDraft(name: 'Salário', type: CategoryType.income)))
        .id;
    await expectLater(
        repo.create(draft(parts: [
          CategoryAllocation(first, 6001),
          CategoryAllocation(income, 4000)
        ])),
        throwsStateError);
    expect(await repo.list(), isEmpty);
  });
  test(
      'histórico arquivado preservado, novo vínculo e mudança de tipo bloqueados',
      () async {
    final item = await repo.create(draft());
    await categories.setArchived(first, archived: true);
    await repo.update(item.id, draft());
    await expectLater(repo.create(draft()), throwsStateError);
    await expectLater(
        categories.update(first,
            const CategoryDraft(name: 'Mudou', type: CategoryType.income)),
        throwsStateError);
  });
  test('parcelamento divide cada ocorrência sem perder centavos', () async {
    await repo.create(
        draft(plan: const SeriesPlan(kind: SeriesKind.installments, count: 3)));
    final rows = await repo.list();
    expect(rows.length, 3);
    expect(rows.fold(0, (s, p) => s + p.amountMinor), 10001);
    for (final row in rows) {
      expect(row.allocations.fold(0, (s, p) => s + p.amountMinor),
          row.amountMinor);
    }
  });
  test('cartão: parcelas, estorno e pagamento não duplicam rateio', () async {
    final cards = CardsRepository(db);
    final card = await cards.save(CardDraft(
        name: 'Cartão', paymentAccountId: account, closingDay: 25, dueDay: 5));
    final id = await cards.createPurchase(draft(
        card: card,
        plan: const SeriesPlan(kind: SeriesKind.installments, count: 2)));
    final entry = await cards.entry(id);
    expect(entry.allocations.fold(0, (s, p) => s + p.amountMinor),
        entry.amountMinor);
    await cards.refund(id, 1, entry.invoiceId, date);
    final refunded = (await cards.entries(cardId: card))
        .firstWhere((e) => e.kind == 'refund');
    expect(refunded.allocations.fold(0, (s, p) => s + p.amountMinor), 1);
    await validateFinancial(db);
    final summary =
        (await SqliteDashboardRepository(db).load(entry.invoiceMonth))
            .currencies
            .single;
    expect(summary.expenseMinor, entry.amountMinor - 1);
    expect(summary.expensesByCategory.fold(0, (s, p) => s + p.amountMinor),
        entry.amountMinor - 1);
    final invoice = await cards.invoice(entry.invoiceId);
    await cards.pay(invoice.id, account, entry.amountMinor - 1, invoice.dueAt);
    final paidSummary =
        (await SqliteDashboardRepository(db).load(entry.invoiceMonth))
            .currencies
            .single;
    expect(paidSummary.expenseMinor, summary.expenseMinor);
    expect(paidSummary.expensesByCategory.fold(0, (s, p) => s + p.amountMinor),
        summary.expenseMinor);
    expect(
        (await SqliteAccountsRepository(db).list()).single.currentBalanceMinor,
        50000 - entry.amountMinor + 1);
    expect((await repo.list()).where((m) => m.cardInvoiceId == invoice.id),
        hasLength(1));
    await validateFinancial(db);
  });
  test('backup financeiro e sync conservam partes e rejeitam soma corrompida',
      () async {
    await repo.create(draft());
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    final packet = await sync(db).createBase('a@example.com');
    final restored =
        SyncPacket.decode(packet.encode(), await financialColumns(other));
    await sync(other).apply([restored], joinEmail: 'a@example.com');
    expect(
        CategoryAllocation.encode(
            (await SqliteTransactionsRepository(other).list())
                .single
                .allocations),
        CategoryAllocation.encode((await repo.list()).single.allocations));
    final rows = await readFinancial(db);
    await other.transaction(() => replaceFinancial(other, rows));
    final row = rows['transactions']!.values.single;
    row['allocations_json'] = CategoryAllocation.encode(
        [CategoryAllocation(first, 1), CategoryAllocation(second, 2)]);
    await expectLater(other.transaction(() => replaceFinancial(other, rows)),
        throwsFormatException);
    expect(
        (await SqliteTransactionsRepository(other).list()).single.amountMinor,
        10001);
  });
  test('pacote v11 mantém digest e ganha classificação vazia ao receber',
      () async {
    await repo.create(draft(parts: []));
    final packet = await sync(db).createBase('a@example.com');
    final old = SyncPacket(
        packet.id, packet.base, packet.device, packet.kind, packet.entries,
        sourceSchema: 11);
    final bytes = old.encode();
    final decoded = SyncPacket.decode(bytes, await financialColumns(db));
    expect(decoded.digest, old.digest);
    expect(
        decoded.entries
            .firstWhere((e) => e.table == 'transactions')
            .data!['allocations_json'],
        '[]');
    final invalid = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    invalid['schema'] = AppDatabase.currentSchemaVersion + 1;
    expect(
        () => SyncPacket.decode(
            Uint8List.fromList(utf8.encode(jsonEncode(invalid))),
            <String, Map<String, String>>{}),
        throwsFormatException);
  });
}
