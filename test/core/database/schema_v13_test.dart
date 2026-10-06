import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/schema_v12.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'schema_v12_test.dart' show LegacyV11;

class LegacyV12 extends LegacyV11 {
  LegacyV12(super.executor);
  @override
  int get schemaVersion => 12;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in schemaV12) {
          await customStatement(sql);
        }
      });
}

void main() {
  test(
      'v12 migra sem perder saldo, rateio e fila; pacote pendente ganha nova identidade',
      () async {
    final folder =
        await Directory.systemTemp.createTemp('investment-migration-');
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}/db.sqlite');
    final old = LegacyV12(NativeDatabase(file));
    await old.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','CDI','investment','BRL',12345,1,1)");
    final row =
        (await old.customSelect('SELECT * FROM accounts').getSingle()).data;
    const device = 'device-investment-001',
        base = 'base-investment-00001',
        id = 'packet-investment-001';
    await old.customStatement('INSERT INTO sync_uploads VALUES(?,?)', [
      id,
      jsonEncode({
        'protocol': 1,
        'schema': 12,
        'id': id,
        'base': base,
        'device': device,
        'kind': 'changes',
        'entries': [
          {
            'table': 'accounts',
            'id': 'a',
            'clock': 9,
            'device': device,
            'deleted': false,
            'data': row
          }
        ]
      })
    ]);
    await old.close();
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        AppDatabase.currentSchemaVersion);
    expect(await db.customSelect('SELECT * FROM investments').get(), isEmpty);
    expect(
        (await db
                .customSelect('SELECT initial_balance_minor FROM accounts')
                .getSingle())
            .read<int>('initial_balance_minor'),
        12345);
    final queued =
        await db.customSelect('SELECT * FROM sync_uploads').getSingle();
    expect(queued.read<String>('packet_id'), isNot(id));
    final packet = SyncPacket.decode(
        utf8.encode(queued.read<String>('payload')),
        await financialColumns(db));
    expect(packet.sourceSchema, AppDatabase.currentSchemaVersion);
    expect(packet.entries.single.data, row);
    expect(packet.entries.single.clock, 9);
    await db.customStatement(
        "UPDATE sync_state SET capture_enabled=1,device_id='device-investment-001' WHERE id=1");
    await db.customStatement(
        "INSERT INTO investments(id,account_id,name,kind,created_at,updated_at) VALUES('v','a','CDI','cdi',1,1)");
    expect(
        (await db
                .customSelect(
                    "SELECT table_name FROM sync_outbox WHERE row_id='v'")
                .getSingle())
            .read<String>('table_name'),
        'investments');
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
