import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/schema_v21.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'schema_v21_test.dart' show LegacyV20;

class LegacyV21 extends LegacyV20 {
  LegacyV21(super.executor);
  @override
  int get schemaVersion => 21;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in schemaV21) {
          await customStatement(sql);
        }
      });
}

void main() {
  test(
      'migração v21 preserva tags, estabelecimento e exclusões internas sem colocá-las na lixeira',
      () async {
    final dir = await Directory.systemTemp.createTemp('trash-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final old = LegacyV21(NativeDatabase(file));
    await old.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','Conta','cash','BRL',0,1,1)");
    await old.customStatement(
        '''INSERT INTO transactions(id,description,type,planned_amount_minor,competence_at,posted_at,due_at,account_id,created_at,updated_at,tags_json,establishment,deleted_at)
      VALUES('transaction-trash-0001','Compra','expense',1234,1,1,1,'a',1,1,'["Viagem"]','Loja',2)''');
    final data =
        (await old.customSelect('SELECT * FROM transactions').getSingle()).data;
    await old.customStatement('INSERT INTO sync_uploads VALUES(?,?)', [
      'old-trash-packet-0001',
      jsonEncode({
        'id': 'old-trash-packet-0001',
        'schema': 21,
        'entries': [
          {'table': 'transactions', 'data': data}
        ]
      })
    ]);
    for (final table in ['sync_versions', 'sync_outbox']) {
      await old.customStatement(
          'INSERT INTO $table(table_name,row_id,clock,device_id,is_deleted,data) VALUES(?,?,?,?,?,?)',
          [
            'transactions',
            'transaction-trash-0001',
            1,
            'device-trash-00000001',
            0,
            jsonEncode(data)
          ]);
    }
    await old.close();
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final row = await db.customSelect('SELECT * FROM transactions').getSingle();
    expect(row.read<String>('trash_state'), 'active');
    expect(row.read<int>('deleted_at'), 2);
    expect(row.read<String>('tags_json'), '["Viagem"]');
    expect(row.read<String>('establishment'), 'Loja');
    final upload =
        await db.customSelect('SELECT * FROM sync_uploads').getSingle();
    final payload = jsonDecode(upload.read<String>('payload'));
    expect(payload['schema'], AppDatabase.currentSchemaVersion);
    expect(upload.read<String>('packet_id'), isNot('old-trash-packet-0001'));
    final queued = payload['entries'][0]['data'];
    expect(queued['tags_json'], '["Viagem"]');
    expect(queued['establishment'], 'Loja');
    expect(queued['trash_state'], 'active');
    for (final table in ['sync_versions', 'sync_outbox']) {
      final local = jsonDecode(
          (await db.customSelect('SELECT data FROM $table').getSingle())
              .read<String>('data'));
      expect(local['trash_state'], 'active');
      expect(local['establishment'], 'Loja');
      expect(local['tags_json'], '["Viagem"]');
    }
    final packet = SyncPacket(
        'packet-trash-00000001',
        'base-trash-000000001',
        'device-trash-00000001',
        'genesis',
        [
          SyncEntry('transactions', 'transaction-trash-0001', 0,
              'device-trash-00000001', false, row.data)
        ],
        sourceSchema: 21);
    final decoded =
        SyncPacket.decode(packet.encode(), await financialColumns(db))
            .entries
            .single
            .data!;
    expect(decoded['trash_state'], 'active');
    expect(decoded['tags_json'], '["Viagem"]');
    expect(decoded['establishment'], 'Loja');
  });
}
