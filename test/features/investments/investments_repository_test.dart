import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/database/backup_service.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:finapp/core/sync/sync_store.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/investments/data/sqlite_investments_repository.dart';
import 'package:finapp/features/investments/domain/investment.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';

void main() {
  late AppDatabase db;
  late SqliteInvestmentsRepository repo;
  late SqliteAccountsRepository accounts;
  late Directory folder;
  late String bank;
  final date = DateTime.now().subtract(const Duration(days: 2));
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('investment-');
    db = AppDatabase(NativeDatabase.memory());
    repo = SqliteInvestmentsRepository(db);
    accounts = SqliteAccountsRepository(db);
    bank = (await accounts.create(const AccountDraft(
            name: 'Banco',
            type: AccountType.checking,
            currencyCode: 'BRL',
            initialBalanceMinor: 100000,
            includeInAnalytics: true)))
        .id;
  });
  tearDown(() async {
    await db.close();
    await folder.delete(recursive: true);
  });
  Future<Investment> create({int initial = 0}) async {
    await repo.save(InvestmentDraft(
        name: 'CDB', kind: InvestmentKind.cdb, initialBalanceMinor: initial));
    return (await repo.load()).investments.single;
  }

  test('conta existente não duplica ativos nem altera saldo/configuração',
      () async {
    await repo.save(InvestmentDraft(
        name: 'Saldo remunerado', kind: InvestmentKind.cdi, accountId: bank));
    final view = await repo.load();
    expect(view.accounts, hasLength(1));
    expect(view.investedMinor, 100000);
    expect(view.financialAssetsMinor, 100000);
    expect(view.investments.single.account.includeInBalance, isTrue);
    expect(await SqliteTransactionsRepository(db).list(), isEmpty);
    await expectLater(
        repo.save(InvestmentDraft(
            name: 'Outra', kind: InvestmentKind.savings, accountId: bank)),
        throwsFormatException);
    await expectLater(
        repo.save(InvestmentDraft(
            name: 'Outra',
            kind: InvestmentKind.cdb,
            accountId: bank,
            initialBalanceMinor: 10)),
        throwsFormatException);
    expect((await repo.load()).accounts, hasLength(1));
  });

  test('aportes/resgates são transferências únicas e preservam patrimônio',
      () async {
    final item = await create();
    expect(item.account.includeInBalance, isFalse);
    await repo.transfer(item.id,
        otherAccountId: bank, deposit: true, amountMinor: 10001, date: date);
    var view = await repo.load();
    expect(view.investedMinor, 10001);
    expect(view.financialAssetsMinor, 100000);
    expect(view.accounts.firstWhere((a) => a.id == bank).currentBalanceMinor,
        89999);
    await repo.transfer(item.id,
        otherAccountId: bank, deposit: false, amountMinor: 3333, date: date);
    view = await repo.load();
    expect(view.investedMinor, 6668);
    expect(view.financialAssetsMinor, 100000);
    expect(await SqliteTransfersRepository(db).list(), hasLength(2));
    expect(await SqliteTransactionsRepository(db).list(), isEmpty);
  });

  test('rendimento é receita e ajuste do banco não presume ganho/gasto',
      () async {
    final item = await create(initial: 10000);
    await repo.recordReturn(item.id, amountMinor: 123, date: date);
    expect((await repo.load()).investedMinor, 10123);
    await repo.reconcile(item.id,
        targetMinor: 10199, expectedBalanceMinor: 10123, date: date);
    expect((await repo.load()).investedMinor, 10199);
    await repo.reconcile(item.id,
        targetMinor: 10000, expectedBalanceMinor: 10199, date: date);
    expect((await repo.load()).investedMinor, 10000);
    final rows = await db
        .customSelect('SELECT * FROM transactions ORDER BY created_at,id')
        .get();
    expect(rows.map((r) => r.read<int>('planned_amount_minor')),
        containsAll([123, 76, 199]));
    final returns = rows.firstWhere(
        (r) => r.read<String>('description').startsWith('Rendimento'));
    expect(returns.read<String>('type'), 'income');
    expect(returns.read<int>('ignore_analytics'), 0);
    final adjustments = rows
        .where((r) => r.read<String>('description').startsWith('Ajuste'))
        .toList();
    expect(adjustments.map((r) => r.read<int>('ignore_analytics')), [1, 1]);
    expect(adjustments.map((r) => r.read<String>('type')),
        containsAll(['income', 'expense']));
    expect((await repo.load()).financialAssetsMinor, 110000);
  });

  test('saldo já conferente e repetição não geram novas movimentações',
      () async {
    final item = await create(initial: 10000);
    await repo.reconcile(item.id,
        targetMinor: 10000, expectedBalanceMinor: 10000, date: date);
    expect(await SqliteTransactionsRepository(db).list(), isEmpty);
    await repo.reconcile(item.id,
        targetMinor: 10100, expectedBalanceMinor: 10000, date: date);
    await expectLater(
        repo.reconcile(item.id,
            targetMinor: 10100, expectedBalanceMinor: 10000, date: date),
        throwsStateError);
    await repo.reconcile(item.id,
        targetMinor: 10100, expectedBalanceMinor: 10100, date: date);
    expect(await SqliteTransactionsRepository(db).list(), hasLength(1));
    await repo.reconcile(item.id,
        targetMinor: 0, expectedBalanceMinor: 10100, date: date);
    expect((await repo.load()).investedMinor, 0);
  });

  test('ajuste passado usa saldo dessa data e preserva movimentos posteriores',
      () async {
    final item = await create(initial: 10000);
    final later = date.add(const Duration(days: 1));
    await repo.recordReturn(item.id, amountMinor: 100, date: later);
    expect((await repo.load(date: date)).investedMinor, 10000);
    await repo.reconcile(item.id,
        targetMinor: 10050, expectedBalanceMinor: 10000, date: date);
    expect((await repo.load(date: date)).investedMinor, 10050);
    expect((await repo.load()).investedMinor, 10150);
  });

  test('limites, data futura e resgate excessivo não gravam parcialmente',
      () async {
    final item = await create(initial: 100);
    for (final amount in [0, -1, 9000000000000001]) {
      await expectLater(
          repo.recordReturn(item.id, amountMinor: amount, date: date),
          throwsFormatException);
    }
    await expectLater(
        repo.recordReturn(item.id,
            amountMinor: 1, date: DateTime.now().add(const Duration(days: 2))),
        throwsFormatException);
    await expectLater(
        repo.transfer(item.id,
            otherAccountId: bank, deposit: false, amountMinor: 101, date: date),
        throwsFormatException);
    await expectLater(
        repo.transfer(item.id,
            otherAccountId: item.account.id,
            deposit: true,
            amountMinor: 1,
            date: date),
        throwsFormatException);
    await expectLater(
        repo.reconcile(item.id,
            targetMinor: -1, expectedBalanceMinor: 100, date: date),
        throwsFormatException);
    expect(await SqliteTransfersRepository(db).list(), isEmpty);
    expect(await SqliteTransactionsRepository(db).list(), isEmpty);
    expect((await repo.load()).investedMinor, 100);
  });

  test('cadastro/edit não aceita moeda estrangeira nem altera histórico',
      () async {
    final usd = (await accounts.create(const AccountDraft(
            name: 'USD',
            type: AccountType.investment,
            currencyCode: 'USD',
            initialBalanceMinor: 100,
            includeInAnalytics: true)))
        .id;
    await expectLater(
        repo.save(InvestmentDraft(
            name: 'Inválida', kind: InvestmentKind.cdb, accountId: usd)),
        throwsFormatException);
    final item = await create(initial: 100);
    await repo.save(
        InvestmentDraft(
            name: 'Poupança',
            kind: InvestmentKind.savings,
            institution: 'Banco',
            maturityDate: DateTime(2027, 10, 25),
            notes: 'Reserva',
            accountId: item.account.id),
        id: item.id);
    await expectLater(
        accounts.update(
            item.account.id,
            const AccountDraft(
                name: 'USD',
                type: AccountType.investment,
                currencyCode: 'USD',
                initialBalanceMinor: 100,
                includeInAnalytics: true)),
        throwsStateError);
    final changed = (await repo.load()).investments.single;
    expect(changed.name, 'Poupança');
    expect(changed.kind, InvestmentKind.savings);
    expect(changed.maturityDate, DateTime.utc(2027, 10, 25));
    expect(changed.account.currentBalanceMinor, 100);
    expect(await SqliteTransactionsRepository(db).list(), isEmpty);
  });

  test(
      'trocar vínculo preserva saldo e histórico, libera conta antiga e rejeita duplicidade',
      () async {
    final item = await create(initial: 100);
    await repo.recordReturn(item.id, amountMinor: 25, date: date);
    final before = await SqliteTransactionsRepository(db).list();
    await repo.save(
        InvestmentDraft(
            name: 'Corrigida', kind: InvestmentKind.cdb, accountId: bank),
        id: item.id);
    expect((await repo.load()).investments.single.account.id, bank);
    expect(
        (await accounts.list())
            .firstWhere((a) => a.id == item.account.id)
            .currentBalanceMinor,
        125);
    expect((await SqliteTransactionsRepository(db).list()).single.id,
        before.single.id);
    await repo.save(InvestmentDraft(
        name: 'Outra', kind: InvestmentKind.cdb, accountId: item.account.id));
    final other =
        (await repo.load()).investments.firstWhere((i) => i.id != item.id);
    await expectLater(
        repo.save(
            InvestmentDraft(
                name: 'Duplicada', kind: InvestmentKind.cdb, accountId: bank),
            id: other.id),
        throwsFormatException);
    expect(
        (await repo.load())
            .investments
            .firstWhere((i) => i.id == other.id)
            .account
            .id,
        item.account.id);
  });

  test(
      'excluir aplicação libera conta sem apagar dinheiro ou movimentos e sincroniza novo vínculo',
      () async {
    final source = SyncStore(
        db, LocalBackupStore(Directory('${folder.path}/source-delete')));
    final genesis = await source.createBase('test@example.com');
    await source.ack(genesis);
    final item = await create(initial: 100);
    await repo.recordReturn(item.id, amountMinor: 25, date: date);
    await source.prepareUpload();
    final created = (await source.uploads()).single;
    await source.ack(created);
    await repo.delete(item.id);
    expect((await repo.load()).investments, isEmpty);
    expect(
        (await accounts.list())
            .firstWhere((a) => a.id == item.account.id)
            .currentBalanceMinor,
        125);
    expect((await SqliteTransactionsRepository(db).list()).single.accountId,
        item.account.id);
    await repo.save(InvestmentDraft(
        name: 'Nova',
        kind: InvestmentKind.savings,
        accountId: item.account.id));
    await source.prepareUpload();
    final changed = (await source.uploads()).single;
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    final target = SyncStore(
        other, LocalBackupStore(Directory('${folder.path}/target-delete')));
    final columns = await financialColumns(other);
    await target.apply([SyncPacket.decode(genesis.encode(), columns)],
        joinEmail: 'test@example.com');
    await target.apply([SyncPacket.decode(created.encode(), columns)]);
    await target.apply([SyncPacket.decode(changed.encode(), columns)]);
    expect(await readFinancial(other), await readFinancial(db));
    expect(
        (await SqliteInvestmentsRepository(other).load())
            .investments
            .single
            .name,
        'Nova');
    final bytes = await BackupService.export(db, folder);
    await repo.delete((await repo.load()).investments.single.id);
    await BackupService.restoreOpen(db, LocalBackupStore(folder), bytes);
    expect((await repo.load()).investments.single.name, 'Nova');
  });

  test('arquivar conserva saldo/histórico e reativação permite novas operações',
      () async {
    final item = await create(initial: 100);
    await repo.setArchived(item.id, true);
    expect((await repo.load()).investedMinor, 100);
    await expectLater(repo.recordReturn(item.id, amountMinor: 1, date: date),
        throwsFormatException);
    await expectLater(
        repo.transfer(item.id,
            otherAccountId: bank, deposit: true, amountMinor: 1, date: date),
        throwsFormatException);
    await repo.setArchived(item.id, false);
    await repo.recordReturn(item.id, amountMinor: 1, date: date);
    expect((await repo.load()).investedMinor, 101);
  });

  test('backup/restauração preserva aplicação, contas e operações', () async {
    final item = await create(initial: 10000);
    await repo.transfer(item.id,
        otherAccountId: bank, deposit: true, amountMinor: 100, date: date);
    await repo.recordReturn(item.id, amountMinor: 1, date: date);
    final snapshot = await readFinancial(db);
    final bytes = await BackupService.export(db, folder);
    await repo.recordReturn(item.id, amountMinor: 500, date: date);
    await BackupService.restoreOpen(db, LocalBackupStore(folder), bytes);
    expect(await readFinancial(db), snapshot);
    expect((await repo.load()).investedMinor, 10101);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });

  test('sync transmite vínculo e operações juntas, sem duplicar ativos',
      () async {
    final source =
        SyncStore(db, LocalBackupStore(Directory('${folder.path}/source')));
    final genesis = await source.createBase('test@example.com');
    await source.ack(genesis);
    final item = await create(initial: 10000);
    await repo.transfer(item.id,
        otherAccountId: bank, deposit: true, amountMinor: 100, date: date);
    await repo.recordReturn(item.id, amountMinor: 1, date: date);
    await source.prepareUpload();
    final packet = (await source.uploads()).single;
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    final target =
        SyncStore(other, LocalBackupStore(Directory('${folder.path}/target')));
    final columns = await financialColumns(other);
    await target.apply([SyncPacket.decode(genesis.encode(), columns)],
        joinEmail: 'test@example.com');
    await target.apply([SyncPacket.decode(packet.encode(), columns)]);
    expect(await readFinancial(other), await readFinancial(db));
    await target.apply([SyncPacket.decode(packet.encode(), columns)]);
    final view = await SqliteInvestmentsRepository(other).load();
    expect(view.investedMinor, 10101);
    expect(view.financialAssetsMinor, 110001);
    for (final version in [11, 12]) {
      final old = SyncPacket(genesis.id, genesis.base, genesis.device,
          genesis.kind, genesis.entries,
          sourceSchema: version);
      expect(SyncPacket.decode(old.encode(), columns).digest, old.digest);
    }
  });

  test(
      'backup/sync recusam conta incompatível e vínculo duplicado com rollback',
      () async {
    final item = await create(initial: 100);
    final before = await readFinancial(db);
    final invalid = await readFinancial(db);
    invalid['accounts']![item.account.id]!['currency_code'] = 'USD';
    await expectLater(db.transaction(() => replaceFinancial(db, invalid)),
        throwsFormatException);
    expect(await readFinancial(db), before);
    final duplicate = await readFinancial(db);
    duplicate['investments']!['duplicada'] = {
      ...duplicate['investments']!.values.single,
      'id': 'duplicada'
    };
    await expectLater(db.transaction(() => replaceFinancial(db, duplicate)),
        throwsA(isA<Exception>()));
    expect(await readFinancial(db), before);
    final invalidDate = await readFinancial(db);
    invalidDate['investments']!.values.single['maturity_at'] = 'data inválida';
    await expectLater(db.transaction(() => replaceFinancial(db, invalidDate)),
        throwsA(isA<Exception>()));
    expect(await readFinancial(db), before);
    await repo.recordReturn(item.id, amountMinor: 1, date: date);
    expect((await repo.load()).investedMinor, 101);
  });

  test('movimentos pendentes não viram saldo realizado da aplicação', () async {
    final item = await create(initial: 100);
    await SqliteTransactionsRepository(db).create(TransactionDraft(
        description: 'Previsto',
        type: TransactionType.income,
        amountMinor: 1000,
        date: date,
        isEffective: false,
        accountId: item.account.id));
    expect((await repo.load()).investedMinor, 100);
    await repo.reconcile(item.id,
        targetMinor: 101, expectedBalanceMinor: 100, date: date);
    expect((await repo.load()).investedMinor, 101);
  });
}
