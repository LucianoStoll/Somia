import 'dart:io';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_manager.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/drive/drive_backup.dart';
import 'package:finapp/core/drive/drive_backup_manager.dart';
import 'package:finapp/core/sync/drive_sync_api.dart';
import 'package:finapp/core/sync/sync_manager.dart';
import 'package:finapp/core/sync/sync_store.dart';
import 'package:finapp/features/settings/presentation/sync_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../core/sync/sync_manager_test.dart'
    show TestAuth, NoTransport, MemoryCloud;

class PanelSync extends SyncManager {
  PanelSync(BackupManager local, DriveBackupManager drive)
      : super(
            local, drive, SyncStore(local.database, local.store), MemoryCloud(),
            primaryAllowed: true);
  int published = 0, received = 0, synced = 0;
  @override
  Future<void> createBase() async {
    published++;
  }

  @override
  Future<void> join(SyncRemoteFile file) async {
    received++;
  }

  @override
  Future<void> synchronize() async {
    synced++;
  }
}

void main() {
  late PanelSync manager;
  setUp(() {
    final local = BackupManager(AppDatabase(NativeDatabase.memory()),
        LocalBackupStore(Directory.systemTemp));
    manager = PanelSync(local,
        DriveBackupManager(local, DriveBackupApi(TestAuth(), NoTransport())));
  });
  tearDown(() async {
    manager.dispose();
    manager.drive.dispose();
    manager.local.dispose();
    await manager.local.database.close();
  });
  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(child: SyncPanel(manager: manager)))));
  }

  testWidgets(
      'publicação e recebimento exigem confirmação e cabem com texto ampliado',
      (tester) async {
    final files = await MemoryCloud()
        .list(const DriveSession('same@example.com', 'token'));
    expect(files, isEmpty);
    manager.bases = [
      SyncRemoteFile(
          DriveCopy(
              id: 'file',
              name: 'base',
              createdAt: DateTime(2026),
              size: 1,
              md5Hash: '',
              sha256Hash: ''),
          'packet-identity-0001',
          'base-identity-00001',
          'android-device-0001',
          'genesis')
    ];
    await show(tester);
    await tester.ensureVisible(find.text('Publicar base deste Android'));
    await tester.tap(find.text('Publicar base deste Android'));
    await tester.pumpAndSettle();
    expect(manager.published, 0);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Receber'));
    await tester.tap(find.text('Receber'));
    await tester.pumpAndSettle();
    expect(manager.received, 0);
    expect(find.textContaining('Uma cópia Antes de restaurar'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(manager.received, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('base vinculada mostra pendências e dispara sync manual',
      (tester) async {
    manager.state =
        const SyncState('base', 'same@example.com', 'device', null, 2, 0);
    await show(tester);
    expect(find.text('Alterações pendentes: 2'), findsOneWidget);
    await tester.ensureVisible(find.text('Sincronizar agora'));
    await tester.tap(find.text('Sincronizar agora'));
    await tester.pumpAndSettle();
    expect(manager.synced, 1);
    expect(tester.takeException(), isNull);
  });
}
