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
import 'package:finapp/core/database/schema_v8.dart';
import 'package:finapp/core/series/movement_series.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

class _LegacyV8 extends GeneratedDatabase {
  _LegacyV8(super.executor);
  @override
  int get schemaVersion => 8;
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
          ...schemaV7,
          ...schemaV8
        ]) {
          await customStatement(statement);
        }
      });
}

void main() {
  test(
      'migration v8 preserva histórico/logos; backup v9 restaura os dois tipos de série',
      () async {
    final dir = await Directory.systemTemp.createTemp('somia-v9-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/finapp.sqlite');
    final old = _LegacyV8(NativeDatabase(file));
    await old.customStatement("""INSERT INTO accounts
      (id, name, type, currency_code, initial_balance_minor, institution_id, created_at, updated_at)
      VALUES ('a', 'Banco', 'checking', 'BRL', 10000, 'sicredi', 1, 1),
        ('b', 'Reserva', 'savings', 'BRL', 10000, NULL, 1, 1)""");
    await old.customStatement("""INSERT INTO transactions
      (id, description, type, planned_amount_minor, actual_amount_minor, competence_at,
      posted_at, due_at, effective_at, account_id, created_at, updated_at)
      VALUES ('old', 'Histórico', 'expense', 100, 100, 1, 1, 1, 1, 'a', 1, 1)""");
    await old.close();
    var db = AppDatabase(NativeDatabase(file));
    final repo = SqliteTransactionsRepository(db);
    expect((await repo.list()).single.series, isNull);
    expect((await repo.list()).single.amountMinor, 100);
    const plan = SeriesPlan(
        kind: SeriesKind.recurring,
        count: 3,
        interval: 2,
        unit: SeriesUnit.week);
    final first = await repo.create(TransactionDraft(
        description: 'Salário',
        type: TransactionType.income,
        amountMinor: 500,
        date: DateTime(2026, 1, 1),
        isEffective: false,
        accountId: 'a',
        seriesPlan: plan));
    final transfer = await SqliteTransfersRepository(db).create(TransferDraft(
        sourceAccountId: 'a',
        destinationAccountId: 'b',
        amountMinor: 501,
        date: DateTime(2026, 1, 1),
        isEffective: false,
        seriesPlan: const SeriesPlan(kind: SeriesKind.installments, count: 2)));
    final bytes = await BackupService.export(db, dir);
    await db.close();
    await BackupService.stageRestore(bytes, dir);
    await BackupService.applyPendingRestore(dir);
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final items = await SqliteTransactionsRepository(db).list();
    expect(items.where((a) => a.series?.id == first.series!.id).length, 3);
    expect(items.firstWhere((a) => a.id == first.id).series!.plan.interval, 2);
    expect(items.firstWhere((a) => a.id == first.id).series!.plan.unit,
        SeriesUnit.week);
    expect(
        (await SqliteTransfersRepository(db).list())
            .firstWhere((a) => a.id == transfer.id)
            .series!
            .plan
            .kind,
        SeriesKind.installments);
    final account = (await SqliteAccountsRepository(db).list())
        .firstWhere((a) => a.id == 'a');
    expect(account.institutionId, 'sicredi');
    expect(account.currentBalanceMinor, 9900);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
