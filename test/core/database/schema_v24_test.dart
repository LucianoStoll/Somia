import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/schema_v22.dart';
import 'package:finapp/core/database/schema_v23.dart';
import 'package:flutter_test/flutter_test.dart';
import 'schema_v22_test.dart' show LegacyV21;

class LegacyV23 extends LegacyV21 {
  LegacyV23(super.executor);
  @override
  int get schemaVersion => 23;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in [...schemaV22, ...schemaV23]) {
          await customStatement(sql);
        }
      });
}

void main() {
  test(
      'v23 preserva vínculos e fila, libera somente contas de aplicações excluídas',
      () async {
    final dir = await Directory.systemTemp.createTemp('investment-v24-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final old = LegacyV23(NativeDatabase(file));
    await old.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','Conta','cash','BRL',123,1,1)");
    await old.customStatement(
        "INSERT INTO investments(id,account_id,name,kind,created_at,updated_at) VALUES('i','a','Aplicação','cdb',1,1)");
    final data =
        (await old.customSelect('SELECT * FROM investments').getSingle()).data;
    await old.customStatement('INSERT INTO sync_uploads VALUES(?,?)', [
      'old-v23-packet-0001',
      jsonEncode({
        'id': 'old-v23-packet-0001',
        'schema': 23,
        'entries': [
          {'table': 'investments', 'data': data}
        ]
      })
    ]);
    await old.close();
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect(
        (await db.customSelect('SELECT * FROM investments').getSingle()).data,
        data);
    await expectLater(
        db.customStatement(
            "INSERT INTO investments(id,account_id,name,kind,created_at,updated_at) VALUES('j','a','Nova','cdb',1,1)"),
        throwsA(isA<Exception>()));
    await db
        .customStatement("UPDATE investments SET deleted_at=2 WHERE id='i'");
    await db.customStatement(
        "INSERT INTO investments(id,account_id,name,kind,created_at,updated_at) VALUES('j','a','Nova','cdb',1,1)");
    expect(
        await db.customSelect('SELECT * FROM investments').get(), hasLength(2));
    expect(
        (await db
                .customSelect('SELECT initial_balance_minor FROM accounts')
                .getSingle())
            .read<int>('initial_balance_minor'),
        123);
    final upload =
        await db.customSelect('SELECT * FROM sync_uploads').getSingle();
    expect(jsonDecode(upload.read<String>('payload'))['schema'], 24);
    expect(upload.read<String>('packet_id'), isNot('old-v23-packet-0001'));
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    expect(
        await db
            .customSelect(
                "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'sync_investments_%'")
            .get(),
        hasLength(3));
  });
}
