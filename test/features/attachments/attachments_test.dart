import 'dart:io';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_service.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/database/financial_data.dart';
import 'package:finapp/core/database/schema_v22.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:finapp/features/attachments/data/attachments_repository.dart';
import 'package:finapp/features/attachments/presentation/attachments_page.dart';
import 'package:finapp/features/transactions/domain/movement_management.dart';
import '../../core/database/schema_v22_test.dart' show LegacyV21;

class LegacyV22 extends LegacyV21 {
  LegacyV22(super.executor);
  @override
  int get schemaVersion => 22;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await super.migration.onCreate(m);
        for (final sql in schemaV22) {
          await customStatement(sql);
        }
      });
}

Future<void> seed(GeneratedDatabase db) async {
  await db.customStatement(
      "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','Conta','cash','BRL',0,1,1)");
  await db.customStatement(
      "INSERT INTO transactions(id,description,type,planned_amount_minor,competence_at,posted_at,due_at,account_id,created_at,updated_at) VALUES('t','Compra','expense',1234,1,1,1,'a',1,1)");
}

void main() {
  late AppDatabase db;
  late AttachmentsRepository repo;
  const owner = MovementReference(MovementKind.transaction, 't', '');
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seed(db);
    repo = AttachmentsRepository(db);
  });
  tearDown(() => db.close());
  test('bytes, nome seguro, hash, isolamento do vínculo e limite', () async {
    await repo.add(
        owner, '../../comprovante.pdf', Uint8List.fromList([1, 2, 3]));
    final file = (await repo.list(owner)).single;
    expect(file.name, 'comprovante.pdf');
    expect(await repo.read(owner, file.id), [1, 2, 3]);
    expect(repo.add(owner, 'vazio', Uint8List(0)), throwsFormatException);
    expect(
        repo.add(
            owner, 'grande', Uint8List(AttachmentsRepository.maxBytes + 1)),
        throwsFormatException);
    expect(
        repo.add(
            const MovementReference(MovementKind.transaction, 'missing', ''),
            'x',
            Uint8List(1)),
        throwsStateError);
    await db.customStatement("UPDATE local_attachments SET sha256='bad'");
    expect(repo.read(owner, file.id), throwsFormatException);
    expect(AttachmentsRepository.validate(db), throwsFormatException);
  });
  test('lixeira preserva arquivo e restauração do movimento reabre acesso',
      () async {
    await repo.add(owner, 'comprovante.txt', Uint8List.fromList([42]));
    await db.customStatement(
        "UPDATE transactions SET deleted_at=2,trash_state='trashed' WHERE id='t'");
    expect(repo.list(owner), throwsStateError);
    expect(
        (await db.customSelect('SELECT id FROM local_attachments').get())
            .length,
        1);
    await db.customStatement(
        "UPDATE transactions SET deleted_at=NULL,trash_state='active' WHERE id='t'");
    final file = (await repo.list(owner)).single;
    expect(await repo.read(owner, file.id), [42]);
    await repo.remove(owner, file.id);
    expect(await repo.list(owner), isEmpty);
  });
  test('backup restaura conteúdo e rejeita hash inválido sem substituir base',
      () async {
    final dir = await Directory.systemTemp.createTemp('somia-attachments-');
    addTearDown(() => dir.delete(recursive: true));
    await repo.add(owner, 'recibo.pdf', Uint8List.fromList([3, 2, 1]));
    final backup = await BackupService.export(db, dir);
    await repo.remove(owner, (await repo.list(owner)).single.id);
    await BackupService.restoreOpen(db, LocalBackupStore(dir), backup);
    final item = (await repo.list(owner)).single;
    expect(await repo.read(owner, item.id), [3, 2, 1]);
    final validHash = (await db
            .customSelect('SELECT sha256 FROM local_attachments')
            .getSingle())
        .read<String>('sha256');
    await db.customStatement("UPDATE local_attachments SET sha256='bad'");
    final bad = await BackupService.export(db, dir);
    await db
        .customStatement('UPDATE local_attachments SET sha256=?', [validHash]);
    await expectLater(BackupService.restoreOpen(db, LocalBackupStore(dir), bad),
        throwsFormatException);
    expect(await repo.read(owner, item.id), [3, 2, 1]);
  });
  test('sync financeiro preserva anexos locais e aceita schema 22', () async {
    await repo.add(owner, 'recibo', Uint8List.fromList([7]));
    final rows = await readFinancial(db);
    await db.transaction(() => replaceFinancial(db, rows));
    expect(await repo.read(owner, (await repo.list(owner)).single.id), [7]);
    final columns = await financialColumns(db);
    expect(columns.containsKey('local_attachments'), false);
    final packet = SyncPacket('packet-attachments-001', 'base-attachments-001',
        'device-attachments-001', 'changes', [],
        sourceSchema: 22);
    expect(SyncPacket.decode(packet.encode(), columns).sourceSchema, 22);
  });
  test('backup v22 migra e restaura sem reter anexos da base substituída',
      () async {
    final dir = await Directory.systemTemp.createTemp('attachments-legacy-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/old.sqlite');
    final old = LegacyV22(NativeDatabase(file));
    await old.customSelect('SELECT * FROM transactions').get();
    await old.close();
    await repo.add(owner, 'recibo', Uint8List.fromList([7]));
    await BackupService.restoreOpen(
        db, LocalBackupStore(dir), await file.readAsBytes());
    expect(await db.customSelect('SELECT * FROM local_attachments').get(),
        isEmpty);
    expect(await db.customSelect('SELECT * FROM transactions').get(), isEmpty);
  });
  test('migration v22 preserva lixeira e renova uploads para schema atual',
      () async {
    final dir = await Directory.systemTemp.createTemp('attachments-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/legacy.sqlite');
    final old = LegacyV22(NativeDatabase(file));
    await seed(old);
    await old.customStatement(
        "UPDATE transactions SET deleted_at=2,trash_state='trashed' WHERE id='t'");
    final row =
        (await old.customSelect('SELECT * FROM transactions').getSingle()).data;
    await old.customStatement('INSERT INTO sync_uploads VALUES(?,?)', [
      'old-attachment-packet',
      jsonEncode({
        'id': 'old-attachment-packet',
        'schema': 22,
        'entries': [
          {'table': 'transactions', 'data': row}
        ]
      })
    ]);
    await old.close();
    final migrated = AppDatabase(NativeDatabase(file));
    try {
      final upload =
          await migrated.customSelect('SELECT * FROM sync_uploads').getSingle();
      final packet = jsonDecode(upload.read<String>('payload'));
      expect(packet['schema'], AppDatabase.currentSchemaVersion);
      expect(packet['id'], isNot('old-attachment-packet'));
      expect(packet['entries'][0]['data']['trash_state'], 'trashed');
      expect(
          (await migrated
                  .customSelect('SELECT trash_state FROM transactions')
                  .getSingle())
              .read<String>('trash_state'),
          'trashed');
    } finally {
      await migrated.close();
    }
  });
  testWidgets('lista anexos e permite cancelar ou confirmar exclusão',
      (tester) async {
    await repo.add(owner, 'comprovante.pdf', Uint8List.fromList([1, 2]));
    await tester.pumpWidget(
        MaterialApp(home: AttachmentsPage(repository: repo, owner: owner)));
    await tester.pumpAndSettle();
    expect(find.text('comprovante.pdf'), findsOneWidget);
    expect(find.textContaining('ainda não sincronizados'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir anexo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await repo.list(owner), hasLength(1));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir anexo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum anexo neste lançamento.'), findsOneWidget);
  });
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('prévias de anexos no Android e Windows', (tester) async {
      for (final pair in [
        ('Roboto', 'Roboto-Regular.ttf'),
        ('MaterialIcons', 'MaterialIcons-Regular.otf')
      ]) {
        final loader = FontLoader(pair.$1)
          ..addFont(Future.value(ByteData.sublistView(File(
                  '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/${pair.$2}')
              .readAsBytesSync())));
        await loader.load();
      }
      await repo.add(
          owner, 'Comprovante de pagamento.pdf', Uint8List.fromList([1, 2, 3]));
      await repo.add(
          owner, 'Nota fiscal do mercado.png', Uint8List.fromList([4, 5, 6]));
      for (final mobile in [true, false]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        tester.view.physicalSize =
            mobile ? const Size(390, 844) : const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
            theme: AppTheme.dark,
            home: AttachmentsPage(repository: repo, owner: owner)));
        await tester.pumpAndSettle();
        await expectLater(
            find.byType(AttachmentsPage),
            matchesGoldenFile(
                'attachments-${mobile ? 'mobile' : 'desktop'}-preview.png'));
      }
    });
  }
}
