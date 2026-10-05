import 'dart:io';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_lifecycle.dart';
import 'package:finapp/core/database/backup_manager.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/settings/presentation/local_backups_panel.dart';
import 'package:finapp/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class PreviewManager extends BackupManager {
  PreviewManager()
      : super(AppDatabase(NativeDatabase.memory()),
            LocalBackupStore(Directory.systemTemp)) {
    copies = [
      LocalBackupCopy(File('auto.sqlite'), BackupKind.automatic,
          DateTime(2026, 10, 5, 10, 40), 98304),
      LocalBackupCopy(File('manual.sqlite'), BackupKind.manual,
          DateTime(2026, 10, 4, 18, 25), 98304),
      LocalBackupCopy(File('protection.sqlite'), BackupKind.beforeRestore,
          DateTime(2026, 10, 3, 12, 30), 98304),
    ];
  }
  int checks = 0, created = 0, restored = 0;
  @override
  Future<void> daily() async {
    checks++;
  }

  @override
  Future<void> refresh() async {}
  @override
  Future<LocalBackupCopy> create() async {
    created++;
    return copies.first;
  }

  @override
  Future<Uint8List> readCopy(LocalBackupCopy copy) async => Uint8List(100);
  @override
  Future<void> restore(Uint8List bytes) async {
    restored++;
    restorePending = true;
    notifyListeners();
  }

  @override
  Future<void> cancelRestore() async {
    restorePending = false;
    notifyListeners();
  }
}

void main() {
  late PreviewManager manager;
  setUp(() async {
    await getIt.reset();
    manager = PreviewManager();
  });
  tearDown(() async {
    await getIt.reset();
    manager.dispose();
    await manager.database.close();
  });

  testWidgets('abrir e retomar verificam backup; pausa cancela agendamento',
      (tester) async {
    await tester
        .pumpWidget(BackupLifecycle(manager: manager, child: const SizedBox()));
    expect(manager.checks, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(days: 2));
    expect(manager.checks, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(manager.checks, 2);
    await tester.pump(const Duration(days: 1));
    expect(manager.checks, greaterThan(2));
    await tester.pumpWidget(const SizedBox());
    final checks = manager.checks;
    await tester.pump(const Duration(days: 1));
    expect(manager.checks, checks);
  });

  testWidgets(
      'Ajustes cria cópia, confirma restauração e permite cancelar preparada',
      (tester) async {
    getIt.registerSingleton<BackupManager>(manager);
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const SettingsPage()));
    await tester.scrollUntilVisible(find.text('Criar cópia agora'), 300);
    await tester.tap(find.text('Criar cópia agora'));
    await tester.pumpAndSettle();
    expect(manager.created, 1);
    await tester.scrollUntilVisible(find.text('Automático'), 200);
    await tester.ensureVisible(find.byType(PopupMenuButton<String>).first);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurar esta cópia'));
    await tester.pumpAndSettle();
    expect(find.text('Restaurar backup?'), findsOneWidget);
    expect(manager.restored, 0);
    await tester.tap(find.text('Restaurar').last);
    await tester.pumpAndSettle();
    expect(manager.restored, 1);
    await tester.scrollUntilVisible(
        find.text('Cancelar restauração preparada'), -200);
    await tester.tap(find.text('Cancelar restauração preparada'));
    await tester.pumpAndSettle();
    expect(manager.restorePending, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('lista e erros legíveis no celular com escala $scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      manager.error = 'Não foi possível concluir o backup. Tente novamente.';
      manager.restorePending = true;
      manager.restoreFailed = true;
      int exported = 0;
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: ListView(children: [
            LocalBackupsPanel(
                manager: manager,
                onCreate: () {},
                onCancel: () {},
                onExport: (_) {
                  exported++;
                },
                onRestore: (_) {})
          ]))));
      await tester.scrollUntilVisible(find.text('Manual'), 200);
      await tester.ensureVisible(find.byType(PopupMenuButton<String>).at(1));
      await tester.tap(find.byType(PopupMenuButton<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exportar cópia'));
      await tester.pumpAndSettle();
      expect(exported, 1);
      expect(tester.takeException(), isNull);
    });
  }

  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    for (final size in [const Size(390, 844), const Size(1280, 900)]) {
      testWidgets('prévia backups $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fonts = Directory(
            '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts');
        final font = FontLoader('Roboto'), icons = FontLoader('MaterialIcons');
        for (final f in fonts.listSync().whereType<File>()) {
          if (f.path.endsWith('Roboto-Regular.ttf') ||
              f.path.endsWith('Roboto-Bold.ttf')) {
            font.addFont(
                Future.value(ByteData.sublistView(f.readAsBytesSync())));
          }
          if (f.path.endsWith('MaterialIcons-Regular.otf')) {
            icons.addFont(
                Future.value(ByteData.sublistView(f.readAsBytesSync())));
          }
        }
        await font.load();
        await icons.load();
        await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            home: Scaffold(
                appBar: AppBar(title: const Text('Ajustes')),
                body: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              LocalBackupsPanel(
                                  manager: manager,
                                  onCreate: () {},
                                  onCancel: () {},
                                  onExport: (_) {},
                                  onRestore: (_) {})
                            ]))))));
        await tester.pumpAndSettle();
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(size.width < 500
                ? 'backups-mobile-preview.png'
                : 'backups-desktop-preview.png'));
      });
    }
  }
}
