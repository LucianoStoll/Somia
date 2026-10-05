import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'app_database.dart';
import 'financial_data.dart';
import 'schema_v11.dart';
import 'local_backup_store.dart';

/// Snapshots consistentes e restauração atômica na conexão em uso.
/// Mantém o fluxo legado de restauração pendente para bases já agendadas.
abstract final class BackupService {
  static const _databaseName = 'finapp.sqlite';
  static const _pendingName = 'finapp.restore.pending';
  static const _previousName = 'finapp.before-restore.sqlite';
  static const _failureName = 'finapp.restore.failed';
  static Future<Map<String, Set<String>>>? _schemaColumns;

  static Future<Map<String, Set<String>>> _expectedColumns() =>
      _schemaColumns ??= () async {
        final reference = AppDatabase(NativeDatabase.memory());
        try {
          final tables = await reference
              .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
              .get();
          final result = <String, Set<String>>{};
          for (final table in tables) {
            final name = table.read<String>('name');
            final columns = await reference
                .customSelect('PRAGMA table_info("$name")')
                .get();
            result[name] = columns
                .map((row) =>
                    '${row.read<String>('name')}:${row.read<String>('type')}')
                .toSet();
          }
          return result;
        } finally {
          await reference.close();
        }
      }();

  static Future<bool> hasRestoreFailure(Directory directory) =>
      File(p.join(directory.path, _failureName)).exists();

  static Future<void> recordRestoreFailure(Directory directory) async {
    try {
      await File(p.join(directory.path, _failureName))
          .writeAsString('failed', flush: true);
    } catch (_) {
      // Falta de espaço não pode impedir abrir a base que foi preservada.
    }
  }

  static Future<void> _clearRestoreFailure(Directory directory) async {
    try {
      final file = File(p.join(directory.path, _failureName));
      if (await file.exists()) await file.delete();
    } catch (_) {
      // O marcador não altera o resultado de uma restauração já concluída.
    }
  }

  static Future<bool> hasPendingRestore(Directory directory) =>
      File(p.join(directory.path, _pendingName)).exists();

  static Future<void> cancelPendingRestore(Directory directory) async {
    final file = File(p.join(directory.path, _pendingName));
    if (await file.exists()) await file.delete();
    await _clearRestoreFailure(directory);
  }

  static Future<void> prepareForOpen(Directory directory) async {
    try {
      await applyPendingRestore(directory);
    } catch (_) {
      if (!await File(p.join(directory.path, _databaseName)).exists()) rethrow;
      await recordRestoreFailure(directory);
    }
  }

  static Future<Uint8List> export(
      AppDatabase database, Directory directory) async {
    await directory.create(recursive: true);
    final snapshot = File(p.join(
        directory.path, 'finapp.export.${const Uuid().v4()}.tmp.sqlite'));
    try {
      // SQLite cria uma cópia consistente mesmo se houver WAL ativo.
      await database.customStatement('VACUUM INTO ?', [snapshot.path]);
      return await snapshot.readAsBytes();
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  /// Apenas dados são importados. Schema e triggers vêm da base operacional,
  /// nunca do arquivo externo. O rollback inclui dados e triggers.
  static Future<void> restoreOpen(
      AppDatabase database, LocalBackupStore store, Uint8List bytes) async {
    final candidate = await _checkedCandidate(bytes, store.directory);
    var attached = false;
    var committed = false;
    try {
      final columns = await _expectedColumns();
      await store.create(database, BackupKind.beforeRestore);
      // Evita que um agendamento antigo sobreponha esta restauração ao abrir.
      await cancelPendingRestore(store.directory);
      await database.customStatement(
          'ATTACH DATABASE ? AS restore_source', [candidate.path]);
      attached = true;
      await database.transaction(() async {
        await database.customStatement('PRAGMA defer_foreign_keys = ON');
        final triggers = await database
            .customSelect(
                "SELECT name, sql FROM main.sqlite_master WHERE type = 'trigger'")
            .get();
        // Regras de novos lançamentos não se aplicam ao histórico: contas e
        // categorias podem ter sido arquivadas depois de usadas.
        for (final trigger in triggers) {
          final name = trigger.read<String>('name').replaceAll('"', '""');
          await database.customStatement('DROP TRIGGER main."$name"');
        }
        for (final table in financialTables) {
          await database.customStatement('DELETE FROM main."$table"');
        }
        for (final entry in columns.entries.where((e) => financialTables.contains(e.key))) {
          final names = entry.value
              .map((column) => '"${column.split(':').first}"')
              .join(', ');
          await database
              .customStatement('INSERT INTO main."${entry.key}" ($names) '
                  'SELECT $names FROM restore_source."${entry.key}"');
        }
        final violations =
            await database.customSelect('PRAGMA main.foreign_key_check').get();
        if (violations.isNotEmpty) {
          throw const FormatException('O backup contém vínculos inválidos.');
        }
        // Uma restauração explícita desvincula a base. Nunca publicar o passado
        // restaurado como exclusões/edições de uma sessão de sync anterior.
        for (final table in columns.keys.where((n) => n.startsWith('sync_'))) {
          await database.customStatement('DELETE FROM "$table"');
        }
        await database.customStatement(schemaV11[1]);
        for (final trigger in triggers) {
          await database.customStatement(trigger.read<String>('sql'));
        }
      });
      committed = true;
      await _clearRestoreFailure(store.directory);
    } finally {
      try {
        if (attached) {
          try {
            await database.customStatement('DETACH DATABASE restore_source');
          } catch (_) {
            if (!committed) rethrow;
            // Limpeza não pode transformar um commit concluído em falha.
          }
        }
      } finally {
        try {
          if (await candidate.exists()) await candidate.delete();
        } catch (_) {
          // O temporário não entra na lista de cópias nem é aplicado ao abrir.
        }
      }
    }
  }

  static Future<void> stageRestore(Uint8List bytes, Directory directory) async {
    final candidate = await _checkedCandidate(bytes, directory);
    try {
      final pending = File(p.join(directory.path, _pendingName));
      if (await pending.exists()) await pending.delete();
      await candidate.rename(pending.path);
      await _clearRestoreFailure(directory);
    } finally {
      if (await candidate.exists()) await candidate.delete();
    }
  }

  static Future<void> validateBytes(
      Uint8List bytes, Directory directory) async {
    final candidate = await _checkedCandidate(bytes, directory);
    await candidate.delete();
  }

  static Future<File> _checkedCandidate(
      Uint8List bytes, Directory directory) async {
    if (bytes.length < 100 ||
        String.fromCharCodes(bytes.take(15)) != 'SQLite format 3') {
      throw const FormatException('O arquivo não é um banco SQLite válido.');
    }
    final schemaVersion = ByteData.sublistView(bytes).getUint32(60, Endian.big);
    if (schemaVersion < 1 || schemaVersion > AppDatabase.currentSchemaVersion) {
      throw const FormatException(
          'Versão do backup incompatível com este aplicativo.');
    }
    await directory.create(recursive: true);
    final candidate = File(p.join(
        directory.path, 'finapp.restore.${const Uuid().v4()}.check.sqlite'));
    try {
      await candidate.writeAsBytes(bytes, flush: true);
      await _validate(candidate);
      return candidate;
    } catch (_) {
      if (await candidate.exists()) await candidate.delete();
      rethrow;
    }
  }

  static Future<void> _validate(File file) async {
    final database = AppDatabase(NativeDatabase(file));
    try {
      final integrity =
          await database.customSelect('PRAGMA integrity_check').get();
      if (integrity.length != 1 ||
          integrity.single.read<String>('integrity_check') != 'ok') {
        throw const FormatException('O backup está corrompido.');
      }
      final violations =
          await database.customSelect('PRAGMA foreign_key_check').get();
      if (violations.isNotEmpty) {
        throw const FormatException('O backup contém vínculos inválidos.');
      }
      final tables = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table'",
          )
          .get();
      final names = tables.map((row) => row.read<String>('name')).toSet();
      if (!names.containsAll(
          ['accounts', 'categories', 'transactions', 'transfers'])) {
        throw const FormatException('O arquivo não contém os dados do Somia.');
      }
      for (final entry in (await _expectedColumns()).entries) {
        if (!names.contains(entry.key)) {
          throw const FormatException('O backup está incompleto.');
        }
        final columns = await database
            .customSelect('PRAGMA table_info("${entry.key}")')
            .get();
        final actual = columns
            .map((row) =>
                '${row.read<String>('name')}:${row.read<String>('type')}')
            .toSet();
        if (!actual.containsAll(entry.value)) {
          throw const FormatException(
              'A estrutura do backup não é compatível com o Somia.');
        }
      }
    } finally {
      await database.close();
    }
  }

  static Future<void> applyPendingRestore(Directory directory) async {
    final pending = File(p.join(directory.path, _pendingName));
    if (!await pending.exists()) return;
    final current = File(p.join(directory.path, _databaseName));
    final previous = File(p.join(directory.path, _previousName));

    // Recupera uma interrupção entre mover a base atual e instalar a nova.
    if (!await current.exists() && await previous.exists()) {
      await previous.rename(current.path);
      for (final suffix in ['-wal', '-shm']) {
        final oldSidecar = File('${previous.path}$suffix');
        if (await oldSidecar.exists()) {
          await oldSidecar.rename('${current.path}$suffix');
        }
      }
    }
    await _validate(pending);
    final restored = AppDatabase(NativeDatabase(pending));
    try {
      await restored.transaction(() async {
        for (final table in ['sync_outbox','sync_versions','sync_history','sync_applied','sync_uploads','sync_state']) {
          await restored.customStatement('DELETE FROM "$table"');
        }
        await restored.customStatement(schemaV11[1]);
      });
    } finally {
      await restored.close();
    }
    // AppDatabase.open chama este método antes de abrir a conexão operacional.
    // VACUUM inclui o WAL e preserva inclusive mudanças feitas após agendar.
    if (await current.exists()) {
      final database = AppDatabase(NativeDatabase(current));
      try {
        await LocalBackupStore(directory)
            .create(database, BackupKind.beforeRestore);
      } finally {
        await database.close();
      }
    }
    for (final suffix in ['', '-wal', '-shm']) {
      final old = File('${previous.path}$suffix');
      if (await old.exists()) await old.delete();
    }
    var movedCurrent = false;
    try {
      if (await current.exists()) {
        await current.rename(previous.path);
        movedCurrent = true;
      }
      for (final suffix in ['-wal', '-shm']) {
        final sidecar = File('${current.path}$suffix');
        if (await sidecar.exists()) {
          await sidecar.rename('${previous.path}$suffix');
        }
      }
      await pending.rename(current.path);
    } catch (_) {
      if (movedCurrent && !await current.exists()) {
        await previous.rename(current.path);
      }
      for (final suffix in ['-wal', '-shm']) {
        final oldSidecar = File('${previous.path}$suffix');
        if (await oldSidecar.exists()) {
          await oldSidecar.rename('${current.path}$suffix');
        }
      }
      rethrow;
    }
    await _clearRestoreFailure(directory);
  }
}
