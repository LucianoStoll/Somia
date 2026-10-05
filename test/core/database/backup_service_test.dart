import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_service.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/database/schema_v1.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _LegacyV1 extends GeneratedDatabase {
  _LegacyV1(super.executor);

  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (_) async {
        for (final statement in schemaV1) {
          await customStatement(statement);
        }
      });
}

void main() {
  test(
      'backup v1 migra, restaura os quatro tipos de registro e preserva a base anterior',
      () async {
    final directory = await Directory.systemTemp.createTemp('somia-backup-');
    addTearDown(() => directory.delete(recursive: true));
    final legacyFile = File(p.join(directory.path, 'legacy.sqlite'));
    final legacy = _LegacyV1(NativeDatabase(legacyFile));
    for (final id in ['a', 'b']) {
      await legacy.customStatement('''INSERT INTO accounts
        (id, name, type, currency_code, initial_balance_minor, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)''', [id, id, 'cash', 'BRL', 10000, 1, 1]);
    }
    await legacy.customStatement('''INSERT INTO categories
      (id, name, type, created_at, updated_at) VALUES (?, ?, ?, ?, ?)''',
        ['c', 'Mercado', 'expense', 1, 1]);
    await legacy.customStatement('''INSERT INTO transactions
      (id, description, type, planned_amount_minor, competence_at,
       effective_at, account_id, category_id, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        ['t', 'Compra', 'expense', 500, 1, 1, 'a', 'c', 1, 1]);
    await legacy.customStatement('''INSERT INTO transfers
      (id, source_account_id, destination_account_id, amount_minor,
       effective_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)''',
        ['x', 'a', 'b', 100, 1, 1, 1]);
    await legacy.close();

    final currentFile = File(p.join(directory.path, 'finapp.sqlite'));
    final current = AppDatabase(NativeDatabase(currentFile));
    await current.customStatement('''INSERT INTO accounts
      (id, name, type, currency_code, initial_balance_minor, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)''',
        ['current', 'Atual', 'cash', 'BRL', 700, 1, 1]);
    final exported = await BackupService.export(current, directory);
    expect(exported.length, greaterThan(100));
    await current.close();

    await BackupService.stageRestore(await legacyFile.readAsBytes(), directory);
    await BackupService.applyPendingRestore(directory);
    final restored = AppDatabase(NativeDatabase(currentFile));
    addTearDown(restored.close);
    expect(
        (await restored.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        AppDatabase.currentSchemaVersion);
    for (final entry in {
      'accounts': 2,
      'categories': 1,
      'transactions': 1,
      'transfers': 1
    }.entries) {
      expect(
          (await restored
                  .customSelect('SELECT COUNT(*) AS n FROM ${entry.key}')
                  .getSingle())
              .read<int>('n'),
          entry.value);
    }
    final row = await restored
        .customSelect('SELECT planned_at FROM transfers')
        .getSingle();
    expect(row.read<int>('planned_at'), 1);

    final previous = AppDatabase(NativeDatabase(
        File(p.join(directory.path, 'finapp.before-restore.sqlite'))));
    expect(
        (await previous.customSelect('SELECT name FROM accounts').getSingle())
            .read<String>('name'),
        'Atual');
    await previous.close();
  });

  test('backup v1 migra e aplica sem reabrir a conexão operacional', () async {
    final directory = await Directory.systemTemp.createTemp('somia-live-v1-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'v1.sqlite'));
    final legacy = _LegacyV1(NativeDatabase(file));
    await legacy.customStatement(
        "INSERT INTO accounts (id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES ('a','Legada','cash','BRL',100,1,1)");
    await legacy.close();
    final current = AppDatabase(NativeDatabase.memory());
    addTearDown(current.close);
    await BackupService.restoreOpen(
        current, LocalBackupStore(directory), await file.readAsBytes());
    expect(
        (await current
                .customSelect('SELECT name, include_in_balance FROM accounts')
                .getSingle())
            .data,
        {'name': 'Legada', 'include_in_balance': 1});
    expect(await current.customSelect('SELECT * FROM credit_cards').get(),
        isEmpty);
  });

  test('arquivo inválido não substitui o banco existente', () async {
    final directory = await Directory.systemTemp.createTemp('somia-invalid-');
    addTearDown(() => directory.delete(recursive: true));
    await expectLater(
        BackupService.stageRestore(Uint8List.fromList([1, 2, 3]), directory),
        throwsFormatException);
    expect(File(p.join(directory.path, 'finapp.restore.pending')).existsSync(),
        isFalse);
  });
}
