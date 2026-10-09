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
    String m,
    Uri u,
    Map<String, String> h,
    Uint8List? b,
  ) =>
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
            sha256Hash: p.digest,
          ),
          p.id,
          p.base,
          p.device,
          p.kind,
        );
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
    final local = BackupManager(
      db,
      LocalBackupStore(Directory('${dir.path}/$id')),
    );
    final auth = TestAuth();
    final drive = DriveBackupManager(
      local,
      DriveBackupApi(auth, NoTransport()),
    );
    await drive.initialize();
    return Device(
      db,
      local,
      drive,
      SyncManager(
        local,
        drive,
        SyncStore(db, local.store, device: id),
        cloud,
        primaryAllowed: primary,
      ),
      auth,
    );
  }

  Future<void> seed(AppDatabase db, String id, String name) =>
      db.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES (?,?,'checking','BRL',100000,1,1)",
        [id, name],
      );
  Future<void> link() async {
    await a.sync.createBase();
    expect(a.sync.error, isNull);
    await b.sync.listBases();
    await b.sync.join(b.sync.bases.single);
    expect(b.sync.error, isNull);
  }

  test('restored unlinked Android can replace while keeping its data',
      () async {
    await link();
    await a.db.customStatement(
        'UPDATE sync_state SET base_id=NULL,email=NULL,capture_enabled=0 WHERE id=1');
    await a.db.customStatement('DELETE FROM sync_outbox');
    await seed(a.db, 'restored', 'Restaurada');
    await a.sync.listBases();
    await a.sync.replaceBase();
    expect(a.sync.error, isNull);
    await b.sync.listBases();
    await b.sync.join(b.sync.bases.single);
    expect(b.sync.error, isNull);
    expect(
        await b.db
            .customSelect("SELECT id FROM accounts WHERE id='restored'")
            .get(),
        hasLength(1));
  });

  test('corrupt recovery packet prevents publication', () async {
    await link();
    final base = (await a.sync.store.state()).base;
    await a.sync.listBases();
    cloud.corrupt = true;
    final sends = cloud.sends;
    await a.sync.replaceBase();
    expect(a.sync.error, isNotNull);
    expect(cloud.sends, sends);
    expect((await a.sync.store.state()).base, base);
    expect((await a.sync.store.state()).replacementPending, isFalse);
  });

  test('pending intent survives manager recreation and refuses another account',
      () async {
    await link();
    await a.sync.listBases();
    cloud.loseResponse = true;
    await a.sync.replaceBase();
    final resumed = SyncManager(a.local, a.drive,
        SyncStore(a.db, a.local.store, device: 'android-device-0001'), cloud,
        primaryAllowed: true);
    try {
      a.auth.email = 'other@example.com';
      await resumed.replaceBase();
      expect(resumed.error, isNotNull);
      a.auth.email = 'same@example.com';
      final sends = cloud.sends;
      await resumed.replaceBase();
      expect(resumed.error, isNull);
      expect(cloud.sends, sends);
    } finally {
      resumed.dispose();
    }
  });

  test('unpublished intent can be cancelled but published intent cannot',
      () async {
    await link();
    await a.sync.listBases();
    await a.sync.store.stageReplacement([a.sync.bases.single.base],
        a.sync.listedRevision!, a.sync.listedEmail!);
    await a.sync.cancelReplacement();
    expect(a.sync.error, isNull);
    expect((await a.sync.store.state()).replacementPending, isFalse);
    await a.sync.listBases();
    cloud.loseResponse = true;
    await a.sync.replaceBase();
    await a.sync.cancelReplacement();
    expect(a.sync.error, contains('Retome'));
    expect((await a.sync.store.state()).replacementPending, isTrue);
  });

  test('concurrent replacements stop without choosing a winner', () async {
    await link();
    await a.sync.listBases();
    final original = a.sync.bases.single.base;
    final revision = a.sync.listedRevision!;
    await a.sync.replaceBase();
    expect(a.sync.error, isNull);
    final competing = await b.sync.store
        .stageReplacement([original], revision, 'same@example.com');
    cloud.files[competing.id] = competing;
    final sends = cloud.sends;
    await a.sync.synchronize();
    expect(a.sync.error, contains('concorrentes'));
    expect(cloud.sends, sends);
    expect(cloud.files.values.where((p) => p.isBase), hasLength(3));
  });

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
  test(
      'replacement preserves local data and blocks old-device uploads until joining',
      () async {
    await link();
    final oldBase = (await a.sync.store.state()).base;
    await seed(a.db, 'new', 'Nova conta Android');
    await seed(b.db, 'offline', 'Somente Windows');
    await a.sync.listBases();
    await a.sync.replaceBase();
    expect(a.sync.error, isNull);
    expect((await a.sync.store.state()).base, isNot(oldBase));
    expect(cloud.files.values.any((p) => p.base == oldBase), isTrue);
    final sends = cloud.sends;
    await b.sync.synchronize();
    expect(b.sync.needsJoin, isTrue);
    expect(cloud.sends, sends);
    expect((await b.sync.store.state()).pending, greaterThan(0));
    await b.sync.join(b.sync.bases.single);
    expect(b.sync.error, isNull);
    expect(
      (await b.db
          .customSelect("SELECT id FROM accounts WHERE id='offline'")
          .get()),
      isEmpty,
    );
    expect(
      (await b.db.customSelect("SELECT id FROM accounts WHERE id='new'").get()),
      hasLength(1),
    );
    expect(await b.local.store.list(), isNotEmpty);
    await seed(b.db, 'after', 'Depois da troca');
    await b.sync.synchronize();
    await a.sync.synchronize();
    expect(a.sync.error, isNull);
    expect(
      (await a.db
          .customSelect("SELECT id FROM accounts WHERE id='after'")
          .get()),
      hasLength(1),
    );
  });

  test(
    'lost replacement response is retried without a duplicate base',
    () async {
      await link();
      await a.sync.listBases();
      cloud.loseResponse = true;
      await a.sync.replaceBase();
      expect(a.sync.error, isNotNull);
      expect((await a.sync.store.state()).replacementPending, isTrue);
      await seed(a.db, 'during', 'Durante o envio');
      final sends = cloud.sends;
      await a.sync.replaceBase();
      expect(a.sync.error, isNull);
      expect(cloud.sends, sends);
      expect((await a.sync.store.state()).pending, greaterThan(0));
      await a.sync.synchronize();
      await b.sync.listBases();
      await b.sync.join(b.sync.bases.single);
      expect(b.sync.error, isNull);
      expect(
        (await b.db
            .customSelect("SELECT id FROM accounts WHERE id='during'")
            .get()),
        hasLength(1),
      );
    },
  );

  test('remote changes after listing require fresh confirmation', () async {
    await link();
    await a.sync.listBases();
    await seed(b.db, 'remote', 'Nova conta remota');
    await b.sync.synchronize();
    final count = cloud.files.length;
    await a.sync.replaceBase();
    expect(a.sync.error, contains('confirme novamente'));
    expect(cloud.files.length, count);
    expect((await a.sync.store.state()).replacementPending, isFalse);
  });

  test('a secondary device cannot replace the base', () async {
    await link();
    await b.sync.listBases();
    await b.sync.replaceBase();
    expect(b.sync.error, contains('Android'));
    expect(cloud.files.values.where((p) => p.kind == 'replacement'), isEmpty);
  });

  test(
    'rede perdida após envio é conciliada sem duplicar e fila persiste',
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
    },
  );
  test(
      'dois dispositivos trocam alterações offline, cartões e pagamentos idempotentes',
      () async {
    await link();
    final cards = CardsRepository(a.db);
    final card = await cards.save(
      const CardDraft(
        name: 'Cartão',
        paymentAccountId: 'a',
        closingDay: 25,
        dueDay: 5,
        limitMinor: 50000,
      ),
    );
    final entry = await cards.createPurchase(
      TransactionDraft(
        description: 'Compra',
        type: TransactionType.expense,
        amountMinor: 10000,
        date: DateTime(2026, 1, 1),
        isEffective: false,
        accountId: 'a',
        cardId: card,
      ),
    );
    await cards.pay(
      (await cards.entry(entry)).invoiceId,
      'a',
      4000,
      DateTime(2026, 2, 5),
      fee: 500,
    );
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
      1,
    );
    expect((await a.sync.store.state()).pending, 0);
    expect((await b.sync.store.state()).pending, 0);
  });
  test(
    'compras offline na mesma fatura nova convergem sem duplicar fatura',
    () async {
      final cardsA = CardsRepository(a.db);
      final card = await cardsA.save(
        const CardDraft(
          name: 'Compartilhado',
          paymentAccountId: 'a',
          closingDay: 25,
          dueDay: 5,
          limitMinor: 50000,
        ),
      );
      await link();
      final cardsB = CardsRepository(b.db);
      Future<void> purchase(
        CardsRepository cards,
        String description,
        int amount,
      ) async {
        await cards.createPurchase(
          TransactionDraft(
            description: description,
            type: TransactionType.expense,
            amountMinor: amount,
            date: DateTime(2026, 3, 1),
            isEffective: false,
            accountId: 'a',
            cardId: card,
          ),
        );
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
                  'SELECT count(DISTINCT invoice_id) n FROM card_entries',
                )
                .getSingle())
            .read<int>('n'),
        1,
      );
      expect(
        (await b.db
                .customSelect('SELECT sum(amount_minor) n FROM card_entries')
                .getSingle())
            .read<int>('n'),
        3000,
      );
    },
  );
  test(
    'conta diferente, relógio e corrupção recusados antes de substituir',
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
    },
  );
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
      'Windows',
    );
    await b.sync.join(b.sync.bases.single);
    cloud.files.clear();
    await b.sync.synchronize();
    expect(b.sync.error, contains('origem'));
    expect(cloud.files, isEmpty);
  });
  test(
      'formulário aberto durante download adia aplicação automática e mantém seção',
      () async {
    await link();
    await seed(a.db, 'remote', 'Recebida');
    await a.sync.synchronize();
    final before = await readFinancial(b.db);
    final revision = b.local.databaseRevision;
    var safe = true;
    cloud.afterDownload = () {
      safe = false;
    };
    await b.sync.synchronize(automatic: true, canApply: () => safe);
    expect(b.sync.deferred, isTrue);
    expect(await readFinancial(b.db), before);
    expect(b.local.databaseRevision, revision);
    cloud.afterDownload = null;
    safe = true;
    await b.sync.synchronize(automatic: true, canApply: () => safe);
    expect(b.sync.error, isNull);
    expect(b.local.preserveLocation, isTrue);
    expect(await readFinancial(b.db), await readFinancial(a.db));
    final updated = b.local.databaseRevision;
    await b.sync.synchronize(automatic: true, canApply: () => true);
    expect(b.local.databaseRevision, updated);
  });
}
