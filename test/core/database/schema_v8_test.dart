import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_service.dart';
import 'package:finapp/core/database/schema_v1.dart';
import 'package:finapp/core/database/schema_v2.dart';
import 'package:finapp/core/database/schema_v3.dart';
import 'package:finapp/core/database/schema_v4.dart';
import 'package:finapp/core/database/schema_v5.dart';
import 'package:finapp/core/database/schema_v6.dart';
import 'package:finapp/core/database/schema_v7.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/presentation/accounts_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

class _LegacyV7 extends GeneratedDatabase {
  _LegacyV7(super.executor);
  @override
  int get schemaVersion => 7;
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
          ...schemaV7
        ]) {
          await customStatement(statement);
        }
      });
}

AccountDraft draft(String? bank) => AccountDraft(
    name: 'Minha reserva',
    type: AccountType.savings,
    currencyCode: 'BRL',
    initialBalanceMinor: 12345,
    includeInAnalytics: false,
    institutionId: bank);

void main() {
  test('v7 preserva conta antiga e instituição sobrevive reabertura e backup',
      () async {
    final directory = await Directory.systemTemp.createTemp('somia-v8-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/finapp.sqlite');
    final old = _LegacyV7(NativeDatabase(file));
    await old.customStatement("""INSERT INTO accounts
      (id, name, type, currency_code, initial_balance_minor, created_at, updated_at)
      VALUES ('old', 'Dinheiro', 'cash', 'BRL', 500, 1, 1)""");
    await old.close();
    var db = AppDatabase(NativeDatabase(file));
    var repo = SqliteAccountsRepository(db);
    final legacy = (await repo.list()).single;
    expect(legacy.institutionId, isNull);
    expect(legacy.currentBalanceMinor, 500);
    final created = await repo.create(draft('sicredi'));
    expect(created.name, 'Minha reserva');
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    repo = SqliteAccountsRepository(db);
    var account = (await repo.list()).firstWhere((a) => a.id == created.id);
    expect(account.institutionId, 'sicredi');
    expect(account.currentBalanceMinor, 12345);
    await repo.update(created.id, draft('nubank'));
    final cubit = AccountsCubit(repo);
    await cubit.toggleBalance(
        (await repo.list()).firstWhere((a) => a.id == created.id));
    await cubit.close();
    account = (await repo.list()).firstWhere((a) => a.id == created.id);
    expect(account.institutionId, 'nubank');
    expect(account.includeInBalance, false);
    final bytes = await BackupService.export(db, directory);
    await db.close();
    await BackupService.stageRestore(bytes, directory);
    await BackupService.applyPendingRestore(directory);
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    repo = SqliteAccountsRepository(db);
    account = (await repo.list()).firstWhere((a) => a.id == created.id);
    expect(account.institutionId, 'nubank');
    expect(account.includeInAnalytics, false);
    expect(account.includeInBalance, false);
    expect(account.currentBalanceMinor, 12345);
    await repo.update(created.id, draft(null));
    expect(
        (await repo.list()).firstWhere((a) => a.id == created.id).institutionId,
        isNull);
  });
}
