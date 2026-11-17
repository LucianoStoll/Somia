import 'dart:io';
import 'package:flutter/services.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_manager.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/drive/drive_backup.dart';
import 'package:finapp/core/drive/drive_backup_manager.dart';
import 'package:finapp/core/sync/drive_sync_api.dart';
import 'package:finapp/core/sync/sync_manager.dart';
import 'package:finapp/core/sync/sync_store.dart';
import 'package:finapp/core/sync/auto_sync_controller.dart';
import '../../core/sync/auto_sync_controller_test.dart' show Preference;
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
  int published = 0, received = 0, synced = 0, replaced = 0;
  @override
  Future<void> replaceBase(
      {String? expectedRevision, String? expectedEmail}) async {
    replaced++;
  }

  @override
  Future<void> createBase() async {
    published++;
  }

  @override
  Future<void> join(SyncRemoteFile file) async {
    received++;
  }

  @override
  Future<void> synchronize(
      {bool automatic = false, bool Function()? canApply}) async {
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
  Future<void> show(WidgetTester tester,
      {AutoSyncController? automatic}) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: SyncPanel(manager: manager, automatic: automatic)))));
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
  testWidgets('substituição exige confirmação explícita e cancelar não publica',
      (tester) async {
    manager.listedEmail = 'same@example.com';
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
    await tester.ensureVisible(find.text('Opções avançadas'));
    await tester.tap(find.text('Opções avançadas'));
    await tester.pumpAndSettle();
    final action = find.text('Substituir base do Drive pela deste Android');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(manager.replaced, 0);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(manager.replaced, 0);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Substituir base do Drive'));
    await tester.tap(find.text('Substituir base do Drive'));
    await tester.pumpAndSettle();
    expect(manager.replaced, 1);
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
  testWidgets(
      'modo a cada alteração é selecionável e persistido com fonte ampliada',
      (tester) async {
    final pref = Preference();
    final auto = AutoSyncController(manager, pref, safeToApply: () => true);
    addTearDown(auto.dispose);
    await auto.initialize();
    await show(tester, automatic: auto);
    await tester.ensureVisible(find.text('Opções avançadas'));
    await tester.tap(find.text('Opções avançadas'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Alterações agrupadas'));
    await tester.tap(find.text('Alterações agrupadas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A cada alteração').last);
    await tester.pumpAndSettle();
    expect(auto.mode, AutoSyncMode.eachChange);
    expect(pref.mode, AutoSyncMode.eachChange);
    pref.failWrite = true;
    await tester.ensureVisible(find.text('A cada alteração'));
    await tester.tap(find.text('A cada alteração'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alterações agrupadas').last);
    await tester.pumpAndSettle();
    expect(auto.mode, AutoSyncMode.eachChange);
    expect(find.text('A cada alteração'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'alternância automática persiste e cabe no painel com fonte ampliada',
      (tester) async {
    final pref = Preference();
    final auto = AutoSyncController(manager, pref, safeToApply: () => true);
    addTearDown(auto.dispose);
    await auto.initialize();
    await show(tester, automatic: auto);
    await tester.ensureVisible(find.text('Sincronização automática'));
    await tester.tap(find.text('Sincronização automática'));
    await tester.pumpAndSettle();
    expect(auto.enabled, isFalse);
    expect(pref.value, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'status e ação principal ficam visíveis, opções avançadas recolhidas',
      (tester) async {
    manager.state = SyncState(
        'base', 'same@example.com', 'device', DateTime(2026, 11, 8), 0, 0);
    await show(tester);
    expect(find.text('Sem pendências locais'), findsOneWidget);
    expect(find.textContaining('Última sincronização:'), findsOneWidget);
    expect(find.text('Ver versões anteriores'), findsNothing);
    expect(find.text('Publicar base deste Android'), findsNothing);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Sincronizar agora'));
    expect(button.onPressed, isNotNull);
    await tester.ensureVisible(find.text('Opções avançadas'));
    await tester.tap(find.text('Opções avançadas'));
    await tester.pumpAndSettle();
    expect(find.text('Ver versões anteriores'), findsOneWidget);
  });

  testWidgets('nova base e publicação pendente não permitem sync comum',
      (tester) async {
    manager.state = const SyncState(
        'base', 'same@example.com', 'device', null, 0, 0,
        replacementPending: true);
    await show(tester);
    expect(find.text('Publicação pendente'), findsOneWidget);
    expect(find.text('Retomar publicação pendente'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Sincronizar agora'))
            .onPressed,
        isNull);
    manager.state =
        const SyncState('base', 'same@example.com', 'device', null, 0, 0);
    manager.needsJoin = true;
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('Receba a base atualizada'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Sincronizar agora'))
            .onPressed,
        isNull);
    expect(find.text('Conectar este dispositivo'), findsOneWidget);
  });

  testWidgets(
      'erros e espera automática ficam visíveis fora das opções avançadas',
      (tester) async {
    final auto =
        AutoSyncController(manager, Preference(), safeToApply: () => false);
    addTearDown(auto.dispose);
    await auto.initialize();
    manager.state =
        const SyncState('base', 'same@example.com', 'device', null, 0, 0);
    auto.waiting = true;
    await show(tester, automatic: auto);
    expect(find.text('Aguardando fechar o formulário'), findsOneWidget);
    manager.error = 'Falha de conexão. Tente novamente.';
    await show(tester, automatic: auto);
    expect(find.text('Sincronização interrompida'), findsOneWidget);
    expect(find.text('Falha de conexão. Tente novamente.'), findsOneWidget);
    expect(find.text('Ver versões anteriores'), findsNothing);
  });

  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('prévia da sincronização simplificada', (tester) async {
      final fonts = Directory(
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts');
      final font = FontLoader('Roboto'), icons = FontLoader('MaterialIcons');
      for (final file in fonts.listSync().whereType<File>()) {
        if (file.path.endsWith('Roboto-Regular.ttf') ||
            file.path.endsWith('Roboto-Bold.ttf')) {
          font.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
        if (file.path.endsWith('MaterialIcons-Regular.otf')) {
          icons.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await font.load();
      await icons.load();
      manager.state = SyncState(
          'base', 'same@example.com', 'device', DateTime(2026, 11, 8, 7), 2, 0);
      await show(tester);
      await tester.pumpAndSettle();
      await expectLater(find.byType(Scaffold),
          matchesGoldenFile('sync-status-mobile-preview.png'));
    });
  }
}
