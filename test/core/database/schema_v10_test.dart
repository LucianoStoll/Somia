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
import 'package:finapp/core/database/schema_v7.dart';
import 'package:finapp/core/database/schema_v8.dart';
import 'package:finapp/core/database/schema_v9.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

class _LegacyV9 extends GeneratedDatabase {
  _LegacyV9(super.executor);
  @override
  int get schemaVersion => 9;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (_) async {
        for (final s in [
          ...schemaV1,
          ...schemaV2,
          ...schemaV3,
          ...schemaV4,
          ...schemaV5,
          ...schemaV6,
          ...schemaV7,
          ...schemaV8,
          ...schemaV9
        ]) {
          await customStatement(s);
        }
      });
}

void main() {
  test(
      'v9 histórico intacto; backup v10 guarda cartões, faturas, liquidações, limites e mudanças',
      () async {
    final dir = await Directory.systemTemp.createTemp('somia-v10-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/finapp.sqlite');
    final old = _LegacyV9(NativeDatabase(file));
    await old.customStatement(
        """INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,institution_id,created_at,updated_at)
      VALUES('a','Banco','checking','BRL',100000,'sicredi',1,1)""");
    await old.customStatement(
        """INSERT INTO transactions(id,description,type,planned_amount_minor,actual_amount_minor,competence_at,posted_at,due_at,effective_at,account_id,created_at,updated_at,series_id,series_index,series_kind,series_count,series_unit,series_interval)
      VALUES('old','Histórico','expense',100,100,1,1,1,1,'a',1,1,'series-old',0,'recurring',2,'month',1)""");
    await old.close();
    var db = AppDatabase(NativeDatabase(file));
    final cards = CardsRepository(db);
    final id = await cards.save(const CardDraft(
        name: 'Nu',
        paymentAccountId: 'a',
        closingDay: 25,
        dueDay: 5,
        limitMinor: 50000,
        institutionId: 'nubank'));
    final entryId = await cards.createPurchase(TransactionDraft(
        description: 'Compra',
        type: TransactionType.expense,
        amountMinor: 10000,
        date: DateTime(2026, 1, 1),
        isEffective: false,
        accountId: 'a',
        cardId: id));
    final entry = await cards.entry(entryId);
    await cards.pay(entry.invoiceId, 'a', 4000, DateTime(2026, 2, 5), fee: 500);
    await cards.opening(id, DateTime(2026, 3), 2000);
    final bytes = await BackupService.export(db, dir);
    await db.close();
    await BackupService.stageRestore(bytes, dir);
    await BackupService.applyPendingRestore(dir);
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final restored = CardsRepository(db);
    expect((await restored.find(id)).institutionId, 'nubank');
    expect(await restored.limitHistory(id), hasLength(1));
    expect((await restored.invoice(entry.invoiceId)).balanceMinor, 6500);
    expect(
        (await restored.invoices(id, selected: DateTime(2026, 3)))
            .firstWhere((i) => i.month == DateTime.utc(2026, 3))
            .balanceMinor,
        8500);
    final tx = await SqliteTransactionsRepository(db).list();
    expect(tx.firstWhere((t) => t.id == 'old').series!.id, 'series-old');
    final account = (await SqliteAccountsRepository(db).list()).single;
    expect(account.institutionId, 'sicredi');
    expect(account.currentBalanceMinor, 95900);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        AppDatabase.currentSchemaVersion);
  });
}
