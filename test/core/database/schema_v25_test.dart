import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/schema_v24.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'schema_v24_test.dart' show LegacyV23;

class LegacyV24 extends LegacyV23 {
  LegacyV24(super.executor);
  @override
  int get schemaVersion => 24;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in schemaV24) {
          await customStatement(sql);
        }
      });
}

void main() {
  test(
      'v24 upgrade preserves account and pending replacement identity, adds empty rewards tables',
      () async {
    final dir = await Directory.systemTemp.createTemp('rewards-upgrade-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final legacy = LegacyV24(NativeDatabase(file));
    await legacy.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','Conta','cash','BRL',123,1,1)");
    final account =
        (await legacy.customSelect('SELECT * FROM accounts').getSingle()).data;
    final packet = SyncPacket(
        'pending-replacement-0024',
        'new-replacement-base-0024',
        'replacement-device-0024',
        'replacement',
        [
          SyncEntry(
              'accounts', 'a', 0, 'replacement-device-0024', false, account)
        ],
        sourceSchema: 24,
        replaces: ['old-replacement-base-0024'],
        remoteRevision: List.filled(64, 'a').join(),
        publicationEmail: 'test@example.com');
    final payload = utf8.decode(packet.encode());
    await legacy.customStatement(
        'INSERT INTO sync_uploads VALUES(?,?)', [packet.id, payload]);
    await legacy.close();
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final queued =
        await db.customSelect('SELECT * FROM sync_uploads').getSingle();
    expect(queued.read<String>('payload'), payload);
    expect(
        SyncPacket.decode(utf8.encode(payload), await financialColumns(db))
            .digest,
        packet.digest);
    expect(
        (await db
                .customSelect('SELECT initial_balance_minor FROM accounts')
                .getSingle())
            .read<int>('initial_balance_minor'),
        123);
    for (final table in [
      'debit_cards',
      'debit_card_links',
      'card_payment_allocations',
      'cashback_rules',
      'cashback_claims',
      'cashback_receipts'
    ]) {
      expect(
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
          0);
    }
    await validateFinancial(db);
  });
}
