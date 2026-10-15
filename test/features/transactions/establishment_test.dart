import 'dart:io';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_service.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transactions/domain/establishment.dart';
import 'package:finapp/features/transactions/presentation/establishment_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normaliza nomes e valida limites', () {
    expect(Establishment.normalize(' Mercado   Central '), 'Mercado Central');
    expect(Establishment.key(' FARMÁCIA '), 'farmácia');
    expect(Establishment.normalize(' '), '');
    expect(() => Establishment.normalize('x' * 101), throwsFormatException);
    expect(() => Establishment.normalize('Mercado\nCentral'),
        throwsFormatException);
  });
  test(
      'cadastro, filtro combinado, edição, backup e sync preservam estabelecimento e tags',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final account = await SqliteAccountsRepository(db).create(
        const AccountDraft(
            name: 'Conta',
            type: AccountType.cash,
            currencyCode: 'BRL',
            initialBalanceMinor: 0,
            includeInAnalytics: true));
    final repo = SqliteTransactionsRepository(db);
    TransactionDraft draft(String establishment) => TransactionDraft(
        description: 'Compra',
        type: TransactionType.expense,
        amountMinor: 100,
        date: DateTime(2026, 10, 8),
        isEffective: false,
        accountId: account.id,
        tags: ['Saúde'],
        establishment: establishment);
    final item = await repo.create(draft(' FARMÁCIA '));
    expect(item.establishment, 'FARMÁCIA');
    expect(
        (await repo.list(const TransactionFilter(
                establishment: ' farmácia ', tag: 'saúde')))
            .single
            .id,
        item.id);
    expect(
        await repo.list(
            const TransactionFilter(establishment: 'Farmácia', tag: 'Outra')),
        isEmpty);
    final columns = await financialColumns(db);
    final data =
        (await db.customSelect('SELECT * FROM transactions').getSingle()).data;
    final packet = SyncPacket('packet-est-0000000001', 'base-est-000000000001',
        'device-est-000000001', 'genesis', [
      SyncEntry('transactions', item.id, 0, 'device-est-000000001', false, data)
    ]);
    expect(
        SyncPacket.decode(packet.encode(), columns)
            .entries
            .single
            .data!['establishment'],
        'FARMÁCIA');
    final legacy = SyncPacket(
        packet.id, packet.base, packet.device, packet.kind, packet.entries,
        sourceSchema: 20);
    final restored =
        SyncPacket.decode(legacy.encode(), columns).entries.single.data!;
    expect(restored['establishment'], '');
    expect(restored['tags_json'], '["Saúde"]');
    final dir = await Directory.systemTemp.createTemp('establishment-backup-');
    addTearDown(() => dir.delete(recursive: true));
    final backup = await BackupService.export(db, dir);
    await repo.update(item.id, draft(''));
    expect((await repo.list()).single.establishment, '');
    await BackupService.restoreOpen(db, LocalBackupStore(dir), backup);
    expect((await repo.list()).single.establishment, 'FARMÁCIA');
    expect((await repo.list()).single.tags, ['Saúde']);
  });
  testWidgets('seleciona nome do histórico e limpa o campo', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    getIt.registerSingleton<AppDatabase>(db);
    addTearDown(() => getIt.unregister<AppDatabase>());
    await db.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','Conta','cash','BRL',0,1,1)");
    await db.customStatement(
        "INSERT INTO transactions(id,description,type,planned_amount_minor,competence_at,posted_at,due_at,account_id,created_at,updated_at,establishment) VALUES('t','Compra','expense',100,1,1,1,'a',1,1,'Mercado Central')");
    var value = '';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body:
                EstablishmentEditor(value: '', onChanged: (v) => value = v))));
    await tester.runAsync(() async {
      await db.customSelect('SELECT 1').get();
    });
    await tester.enterText(find.byType(TextField), 'merc');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Mercado Central'));
    await tester.pump();
    expect(value, 'Mercado Central');
    await tester.tap(find.byTooltip('Limpar estabelecimento'));
    await tester.pump();
    expect(value, '');
  });
}
