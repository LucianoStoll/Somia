import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:finapp/core/sync/sync_store.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/assets/data/sqlite_assets_repository.dart';
import 'package:finapp/features/assets/domain/asset.dart';
import 'package:finapp/features/debts/data/sqlite_debts_repository.dart';
import 'package:finapp/features/debts/domain/debt.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';

void main() {
  late AppDatabase db;
  late SqliteDebtsRepository debts;
  late SqliteTransactionsRepository transactions;
  late String account;
  final reference = DateTime(2025, 1, 1);
  DebtDraft debt({int balance = 100000, String? asset}) => DebtDraft(
      name: 'Empréstimo',
      creditor: 'Credor',
      kind: DebtKind.loan,
      balanceMinor: balance,
      referenceAt: reference,
      assetId: asset);
  Future<String> expense(
          {int amount = 50000,
          bool paid = false,
          DateTime? date,
          TransactionType type = TransactionType.expense}) async =>
      (await transactions.create(TransactionDraft(
              description: 'Parcela',
              type: type,
              amountMinor: amount,
              date: date ?? DateTime(2026, 1, 25),
              dueDate: date ?? DateTime(2026, 1, 25),
              effectiveDate: date ?? DateTime(2026, 1, 25),
              isEffective: paid,
              accountId: account)))
          .id;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    debts = SqliteDebtsRepository(db);
    transactions = SqliteTransactionsRepository(db);
    account = (await SqliteAccountsRepository(db).create(const AccountDraft(
            name: 'Banco',
            type: AccountType.checking,
            currencyCode: 'BRL',
            initialBalanceMinor: 200000,
            includeInAnalytics: true)))
        .id;
  });
  tearDown(() => db.close());
  test(
      'principal separado de encargos, efetivação, desfazer e excluir recompõem saldo',
      () async {
    final id = await debts.save(debt());
    final tx = await expense();
    await debts.link(id, tx, 35000);
    var d = (await debts.load()).single;
    expect(d.balanceMinor, 100000);
    expect(d.projectedMinor, 65000);
    expect(d.payments.single.chargesMinor, 15000);
    expect(
        (await SqliteAccountsRepository(db).list()).single.currentBalanceMinor,
        200000);
    await transactions.setEffective(tx,
        effective: true, effectiveDate: DateTime(2026, 1, 25));
    expect((await debts.load()).single.balanceMinor, 65000);
    expect(
        (await SqliteAccountsRepository(db).list()).single.currentBalanceMinor,
        150000);
    await transactions.setEffective(tx, effective: false);
    expect((await debts.load()).single.balanceMinor, 100000);
    await transactions.setEffective(tx,
        effective: true, effectiveDate: DateTime(2026, 1, 25));
    await transactions.delete(tx);
    d = (await debts.load()).single;
    expect(d.balanceMinor, 100000);
    expect(d.projectedMinor, 100000);
    expect(d.payments.single.deleted, true);
    expect(
        (await SqliteAccountsRepository(db).list()).single.currentBalanceMinor,
        200000);
  });
  test('efetivação futura não amortiza hoje e desvinculação preserva histórico',
      () async {
    final id = await debts.save(debt());
    final tx = await expense(paid: true, date: DateTime(2090, 1, 1));
    await debts.link(id, tx, 50000);
    var d = (await debts.load()).single;
    expect(d.balanceMinor, 100000);
    expect(d.projectedMinor, 50000);
    await debts.unlink(d.payments.single.id);
    d = (await debts.load()).single;
    expect(d.projectedMinor, 100000);
    expect(d.payments.single.unlinked, true);
    await debts.link(id, tx, 30000);
    expect((await debts.load()).single.payments, hasLength(2));
  });
  test(
      'duplicações, amortização excessiva, datas e edição incompatível fazem rollback',
      () async {
    final id = await debts.save(debt(balance: 50000));
    final tx = await expense(paid: true);
    await expectLater(debts.link(id, tx, 50001), throwsFormatException);
    await debts.link(id, tx, 35000);
    final before = await readFinancial(db);
    await expectLater(debts.link(id, tx, 100), throwsFormatException);
    await expectLater(
        transactions.updateAmount(tx,
            expectedAmountMinor: 50000, amountMinor: 34000),
        throwsFormatException);
    await expectLater(
        transactions.changeEffectiveDate(tx,
            expectedDate: DateTime(2026, 1, 25),
            effectiveDate: DateTime(2024, 1, 1)),
        throwsFormatException);
    await expectLater(
        debts.save(debt(balance: 60000), id: id), throwsFormatException);
    expect(await readFinancial(db), before);
    final other = await expense();
    await expectLater(debts.link(id, other, 20000), throwsFormatException);
    final income = await expense(type: TransactionType.income);
    await expectLater(debts.link(id, income, 0), throwsFormatException);
    final old = await expense(date: DateTime(2024, 1, 1));
    await expectLater(debts.link(id, old, 100), throwsFormatException);
    expect((await debts.load()).single.balanceMinor, 15000);
  });
  test(
      'financiamento substitui saldo manual do bem, outras dívidas entram uma vez',
      () async {
    final assets = SqliteAssetsRepository(db);
    final asset = await assets.save(
        AssetDraft(
            name: 'Carro',
            kind: AssetKind.vehicle,
            acquiredAt: reference,
            acquisitionMinor: 2000000),
        initial: AssetValuationDraft(
            date: reference,
            valueMinor: 1800000,
            debtMinor: 900000,
            creditor: 'Banco'));
    final id = await debts.save(debt(balance: 800000, asset: asset));
    await debts.save(debt(balance: 100000));
    var overview = await assets.load();
    expect(overview.assetDebtMinor, 800000);
    expect(overview.otherDebtMinor, 100000);
    expect(overview.netMinor, 1100000);
    final tx = await expense(paid: true);
    await debts.link(id, tx, 35000);
    overview = await assets.load();
    expect(overview.assetDebtMinor, 765000);
    expect(overview.netMinor, 1085000);
    await assets.archive(asset, true);
    overview = await assets.load();
    expect(overview.assetsMinor, 0);
    expect(overview.assetDebtMinor, 765000);
    await expectLater(debts.save(debt(asset: asset)), throwsFormatException);
    await expectLater(
        assets.assess(
            asset,
            AssetValuationDraft(
                date: DateTime(2026, 1, 1), valueMinor: 1700000, debtMinor: 0)),
        throwsFormatException);
    await assets.assess(
        asset,
        AssetValuationDraft(
            date: DateTime(2026, 1, 1),
            valueMinor: 1700000,
            debtMinor: 900000,
            creditor: 'Banco'));
    expect((await assets.load()).assetDebtMinor, 765000);
    expect(await db.customSelect('SELECT * FROM transactions').get(),
        hasLength(1));
  });
  test('quitação exata e parcela só de encargos não duplicam caixa', () async {
    final id = await debts.save(debt(balance: 35000));
    final fee = await expense(paid: true, amount: 1000);
    await debts.link(id, fee, 0);
    final tx = await expense(paid: true);
    await debts.link(id, tx, 35000);
    expect((await debts.load()).single.balanceMinor, 0);
    expect((await debts.load()).single.projectedMinor, 0);
    expect(
        (await SqliteAccountsRepository(db).list()).single.currentBalanceMinor,
        149000);
  });
  test(
      'snapshot inválido preserva dados e sync é idempotente com legado v14 legível',
      () async {
    final dir = await Directory.systemTemp.createTemp('debt-sync-');
    addTearDown(() => dir.delete(recursive: true));
    final source =
        SyncStore(db, LocalBackupStore(Directory('${dir.path}/source')));
    final genesis = await source.createBase('test@example.com');
    await source.ack(genesis);
    final id = await debts.save(debt());
    final tx = await expense(paid: true);
    await debts.link(id, tx, 35000);
    await source.prepareUpload();
    final packet = (await source.uploads()).single;
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    final target =
        SyncStore(other, LocalBackupStore(Directory('${dir.path}/target')));
    final columns = await financialColumns(other);
    await target.apply([SyncPacket.decode(genesis.encode(), columns)],
        joinEmail: 'test@example.com');
    await target.apply([SyncPacket.decode(packet.encode(), columns)]);
    await target.apply([SyncPacket.decode(packet.encode(), columns)]);
    expect(await readFinancial(other), await readFinancial(db));
    expect(
        (await SqliteDebtsRepository(other).load()).single.balanceMinor, 65000);
    final historical = SyncPacket(
        genesis.id, genesis.base, genesis.device, genesis.kind, genesis.entries,
        sourceSchema: 14);
    expect(SyncPacket.decode(historical.encode(), columns).digest,
        historical.digest);
    final invalidLegacy = SyncPacket(
        packet.id, packet.base, packet.device, packet.kind, packet.entries,
        sourceSchema: 14);
    expect(() => SyncPacket.decode(invalidLegacy.encode(), columns),
        throwsFormatException);
    final before = await readFinancial(db);
    final invalid = await readFinancial(db);
    invalid['debt_payments']!.values.single['principal_minor'] = 100001;
    await expectLater(db.transaction(() => replaceFinancial(db, invalid)),
        throwsFormatException);
    expect(await readFinancial(db), before);
    await other.transaction(() => replaceFinancial(other, before));
    expect(await readFinancial(other), before);
  });
}
