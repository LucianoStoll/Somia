import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

import '../database/backup_manager.dart';
import '../drive/drive_backup.dart';
import '../drive/drive_backup_manager.dart';
import 'sync_store.dart';
import 'sync_packet.dart';
import 'drive_sync_api.dart';

class SyncManager extends ChangeNotifier {
  SyncManager(
    this.local,
    this.drive,
    this.store,
    this.cloud, {
    required this.primaryAllowed,
  });
  final BackupManager local;
  final DriveBackupManager drive;
  final SyncStore store;
  final SyncCloud cloud;
  final bool primaryAllowed;
  SyncState? state;
  List<SyncRemoteFile> bases = const [];
  List<SyncEntry> history = const [];
  bool busy = false;
  bool deferred = false;
  bool needsJoin = false;
  String? listedRevision, listedEmail;
  int completedSyncCycles = 0;
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

  void observe(SyncState next) {
    final old = state;
    state = next;
    if (old?.base != next.base ||
        old?.pending != next.pending ||
        old?.uploads != next.uploads ||
        old?.lastSync != next.lastSync) {
      _notify();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy || drive.busy || local.busy) return;
    busy = true;
    deferred = false;
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
        'Esta base está vinculada a outra conta Google. Reconecte a conta original.',
      );
    }
    return s;
  }

  Future<void> _account(DriveSession s) async {
    if (await drive.api.auth.account() != s.email) {
      throw const DriveFailure(
        'A conta mudou durante a sincronização. Os dados atuais foram mantidos.',
      );
    }
  }

  void _clock() {
    final server = cloud.serverTime;
    if (server != null &&
        DateTime.now().toUtc().difference(server.toUtc()).inSeconds.abs() >
            300) {
      throw const DriveFailure(
        'Data e hora estão diferentes do Drive. Ative o horário automático no dispositivo antes de sincronizar.',
      );
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
          'Pacotes repetidos com conteúdo divergente. A sincronização foi interrompida.',
        );
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
        'Arquivo de sincronização incompleto ou corrompido.',
      );
    }
    final p = SyncPacket.decode(bytes, await store.columns());
    if (p.id != file.packet ||
        p.base != file.base ||
        p.kind != file.kind ||
        p.device != file.device ||
        p.digest != file.copy.sha256Hash) {
      throw const DriveFailure(
        'Conteúdo e identidade da sincronização não correspondem.',
      );
    }
    await _account(s);
    return p;
  }

  Future<List<SyncPacket>> _receive(
    DriveSession s,
    List<SyncRemoteFile> files, {
    bool joining = false,
  }) async {
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
          'As alterações pendentes excedem 64 MB nesta operação.',
        );
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
            'O pacote pendente tem outra versão no Drive.',
          );
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

  String _revision(Iterable<SyncRemoteFile> files) {
    final rows = files
        .map((f) => '${f.packet}:${f.base}:${f.kind}:${f.copy.sha256Hash}')
        .toSet()
        .toList()
      ..sort();
    return sha256.convert(utf8.encode(rows.join('\n'))).toString();
  }

  Future<List<SyncRemoteFile>> _activeBases(
    DriveSession session,
    Map<String, SyncRemoteFile> all,
  ) async {
    final retired = <String>{};
    final origins = all.values.where((f) => f.isBase).toList();
    for (final file in origins.where((f) => f.kind == 'replacement')) {
      final packet = await _download(session, file);
      if (!packet.replaces.every((id) => origins.any((f) => f.base == id))) {
        throw const DriveFailure(
          'A proteção da base anterior está incompleta. Nenhum dado foi alterado.',
        );
      }
      retired.addAll(packet.replaces);
    }
    final active = origins.where((f) => !retired.contains(f.base)).toList();
    if (origins.isNotEmpty && active.length != 1) {
      throw const DriveFailure(
        'Existem publicações concorrentes no Drive. A sincronização foi interrompida e as bases foram preservadas para recuperação.',
      );
    }
    if (active.length == 1 && active.single.kind == 'replacement') {
      final packet = await _download(session, active.single);
      final ancestors =
          all.values.where((f) => packet.replaces.contains(f.base));
      if (_revision(ancestors) != packet.remoteRevision) {
        throw const DriveFailure(
            'A base anterior recebeu alterações durante a substituição. A sincronização foi interrompida; todas as versões foram preservadas para recuperação.');
      }
    }
    return active;
  }

  Future<void> _rememberBases(
    DriveSession session,
    Map<String, SyncRemoteFile> all,
  ) async {
    bases = await _activeBases(session, all);
    listedRevision = _revision(all.values);
    listedEmail = session.email;
    final current = await store.state();
    needsJoin = current.base != null &&
        bases.isNotEmpty &&
        bases.single.base != current.base;
  }

  Future<void> listBases() => _run(() async {
        final s = await _session();
        final all = _unique(await cloud.list(s));
        await _account(s);
        _clock();
        await _rememberBases(s, all);
        if (bases.isEmpty) {
          message = 'Nenhuma base publicada. Inicie pelo Android.';
        }
      });

  Future<void> replaceBase({String? expectedRevision, String? expectedEmail}) =>
      _run(() async {
        if (!primaryAllowed) {
          throw const DriveFailure('Publique a nova base pelo Android.');
        }
        final s = await _session();
        final all = _unique(await cloud.list(s));
        await _account(s);
        _clock();
        final pending = (await store.uploads()).where(
          (p) => p.kind == 'replacement',
        );
        if (pending.isNotEmpty) {
          await _finishReplacement(s, pending.single);
          return;
        }
        if ((expectedEmail ?? listedEmail) != s.email ||
            (expectedRevision ?? listedRevision) != _revision(all.values) ||
            bases.isEmpty) {
          throw const DriveFailure(
            'A base mudou desde a confirmação. Busque as bases no Drive e confirme novamente.',
          );
        }
        await _activeBases(s, all);
        // The immutable old packets stay in Drive, including every change packet.
        // Validate that this recovery set can be downloaded before publication.
        await _receive(s, all.values.toList(), joining: true);
        final packet = await local.maintain(
          () => store.stageReplacement(
            all.values
                .where((f) => f.isBase)
                .map((f) => f.base)
                .toSet()
                .toList(),
            listedRevision!,
            s.email,
          ),
          refreshScreens: false,
        );
        await _finishReplacement(s, packet);
      });

  Future<void> _finishReplacement(DriveSession s, SyncPacket packet) async {
    if (packet.publicationEmail != s.email) {
      throw const DriveFailure(
        'A publicação pendente pertence a outra conta Google. Reconecte a conta original.',
      );
    }
    final all = _unique(await cloud.list(s));
    await _account(s);
    _clock();
    if (!all.containsKey(packet.id)) {
      if (_revision(all.values) != packet.remoteRevision) {
        throw const DriveFailure(
          'O Drive mudou durante a publicação. A base atual foi preservada. Cancele a publicação pendente, busque as bases e confirme novamente.',
        );
      }
      await cloud.upload(s, packet);
    }
    // Read back and verify before changing the local link. A lost response can
    // safely be retried using the same persisted packet id.
    final published = _unique(await cloud.list(s));
    final file = published[packet.id];
    if (file == null || (await _download(s, file)).digest != packet.digest) {
      throw const DriveFailure(
        'Não foi possível confirmar a publicação. Tente novamente.',
      );
    }
    final active = await _activeBases(s, published);
    if (active.single.base != packet.base) {
      throw const DriveFailure(
        'Outra base foi publicada. Receba a base atual após conferir seus dados.',
      );
    }
    await _account(s);
    await local.maintain(
      () => store.activateReplacement(packet, s.email),
      refreshScreens: false,
    );
    await store.markCompleted();
    needsJoin = false;
    await _rememberBases(s, published);
    message =
        'Base substituída com proteção. Atualize o Somia no Windows e receba a nova base. As bases anteriores permanecem preservadas no Drive.';
  }

  Future<void> cancelReplacement() => _run(() async {
        final s = await _session();
        final all = _unique(await cloud.list(s));
        await _account(s);
        for (final packet in (await store.uploads()).where(
          (p) => p.kind == 'replacement',
        )) {
          if (packet.publicationEmail != s.email ||
              all.containsKey(packet.id)) {
            throw const DriveFailure(
              'Esta publicação pode já estar no Drive. Retome a publicação para confirmar o resultado.',
            );
          }
          await store.discardReplacement(packet.id);
        }
        message =
            'Publicação pendente cancelada. Busque as bases para confirmar uma nova substituição.';
      });
  Future<void> createBase() => _run(() async {
        if (!primaryAllowed) {
          throw const DriveFailure(
            'A base inicial deve ser publicada pelo Android.',
          );
        }
        final s = await _session();
        final files = await cloud.list(s);
        await _account(s);
        _clock();
        if (files.any((f) => f.isBase)) {
          await _rememberBases(s, _unique(files));
          throw const DriveFailure(
            'Já existe uma base no Drive. Receba essa base ou escolha substituí-la pelos dados deste Android.',
          );
        }
        await local.maintain(
          () => store.createBase(s.email),
          refreshScreens: false,
        );
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
            !fresh.isBase ||
            fresh.base != selected.base ||
            fresh.copy.sha256Hash != selected.copy.sha256Hash) {
          throw const DriveFailure(
            'A base mudou ou não está disponível. Atualize a lista.',
          );
        }
        final active = await _activeBases(s, all);
        if (!active.any((f) => f.packet == selected.packet)) {
          throw const DriveFailure(
            'Esta base foi substituída. Busque a base atual no Drive.',
          );
        }
        final genesis = all.values.where(
          (f) => f.base == selected.base && f.isBase,
        );
        if (genesis.length != 1) {
          throw const DriveFailure(
            'A base tem mais de uma origem. Nenhum dado foi substituído.',
          );
        }
        final packets = await _receive(
          s,
          all.values.where((f) => f.base == selected.base).toList(),
          joining: true,
        );
        await _account(s);
        await local.maintain(() => store.apply(packets, joinEmail: s.email));
        await store.markCompleted();
        needsJoin = false;
        message =
            'Base recebida. Este dispositivo já pode enviar e receber alterações.';
      });
  Future<void> synchronize({
    bool automatic = false,
    bool Function()? canApply,
  }) =>
      _run(() async {
        if (automatic && !(canApply?.call() ?? false)) {
          deferred = true;
          return;
        }
        final s = await _session();
        if ((await store.uploads()).any((p) => p.kind == 'replacement')) {
          throw const DriveFailure(
            'Existe uma substituição pendente. Retome ou cancele a publicação na tela de sincronização.',
          );
        }
        final current = await store.state();
        if (current.base == null) {
          throw const DriveFailure(
              'Publique ou receba a base inicial primeiro.');
        }
        final all = _unique(await cloud.list(s));
        await _account(s);
        _clock();
        await _rememberBases(s, all);
        if (needsJoin) {
          throw const DriveFailure(
            'A base do Drive foi substituída. Receba a nova base para continuar. Seus dados locais e pendências foram preservados.',
          );
        }
        final files = all.values.where((f) => f.base == current.base).toList();
        if (files.where((f) => f.isBase).length > 1) {
          throw const DriveFailure(
            'Esta base tem mais de uma origem. Nenhum dado foi alterado.',
          );
        }
        final queued = await store.uploads();
        if (!files.any((f) => f.isBase) && !queued.any((p) => p.isBase)) {
          throw const DriveFailure(
            'A origem da base não está no Drive. Os dados locais foram mantidos.',
          );
        }
        final packets = await _receive(s, files);
        await _account(s);
        if (automatic && !(canApply?.call() ?? false)) {
          deferred = true;
          return;
        }
        if (packets.isNotEmpty) {
          await local.maintain(
            () async {
              if (automatic && !(canApply?.call() ?? false)) {
                deferred = true;
                return false;
              }
              return store.apply(packets);
            },
            preserveLocation: automatic,
            shouldRefresh: (changed) => changed,
          );
        }
        if (deferred) return;
        final latest = _unique(await cloud.list(s));
        await _rememberBases(s, latest);
        if (needsJoin) {
          throw const DriveFailure(
            'A base foi substituída durante a sincronização. Receba a nova base.',
          );
        }
        await _send(s, latest);
        // Novas edições feitas durante a rede permanecem pendentes para o próximo
        // ciclo. last_sync_at informa a conclusão deste ciclo, não trabalho futuro.
        await store.markCompleted();
        completedSyncCycles++;
        message = 'Sincronização concluída.';
      });
  Future<void> recover(SyncEntry entry) => _run(() async {
        await local.maintain(() => store.recover(entry));
        message =
            'Versão recuperada neste dispositivo. Sincronize para enviá-la.';
      });
}
