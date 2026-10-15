import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_service.dart';
import 'package:finapp/core/database/schema_v1.dart';
import 'package:finapp/core/database/schema_v2.dart';
import 'package:finapp/core/database/schema_v3.dart';
import 'package:finapp/core/database/schema_v4.dart';
import 'package:finapp/core/database/schema_v5.dart';
import 'package:finapp/core/database/schema_v6.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

class _LegacyV6 extends GeneratedDatabase {
  _LegacyV6(super.executor);
  @override
  int get schemaVersion => 6;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (_) async {
        for (final statement in [
          ...schemaV1,
          ...schemaV2,
          ...schemaV3,
          ...schemaV4,
          ...schemaV5,
          ...schemaV6,
        ]) {
          await customStatement(statement);
        }
      });
}

void main() {
  test('v6 migra sem mudar saldos e backup preserva descrição da transferência',
      () async {
    final directory = await Directory.systemTemp.createTemp('somia-v7-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/finapp.sqlite');
    final old = _LegacyV6(NativeDatabase(file));
    await old.customStatement('''INSERT INTO accounts
      (id, name, type, currency_code, initial_balance_minor, include_in_balance, created_at, updated_at)
      VALUES ('a', 'Banco', 'checking', 'BRL', 1000, 1, 1, 1),
             ('b', 'Reserva', 'savings', 'BRL', 0, 0, 1, 1)''');
    await old.customStatement('''INSERT INTO transfers
      (id, source_account_id, destination_account_id, amount_minor,
       planned_at, posted_at, due_at, effective_at, created_at, updated_at)
      VALUES ('t', 'a', 'b', 500, 1, 1, 1, 1, 1, 1)''');
    await old.close();
    final db = AppDatabase(NativeDatabase(file));
    final transfers = SqliteTransfersRepository(db);
    final migrated = (await transfers.list()).single;
    expect(migrated.description, 'Transferência');
    expect(migrated.amountMinor, 500);
    expect(migrated.isEffective, true);
    final accounts = await SqliteAccountsRepository(db).list();
    expect(accounts.map((a) => a.currentBalanceMinor), [500, 500]);
    expect(accounts.last.includeInBalance, false);
    await transfers.update(
        't',
        TransferDraft(
            description: 'Aplicação de janeiro',
            sourceAccountId: 'a',
            destinationAccountId: 'b',
            amountMinor: 500,
            date: migrated.date,
            dueDate: migrated.dueDate,
            effectiveDate: migrated.effectiveDate,
            isEffective: true));
    final bytes = await BackupService.export(db, directory);
    await db.close();
    await BackupService.stageRestore(bytes, directory);
    await BackupService.applyPendingRestore(directory);
    final restored = AppDatabase(NativeDatabase(file));
    addTearDown(restored.close);
    expect(
        (await SqliteTransfersRepository(restored).list()).single.description,
        'Aplicação de janeiro');
    expect(
        (await SqliteAccountsRepository(restored).list())
            .map((a) => a.currentBalanceMinor),
        [500, 500]);
    expect(
        await restored.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  }, timeout: Timeout(Duration(seconds: Platform.isWindows ? 120 : 30)));
}
