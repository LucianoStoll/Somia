import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/sync/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/schema_v1.dart';
import 'package:finapp/core/database/schema_v2.dart';
import 'package:finapp/core/database/schema_v3.dart';
import 'package:finapp/core/database/schema_v4.dart';
import 'package:finapp/core/database/schema_v5.dart';
import 'package:finapp/core/database/schema_v6.dart';
import 'package:finapp/core/database/schema_v7.dart';
import 'package:finapp/core/database/schema_v8.dart';
import 'package:finapp/core/database/schema_v9.dart';
import 'package:finapp/core/database/schema_v10.dart';
class LegacyV10 extends GeneratedDatabase {
  LegacyV10(super.executor);
  @override int get schemaVersion=>10;
  @override Iterable<TableInfo<Table,dynamic>> get allTables=>const [];
  @override Iterable<DatabaseSchemaEntity> get allSchemaEntities=>const [];
  @override MigrationStrategy get migration=>MigrationStrategy(onCreate:(_)async{
    for(final statement in [...schemaV1,...schemaV2,...schemaV3,...schemaV4,...schemaV5,...schemaV6,...schemaV7,...schemaV8,...schemaV9,...schemaV10])await customStatement(statement);
  });
}
void main(){
  test('v10 protegida antes de migrar e fila/identidade persistem após reabrir',()async{
    final dir=await Directory.systemTemp.createTemp('somia-v11-');
    addTearDown(()=>dir.delete(recursive:true));
    final file=File('${dir.path}/finapp.sqlite');
    final old=LegacyV10(NativeDatabase(file));
    await old.customStatement("INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','Legado','cash','BRL',123,1,1)");
    await old.close();
    await AppDatabase.protectBeforeMigration(file,dir);
    final copies=await LocalBackupStore(dir).list();
    expect(copies.single.kind,BackupKind.beforeMigration);
    final protected=LegacyV10(NativeDatabase(copies.single.file));
    expect((await protected.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'),10);
    expect((await protected.customSelect('SELECT name FROM accounts').getSingle()).read<String>('name'),'Legado');
    await protected.close();
    var db=AppDatabase(NativeDatabase(file));
    var store=SyncStore(db,LocalBackupStore(dir));
    final rows=await readFinancial(db);
    expect(rows['accounts']!['a']!['initial_balance_minor'],123);
    expect((await store.state()).base,isNull);
    final device=await store.device();
    final base=await store.createBase('same@example.com');await store.ack(base);
    await db.customStatement("UPDATE accounts SET name='Pendente' WHERE id='a'");
    await store.prepareUpload();final packet=(await store.uploads()).single;
    await db.close();
    await AppDatabase.protectBeforeMigration(file,dir);
    expect(await LocalBackupStore(dir).list(),hasLength(1));
    db=AppDatabase(NativeDatabase(file));store=SyncStore(db,LocalBackupStore(dir));
    try{
      expect(await store.device(),device);
      expect((await store.state()).pending,1);
      expect((await store.uploads()).single.digest,packet.digest);
      await store.ack(packet);expect((await store.state()).pending,0);
      await db.customStatement("UPDATE accounts SET name='Nova' WHERE id='a'");
      expect((await store.state()).pending,1);
    }finally{await db.close();}
  });
}
