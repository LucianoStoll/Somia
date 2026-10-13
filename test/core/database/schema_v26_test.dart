import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/schema_v25.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:finapp/features/attachments/data/attachments_repository.dart';
import 'package:finapp/features/transactions/domain/movement_management.dart';
import 'schema_v25_test.dart' show LegacyV24;

class LegacyV25 extends LegacyV24 {
  LegacyV25(super.executor);
  @override
  int get schemaVersion => 25;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in schemaV25) {
          await customStatement(sql);
        }
      });
}

void main() {
  test(
      'migra arquivos locais, captura metadados e preserva upload financeiro v25',
      () async {
    final dir = await Directory.systemTemp.createTemp('attachment-v26-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final old = LegacyV25(NativeDatabase(file));
    await old.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','Conta','cash','BRL',123,1,1)");
    await old.customStatement(
        "INSERT INTO transactions(id,description,type,planned_amount_minor,competence_at,posted_at,due_at,account_id,created_at,updated_at) VALUES('t','Compra','expense',123,1,1,1,'a',1,1)");
    final bytes = Uint8List.fromList([7, 8, 9]),
        hash = sha256.convert([7, 8, 9]).toString();
    await old.customStatement(
        'INSERT INTO local_attachments VALUES(?,?,?,?,?,?,?,?)',
        ['old-file', 'transactions', 't', 'recibo.pdf', 3, hash, bytes, 1]);
    await old.customStatement(
        'INSERT INTO local_attachments VALUES(?,?,?,?,?,?,?,?)', [
      'old-orphan',
      'transactions',
      'missing',
      'arquivo-antigo.pdf',
      3,
      hash,
      bytes,
      1
    ]);
    await old.customStatement(
        "UPDATE sync_state SET base_id='base-legacy-attachments',device_id='android-device-old1',email='same@example.com',capture_enabled=1 WHERE id=1");
    final row =
        (await old.customSelect('SELECT * FROM accounts').getSingle()).data;
    final packet = SyncPacket(
        'pending-financial-old1',
        'base-legacy-attachments',
        'android-device-old1',
        'changes',
        [
          SyncEntry('accounts', 'a', 1, 'android-device-old1', false,
              Map<String, Object?>.from(row))
        ],
        sourceSchema: 25);
    await old.customStatement('INSERT INTO sync_uploads VALUES(?,?)',
        [packet.id, utf8.decode(packet.encode())]);
    await old.close();
    final db = AppDatabase(NativeDatabase(file));
    try {
      final repo = AttachmentsRepository(db);
      const owner = MovementReference(MovementKind.transaction, 't', '');
      expect((await repo.list(owner)).single.id, 'old-file');
      expect(await repo.read(owner, 'old-file'), bytes);
      expect(
          (await db.customSelect('SELECT id FROM local_attachments').get())
              .single
              .read<String>('id'),
          'old-orphan');
      await validateFinancial(db);
      await AttachmentsRepository.validate(db);
      expect(
          (await db
                  .customSelect(
                      "SELECT * FROM sync_outbox WHERE table_name='attachment_manifest'")
                  .get())
              .length,
          1);
      final payload = (await db
              .customSelect('SELECT payload FROM sync_uploads')
              .getSingle())
          .read<String>('payload');
      expect(payload, utf8.decode(packet.encode()));
      expect(
          SyncPacket.decode(Uint8List.fromList(utf8.encode(payload)),
                  await financialColumns(db))
              .sourceSchema,
          25);
    } finally {
      await db.close();
    }
  });
}
