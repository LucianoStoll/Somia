import 'dart:io';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_manager.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/drive/drive_backup.dart';
import 'package:finapp/core/drive/drive_backup_manager.dart';
import 'package:finapp/core/sync/auto_sync_controller.dart';
import 'package:finapp/core/sync/sync_lifecycle.dart';
import 'package:finapp/core/sync/sync_manager.dart';
import 'package:finapp/core/sync/sync_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'sync_manager_test.dart' show TestAuth,NoTransport,MemoryCloud;
import 'auto_sync_controller_test.dart' show Preference;

void main(){
  testWidgets('lifecycle retoma uma vez e cancela timers ao pausar ou desmontar',(tester)async{
    final db=AppDatabase(NativeDatabase.memory());final local=BackupManager(db,LocalBackupStore(Directory.systemTemp));
    final drive=DriveBackupManager(local,DriveBackupApi(TestAuth(),NoTransport()));
    final manager=SyncManager(local,drive,SyncStore(db,local.store),MemoryCloud(),primaryAllowed:true);
    final pref=Preference()..value=false;
    final auto=AutoSyncController(manager,pref,safeToApply:()=>true);
    addTearDown(()async{auto.dispose();manager.dispose();drive.dispose();local.dispose();await db.close();});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(SyncLifecycle(controller:auto,child:const SizedBox()));
    await tester.pump();expect(auto.active,isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);await tester.pump();expect(auto.active,isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pump();expect(auto.active,isTrue);
    await tester.pumpWidget(const SizedBox());expect(auto.active,isFalse);
  });
}
