import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_manager.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/drive/drive_backup.dart';
import 'package:finapp/core/drive/drive_backup_manager.dart';
import 'package:finapp/core/sync/auto_sync_controller.dart';
import 'package:finapp/core/sync/sync_manager.dart';
import 'package:finapp/core/sync/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'sync_manager_test.dart' show TestAuth, NoTransport, MemoryCloud;

class Preference implements AutoSyncPreference {
  bool value = true, failRead = false, failWrite = false;
  @override
  Future<bool> read() async {
    if (failRead) throw const FileSystemException();
    return value;
  }

  @override
  Future<void> write(bool enabled) async {
    if (failWrite) throw const FileSystemException();
    value = enabled;
  }
}

class ObservedStore extends SyncStore {
  ObservedStore(super.db, super.backups);
  SyncState snapshot = const SyncState(
      'base', 'same@example.com', 'device', null, 0, 0,
      clock: 1);
  void edit(int clock, {int pending = 1}) {
    snapshot = SyncState(
        snapshot.base, snapshot.email, snapshot.device, null, pending, 0,
        clock: clock);
  }

  @override
  Future<SyncState> state() async => snapshot;
}

class ScheduledManager extends SyncManager {
  ScheduledManager(
      BackupManager local, DriveBackupManager drive, ObservedStore store)
      : super(local, drive, store, MemoryCloud(), primaryAllowed: true);
  int calls = 0;
  bool fail = false;
  Completer<void>? gate;
  void Function()? afterCycle;
  @override
  Future<void> synchronize(
      {bool automatic = false, bool Function()? canApply}) async {
    expect(automatic, isTrue);
    expect(busy, isFalse);
    busy = true;
    calls++;
    deferred = false;
    error = null;
    await gate?.future;
    if (!(canApply?.call() ?? false)) {
      deferred = true;
      busy = false;
      return;
    }
    if (fail) {
      error = 'Sem rede';
    } else {
      final observed = store as ObservedStore;
      observed.edit(observed.snapshot.clock, pending: 0);
      state = observed.snapshot;
      completedSyncCycles++;
      afterCycle?.call();
      state = observed.snapshot;
    }
    busy = false;
  }
}

void main() {
  late AppDatabase db;
  late BackupManager local;
  late DriveBackupManager drive;
  late ObservedStore store;
  late ScheduledManager manager;
  late Preference preference;
  AutoSyncController? controller;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    local = BackupManager(db, LocalBackupStore(Directory.systemTemp));
    drive =
        DriveBackupManager(local, DriveBackupApi(TestAuth(), NoTransport()));
    store = ObservedStore(db, local.store);
    manager = ScheduledManager(local, drive, store);
    preference = Preference();
  });
  tearDown(() async {
    controller?.dispose();
    controller = null;
    manager.dispose();
    drive.dispose();
    local.dispose();
    await db.close();
  });
  AutoSyncController setup(FakeAsync time, {bool Function()? safe}) {
    final origin = DateTime(2026, 10, 5);
    return controller = AutoSyncController(manager, preference,
        safeToApply: safe ?? () => true,
        poll: const Duration(seconds: 1),
        debounce: const Duration(seconds: 3),
        remoteInterval: const Duration(seconds: 30),
        retryDelays: const [Duration(seconds: 5), Duration(seconds: 10)],
        clock: () => origin.add(time.elapsed));
  }

  void flush(FakeAsync time) {
    time.flushMicrotasks();
    time.elapse(Duration.zero);
    time.flushMicrotasks();
  }

  test(
      'abertura só sincroniza após vínculo explícito e consulta remota periodicamente',
      () {
    fakeAsync((time) {
      store.snapshot = const SyncState(null, null, null, null, 0, 0);
      final auto = setup(time);
      auto.resume();
      flush(time);
      time.elapse(const Duration(seconds: 35));
      expect(manager.calls, 0);
      store.snapshot = const SyncState(
          'base', 'same@example.com', 'device', null, 0, 0,
          clock: 1);
      time.elapse(const Duration(seconds: 1));
      expect(manager.calls, 1);
      time.elapse(const Duration(seconds: 29));
      expect(manager.calls, 1);
      time.elapse(const Duration(seconds: 1));
      expect(manager.calls, 2);
      auto.pause();
      expect(time.nonPeriodicTimerCount, 0);
    });
  });
  test(
      'rajada de edições reinicia espera; recebimento sem pendências não gera eco',
      () {
    fakeAsync((time) {
      final auto = setup(time);
      auto.resume();
      flush(time);
      expect(manager.calls, 1);
      store.edit(2);
      time.elapse(const Duration(seconds: 2));
      store.edit(3);
      time.elapse(const Duration(seconds: 2));
      expect(manager.calls, 1);
      time.elapse(const Duration(seconds: 2));
      expect(manager.calls, 2);
      store.edit(4, pending: 0);
      time.elapse(const Duration(seconds: 4));
      expect(manager.calls, 2);
    });
  });
  test('falhas preservam pendências e tentativas respeitam espera crescente',
      () {
    fakeAsync((time) {
      store.edit(2);
      manager.fail = true;
      final auto = setup(time);
      auto.resume();
      flush(time);
      expect(manager.calls, 1);
      expect(store.snapshot.pending, 1);
      expect(auto.retryAt, isNotNull);
      time.elapse(const Duration(seconds: 4));
      expect(manager.calls, 1);
      time.elapse(const Duration(seconds: 1));
      expect(manager.calls, 2);
      store.edit(3);
      time.elapse(const Duration(seconds: 9));
      expect(manager.calls, 2);
      manager.fail = false;
      time.elapse(const Duration(seconds: 1));
      expect(manager.calls, 3);
      expect(auto.retryAt, isNull);
      expect(store.snapshot.pending, 0);
    });
  });
  test(
      'backup, autorização e sincronização manual ocupados não sobrepõem ciclos',
      () {
    fakeAsync((time) {
      local.busy = true;
      final auto = setup(time);
      auto.resume();
      flush(time);
      expect(manager.calls, 0);
      local.busy = false;
      drive.busy = true;
      time.elapse(const Duration(seconds: 2));
      expect(manager.calls, 0);
      drive.busy = false;
      manager.busy = true;
      time.elapse(const Duration(seconds: 2));
      expect(manager.calls, 0);
      manager.busy = false;
      time.elapse(const Duration(seconds: 1));
      expect(manager.calls, 1);
    });
  });
  test('pausa suspende timers e recebimento; retomada executa novo ciclo', () {
    fakeAsync((time) {
      manager.gate = Completer<void>();
      final auto = setup(time);
      auto.resume();
      flush(time);
      expect(manager.calls, 1);
      auto.pause();
      manager.gate!.complete();
      flush(time);
      expect(manager.deferred, isTrue);
      time.elapse(const Duration(minutes: 5));
      expect(manager.calls, 1);
      manager.gate = null;
      auto.resume();
      flush(time);
      expect(manager.calls, 2);
      expect(manager.completedSyncCycles, 1);
    });
  });
  test(
      'formulários aguardam; alterações feitas durante envio ganham outro ciclo',
      () {
    fakeAsync((time) {
      var safe = false;
      final auto = setup(time, safe: () => safe);
      auto.resume();
      flush(time);
      expect(manager.calls, 0);
      expect(auto.waiting, isTrue);
      safe = true;
      manager.afterCycle = () {
        store.edit(2);
        manager.afterCycle = null;
      };
      time.elapse(const Duration(seconds: 1));
      expect(manager.calls, 1);
      time.elapse(const Duration(seconds: 3));
      expect(manager.calls, 2);
    });
  });
  test(
      'preferência desligada persiste; falha de escrita conserva escolha anterior',
      () {
    fakeAsync((time) {
      preference.value = false;
      final auto = setup(time);
      auto.resume();
      flush(time);
      time.elapse(const Duration(seconds: 5));
      expect(manager.calls, 0);
      auto.setEnabled(true);
      flush(time);
      expect(preference.value, isTrue);
      expect(manager.calls, 1);
      preference.failWrite = true;
      auto.setEnabled(false);
      flush(time);
      expect(auto.enabled, isTrue);
      expect(auto.error, isNotNull);
      preference.failWrite = false;
      auto.setEnabled(false);
      flush(time);
      time.elapse(const Duration(minutes: 1));
      expect(manager.calls, 1);
      expect(preference.value, isFalse);
    });
  });
  test('restauração desvinculada e preferência inválida não iniciam rede', () {
    fakeAsync((time) {
      preference.failRead = true;
      final auto = setup(time);
      auto.resume();
      flush(time);
      expect(auto.enabled, isFalse);
      expect(manager.calls, 0);
      store.snapshot = const SyncState(null, null, null, null, 0, 0);
      auto.setEnabled(true);
      flush(time);
      time.elapse(const Duration(seconds: 5));
      expect(manager.calls, 0);
    });
  });
  test(
      'preferência em arquivo é independente do backup e mantém opção ao reabrir',
      () async {
    final dir = await Directory.systemTemp.createTemp('somia-auto-pref-');
    addTearDown(() => dir.delete(recursive: true));
    final pref = FileAutoSyncPreference(dir);
    expect(await pref.read(), isTrue);
    await pref.write(false);
    expect(await FileAutoSyncPreference(dir).read(), isFalse);
    await pref.write(true);
    expect(await FileAutoSyncPreference(dir).read(), isTrue);
  });
  test('sucesso manual limpa repetição antiga sem gerar um ciclo duplicado',
      () {
    fakeAsync((time) {
      manager.fail = true;
      final auto = setup(time);
      auto.resume();
      flush(time);
      expect(manager.calls, 1);
      manager.fail = false;
      manager.error = null;
      store.snapshot = SyncState(
          'base', 'same@example.com', 'device', DateTime(2026, 10, 5), 0, 0,
          clock: 2);
      time.elapse(const Duration(seconds: 10));
      expect(manager.calls, 1);
      expect(auto.retryAt, isNull);
      time.elapse(const Duration(seconds: 21));
      expect(manager.calls, 2);
    });
  });
}
