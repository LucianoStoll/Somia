import 'dart:io';
import 'package:drift/native.dart';
import 'package:finapp/core/database/backup_service.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transactions/domain/transaction_tags.dart';
import 'package:finapp/features/transactions/presentation/transaction_tags_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normaliza tags sem duplicar maiúsculas e rejeita limites inválidos',
      () {
    expect(TransactionTags.normalize([' Viagem ', 'viagem', '', 'FÉRIAS']),
        ['Viagem', 'FÉRIAS']);
    expect(() => TransactionTags.encode(List.generate(21, (i) => 'tag$i')),
        throwsFormatException);
    expect(() => TransactionTags.encode(['x' * 41]), throwsFormatException);
    expect(() => TransactionTags.decode('[2]'), throwsFormatException);
  });
  test('tags persistem, filtram sem diferença de caixa e removem ao editar',
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
    TransactionDraft draft(List<String> tags) => TransactionDraft(
        description: 'Teste',
        type: TransactionType.expense,
        amountMinor: 100,
        date: DateTime(2026, 10, 8),
        isEffective: false,
        accountId: account.id,
        tags: tags);
    final item = await repo.create(draft(['FÉRIAS', 'Viagem', 'viagem']));
    expect(item.tags, ['FÉRIAS', 'Viagem']);
    expect(
        (await repo.list(const TransactionFilter(tag: ' férias '))).single.id,
        item.id);
    expect(await repo.list(const TransactionFilter(tag: 'outra')), isEmpty);
    final columns = await financialColumns(db);
    final data =
        (await db.customSelect('SELECT * FROM transactions').getSingle()).data;
    final packet = SyncPacket('packet-tags-000000001', 'base-tags-0000000001',
        'device-tags-00000001', 'genesis', [
      SyncEntry('transactions', item.id, 0, 'device-tags-00000001', false, data)
    ]);
    expect(
        SyncPacket.decode(packet.encode(), columns)
            .entries
            .single
            .data!['tags_json'],
        '["FÉRIAS","Viagem"]');
    final old = SyncPacket(
        packet.id, packet.base, packet.device, packet.kind, packet.entries,
        sourceSchema: 19);
    expect(
        SyncPacket.decode(old.encode(), columns)
            .entries
            .single
            .data!['tags_json'],
        '[]');
    final dir = await Directory.systemTemp.createTemp('tags-backup-');
    addTearDown(() => dir.delete(recursive: true));
    final bytes = await BackupService.export(db, dir);
    expect((await repo.update(item.id, draft([]))).tags, isEmpty);
    await BackupService.restoreOpen(db, LocalBackupStore(dir), bytes);
    expect(
        (await repo.list(const TransactionFilter(tag: 'Viagem'))).single.tags,
        ['FÉRIAS', 'Viagem']);
    await repo.update(item.id, draft([]));
    expect(await repo.list(const TransactionFilter(tag: 'Viagem')), isEmpty);
  });
  testWidgets('adiciona e remove etiquetas no editor', (tester) async {
    var tags = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, refresh) => TransactionTagsEditor(
                    tags: tags,
                    onChanged: (value) => refresh(() => tags = value))))));
    await tester.enterText(find.byType(TextField), 'Viagem');
    await tester.tap(find.byTooltip('Adicionar tag'));
    await tester.pump();
    expect(tags, ['Viagem']);
    await tester.tap(find.byType(InputChip).first);
    final chip = tester.widget<InputChip>(find.byType(InputChip).first);
    chip.onDeleted!();
    await tester.pump();
    expect(tags, isEmpty);
  });
}
