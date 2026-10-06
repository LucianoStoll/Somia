import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_manager.dart';
import 'package:finapp/core/database/backup_service.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/series/movement_series.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late AppDatabase db;
  late DateTime now;
  late LocalBackupStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('somia-daily-');
    db = AppDatabase(
        NativeDatabase(File(p.join(directory.path, 'finapp.sqlite'))));
    await db.customSelect('PRAGMA user_version').getSingle();
    now = DateTime(2026, 10, 5, 12);
    store = LocalBackupStore(directory, clock: () => now);
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<void> account(String name) =>
      db.customStatement('''INSERT INTO accounts
      (id, name, type, currency_code, initial_balance_minor, created_at, updated_at)
      VALUES (?, ?, 'cash', 'BRL', 12345, 1, 1)''', [name, name]);
  Future<String> name(File file) async {
    final copy = AppDatabase(NativeDatabase(file));
    try {
      return (await copy
              .customSelect('SELECT name FROM accounts ORDER BY name')
              .getSingle())
          .read<String>('name');
    } finally {
      await copy.close();
    }
  }

  test('uma cópia por dia, três automáticas e retenção independente', () async {
    await account('Original');
    final manual = await store.create(db, BackupKind.manual);
    final protected = await store.create(db, BackupKind.beforeRestore);
    for (var day = 5; day <= 9; day++) {
      now = DateTime(2026, 10, day, 12);
      expect(await store.daily(db), isNotNull);
      expect(await store.daily(db), isNull);
    }
    final copies = await store.list();
    expect(
        copies
            .where((c) => c.kind == BackupKind.automatic)
            .map((c) => c.createdAt.day),
        [9, 8, 7]);
    expect(await manual.file.exists(), isTrue);
    expect(await protected.file.exists(), isTrue);
    expect(await name(copies.first.file), 'Original');
  });

  test('falha de escrita preserva cópias antigas e não bloqueia banco',
      () async {
    await account('Original');
    final first = await store.daily(db);
    final blocker = File(p.join(directory.path, 'sem-diretorio'));
    await blocker.writeAsString('bloqueio');
    final manager =
        BackupManager(db, LocalBackupStore(Directory(blocker.path)));
    await manager.daily();
    expect(manager.error, isNotNull);
    expect(manager.busy, isFalse);
    expect(await first!.file.exists(), isTrue);
    expect(
        (await db.customSelect('SELECT name FROM accounts').getSingle())
            .read<String>('name'),
        'Original');
    manager.dispose();
  });

  test('cópia corrompida de hoje permite nova proteção válida', () async {
    await account('Original');
    final first = await store.daily(db);
    await first!.file.writeAsBytes([1, 2, 3]);
    final replacement = await store.daily(db);
    expect(replacement, isNotNull);
    expect(await name(replacement!.file), 'Original');
    expect(await store.daily(db), isNull);
  });

  test('operações simultâneas são serializadas e não duplicam o backup diário',
      () async {
    await account('Original');
    final manager = BackupManager(db, store);
    await Future.wait(
        [manager.daily(), manager.daily(), manager.create(), manager.export()]);
    expect(manager.copies.where((c) => c.kind == BackupKind.automatic),
        hasLength(1));
    expect(
        manager.copies.where((c) => c.kind == BackupKind.manual), hasLength(1));
    expect(manager.error, isNull);
    expect(manager.busy, isFalse);
    manager.dispose();
  });

  test(
      'restauração inválida preserva a preparada; cancelar mantém os dados atuais',
      () async {
    await account('Original');
    final manager = BackupManager(db, store);
    final bytes = await manager.export();
    await BackupService.stageRestore(bytes, directory);
    await manager.refresh();
    await expectLater(
        manager.restore(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    expect(await BackupService.hasPendingRestore(directory), isTrue);
    expect(manager.restorePending, isTrue);
    await manager.cancelRestore();
    expect(await BackupService.hasPendingRestore(directory), isFalse);
    expect(manager.restorePending, isFalse);
    await BackupService.applyPendingRestore(directory);
    expect(
        (await db.customSelect('SELECT name FROM accounts').getSingle())
            .read<String>('name'),
        'Original');
    manager.dispose();
  });

  test(
      'proteção antes de restaurar inclui mudanças posteriores ao agendamento e WAL',
      () async {
    await db.customStatement('PRAGMA journal_mode=WAL');
    await account('Antigo');
    final old = await BackupService.export(db, directory);
    await BackupService.stageRestore(old, directory);
    await db.customStatement("UPDATE accounts SET name='Depois de agendar'");
    await db.close();
    await BackupService.applyPendingRestore(directory);
    expect(await name(File(p.join(directory.path, 'finapp.sqlite'))), 'Antigo');
    final recovery = (await store.list())
        .singleWhere((c) => c.kind == BackupKind.beforeRestore);
    expect(await name(recovery.file), 'Depois de agendar');
    await BackupService.stageRestore(
        await recovery.file.readAsBytes(), directory);
    await BackupService.applyPendingRestore(directory);
    expect(await name(File(p.join(directory.path, 'finapp.sqlite'))),
        'Depois de agendar');
    db = AppDatabase(NativeDatabase.memory());
  });

  test(
      'snapshot completo preserva séries, cartões, faturas, pagamentos e todos os dados',
      () async {
    final accounts = SqliteAccountsRepository(db);
    Future<Account> add(String name) => accounts.create(AccountDraft(
        name: name,
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 100000,
        includeInAnalytics: true));
    final a = await add('Principal'), b = await add('Outra');
    await db.customStatement(
        "INSERT INTO categories(id,name,type,created_at,updated_at) VALUES ('c','Mercado','expense',1,1)");
    await SqliteTransactionsRepository(db).create(TransactionDraft(
        description: 'Recorrente',
        type: TransactionType.expense,
        amountMinor: 1000,
        date: DateTime(2026, 1, 10),
        isEffective: false,
        accountId: a.id,
        categoryId: 'c',
        seriesPlan: const SeriesPlan(kind: SeriesKind.recurring, count: 3)));
    await SqliteTransfersRepository(db).create(TransferDraft(
        sourceAccountId: a.id,
        destinationAccountId: b.id,
        amountMinor: 500,
        date: DateTime(2026, 1, 10),
        isEffective: true));
    final cards = CardsRepository(db);
    final id = await cards.save(CardDraft(
        name: 'Cartão',
        paymentAccountId: a.id,
        closingDay: 25,
        dueDay: 5,
        limitMinor: 100000));
    final purchase = await cards.createPurchase(TransactionDraft(
        description: 'Parcelada',
        type: TransactionType.expense,
        amountMinor: 10001,
        date: DateTime(2026, 1, 10),
        isEffective: false,
        accountId: a.id,
        cardId: id,
        categoryId: 'c',
        seriesPlan: const SeriesPlan(kind: SeriesKind.installments, count: 3)));
    final entry = await cards.entry(purchase);
    await cards.pay(entry.invoiceId, a.id, 1000, DateTime(2026, 2, 5));
    final copy = await store.create(db, BackupKind.manual);
    final restored = AppDatabase(NativeDatabase(copy.file));
    try {
      final tables = await db
          .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
          .get();
      for (final table in tables) {
        final name = table.read<String>('name');
        final original =
            await db.customSelect('SELECT * FROM "$name" ORDER BY rowid').get();
        final recovered = await restored
            .customSelect('SELECT * FROM "$name" ORDER BY rowid')
            .get();
        expect(recovered.map((r) => r.data).toList(),
            original.map((r) => r.data).toList(),
            reason: name);
      }
      expect(await restored.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty);
    } finally {
      await restored.close();
    }
  });
  test(
      'sem espaço para proteção aborta restauração e permite abrir dados atuais',
      () async {
    await account('Original');
    final old = await BackupService.export(db, directory);
    await BackupService.stageRestore(old, directory);
    await db.customStatement("UPDATE accounts SET name='Atual'");
    await db.close();
    await File(p.join(directory.path, 'somia-backups'))
        .writeAsString('bloqueio');
    await BackupService.prepareForOpen(directory);
    expect(await name(File(p.join(directory.path, 'finapp.sqlite'))), 'Atual');
    expect(await BackupService.hasPendingRestore(directory), isTrue);
    expect(await BackupService.hasRestoreFailure(directory), isTrue);
    await BackupService.cancelPendingRestore(directory);
    expect(await BackupService.hasRestoreFailure(directory), isFalse);
    db = AppDatabase(NativeDatabase.memory());
  });

  test(
      'versão futura e schema incompleto são rejeitados sem substituir pendência válida',
      () async {
    await account('Original');
    final bytes = await BackupService.export(db, directory);
    await BackupService.stageRestore(bytes, directory);
    final future = Uint8List.fromList(bytes);
    ByteData.sublistView(future)
        .setUint32(60, AppDatabase.currentSchemaVersion + 1, Endian.big);
    await expectLater(
        BackupService.stageRestore(future, directory), throwsFormatException);
    final impostor = AppDatabase(NativeDatabase.memory());
    try {
      await impostor.customSelect('PRAGMA user_version').getSingle();
      await impostor.customStatement('DROP TABLE card_limit_history');
      final invalid = await BackupService.export(impostor, directory);
      await expectLater(BackupService.stageRestore(invalid, directory),
          throwsFormatException);
    } finally {
      await impostor.close();
    }
    expect(await BackupService.hasPendingRestore(directory), isTrue);
  });

  test('proteções mantêm três versões sem apagar cópias manuais', () async {
    await account('Original');
    final manual = await store.create(db, BackupKind.manual);
    for (var day = 5; day <= 9; day++) {
      now = DateTime(2026, 10, day);
      await store.create(db, BackupKind.beforeRestore);
    }
    expect(
        (await store.list())
            .where((c) => c.kind == BackupKind.beforeRestore)
            .map((c) => c.createdAt.day),
        [9, 8, 7]);
    expect(await manual.file.exists(), isTrue);
  });
}
