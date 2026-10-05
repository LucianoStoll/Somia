import 'dart:io';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_manager.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/drive/drive_backup.dart';
import 'package:finapp/core/drive/drive_backup_manager.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/settings/presentation/drive_backups_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../core/drive/drive_backup_test.dart'
    show FakeAuth, FakeTransport, jsonResponse;

class PanelManager extends DriveBackupManager {
  PanelManager()
      : super(
            BackupManager(AppDatabase(NativeDatabase.memory()),
                LocalBackupStore(Directory.systemTemp)),
            DriveBackupApi(
                FakeAuth(),
                FakeTransport((method, uri, headers, body) async =>
                    jsonResponse({'files': []}))));
  int restored = 0;
  int uploads = 0;
  @override
  Future<void> restore(DriveCopy copy) async {
    restored++;
  }

  @override
  Future<void> upload() async {
    uploads++;
  }
}

void main() {
  late PanelManager manager;
  setUp(() {
    manager = PanelManager()
      ..email = 'luciano@example.com'
      ..copies = [
        DriveCopy(
            id: 'copy',
            name: 'somia.sqlite',
            createdAt: DateTime(2026, 10, 5, 12),
            size: 98304,
            md5Hash: '',
            sha256Hash: '')
      ];
  });
  tearDown(() async {
    manager.dispose();
    manager.local.dispose();
    await manager.local.database.close();
  });
  testWidgets('envio manual e restauração confirmada com fonte ampliada',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: DriveBackupsPanel(manager: manager)))));
    await tester.tap(find.text('Enviar backup'));
    await tester.pumpAndSettle();
    expect(manager.uploads, 1);
    final restore = find.byTooltip('Restaurar cópia do Drive');
    await tester.ensureVisible(restore);
    await tester.pumpAndSettle();
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(manager.restored, 0);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurar'));
    await tester.pumpAndSettle();
    expect(manager.restored, 1);
    expect(tester.takeException(), isNull);
  });
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('prévia mobile do Drive', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark,
          home: Scaffold(appBar: AppBar(title: const Text('Ajustes')),
              body: SingleChildScrollView(child: DriveBackupsPanel(manager: manager)))));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('drive-backup-mobile-preview.png'));
    });
  }

}
