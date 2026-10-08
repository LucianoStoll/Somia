import 'dart:io';
import 'dart:convert';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/database/backup_service.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/database/schema_v16.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/reimbursements/data/reimbursements_repository.dart';
import 'package:finapp/features/reimbursements/domain/reimbursement.dart';
import '../../core/database/schema_v16_test.dart' show LegacyV15;

class LegacyV16 extends LegacyV15 {
  LegacyV16(super.executor);
  @override
  int get schemaVersion => 16;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in schemaV16) {
          await customStatement(sql);
        }
      });
}

void main() {
  late AppDatabase db;
  late ReimbursementsRepository repo;
  late SqliteTransactionsRepository tx;
  late SqliteAccountsRepository accounts;
  late String account, person;
  final date = DateTime.utc(2026, 9, 1);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ReimbursementsRepository(db);
    tx = SqliteTransactionsRepository(db);
    accounts = SqliteAccountsRepository(db);
    account = (await accounts.create(const AccountDraft(
            name: 'Conta',
            type: AccountType.cash,
            currencyCode: 'BRL',
            initialBalanceMinor: 20000,
            includeInAnalytics: true)))
        .id;
    person = await repo.savePerson('Mãe');
  });
  tearDown(() async {
    await db.close();
  });
  Future<FinancialTransaction> expense({int claim = 4000}) =>
      tx.create(TransactionDraft(
          description: 'Compra',
          type: TransactionType.expense,
          amountMinor: 10000,
          date: date,
          isEffective: true,
          accountId: account,
          reimbursements: [ReimbursementDraft(person, claim)]));
  test('despesa integral, recebimentos parciais, saldo e exclusão da receita',
      () async {
    await expense();
    expect((await accounts.list()).single.currentBalanceMinor, 10000);
    var r = (await repo.load()).single;
    expect(r.pending, 4000);
    await repo.receive(r, amount: 1500, accountId: account, date: date);
    r = (await repo.load()).single;
    expect(r.received, 1500);
    expect(r.pending, 2500);
    await repo.receive(r, amount: 2500, accountId: account, date: date);
    r = (await repo.load()).single;
    expect(r.received, 4000);
    expect(r.pending, 0);
    expect((await accounts.list()).single.currentBalanceMinor, 14000);
    expect(
        (await tx.list(const TransactionFilter(type: TransactionType.expense)))
            .single
            .amountMinor,
        10000);
    await tx.delete(r.receipts.first.transactionId);
    expect((await repo.load()).single.pending, 2500);
    await validateFinancial(db);
  });
  test('agendamento não entra no recebido e impede exceder obrigação',
      () async {
    await expense();
    var r = (await repo.load()).single;
    await repo.receive(r,
        amount: 2500,
        accountId: account,
        date: DateTime.now().add(const Duration(days: 30)));
    r = (await repo.load()).single;
    expect(r.received, 0);
    expect(r.scheduled, 2500);
    expect(r.available, 1500);
    await expectLater(
        repo.receive(r, amount: 2000, accountId: account, date: date),
        throwsA(isA<FormatException>()));
    expect((await tx.list()).length, 2);
    expect((await accounts.list()).single.currentBalanceMinor, 10000);
    final receipt = r.receipts.single;
    await tx.changeEffectiveDate(receipt.transactionId,
        expectedDate: receipt.date, effectiveDate: date);
    expect((await repo.load()).single.received, 2500);
  });
  test('vincular existente, não duplicar, desfazer e editar protegem limites',
      () async {
    final source = await expense();
    var r = (await repo.load()).single;
    final income = await tx.create(TransactionDraft(
        description: 'Recebido',
        type: TransactionType.income,
        amountMinor: 4000,
        date: date,
        isEffective: true,
        accountId: account));
    final balance = (await accounts.list()).single.currentBalanceMinor;
    await repo.link(r.id, income.id);
    expect((await accounts.list()).single.currentBalanceMinor, balance);
    await expectLater(
        repo.link(r.id, income.id), throwsA(isA<FormatException>()));
    await expectLater(
        tx.updateAmount(income.id,
            expectedAmountMinor: 4000, amountMinor: 5000),
        throwsA(isA<FormatException>()));
    await expectLater(
        tx.updateAmount(source.id,
            expectedAmountMinor: 10000, amountMinor: 3000),
        throwsA(isA<FormatException>()));
    await expectLater(tx.delete(source.id), throwsA(isA<FormatException>()));
    await tx.setEffective(income.id, effective: false);
    expect((await repo.load()).single.received, 0);
    r = (await repo.load()).single;
    await repo.unlink(r.receipts.single.id);
    expect((await tx.list()).length, 2);
    await repo.replace(source.id, []);
    await tx.delete(source.id);
    await validateFinancial(db);
  });
  test(
      'mais de uma pessoa, arquivamento, aliases e mesclagem preservam vínculos',
      () async {
    final other = await repo.savePerson('Pai');
    await tx.create(TransactionDraft(
        description: 'Compra',
        type: TransactionType.expense,
        amountMinor: 10000,
        date: date,
        isEffective: false,
        accountId: account,
        reimbursements: [
          ReimbursementDraft(person, 4000),
          ReimbursementDraft(other, 3000)
        ]));
    await repo.archivePerson(
        (await repo.people()).singleWhere((p) => p.id == person));
    expect((await repo.load()).length, 2);
    await repo.mergePeople(person, other);
    expect((await repo.load(personId: other)).length, 2);
    expect((await repo.people()).single.aliases, contains('Mãe'));
    await validateFinancial(db);
  });
  test('valores inválidos e soma de pessoas rejeitados atomicamente', () async {
    await expectLater(expense(claim: 11000), throwsA(isA<FormatException>()));
    expect(await tx.list(), isEmpty);
    await expectLater(expense(claim: 0), throwsA(isA<FormatException>()));
    await expectLater(
        tx.create(TransactionDraft(
            description: 'Receita',
            type: TransactionType.income,
            amountMinor: 10000,
            date: date,
            isEffective: false,
            accountId: account,
            reimbursements: [ReimbursementDraft(person, 1000)])),
        throwsA(isA<FormatException>()));
    expect(await repo.load(), isEmpty);
  });
  test('cartão vincula compra, preserva fatura e protege exclusão', () async {
    final cards = CardsRepository(db);
    final card = await cards.save(CardDraft(
        name: 'Cartão',
        paymentAccountId: account,
        closingDay: 25,
        dueDay: 5,
        limitMinor: 50000));
    final entry = await cards.createPurchase(TransactionDraft(
        description: 'Compra cartão',
        type: TransactionType.expense,
        amountMinor: 10000,
        date: date,
        isEffective: false,
        accountId: account,
        cardId: card,
        reimbursements: [ReimbursementDraft(person, 4000)]));
    expect((await repo.drafts('card:$entry')).single.amountMinor, 4000);
    final r = (await repo.load()).single;
    await repo.receive(r, amount: 4000, accountId: account, date: date);
    expect((await cards.find(card)).committedMinor, 10000);
    expect((await accounts.list()).single.currentBalanceMinor, 24000);
    await expectLater(
        tx.delete('card:$entry'), throwsA(isA<FormatException>()));
    await validateFinancial(db);
  });
  test(
      'backup restaura pessoas, obrigação e recebimento; sync contém novas entidades',
      () async {
    final dir = await Directory.systemTemp.createTemp('reimbursement-backup-');
    addTearDown(() => dir.delete(recursive: true));
    await expense();
    await repo.receive((await repo.load()).single,
        amount: 1500, accountId: account, date: date);
    final bytes = await BackupService.export(db, dir);
    await repo.savePerson('Extra');
    await BackupService.restoreOpen(db, LocalBackupStore(dir), bytes);
    expect((await repo.people()).length, 1);
    expect((await repo.load()).single.received, 1500);
    final rows = await readFinancial(db), columns = await financialColumns(db);
    final entries = [
      for (final table in [
        'people',
        'reimbursements',
        'reimbursement_receipts'
      ])
        for (final row in rows[table]!.values)
          SyncEntry(table, row['id'] as String, 0, 'device-reimbursement-0001',
              false, row)
    ];
    final packet = SyncPacket(
        'packet-reimbursement-0001',
        'base-reimbursement-0001',
        'device-reimbursement-0001',
        'genesis',
        entries);
    expect(SyncPacket.decode(packet.encode(), columns).entries.length, 3);
    final legacy = SyncPacket(
        'packet-reimbursement-0001',
        'base-reimbursement-0001',
        'device-reimbursement-0001',
        'genesis',
        entries,
        sourceSchema: 16);
    expect(() => SyncPacket.decode(legacy.encode(), columns),
        throwsA(isA<FormatException>()));
  });
  test('v16 migra sem perder cor e reidentifica upload mantendo seus dados',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('reimbursement-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/old.sqlite');
    final old = LegacyV16(NativeDatabase(file));
    await old.customStatement('INSERT INTO sync_uploads VALUES(?,?)', [
      'old-packet-reimbursement',
      jsonEncode({
        'id': 'old-packet-reimbursement',
        'schema': 16,
        'entries': [
          {
            'table': 'credit_cards',
            'data': {'color_argb': 4286421725}
          }
        ]
      })
    ]);
    await old.close();
    final upgraded = AppDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    expect(await ReimbursementsRepository(upgraded).people(), isEmpty);
    final packet = jsonDecode((await upgraded
            .customSelect('SELECT payload FROM sync_uploads')
            .getSingle())
        .read<String>('payload'));
    expect(packet['schema'], AppDatabase.currentSchemaVersion);
    expect(packet['id'], isNot('old-packet-reimbursement'));
    expect(packet['entries'][0]['data']['color_argb'], 4286421725);
  });
}
