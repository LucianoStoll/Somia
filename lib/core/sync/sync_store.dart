import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../database/financial_data.dart';
import '../database/local_backup_store.dart';
import 'sync_packet.dart';

class SyncState {
  const SyncState(this.base, this.email, this.device, this.lastSync,
      this.pending, this.uploads);
  final String? base, email, device;
  final DateTime? lastSync;
  final int pending, uploads;
}

class SyncStore {
  SyncStore(this.db, this.backups, {String? device}) : _device = device;
  final AppDatabase db;
  final LocalBackupStore backups;
  String? _device;
  Future<String> device() async {
    if (_device != null) return _device!;
    final f = File('${backups.directory.path}/somia-sync-device.txt');
    if (await f.exists()) {
      final value = (await f.readAsString()).trim();
      if (RegExp(r'^[a-zA-Z0-9-]{16,80}$').hasMatch(value)) {
        return _device = value;
      }
      throw const FormatException('Identidade deste dispositivo inválida.');
    }
    await backups.directory.create(recursive: true);
    final value = const Uuid().v4();
    final temporary = File('${f.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(f.path);
    return _device = value;
  }

  Future<SyncState> state() async {
    final row = await db
        .customSelect('SELECT * FROM sync_state WHERE id=1')
        .getSingle();
    final pending = (await db
            .customSelect('SELECT count(*) n FROM sync_outbox')
            .getSingle())
        .read<int>('n');
    final uploads = (await db
            .customSelect('SELECT count(*) n FROM sync_uploads')
            .getSingle())
        .read<int>('n');
    final time = row.readNullable<int>('last_sync_at');
    return SyncState(
        row.readNullable<String>('base_id'),
        row.readNullable<String>('email'),
        row.readNullable<String>('device_id'),
        time == null ? null : DateTime.fromMillisecondsSinceEpoch(time),
        pending,
        uploads);
  }

  Future<Map<String, Map<String, String>>> columns() => financialColumns(db);
  SyncEntry _entry(QueryRow row) {
    final payload = row.readNullable<String>('data');
    return SyncEntry.parse({
      'table': row.read<String>('table_name'),
      'id': row.read<String>('row_id'),
      'clock': row.read<int>('clock'),
      'device': row.read<String>('device_id'),
      'deleted': row.read<int>('is_deleted') == 1,
      'data': payload == null ? null : jsonDecode(payload),
    }, _columns!);
  }

  Map<String, Map<String, String>>? _columns;
  Future<void> _prepare() async {
    _columns ??= await columns();
  }

  Future<void> _write(String table, SyncEntry entry) => db.customStatement(
          'INSERT OR REPLACE INTO $table(table_name,row_id,clock,device_id,is_deleted,data) VALUES(?,?,?,?,?,?)',
          [
            entry.table,
            entry.id,
            entry.clock,
            entry.device,
            entry.deleted ? 1 : 0,
            entry.data == null ? null : jsonEncode(entry.data)
          ]);
  Future<void> _history(SyncEntry entry, String reason) => db.customStatement(
          '''INSERT INTO sync_history VALUES(?,?,?,?,?,?,?,?)
      ON CONFLICT(table_name,row_id,clock,device_id) DO UPDATE SET
      reason=CASE WHEN excluded.reason='conflict' THEN 'conflict' ELSE sync_history.reason END''',
          [
            entry.table,
            entry.id,
            entry.clock,
            entry.device,
            entry.deleted ? 1 : 0,
            entry.data == null ? null : jsonEncode(entry.data),
            reason,
            DateTime.now().millisecondsSinceEpoch
          ]);
  Future<void> _queue(SyncPacket packet) async {
    if (packet.encode().length > maxSyncBytes) {
      throw const FormatException('A sincronização excede 64 MB.');
    }
    await db.customStatement('INSERT INTO sync_uploads VALUES(?,?)',
        [packet.id, utf8.decode(packet.encode())]);
  }

  Future<SyncPacket> createBase(String email) async {
    await _prepare();
    final deviceId = await device();
    return db.transaction(() async {
      if ((await state()).base != null) {
        throw StateError('Este dispositivo já tem uma base vinculada.');
      }
      final base = const Uuid().v4();
      final rows = await readFinancial(db);
      final entries = [
        for (final t in financialTables)
          for (final row in rows[t]!.entries)
            SyncEntry(t, row.key, 0, deviceId, false, row.value)
      ];
      await db.customStatement(
          'UPDATE sync_state SET base_id=?,email=?,device_id=?,capture_enabled=1,clock=? WHERE id=1',
          [base, email, deviceId, DateTime.now().millisecondsSinceEpoch]);
      for (final entry in entries) {
        await _write('sync_versions', entry);
      }
      final packet =
          SyncPacket(const Uuid().v4(), base, deviceId, 'genesis', entries);
      await _queue(packet);
      return packet;
    });
  }

  Future<void> prepareUpload() async {
    await _prepare();
    await db.transaction(() async {
      if ((await state()).uploads > 0) return;
      final stateNow = await state();
      if (stateNow.base == null) return;
      final entries = (await db
              .customSelect(
                  'SELECT * FROM sync_outbox ORDER BY table_name,row_id')
              .get())
          .map(_entry)
          .toList();
      if (entries.isEmpty) return;
      await _queue(SyncPacket(const Uuid().v4(), stateNow.base!,
          stateNow.device!, 'changes', entries));
    });
  }

  Future<List<SyncPacket>> uploads() async {
    await _prepare();
    return (await db
            .customSelect('SELECT payload FROM sync_uploads ORDER BY rowid')
            .get())
        .map((r) => SyncPacket.decode(
            Uint8List.fromList(utf8.encode(r.read<String>('payload'))),
            _columns!))
        .toList();
  }

  Future<Map<String, String>> applied() async => {
        for (final row
            in await db.customSelect('SELECT * FROM sync_applied').get())
          row.read<String>('packet_id'): row.read<String>('digest'),
      };
  Future<void> ack(SyncPacket packet) => db.transaction(() async {
        for (final entry in packet.entries) {
          await db.customStatement(
              'DELETE FROM sync_outbox WHERE table_name=? AND row_id=? AND device_id=? AND clock<=?',
              [entry.table, entry.id, entry.device, entry.clock]);
        }
        await db.customStatement(
            'DELETE FROM sync_uploads WHERE packet_id=?', [packet.id]);
        await db.customStatement(
            'INSERT OR REPLACE INTO sync_applied VALUES(?,?)',
            [packet.id, packet.digest]);
      });

  /// Integrity, rows, versions, history and receipt markers commit together.
  Future<bool> apply(List<SyncPacket> packets, {String? joinEmail}) async {
    await _prepare();
    final deviceId = await device();
    if (packets.isEmpty) return false;
    final initial = joinEmail != null;
    if (initial) await backups.create(db, BackupKind.beforeRestore);
    return db.transaction(() async {
      final current = await state();
      if (initial &&
          (current.base != null ||
              packets.where((p) => p.kind == 'genesis').length != 1)) {
        throw const FormatException('Vínculo inicial inválido.');
      }
      final base = initial
          ? packets.firstWhere((p) => p.kind == 'genesis').base
          : current.base;
      if (base == null || packets.any((p) => p.base != base)) {
        throw const FormatException('As alterações pertencem a outra base.');
      }
      final seen = await applied();
      final versions = initial
          ? <String, SyncEntry>{}
          : {
              for (final row
                  in await db.customSelect('SELECT * FROM sync_versions').get())
                _entry(row).key: _entry(row),
            };
      final rows = initial
          ? <String, Map<String, Map<String, Object?>>>{
              for (final t in financialTables) t: {}
            }
          : await readFinancial(db);
      var changed = initial;
      var maxClock = (await db
              .customSelect('SELECT clock FROM sync_state WHERE id=1')
              .getSingle())
          .read<int>('clock');
      for (final packet in packets) {
        if (seen.containsKey(packet.id)) {
          if (seen[packet.id] != packet.digest) {
            throw const FormatException('Um pacote mudou de conteúdo.');
          }
          continue;
        }
        for (final entry in packet.entries) {
          if (entry.clock > DateTime.now().millisecondsSinceEpoch + 300000) {
            throw const FormatException(
                'Relógio divergente. Ajuste data e hora dos dispositivos antes de sincronizar.');
          }
          if (entry.clock > maxClock) maxClock = entry.clock;
          final previous = versions[entry.key];
          if (previous != null) {
            final order = entry.compare(previous);
            if (order == 0 && !entry.sameData(previous)) {
              throw const FormatException(
                  'Versões iguais com dados diferentes.');
            }
            if (order <= 0) {
              if (order < 0 && !entry.sameData(previous)) {
                await _history(entry, 'conflict');
              }
              continue;
            }
            if (!entry.sameData(previous)) await _history(previous, 'conflict');
          }
          if (previous == null || !entry.sameData(previous)) changed = true;
          versions[entry.key] = entry;
          if (entry.deleted) {
            rows[entry.table]!.remove(entry.id);
          } else {
            rows[entry.table]![entry.id] = entry.data!;
          }
        }
        seen[packet.id] = packet.digest;
      }
      if (changed) await replaceFinancial(db, rows);
      if (initial) {
        await db.customStatement('DELETE FROM sync_versions');
        await db.customStatement('DELETE FROM sync_outbox');
        await db.customStatement('DELETE FROM sync_applied');
        await db.customStatement(
            'UPDATE sync_state SET base_id=?,email=?,device_id=?,capture_enabled=1 WHERE id=1',
            [base, joinEmail, deviceId]);
      }
      for (final entry in versions.values) {
        await _write('sync_versions', entry);
      }
      for (final pair in seen.entries) {
        await db.customStatement(
            'INSERT OR REPLACE INTO sync_applied VALUES(?,?)',
            [pair.key, pair.value]);
      }
      await db.customStatement(
          'UPDATE sync_state SET clock=? WHERE id=1', [maxClock]);
      return changed;
    });
  }

  Future<void> markCompleted() => db.customStatement(
      'UPDATE sync_state SET last_sync_at=? WHERE id=1',
      [DateTime.now().millisecondsSinceEpoch]);
  Future<List<SyncEntry>> history() async {
    await _prepare();
    return (await db
            .customSelect(
                "SELECT * FROM sync_history WHERE reason='conflict' ORDER BY archived_at DESC LIMIT 100")
            .get())
        .map(_entry)
        .toList();
  }

  Future<void> recover(SyncEntry entry) async {
    await _prepare();
    await backups.create(db, BackupKind.beforeRestore);
    await db.transaction(() async {
      final s = await state();
      if (s.base == null) {
        throw const FormatException(
            'Vincule a base antes de recuperar uma versão.');
      }
      final exists = await db.customSelect(
          'SELECT * FROM sync_history WHERE table_name=? AND row_id=? AND clock=? AND device_id=?',
          variables: [
            Variable(entry.table),
            Variable(entry.id),
            Variable(entry.clock),
            Variable(entry.device)
          ]).get();
      if (exists.isEmpty || !_entry(exists.single).sameData(entry)) {
        throw const FormatException('Versão de histórico indisponível.');
      }
      final rows = await readFinancial(db);
      if (entry.deleted) {
        rows[entry.table]!.remove(entry.id);
      } else {
        rows[entry.table]![entry.id] = entry.data!;
      }
      final old = await db.customSelect(
          'SELECT * FROM sync_versions WHERE table_name=? AND row_id=?',
          variables: [Variable(entry.table), Variable(entry.id)]).get();
      if (old.isNotEmpty) await _history(_entry(old.single), 'conflict');
      await replaceFinancial(db, rows);
      final oldClock = (await db
              .customSelect('SELECT clock FROM sync_state WHERE id=1')
              .getSingle())
          .read<int>('clock');
      final now = DateTime.now().millisecondsSinceEpoch;
      final clock = oldClock >= now ? oldClock + 1 : now;
      final next = SyncEntry(
          entry.table, entry.id, clock, s.device!, entry.deleted, entry.data);
      await _write('sync_versions', next);
      await _write('sync_outbox', next);
      await db
          .customStatement('UPDATE sync_state SET clock=? WHERE id=1', [clock]);
    });
  }
}
