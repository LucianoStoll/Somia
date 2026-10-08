import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/schema_v16.dart';
import 'package:finapp/core/database/schema_v17.dart';
import 'package:finapp/core/database/schema_v18.dart';
import 'package:finapp/core/database/schema_v19.dart';
import 'package:flutter_test/flutter_test.dart';
import 'schema_v16_test.dart' show LegacyV15;

class LegacyV19 extends LegacyV15 {
  LegacyV19(super.executor);
  @override
  int get schemaVersion => 19;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in [
          ...schemaV16,
          ...schemaV17,
          ...schemaV18,
          ...schemaV19
        ]) {
          await customStatement(sql);
        }
      });
}

void main() {
  test('v19 migra sem alterar valores e renova uploads antigos com tags vazias',
      () async {
    final dir = await Directory.systemTemp.createTemp('tags-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final old = LegacyV19(NativeDatabase(file));
    await old.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','Banco','checking','BRL',0,1,1)");
    await old.customStatement(
        "INSERT INTO transactions(id,description,type,planned_amount_minor,competence_at,posted_at,due_at,account_id,created_at,updated_at) VALUES('t','Compra','expense',1234,1,1,1,'a',1,1)");
    final data =
        (await old.customSelect('SELECT * FROM transactions').getSingle()).data;
    await old.customStatement('INSERT INTO sync_uploads VALUES(?,?)', [
      'old-tags-packet-0001',
      jsonEncode({
        'id': 'old-tags-packet-0001',
        'schema': 19,
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
            'device-tags-00000001',
            0,
            jsonEncode(data)
          ]);
    }
    await old.close();
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final row = await db.customSelect('SELECT * FROM transactions').getSingle();
    expect(row.read<int>('planned_amount_minor'), 1234);
    expect(row.read<String>('tags_json'), '[]');
    final upload =
        await db.customSelect('SELECT * FROM sync_uploads').getSingle();
    expect(upload.read<String>('packet_id'), isNot('old-tags-packet-0001'));
    final payload = jsonDecode(upload.read<String>('payload'));
    expect(payload['schema'], AppDatabase.currentSchemaVersion);
    expect(payload['entries'][0]['data']['tags_json'], '[]');
    for (final table in ['sync_versions', 'sync_outbox']) {
      final synced = jsonDecode(
          (await db.customSelect('SELECT data FROM $table').getSingle())
              .read<String>('data'));
      expect(synced['tags_json'], '[]');
    }
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
