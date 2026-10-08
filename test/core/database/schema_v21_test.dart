import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/schema_v20.dart';
import 'package:flutter_test/flutter_test.dart';
import 'schema_v20_test.dart' show LegacyV19;

class LegacyV20 extends LegacyV19 {
  LegacyV20(super.executor);
  @override
  int get schemaVersion => 20;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in schemaV20) {
          await customStatement(sql);
        }
      });
}

void main() {
  test(
      'migração v20 preserva tags e valores nos dados e na sincronização pendente',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('establishment-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final old = LegacyV20(NativeDatabase(file));
    await old.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','Conta','cash','BRL',0,1,1)");
    await old.customStatement(
        "INSERT INTO transactions(id,description,type,planned_amount_minor,competence_at,posted_at,due_at,account_id,created_at,updated_at,tags_json) VALUES('t','Compra','expense',1234,1,1,1,'a',1,1,'[\"Viagem\"]')");
    final data =
        (await old.customSelect('SELECT * FROM transactions').getSingle()).data;
    await old.customStatement('INSERT INTO sync_uploads VALUES(?,?)', [
      'old-establishment-0001',
      jsonEncode({
        'id': 'old-establishment-0001',
        'schema': 20,
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
            't',
            1,
            'device-est-000000001',
            0,
            jsonEncode(data)
          ]);
    }
    await old.close();
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final row = await db.customSelect('SELECT * FROM transactions').getSingle();
    expect(row.read<String>('establishment'), '');
    expect(row.read<String>('tags_json'), '["Viagem"]');
    expect(row.read<int>('planned_amount_minor'), 1234);
    final upload =
        await db.customSelect('SELECT * FROM sync_uploads').getSingle();
    final payload = jsonDecode(upload.read<String>('payload'));
    expect(payload['schema'], AppDatabase.currentSchemaVersion);
    expect(upload.read<String>('packet_id'), isNot('old-establishment-0001'));
    expect(payload['entries'][0]['data']['tags_json'], '["Viagem"]');
    expect(payload['entries'][0]['data']['establishment'], '');
    for (final table in ['sync_versions', 'sync_outbox']) {
      final local = jsonDecode(
          (await db.customSelect('SELECT data FROM $table').getSingle())
              .read<String>('data'));
      expect(local['establishment'], '');
      expect(local['tags_json'], '["Viagem"]');
    }
  });
}
