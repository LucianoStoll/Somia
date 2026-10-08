import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_service.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/database/schema_v15.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'schema_v15_test.dart' show LegacyV14;

class LegacyV15 extends LegacyV14 {
  LegacyV15(super.executor);
  @override
  int get schemaVersion => 15;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in schemaV15) {
          await customStatement(sql);
        }
      });
}

void main() {
  test('v15 preserva cartão e reidentifica upload com cor padrão', () async {
    final dir = await Directory.systemTemp.createTemp('card-color-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final old = LegacyV15(NativeDatabase(file));
    await old.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','Banco','checking','BRL',0,1,1)");
    await old.customStatement(
        "INSERT INTO credit_cards(id,name,payment_account_id,closing_day,due_day,created_at,updated_at) VALUES('c','Cartão','a',25,5,1,1)");
    final data =
        (await old.customSelect('SELECT * FROM credit_cards').getSingle()).data;
    await old.customStatement('INSERT INTO sync_uploads VALUES(?,?)', [
      'old-color-packet-0001',
      jsonEncode({
        'id': 'old-color-packet-0001',
        'schema': 15,
        'entries': [
          {'table': 'credit_cards', 'data': data}
        ],
      })
    ]);
    await old.close();
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final card =
        await db.customSelect('SELECT * FROM credit_cards').getSingle();
    expect(card.read<String>('name'), 'Cartão');
    expect(card.readNullable<int>('color_argb'), isNull);
    final upload =
        await db.customSelect('SELECT * FROM sync_uploads').getSingle();
    expect(upload.read<String>('packet_id'), isNot('old-color-packet-0001'));
    final packet = jsonDecode(upload.read<String>('payload'));
    expect(packet['schema'], 16);
    expect(packet['entries'][0]['data']['color_argb'], isNull);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    await expectLater(
        db.customStatement('UPDATE credit_cards SET color_argb=-1'),
        throwsA(anything));
    await db.customStatement('UPDATE credit_cards SET color_argb=4286421725');
    expect(
        (await db
                .customSelect('SELECT color_argb FROM credit_cards')
                .getSingle())
            .read<int>('color_argb'),
        4286421725);
    final bytes = await BackupService.export(db, dir);
    await db.customStatement('UPDATE credit_cards SET color_argb=NULL');
    await BackupService.restoreOpen(db, LocalBackupStore(dir), bytes);
    expect(
        (await db
                .customSelect('SELECT color_argb FROM credit_cards')
                .getSingle())
            .read<int>('color_argb'),
        4286421725);
    final columns = await financialColumns(db);
    final entry = SyncEntry(
        'credit_cards',
        'c',
        0,
        'device-color-00000001',
        false,
        (await db.customSelect('SELECT * FROM credit_cards').getSingle()).data);
    final current = SyncPacket('packet-color-00000001', 'base-color-00000001',
        'device-color-00000001', 'genesis', [entry]);
    expect(
        SyncPacket.decode(current.encode(), columns)
            .entries
            .single
            .data!['color_argb'],
        4286421725);
    final historic = SyncPacket('packet-color-00000001', 'base-color-00000001',
        'device-color-00000001', 'genesis', [entry],
        sourceSchema: 15);
    final decoded = SyncPacket.decode(historic.encode(), columns);
    expect(decoded.entries.single.data!['color_argb'], isNull);
    expect(decoded.encode(), historic.encode());
  });
}
