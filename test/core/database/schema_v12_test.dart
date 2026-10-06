import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/schema_v11.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'schema_v11_test.dart' show LegacyV10;

class LegacyV11 extends LegacyV10 {
  LegacyV11(super.executor);
  @override
  int get schemaVersion => 11;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in schemaV11) {
          await customStatement(sql);
        }
      });
}

void main() {
  test(
      'v11 preserva dados, versão da fila, histórico e regenera captura de rateio',
      () async {
    final dir = await Directory.systemTemp.createTemp('allocation-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/data.sqlite');
    final old = LegacyV11(NativeDatabase(file));
    await old.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','Conta','checking','BRL',0,1,1)");
    await old.customStatement(
        "INSERT INTO transactions(id,description,type,planned_amount_minor,competence_at,posted_at,due_at,account_id,created_at,updated_at) VALUES('t','Antigo','expense',100,1,1,1,'a',1,1)");
    final row = (await old
            .customSelect("SELECT * FROM transactions WHERE id='t'")
            .getSingle())
        .data;
    const device = 'device-allocation-0001',
        base = 'base-allocation-000001',
        packetId = 'packet-allocation-0001';
    final data = jsonEncode(row);
    for (final t in ['sync_versions', 'sync_outbox']) {
      await old.customStatement('INSERT INTO $t VALUES(?,?,?,?,?,?)',
          ['transactions', 't', 9, device, 0, data]);
    }
    await old.customStatement(
        'INSERT INTO sync_history VALUES(?,?,?,?,?,?,?,?)',
        ['transactions', 't', 8, device, 0, data, 'local', 9]);
    await old.customStatement(
        'UPDATE sync_state SET base_id=?,device_id=?,email=?,clock=9,capture_enabled=1 WHERE id=1',
        [base, device, 'a@example.com']);
    await old.customStatement('INSERT INTO sync_uploads VALUES(?,?)', [
      packetId,
      jsonEncode({
        'protocol': 1,
        'schema': 11,
        'id': packetId,
        'base': base,
        'device': device,
        'kind': 'changes',
        'entries': [
          {
            'table': 'transactions',
            'id': 't',
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
        (await db
                .customSelect(
                    "SELECT allocations_json FROM transactions WHERE id='t'")
                .getSingle())
            .read<String>('allocations_json'),
        '[]');
    final queued =
        await db.customSelect('SELECT * FROM sync_uploads').getSingle();
    expect(queued.read<String>('packet_id'), isNot(packetId));
    final packet = SyncPacket.decode(
        utf8.encode(queued.read<String>('payload')),
        await financialColumns(db));
    expect(packet.sourceSchema, AppDatabase.currentSchemaVersion);
    expect(packet.entries.single.clock, 9);
    expect(
        (await db.customSelect('SELECT clock FROM sync_state').getSingle())
            .read<int>('clock'),
        9);
    await db.customStatement(
        "UPDATE transactions SET description='Novo' WHERE id='t'");
    final captured = jsonDecode((await db
            .customSelect("SELECT data FROM sync_outbox WHERE row_id='t'")
            .getSingle())
        .read<String>('data'));
    expect(captured['allocations_json'], '[]');
    expect(captured['description'], 'Novo');
  });
}
