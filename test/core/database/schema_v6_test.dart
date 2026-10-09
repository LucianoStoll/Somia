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
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:flutter_test/flutter_test.dart';

class _LegacyV5 extends GeneratedDatabase {
  _LegacyV5(super.executor);
  @override
  int get schemaVersion => 5;
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
          ...schemaV5
        ]) {
          await customStatement(statement);
        }
      });
}

void main() {
  test('v5 migra sem perder dados e backup v6 preserva preferência de saldo',
      () async {
    final directory = await Directory.systemTemp.createTemp('somia-v6-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/finapp.sqlite');
    final old = _LegacyV5(NativeDatabase(file));
    await old.customStatement('''INSERT INTO accounts
      (id, name, type, currency_code, initial_balance_minor, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)''',
        ['a', 'Aplicação', 'investment', 'BRL', 12345, 1, 1]);
    await old.customStatement('''INSERT INTO transactions
      (id, description, type, planned_amount_minor, actual_amount_minor,
       competence_at, posted_at, due_at, effective_at, account_id, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        ['t', 'Rendimento', 'income', 500, 500, 1, 1, 1, 1, 'a', 1, 1]);
    await old.close();
    final db = AppDatabase(NativeDatabase(file));
    final repo = SqliteAccountsRepository(db);
    final migrated = (await repo.list()).single;
    expect(migrated.includeInBalance, true);
    expect(migrated.currentBalanceMinor, 12845);
    expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        AppDatabase.currentSchemaVersion);
    await repo.update(
        'a',
        const AccountDraft(
            name: 'Aplicação',
            type: AccountType.investment,
            currencyCode: 'BRL',
            initialBalanceMinor: 12345,
            includeInAnalytics: true,
            includeInBalance: false));
    final bytes = await BackupService.export(db, directory);
    await db.close();
    await BackupService.stageRestore(bytes, directory);
    await BackupService.applyPendingRestore(directory);
    final restored = AppDatabase(NativeDatabase(file));
    addTearDown(restored.close);
    final account = (await SqliteAccountsRepository(restored).list()).single;
    expect(account.includeInBalance, false);
    expect(account.includeInAnalytics, true);
    expect(account.currentBalanceMinor, 12845);
    expect(
        (await restored
                .customSelect('SELECT description FROM transactions')
                .getSingle())
            .read<String>('description'),
        'Rendimento');
    expect(
        await restored.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  }, timeout: Timeout(Duration(seconds: Platform.isWindows ? 120 : 30)));
}
