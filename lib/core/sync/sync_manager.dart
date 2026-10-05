import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../database/backup_manager.dart';
import '../drive/drive_backup.dart';
import '../drive/drive_backup_manager.dart';
import 'sync_store.dart';
import 'sync_packet.dart';
import 'drive_sync_api.dart';

class SyncManager extends ChangeNotifier {
  SyncManager(this.local, this.drive, this.store, this.cloud,
      {required this.primaryAllowed});
  final BackupManager local;
  final DriveBackupManager drive;
  final SyncStore store;
  final SyncCloud cloud;
  final bool primaryAllowed;
  SyncState? state;
  List<SyncRemoteFile> bases = const [];
  List<SyncEntry> history = const [];
  bool busy = false;
  String? error, message;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> refresh() async {
    state = await store.state();
    history = await store.history();
    _notify();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy || drive.busy || local.busy) return;
    busy = true;
    error = null;
    message = null;
    _notify();
    try {
      await action();
    } catch (e) {
      error = e is DriveFailure
          ? e.message
          : e is FormatException
              ? e.message
              : 'Não foi possível sincronizar. Seus dados e alterações pendentes foram preservados. Tente novamente.';
    } finally {
      try {
        await refresh();
      } catch (_) {
        error ??= 'Não foi possível atualizar o estado da sincronização.';
      }
      busy = false;
      _notify();
    }
  }

  Future<DriveSession> _session() async {
    final s = await drive.api.auth.authorize();
    if (await drive.api.auth.account() != s.email) {
      throw const DriveFailure('A conta mudou. Reconecte o Google Drive.');
    }
    final current = await store.state();
    if (current.email != null && current.email != s.email) {
      throw const DriveFailure(
          'Esta base está vinculada a outra conta Google. Reconecte a conta original.');
    }
    return s;
  }

  Future<void> _account(DriveSession s) async {
    if (await drive.api.auth.account() != s.email) {
      throw const DriveFailure(
          'A conta mudou durante a sincronização. Os dados atuais foram mantidos.');
    }
  }

  void _clock() {
    final server = cloud.serverTime;
    if (server != null &&
        DateTime.now().toUtc().difference(server.toUtc()).inSeconds.abs() >
            300) {
      throw const DriveFailure(
          'Data e hora estão diferentes do Drive. Ative o horário automático no dispositivo antes de sincronizar.');
    }
  }

  Map<String, SyncRemoteFile> _unique(List<SyncRemoteFile> files) {
    final result = <String, SyncRemoteFile>{};
    for (final file in files) {
      final old = result[file.packet];
      if (old != null &&
          (old.copy.sha256Hash != file.copy.sha256Hash ||
              old.base != file.base ||
              old.kind != file.kind ||
              old.device != file.device)) {
        throw const DriveFailure(
            'Pacotes repetidos com conteúdo divergente. A sincronização foi interrompida.');
      }
      result[file.packet] = file;
    }
    return result;
  }

  Future<SyncPacket> _download(DriveSession s, SyncRemoteFile file) async {
    final bytes = await cloud.download(s, file);
    if (bytes.length != file.copy.size ||
        sha256.convert(bytes).toString() != file.copy.sha256Hash ||
        md5.convert(bytes).toString() != file.copy.md5Hash) {
      throw const DriveFailure(
          'Arquivo de sincronização incompleto ou corrompido.');
    }
    final p = SyncPacket.decode(bytes, await store.columns());
    if (p.id != file.packet ||
        p.base != file.base ||
        p.kind != file.kind ||
        p.device != file.device ||
        p.digest != file.copy.sha256Hash) {
      throw const DriveFailure(
          'Conteúdo e identidade da sincronização não correspondem.');
    }
    await _account(s);
    return p;
  }

  Future<List<SyncPacket>> _receive(DriveSession s, List<SyncRemoteFile> files,
      {bool joining = false}) async {
    final received = <SyncPacket>[];
    final applied = joining ? <String, String>{} : await store.applied();
    var bytes = 0;
    for (final file in _unique(files).values) {
      if (applied.containsKey(file.packet)) {
        if (applied[file.packet] != file.copy.sha256Hash) {
          throw const DriveFailure('Um pacote já recebido foi alterado.');
        }
        continue;
      }
      bytes += file.copy.size;
      if (bytes > maxSyncBytes) {
        throw const DriveFailure(
            'As alterações pendentes excedem 64 MB nesta operação.');
      }
      received.add(await _download(s, file));
    }
    return received;
  }

  Future<void> _send(DriveSession s, Map<String, SyncRemoteFile> files) async {
    await store.prepareUpload();
    // Uma fila imutável é mantida no SQLite até confirmação. Uma resposta
    // perdida é conciliada com a lista antes de qualquer novo envio.
    for (final p in await store.uploads()) {
      final existing = files[p.id];
      if (existing != null) {
        if (existing.base != p.base || existing.copy.sha256Hash != p.digest) {
          throw const DriveFailure(
              'O pacote pendente tem outra versão no Drive.');
        }
        await _download(s, existing);
      } else {
        await _account(s);
        _clock();
        await cloud.upload(s, p);
        await _account(s);
      }
      await store.ack(p);
    }
  }

  Future<void> listBases() => _run(() async {
        final s = await _session();
        final files = await cloud.list(s);
        await _account(s);
        _clock();
        final all = _unique(files);
        bases = all.values.where((f) => f.kind == 'genesis').toList()
          ..sort((a, b) => b.copy.createdAt.compareTo(a.copy.createdAt));
        if (bases.isEmpty) {
          message = 'Nenhuma base publicada. Inicie pelo Android.';
        }
      });
  Future<void> createBase() => _run(() async {
        if (!primaryAllowed) {
          throw const DriveFailure(
              'A base inicial deve ser publicada pelo Android.');
        }
        final s = await _session();
        final files = await cloud.list(s);
        await _account(s);
        _clock();
        if (files.any((f) => f.kind == 'genesis')) {
          throw const DriveFailure(
              'Já existe uma base no Drive. Receba essa base para continuar.');
        }
        await local.maintain(() => store.createBase(s.email),
            refreshScreens: false);
        await _send(s, _unique(files));
        await store.markCompleted();
        message =
            'Base do Android publicada. No Windows, receba a base do Drive.';
      });
  Future<void> join(SyncRemoteFile selected) => _run(() async {
        final s = await _session();
        final all = _unique(await cloud.list(s));
        await _account(s);
        _clock();
        final fresh = all[selected.packet];
        if (fresh == null ||
            fresh.kind != 'genesis' ||
            fresh.base != selected.base ||
            fresh.copy.sha256Hash != selected.copy.sha256Hash) {
          throw const DriveFailure(
              'A base mudou ou não está disponível. Atualize a lista.');
        }
        final genesis = all.values
            .where((f) => f.base == selected.base && f.kind == 'genesis');
        if (genesis.length != 1) {
          throw const DriveFailure(
              'A base tem mais de uma origem. Nenhum dado foi substituído.');
        }
        final packets = await _receive(
            s, all.values.where((f) => f.base == selected.base).toList(),
            joining: true);
        await _account(s);
        await local.maintain(() => store.apply(packets, joinEmail: s.email));
        await store.markCompleted();
        message =
            'Base recebida. Este dispositivo já pode enviar e receber alterações.';
      });
  Future<void> synchronize() => _run(() async {
        final s = await _session();
        final current = await store.state();
        if (current.base == null) {
          throw const DriveFailure(
              'Publique ou receba a base inicial primeiro.');
        }
        final all = _unique(await cloud.list(s));
        await _account(s);
        _clock();
        final files = all.values.where((f) => f.base == current.base).toList();
        if (files.where((f) => f.kind == 'genesis').length > 1) {
          throw const DriveFailure(
              'Esta base tem mais de uma origem. Nenhum dado foi alterado.');
        }
        final queued = await store.uploads();
        if (!files.any((f) => f.kind == 'genesis') &&
            !queued.any((p) => p.kind == 'genesis')) {
          throw const DriveFailure(
              'A origem da base não está no Drive. Os dados locais foram mantidos.');
        }
        final packets = await _receive(s, files);
        await _account(s);
        if (packets.isNotEmpty) {
          await local.maintain(() => store.apply(packets));
        }
        await _send(s, all);
        // Novas edições feitas durante a rede permanecem pendentes para o próximo
        // clique. last_sync_at informa a conclusão deste ciclo, não trabalho futuro.
        await store.markCompleted();
        message = 'Sincronização concluída.';
      });
  Future<void> recover(SyncEntry entry) => _run(() async {
        await local.maintain(() => store.recover(entry));
        message =
            'Versão recuperada neste dispositivo. Sincronize para enviá-la.';
      });
}
