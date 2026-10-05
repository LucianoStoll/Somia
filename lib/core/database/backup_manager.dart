import 'package:flutter/foundation.dart';
import 'app_database.dart';
import 'backup_service.dart';
import 'local_backup_store.dart';

/// Serializa operações locais e expõe falhas sem bloquear o uso financeiro.
class BackupManager extends ChangeNotifier {
  BackupManager(this.database, this.store);
  final AppDatabase database;
  final LocalBackupStore store;
  List<LocalBackupCopy> copies = const [];
  String? error;
  bool busy = false;
  bool restorePending = false;
  bool restoring = false;
  int databaseRevision = 0;
  bool restoreFailed = false;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<T> _run<T>(Future<T> Function() action, {bool clearError = true}) {
    final result = _queue.then((_) async {
      busy = true;
      _notify();
      try {
        final revision = databaseRevision;
        final value = await action();
        try {
          copies = await store.list();
          restorePending =
              await BackupService.hasPendingRestore(store.directory);
          restoreFailed =
              await BackupService.hasRestoreFailure(store.directory);
          if (clearError) error = null;
        } catch (_) {
          if (databaseRevision == revision) rethrow;
          error =
              'Dados restaurados. Não foi possível atualizar a lista de cópias.';
        }
        return value;
      } catch (_) {
        error =
            'Não foi possível concluir o backup. Tente novamente e confira o espaço disponível.';
        rethrow;
      } finally {
        busy = false;
        _notify();
      }
    });
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> daily() async {
    try {
      await _run(() => store.daily(database));
    } catch (_) {
      // Mensagem disponível em Ajustes; o app continua funcionando.
    }
  }

  Future<void> refresh() => _run(() async {
        restorePending = await BackupService.hasPendingRestore(store.directory);
      }, clearError: false);
  Future<LocalBackupCopy> create() =>
      _run(() => store.create(database, BackupKind.manual));
  Future<Uint8List> export() =>
      _run(() => BackupService.export(database, store.directory));
  Future<Uint8List> readCopy(LocalBackupCopy copy) => _run(() async {
        final bytes = await copy.file.readAsBytes();
        await BackupService.validateBytes(bytes, store.directory);
        return bytes;
      });
  Future<void> cancelRestore() => _run(() async {
        await BackupService.cancelPendingRestore(store.directory);
        restorePending = false;
      });
  Future<void> restore(Uint8List bytes) => _run(() async {
        restoring = true;
        _notify();
        try {
          await BackupService.restoreOpen(database, store, bytes);
          restorePending = false;
          databaseRevision++;
        } finally {
          restoring = false;
          _notify();
        }
      });
  Future<T> maintain<T>(Future<T> Function() action,
      {bool refreshScreens = true}) => _run(() async {
    restoring = true;
    _notify();
    try {
      final result = await action();
      if (refreshScreens) databaseRevision++;
      return result;
    } finally {
      restoring = false;
      _notify();
    }
  });

}
