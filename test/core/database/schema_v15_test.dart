import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/schema_v14.dart';
import 'schema_v14_test.dart' show LegacyV13;

class LegacyV14 extends LegacyV13 {
  LegacyV14(super.executor);
  @override
  int get schemaVersion => 14;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in schemaV14) {
          await customStatement(sql);
        }
      });
}

void main() {
  test('v14 preserva bens, avaliações e uploads migrando dívidas para v15',
      () async {
    final dir = await Directory.systemTemp.createTemp('debt-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final old = LegacyV14(NativeDatabase(file));
    await old.customStatement(
        "INSERT INTO assets(id,name,kind,acquired_at,acquisition_minor,created_at,updated_at) VALUES('a','Carro','vehicle',1735689600000,2000000,1,1)");
    await old.customStatement(
        "INSERT INTO asset_valuations(id,asset_id,assessed_at,value_minor,debt_minor,creditor,created_at,updated_at) VALUES('v','a',1735689600000,1800000,800000,'Banco',1,1)");
    await old.customStatement('INSERT INTO sync_uploads VALUES(?,?)', [
      'old-packet-id-0001',
      jsonEncode({'id': 'old-packet-id-0001', 'schema': 14, 'entries': []})
    ]);
    await old.close();
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        15);
    expect(
        (await db
                .customSelect('SELECT debt_minor FROM asset_valuations')
                .getSingle())
            .read<int>('debt_minor'),
        800000);
    expect(await db.customSelect('SELECT * FROM debts').get(), isEmpty);
    final upload =
        await db.customSelect('SELECT * FROM sync_uploads').getSingle();
    expect(upload.read<String>('packet_id'), isNot('old-packet-id-0001'));
    expect(jsonDecode(upload.read<String>('payload'))['schema'], 15);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
