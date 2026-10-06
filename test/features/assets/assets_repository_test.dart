import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:finapp/core/sync/sync_store.dart';
import 'package:finapp/features/assets/domain/asset.dart';
import 'package:finapp/features/assets/data/sqlite_assets_repository.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/investments/data/sqlite_investments_repository.dart';
import 'package:finapp/features/investments/domain/investment.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';

void main() {
  late AppDatabase db;
  late SqliteAssetsRepository repo;
  final acquired = DateTime(2025, 1, 1), assessed = DateTime(2026, 1, 1);
  AssetDraft draft({DateTime? date}) => AssetDraft(
      name: 'Palio',
      kind: AssetKind.vehicle,
      acquiredAt: date ?? acquired,
      acquisitionMinor: 3000000);
  AssetValuationDraft value(int amount, {int debt = 1000000, DateTime? date}) =>
      AssetValuationDraft(
          date: date ?? assessed,
          valueMinor: amount,
          debtMinor: debt,
          creditor: debt > 0 ? 'Banco' : '');
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SqliteAssetsRepository(db);
  });
  tearDown(() => db.close());
  test(
      'patrimônio usa bens, dívida, cartão e conta de investimento uma única vez',
      () async {
    final bank = await SqliteAccountsRepository(db).create(AccountDraft(
        name: 'Banco',
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 100000,
        includeInAnalytics: true));
    await SqliteInvestmentsRepository(db).save(const InvestmentDraft(
        name: 'CDB', kind: InvestmentKind.cdb, initialBalanceMinor: 200000));
    final cards = CardsRepository(db);
    final card = await cards.save(CardDraft(
        name: 'Cartão', paymentAccountId: bank.id, closingDay: 25, dueDay: 5));
    await cards.createPurchase(TransactionDraft(
        description: 'Compra',
        type: TransactionType.expense,
        amountMinor: 10000,
        date: assessed,
        isEffective: false,
        accountId: bank.id,
        cardId: card));
    await repo.save(draft(), initial: value(2500000));
    final totals = await repo.load();
    expect(totals.accountsMinor, 300000);
    expect(totals.assetsMinor, 2500000);
    expect(totals.assetDebtMinor, 1000000);
    expect(totals.cardDebtMinor, 10000);
    expect(totals.netMinor, 1790000);
    expect(await db.customSelect('SELECT * FROM transactions').get(), isEmpty);
    expect(await db.customSelect('SELECT * FROM transfers').get(), isEmpty);
  });
  test(
      'avaliações preservam histórico, backdate não substitui atual e retirada é reversível',
      () async {
    final id = await repo.save(draft(), initial: value(2500000));
    var item = (await repo.load()).assets.single;
    final first = item.current!.id;
    await repo.assess(
        id, value(2600000, debt: 500000, date: DateTime(2026, 2, 1)),
        expectedLatestId: first);
    await repo.assess(id, value(2400000, date: DateTime(2025, 12, 1)));
    item = (await repo.load()).assets.single;
    expect(item.valueMinor, 2600000);
    expect(item.debtMinor, 500000);
    expect(item.history, hasLength(3));
    await expectLater(
        repo.assess(id, value(1), expectedLatestId: first), throwsStateError);
    await repo.archive(id, true);
    expect((await repo.load()).assetsMinor, 0);
    expect((await repo.load()).assetDebtMinor, 500000);
    await repo.assess(
        id, value(2600000, debt: 400000, date: DateTime(2026, 2, 1)));
    expect((await repo.load()).assetDebtMinor, 400000);
    await repo.archive(id, false);
    expect((await repo.load()).assetsMinor, 2600000);
    await repo.assess(
        id, value(2700000, debt: 400000, date: DateTime(2026, 2, 1)));
    expect((await repo.load()).assets.single.valueMinor, 2700000);
  });
  test('valores, datas e credor inválidos causam rollback integral', () async {
    await expectLater(
        repo.save(draft(), initial: value(-1)), throwsFormatException);
    expect((await repo.load()).assets, isEmpty);
    final id = await repo.save(draft(), initial: value(1, debt: 5));
    final before = await readFinancial(db);
    await expectLater(
        repo.assess(id,
            AssetValuationDraft(date: assessed, valueMinor: 1, debtMinor: 5)),
        throwsFormatException);
    await expectLater(
        repo.assess(id, value(1, date: DateTime(2024))), throwsFormatException);
    await expectLater(
        repo.assess(id, value(1, date: DateTime(2200))), throwsFormatException);
    await expectLater(repo.save(draft(date: DateTime(2026, 2)), id: id),
        throwsFormatException);
    expect(await readFinancial(db), before);
    expect((await repo.load()).netMinor, -4);
  });
  test(
      'backup/sync preservam bens e avaliações; versões antigas não podem inventar bens',
      () async {
    final dir = await Directory.systemTemp.createTemp('asset-sync-');
    addTearDown(() => dir.delete(recursive: true));
    final source =
        SyncStore(db, LocalBackupStore(Directory('${dir.path}/source')));
    final genesis = await source.createBase('test@example.com');
    await source.ack(genesis);
    final id = await repo.save(draft(), initial: value(2500000));
    await repo.assess(id, value(2600000, debt: 500000));
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
    expect((await SqliteAssetsRepository(other).load()).assets.single.history,
        hasLength(2));
    for (final schema in [11, 12, 13]) {
      final historical = SyncPacket(genesis.id, genesis.base, genesis.device,
          genesis.kind, genesis.entries,
          sourceSchema: schema);
      expect(SyncPacket.decode(historical.encode(), columns).digest,
          historical.digest);
      final invalid = SyncPacket(
          packet.id, packet.base, packet.device, packet.kind, packet.entries,
          sourceSchema: schema);
      expect(() => SyncPacket.decode(invalid.encode(), columns),
          throwsFormatException);
    }
    final before = await readFinancial(db);
    final invalid = await readFinancial(db);
    invalid['asset_valuations']!.values.first['assessed_at'] =
        DateTime.utc(2024).millisecondsSinceEpoch;
    await expectLater(db.transaction(() => replaceFinancial(db, invalid)),
        throwsFormatException);
    expect(await readFinancial(db), before);
    final future = await readFinancial(db);
    future['asset_valuations']!.values.first['assessed_at'] =
        DateTime.utc(2090).millisecondsSinceEpoch;
    await expectLater(db.transaction(() => replaceFinancial(db, future)),
        throwsFormatException);
    expect(await readFinancial(db), before);
    await other.transaction(() => replaceFinancial(other, before));
    expect(await readFinancial(other), before);
  });
}
