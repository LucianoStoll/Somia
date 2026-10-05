import 'package:flutter/foundation.dart';

import '../database/backup_manager.dart';
import '../database/backup_service.dart';
import 'drive_backup.dart';
import 'windows_drive_auth.dart';

class DriveBackupManager extends ChangeNotifier {
  DriveBackupManager(this.local, this.api);
  final BackupManager local;
  final DriveBackupApi api;
  String? email;
  String? error;
  String? message;
  bool busy = false;
  bool connecting = false;
  List<DriveCopy> copies = const [];
  String? _listedAccount;
  bool get configurable => api.auth is ConfigurableDriveAuth;
  bool get configured =>
      !configurable || (api.auth as ConfigurableDriveAuth).configured;
  void cancelConnection() {
    if (api.auth is ConfigurableDriveAuth) {
      (api.auth as ConfigurableDriveAuth).cancel();
    }
  }

  Future<void> configure(Uint8List bytes) => _run(() async {
        if (api.auth is! ConfigurableDriveAuth) return;
        await (api.auth as ConfigurableDriveAuth).configure(bytes);
        email = null;
        copies = const [];
        _listedAccount = null;
        message = 'Cliente Google configurado. Agora conecte sua conta.';
      });
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    message = null;
    _notify();
    try {
      await action();
    } catch (failure) {
      error = failure is DriveFailure
          ? failure.message
          : failure is FormatException
              ? failure.message
              : 'Não foi possível concluir. Confira sua conexão e tente novamente.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> initialize() => _run(() async {
        email = await api.auth.account();
      });
  Future<void> connect() => _run(() async {
        connecting = true;
        _notify();
        try {
          final session = await api.auth.connect();
          email = session.email;
          copies = const [];
          _listedAccount = null;
          await _list(session);
        } finally {
          connecting = false;
        }
      });
  Future<void> disconnect() => _run(() async {
        await api.auth.disconnect();
        email = null;
        copies = const [];
        _listedAccount = null;
        message = 'Conta desconectada. As cópias foram mantidas.';
      });
  Future<DriveSession> _session() async {
    final session = await api.auth.authorize();
    if (session.email != email) {
      email = session.email;
      copies = const [];
      _listedAccount = null;
      throw const DriveFailure(
          'A conta mudou. Atualize a lista para continuar.');
    }
    return session;
  }

  Future<void> _checkAccount(DriveSession session) async {
    if (await api.auth.account() != session.email) {
      copies = const [];
      _listedAccount = null;
      throw const DriveFailure(
          'A conta mudou durante a operação. Reconecte e tente novamente.');
    }
  }

  Future<void> _list(DriveSession session) async {
    final result = await api.list(session);
    await _checkAccount(session);
    copies = result;
    _listedAccount = session.email;
  }

  Future<void> refresh() => _run(() async {
        await _list(await _session());
      });
  Future<void> upload() => _run(() async {
        if (local.restorePending) {
          throw const DriveFailure(
              'Aplique ou cancele a restauração pendente antes de enviar.');
        }
        final session = await _session();
        final bytes = await local.export();
        await BackupService.validateBytes(bytes, local.store.directory);
        await _checkAccount(session);
        await api.upload(session, bytes);
        message = 'Backup enviado ao Drive.';
        // O envio já foi concluído; uma falha na listagem não deve sugerir reenvio.
        try {
          await _list(session);
        } catch (_) {
          message = 'Backup enviado. Atualize a lista para conferir a cópia.';
        }
      });
  Future<void> restore(DriveCopy copy) => _run(() async {
        final session = await _session();
        if (_listedAccount != session.email || !copies.contains(copy)) {
          throw const DriveFailure('Atualize a lista antes de restaurar.');
        }
        final bytes = await api.download(session, copy);
        await _checkAccount(session);
        await local.restore(bytes);
        message = 'Backup validado. Feche e abra o Somia para aplicar.';
      });
}
