import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/allocations/category_allocation.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/database/schema_v17.dart';
import 'package:finapp/core/database/planning_integrity.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/planning/data/planning_repository.dart';
import 'package:finapp/features/planning/domain/planning.dart';
import '../reimbursements/reimbursements_repository_test.dart' show LegacyV16;

class LegacyV17 extends LegacyV16 {
  LegacyV17(super.executor);
  @override
  int get schemaVersion => 17;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in schemaV17) {
          await customStatement(sql);
        }
      });
}

void main() {
  late AppDatabase db;
  late PlanningRepository repo;
  late SqliteAccountsRepository accounts;
  late SqliteCategoriesRepository categories;
  late SqliteTransactionsRepository tx;
  late String account, category, sub;
  final now = DateTime(2026, 10, 8), period = DateTime(2026, 10);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = PlanningRepository(db, now: () => now);
    accounts = SqliteAccountsRepository(db);
    categories = SqliteCategoriesRepository(db);
    tx = SqliteTransactionsRepository(db);
    account = (await accounts.create(const AccountDraft(
            name: 'Reserva',
            type: AccountType.savings,
            currencyCode: 'BRL',
            initialBalanceMinor: 100000,
            includeInAnalytics: true)))
        .id;
    category = (await categories.create(const CategoryDraft(
            name: 'Alimentação', type: CategoryType.expense)))
        .id;
    sub = (await categories.create(CategoryDraft(
            name: 'Mercado', type: CategoryType.expense, parentId: category)))
        .id;
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> expense(int amount, DateTime date,
      {bool paid = true, String? cat}) async {
    await tx.create(TransactionDraft(
        description: 'Compra',
        type: TransactionType.expense,
        amountMinor: amount,
        date: date,
        isEffective: paid,
        accountId: account,
        categoryId: cat ?? sub));
  }

  GoalDraft goal(
          {String name = 'Viagem',
          List<String>? linked,
          String kind = 'goal',
          List<String>? essential,
          int months = 6}) =>
      GoalDraft(
          name: name,
          kind: kind,
          currency: 'BRL',
          target: kind == 'goal' ? 200000 : 0,
          accounts: linked ?? [account],
          essential: essential ?? (kind == 'reserve' ? [category] : []),
          months: months);
  test('orçamento separa realizado, pendente e efetivação futura', () async {
    await expense(2000, DateTime(2026, 10, 5));
    await expense(3000, DateTime(2026, 10, 10), paid: false);
    await expense(4000, DateTime(2026, 10, 20));
    await repo.saveBudget(period, category, 'BRL', 10000);
    final b = (await repo.budgets(period)).single;
    expect(b.realized, 2000);
    expect(b.projected, 9000);
    expect(b.amount, 10000);
    await repo.saveBudget(period, category, 'BRL', 12000);
    expect((await repo.budgets(period)).single.id, b.id);
  });
  test('rateio mantém o total e distribui limites por categoria', () async {
    final other = (await categories.create(const CategoryDraft(
            name: 'Transporte', type: CategoryType.expense)))
        .id;
    await tx.create(TransactionDraft(
        description: 'Rateio',
        type: TransactionType.expense,
        amountMinor: 10000,
        date: DateTime(2026, 10, 3),
        isEffective: true,
        accountId: account,
        allocations: [
          CategoryAllocation(sub, 4000),
          CategoryAllocation(other, 6000)
        ]));
    await repo.saveBudget(period, category, 'BRL', 10000);
    await repo.saveBudget(period, other, 'BRL', 10000);
    final budgets = await repo.budgets(period);
    expect(budgets.singleWhere((b) => b.categoryId == category).realized, 4000);
    expect(budgets.fold<int>(0, (v, b) => v + b.projected), 10000);
  });
  test('histórico mensal e cópia não sobrescrevem mês de destino', () async {
    await repo.saveBudget(DateTime(2026, 9), category, 'BRL', 10000);
    await repo.copyPrevious(period);
    await repo.saveBudget(period, category, 'BRL', 12000);
    await repo.copyPrevious(period);
    expect((await repo.budgets(DateTime(2026, 9))).single.amount, 10000);
    expect((await repo.budgets(period)).single.amount, 12000);
    await repo.deleteBudget((await repo.budgets(period)).single.id);
    expect(await repo.budgets(period), isEmpty);
  });
  test('categoria e subcategoria não duplicam limites; moeda separada',
      () async {
    await repo.saveBudget(period, category, 'BRL', 10000);
    await expectLater(repo.saveBudget(period, sub, 'BRL', 4000),
        throwsA(isA<FormatException>()));
    expect((await repo.budgets(period)).length, 1);
    await repo.saveBudget(period, sub, 'USD', 4000);
    expect((await repo.budgets(period)).length, 2);
    await expectLater(repo.saveBudget(period, category, 'BRL', 0),
        throwsA(isA<FormatException>()));
  });
  test('parcelas e estornos no mês da fatura, pagamento não duplica', () async {
    final cards = CardsRepository(db);
    final card = await cards.save(CardDraft(
        name: 'Cartão',
        paymentAccountId: account,
        closingDay: 25,
        dueDay: 10,
        limitMinor: 100000));
    await cards.createPurchase(TransactionDraft(
        description: 'Cartão',
        type: TransactionType.expense,
        amountMinor: 12000,
        date: DateTime(2026, 10, 1),
        isEffective: false,
        accountId: account,
        cardId: card,
        categoryId: sub,
        cardInvoiceMonth: period));
    await repo.saveBudget(period, category, 'BRL', 20000);
    final b = (await repo.budgets(period)).single;
    expect(b.projected, 12000);
    expect(b.realized, 12000);
    final invoice = (await db
            .customSelect(
                'SELECT id FROM card_invoices WHERE card_id=\'$card\'')
            .get())
        .first
        .read<String>('id');
    final stamp = PlanningRepository.day(now);
    await db.customStatement(
        'INSERT INTO card_payments(id,invoice_id,account_id,amount_minor,effective_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',
        ['payment', invoice, account, 12000, stamp, stamp, stamp]);
    expect((await repo.budgets(period)).single.projected, 12000);
    await db.customStatement(
        "INSERT INTO card_entries(id,card_id,invoice_id,purchase_id,description,kind,category_id,amount_minor,posted_at,created_at,updated_at) VALUES(?,?,?,?,?,'refund',?,?,?,?,?)",
        [
          'refund',
          card,
          invoice,
          'refund',
          'Estorno',
          sub,
          -2000,
          stamp,
          stamp,
          stamp
        ]);
    expect((await repo.budgets(period)).single.projected, 10000);
  });
  test('meta usa saldo real sem modificar contas, reserva ou patrimônio',
      () async {
    final before = (await accounts.list()).single.currentBalanceMinor;
    final id = await repo.saveGoal(goal());
    final g = (await repo.goals()).single;
    expect(g.id, id);
    expect(g.saved, before);
    expect(g.target, 200000);
    expect((await accounts.list()).single.currentBalanceMinor, before);
    await repo.deleteGoal(id);
    expect(await repo.goals(), isEmpty);
    expect((await accounts.list()).single.currentBalanceMinor, before);
  });
  test('conta exclusiva para meta ativa, arquivamento e reativação atômicos',
      () async {
    await repo.saveGoal(goal());
    await expectLater(
        repo.saveGoal(goal(name: 'Outra')), throwsA(isA<FormatException>()));
    expect((await repo.goals()).length, 1);
    await repo.archiveGoal((await repo.goals()).single);
    await repo.saveGoal(goal(name: 'Outra'));
    await expectLater(
        repo.archiveGoal((await repo.goals()).firstWhere((g) => g.archived)),
        throwsA(isA<FormatException>()));
    expect((await repo.goals()).where((g) => !g.archived).length, 1);
  });
  test('reserva calcula média de três meses completos e não duplica filhas',
      () async {
    await expense(3000, DateTime(2026, 7, 5));
    await expense(6000, DateTime(2026, 8, 5));
    await expense(99000, DateTime(2026, 9, 5), paid: false);
    await expense(10000, now);
    await repo.saveGoal(goal(kind: 'reserve', months: 6));
    final g = (await repo.goals()).single;
    expect(g.monthlyEssential, 3000);
    expect(g.target, 18000);
    await expectLater(
        repo.saveGoal(goal(kind: 'reserve', essential: [category, sub]),
            id: g.id),
        throwsA(isA<FormatException>()));
    expect((await repo.goals()).single.target, 18000);
  });
  test('reserva sem histórico mostra base zero e seleção essencial obrigatória',
      () async {
    await repo.saveGoal(goal(kind: 'reserve'));
    expect((await repo.goals()).single.target, 0);
    await expectLater(
        repo.saveGoal(goal(kind: 'reserve', essential: []),
            id: (await repo.goals()).single.id),
        throwsA(isA<FormatException>()));
  });
  test('metas bloqueiam moeda incompatível e categorias de receita', () async {
    await repo.saveGoal(goal());
    await expectLater(
        accounts.update(
            account,
            const AccountDraft(
                name: 'Conta',
                type: AccountType.savings,
                currencyCode: 'USD',
                initialBalanceMinor: 100000,
                includeInAnalytics: true)),
        throwsStateError);
    final income = (await categories.create(
            const CategoryDraft(name: 'Salário', type: CategoryType.income)))
        .id;
    await expectLater(repo.saveBudget(period, income, 'BRL', 1000),
        throwsA(isA<FormatException>()));
    await repo.saveBudget(period, category, 'BRL', 1000);
    await expectLater(
        categories.update(category,
            const CategoryDraft(name: 'Renda', type: CategoryType.income)),
        throwsStateError);
  });
  test(
      'snapshot e sync preservam planejamento e rejeitam histórico falsificado',
      () async {
    await repo.saveBudget(period, category, 'BRL', 1000);
    await repo.saveGoal(goal());
    final snapshot = await readFinancial(db);
    await db.transaction(() => replaceFinancial(db, snapshot));
    await validateFinancial(db);
    expect((await repo.budgets(period)).single.amount, 1000);
    expect((await repo.goals()).single.saved, 100000);
    const device = 'device-1234567890';
    final entries = <SyncEntry>[];
    for (final table in ['budget_limits', 'planning_goals', 'goal_accounts']) {
      for (final e in snapshot[table]!.entries) {
        entries.add(SyncEntry(table, e.key, 0, device, false, e.value));
      }
    }
    final packet = SyncPacket(
        'packet-1234567890', 'base-123456789000', device, 'genesis', entries);
    final columns = await financialColumns(db);
    expect(SyncPacket.decode(packet.encode(), columns).entries.length, 3);
    expect(
        () => SyncPacket.decode(
            SyncPacket(packet.id, packet.base, device, 'genesis', entries,
                    sourceSchema: 17)
                .encode(),
            columns),
        throwsA(isA<FormatException>()));
    await db.customStatement(
        'UPDATE planning_goals SET essential_json=\'["missing"]\'');
    await expectLater(validatePlanning(db), throwsA(isA<FormatException>()));
  });
  test('migration v17 preserva fila e reidentifica pacote', () async {
    final directory =
        await Directory.systemTemp.createTemp('planning-migration');
    final file = File('${directory.path}/old.sqlite');
    final old = LegacyV17(NativeDatabase(file));
    await old.customSelect('PRAGMA user_version').get();
    final payload =
        jsonEncode({'schema': 17, 'id': 'old-packet', 'entries': []});
    await old.customStatement(
        'INSERT INTO sync_uploads(packet_id,payload) VALUES(?,?)',
        ['old-packet', payload]);
    await old.close();
    final migrated = AppDatabase(NativeDatabase(file));
    try {
      final row =
          await migrated.customSelect('SELECT * FROM sync_uploads').getSingle();
      final packet = jsonDecode(row.read<String>('payload'));
      expect(packet['schema'], 18);
      expect(packet['id'], isNot('old-packet'));
      expect(
          (await migrated.customSelect('SELECT * FROM planning_goals').get()),
          isEmpty);
    } finally {
      await migrated.close();
      await directory.delete(recursive: true);
    }
  });
}
