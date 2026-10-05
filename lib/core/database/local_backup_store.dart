import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'app_database.dart';
import 'backup_service.dart';

enum BackupKind { automatic, manual, beforeRestore, beforeMigration }

class LocalBackupCopy {
  const LocalBackupCopy(this.file, this.kind, this.createdAt, this.size);
  final File file;
  final BackupKind kind;
  final DateTime createdAt;
  final int size;
}

class LocalBackupStore {
  LocalBackupStore(this.directory, {DateTime Function()? clock})
      : clock = clock ?? DateTime.now;
  final Directory directory;
  final DateTime Function() clock;
  Directory get folder => Directory(p.join(directory.path, 'somia-backups'));

  Future<List<LocalBackupCopy>> list() async {
    if (!await folder.exists()) return [];
    final result = <LocalBackupCopy>[];
    await for (final entity in folder.list()) {
      if (entity is! File) continue;
      final match =
          RegExp(r'^(automatic|manual|beforeRestore|beforeMigration)-(\d+)-[a-f0-9-]+\.sqlite$')
              .firstMatch(p.basename(entity.path));
      if (match == null) continue;
      final timestamp = int.tryParse(match.group(2)!);
      if (timestamp == null) continue;
      result.add(LocalBackupCopy(
          entity,
          BackupKind.values.byName(match.group(1)!),
          DateTime.fromMicrosecondsSinceEpoch(timestamp),
          await entity.length()));
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<LocalBackupCopy?> daily(AppDatabase database) async {
    final now = clock();
    for (final copy in await list()) {
      if (copy.kind != BackupKind.automatic) continue;
      final date = copy.createdAt;
      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        try {
          await BackupService.validateBytes(
              await copy.file.readAsBytes(), directory);
          await _prune(copy);
          return null;
        } catch (_) {
          // Uma cópia corrompida não impede criar uma proteção válida hoje.
        }
      }
    }
    return create(database, BackupKind.automatic);
  }

  Future<LocalBackupCopy> create(AppDatabase database, BackupKind kind) async {
    await folder.create(recursive: true);
    final now = clock();
    final bytes = await BackupService.export(database, directory);
    await BackupService.validateBytes(bytes, directory);
    final file = File(p.join(folder.path,
        '${kind.name}-${now.microsecondsSinceEpoch}-${const Uuid().v4()}.sqlite'));
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    final copy = LocalBackupCopy(file, kind, now, bytes.length);
    await _prune(copy);
    return copy;
  }

  Future<void> _prune(LocalBackupCopy newest) async {
    // Retenção só depois que a cópia nova está validada e salva.
    if (newest.kind != BackupKind.manual) {
      final copies = (await list())
          .where(
              (c) => c.kind == newest.kind && c.file.path != newest.file.path)
          .toList();
      for (final old in copies.skip(2)) {
        await old.file.delete();
      }
    }
  }
}
