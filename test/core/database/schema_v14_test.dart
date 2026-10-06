import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/schema_v13.dart';
import 'schema_v13_test.dart' show LegacyV12;

class LegacyV13 extends LegacyV12 {
  LegacyV13(super.executor);
  @override
  int get schemaVersion => 13;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in schemaV13) {
          await customStatement(sql);
        }
      });
}

void main() {
  test(
      'v13 migra bens sem perder contas/aplicações e reidentifica uploads pendentes',
      () async {
    final dir = await Directory.systemTemp.createTemp('asset-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final old = LegacyV13(NativeDatabase(file));
    await old.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','CDB','investment','BRL',12345,1,1)");
    await old.customStatement(
        "INSERT INTO investments(id,account_id,name,kind,created_at,updated_at) VALUES('v','a','CDB','cdb',1,1)");
    final payload = {'schema': 13, 'id': 'old-packet-id-0001', 'entries': []};
    await old.customStatement('INSERT INTO sync_uploads VALUES(?,?)',
        ['old-packet-id-0001', jsonEncode(payload)]);
    await old.close();
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        14);
    expect(
        (await db
                .customSelect('SELECT initial_balance_minor FROM accounts')
                .getSingle())
            .read<int>('initial_balance_minor'),
        12345);
    expect(
        await db.customSelect('SELECT * FROM investments').get(), hasLength(1));
    expect(await db.customSelect('SELECT * FROM assets').get(), isEmpty);
    final queued =
        await db.customSelect('SELECT * FROM sync_uploads').getSingle();
    expect(queued.read<String>('packet_id'), isNot(payload['id']));
    expect(jsonDecode(queued.read<String>('payload'))['schema'], 14);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
