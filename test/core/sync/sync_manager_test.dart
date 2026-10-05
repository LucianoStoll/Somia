import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_manager.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/drive/drive_backup.dart';
import 'package:finapp/core/drive/drive_backup_manager.dart';
import 'package:finapp/core/sync/drive_sync_api.dart';
import 'package:finapp/core/sync/sync_store.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:finapp/core/sync/sync_manager.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

class TestAuth implements DriveAuth {
  String email = 'same@example.com';
  @override
  Future<String?> account() async => email;
  @override
  Future<DriveSession> authorize() async => DriveSession(email, 'token');
  @override
  Future<DriveSession> connect() => authorize();
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> clearToken(String token) async {}
}

class NoTransport implements DriveTransport {
  @override
  Future<DriveResponse> send(
          String m, Uri u, Map<String, String> h, Uint8List? b) =>
      throw UnimplementedError();
}

class MemoryCloud implements SyncCloud {
  final files = <String, SyncPacket>{};
  bool loseResponse = false, corrupt = false;
  int sends = 0;
  void Function()? afterDownload;
  @override
  DateTime? serverTime;
  @override
  Future<List<SyncRemoteFile>> list(DriveSession s) async =>
      files.values.map((p) {
        final bytes = p.encode();
        return SyncRemoteFile(
            DriveCopy(
                id: 'drive-${p.id}',
                name: 'sync.json',
                createdAt: DateTime.now(),
                size: bytes.length,
                md5Hash: md5.convert(bytes).toString(),
                sha256Hash: p.digest),
            p.id,
            p.base,
            p.device,
            p.kind);
      }).toList();
  @override
  Future<Uint8List> download(DriveSession s, SyncRemoteFile f) async {
    afterDownload?.call();
    return corrupt ? Uint8List.fromList([1, 2, 3]) : files[f.packet]!.encode();
  }

  @override
  Future<void> upload(DriveSession s, SyncPacket p) async {
    sends++;
    files[p.id] = p;
    if (loseResponse) {
      loseResponse = false;
      throw const DriveFailure('Resposta perdida');
    }
  }
}

class Device {
  Device(this.db, this.local, this.drive, this.sync, this.auth);
  final AppDatabase db;
  final BackupManager local;
  final DriveBackupManager drive;
  final SyncManager sync;
  final TestAuth auth;
  Future<void> close() async {
    sync.dispose();
    drive.dispose();
    local.dispose();
    await db.close();
  }
}

void main() {
  late Directory dir;
  late MemoryCloud cloud;
  late Device a, b;
  Future<Device> create(String id, bool primary) async {
    final db = AppDatabase(NativeDatabase.memory());
    final local =
        BackupManager(db, LocalBackupStore(Directory('${dir.path}/$id')));
    final auth = TestAuth();
    final drive =
        DriveBackupManager(local, DriveBackupApi(auth, NoTransport()));
    await drive.initialize();
    return Device(
        db,
        local,
        drive,
        SyncManager(local, drive, SyncStore(db, local.store, device: id), cloud,
            primaryAllowed: primary),
        auth);
  }

  Future<void> seed(AppDatabase db, String id, String name) => db.customStatement(
      "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES (?,?,'checking','BRL',100000,1,1)",
      [id, name]);
  Future<void> link() async {
    await a.sync.createBase();
    expect(a.sync.error, isNull);
    await b.sync.listBases();
    await b.sync.join(b.sync.bases.single);
    expect(b.sync.error, isNull);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('somia-sync-cloud-');
    cloud = MemoryCloud();
    a = await create('android-device-0001', true);
    b = await create('windows-device-0001', false);
    await seed(a.db, 'a', 'Android');
    await seed(b.db, 'old', 'Windows');
  });
  tearDown(() async {
    await a.close();
    await b.close();
    await dir.delete(recursive: true);
  });
  test('rede perdida após envio é conciliada sem duplicar e fila persiste',
      () async {
    cloud.loseResponse = true;
    await a.sync.createBase();
    expect(a.sync.error, isNotNull);
    expect((await a.sync.store.state()).uploads, 1);
    await a.sync.synchronize();
    expect(a.sync.error, isNull);
    expect(cloud.sends, 1);
    expect((await a.sync.store.state()).uploads, 0);
    await b.sync.listBases();
    await b.sync.join(b.sync.bases.single);
    expect(await readFinancial(a.db), await readFinancial(b.db));
  });
  test(
      'dois dispositivos trocam alterações offline, cartões e pagamentos idempotentes',
      () async {
    await link();
    final cards = CardsRepository(a.db);
    final card = await cards.save(const CardDraft(
        name: 'Cartão',
        paymentAccountId: 'a',
        closingDay: 25,
        dueDay: 5,
        limitMinor: 50000));
    final entry = await cards.createPurchase(TransactionDraft(
        description: 'Compra',
        type: TransactionType.expense,
        amountMinor: 10000,
        date: DateTime(2026, 1, 1),
        isEffective: false,
        accountId: 'a',
        cardId: card));
    await cards.pay(
        (await cards.entry(entry)).invoiceId, 'a', 4000, DateTime(2026, 2, 5),
        fee: 500);
    await seed(b.db, 'new', 'Criada offline');
    await a.sync.synchronize();
    await b.sync.synchronize();
    await a.sync.synchronize();
    expect(a.sync.error, isNull);
    expect(b.sync.error, isNull);
    expect(await readFinancial(a.db), await readFinancial(b.db));
    await b.sync.synchronize();
    await a.sync.synchronize();
    expect(
        (await b.db
                .customSelect('SELECT count(*) n FROM card_payments')
                .getSingle())
            .read<int>('n'),
        1);
    expect((await a.sync.store.state()).pending, 0);
    expect((await b.sync.store.state()).pending, 0);
  });
  test('compras offline na mesma fatura nova convergem sem duplicar fatura',
      () async {
    final cardsA = CardsRepository(a.db);
    final card = await cardsA.save(const CardDraft(
        name: 'Compartilhado',
        paymentAccountId: 'a',
        closingDay: 25,
        dueDay: 5,
        limitMinor: 50000));
    await link();
    final cardsB = CardsRepository(b.db);
    Future<void> purchase(
        CardsRepository cards, String description, int amount) async {
      await cards.createPurchase(TransactionDraft(
          description: description,
          type: TransactionType.expense,
          amountMinor: amount,
          date: DateTime(2026, 3, 1),
          isEffective: false,
          accountId: 'a',
          cardId: card));
    }

    await purchase(cardsA, 'Android', 1000);
    await purchase(cardsB, 'Windows', 2000);
    await a.sync.synchronize();
    await b.sync.synchronize();
    await a.sync.synchronize();
    expect(a.sync.error, isNull);
    expect(b.sync.error, isNull);
    expect(await readFinancial(a.db), await readFinancial(b.db));
    expect(
        (await b.db
                .customSelect(
                    'SELECT count(DISTINCT invoice_id) n FROM card_entries')
                .getSingle())
            .read<int>('n'),
        1);
    expect(
        (await b.db
                .customSelect('SELECT sum(amount_minor) n FROM card_entries')
                .getSingle())
            .read<int>('n'),
        3000);
  });
  test('conta diferente, relógio e corrupção recusados antes de substituir',
      () async {
    await link();
    await seed(a.db, 'later', 'Posterior');
    await a.sync.synchronize();
    final before = await readFinancial(b.db);
    b.auth.email = 'other@example.com';
    await b.sync.synchronize();
    expect(b.sync.error, contains('outra conta'));
    expect(await readFinancial(b.db), before);
    b.auth.email = 'same@example.com';
    cloud.serverTime = DateTime.now().subtract(const Duration(hours: 1));
    await b.sync.synchronize();
    expect(b.sync.error, contains('Data e hora'));
    expect(await readFinancial(b.db), before);
    cloud.serverTime = null;
    cloud.corrupt = true;
    await b.sync.synchronize();
    expect(b.sync.error, contains('corrompido'));
    expect(await readFinancial(b.db), before);
    cloud.corrupt = false;
    cloud.afterDownload = () {
      b.auth.email = 'changed@example.com';
    };
    await b.sync.synchronize();
    expect(b.sync.error, contains('conta mudou'));
    expect(await readFinancial(b.db), before);
  });
  test(
      'Windows não publica base, vínculo é explícito e base removida não recria origem',
      () async {
    await b.sync.createBase();
    expect(b.sync.error, contains('Android'));
    expect((await b.sync.store.state()).base, isNull);
    await a.sync.createBase();
    await b.sync.listBases();
    expect(
        (await b.db.customSelect('SELECT name FROM accounts').getSingle())
            .read<String>('name'),
        'Windows');
    await b.sync.join(b.sync.bases.single);
    cloud.files.clear();
    await b.sync.synchronize();
    expect(b.sync.error, contains('origem'));
    expect(cloud.files, isEmpty);
  });
}
