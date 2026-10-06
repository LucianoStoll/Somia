import 'dart:io';
import 'package:drift/native.dart';
import 'package:finapp/app/app.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_manager.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class QuietManager extends BackupManager {
  QuietManager(super.database, super.store);
  @override
  Future<void> daily() async {}
  @override
  Future<void> refresh() async {}
}

class EmptyStore extends LocalBackupStore {
  EmptyStore(super.directory);
  @override
  Future<List<LocalBackupCopy>> list() async => [];
}

void main() {
  testWidgets(
      'sincronização mantém URI atual; restauração continua voltando para Ajustes',
      (tester) async {
    final directory = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('somia-auto-ui-')))!;
    final db = AppDatabase(NativeDatabase.memory());
    final manager = QuietManager(db, EmptyStore(directory));
    getIt.registerSingleton<BackupManager>(manager);
    appRouter.dispose();
    appRouter = createAppRouter(initialLocation: '/settings?keep=true');
    await tester.pumpWidget(const FinApp());
    await tester.pumpAndSettle();
    await tester.runAsync(() => manager.maintain(() => Future.value(true),
        preserveLocation: true, shouldRefresh: (changed) => changed));
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.toString(),
        '/settings?keep=true');
    final revision = manager.databaseRevision;
    await tester.runAsync(() => manager.maintain(() => Future.value(false),
        preserveLocation: true, shouldRefresh: (changed) => changed));
    await tester.pumpAndSettle();
    expect(manager.databaseRevision, revision);
    await tester.runAsync(() => manager.maintain(() => Future.value(true)));
    await tester.pumpAndSettle();
    expect(
        appRouter.routeInformationProvider.value.uri.toString(), '/settings');
    await tester.pumpWidget(const SizedBox());
    appRouter.dispose();
    await getIt.reset();
    manager.dispose();
    await db.close();
    await tester.runAsync(() => directory.delete(recursive: true));
  });
}
