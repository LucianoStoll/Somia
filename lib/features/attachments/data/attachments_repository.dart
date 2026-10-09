import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../transactions/domain/movement_management.dart';

class LocalAttachment {
  const LocalAttachment(this.id, this.name, this.size);
  final String id, name;
  final int size;
}

class AttachmentsRepository {
  AttachmentsRepository(this.db);
  final AppDatabase db;
  static const maxBytes = 20 * 1024 * 1024;
  static String safeName(String name) {
    final clean = name
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_')
        .trim();
    if (clean.isEmpty || clean == '.' || clean == '..' || clean.length > 240) {
      throw const FormatException('Nome de arquivo inválido ou muito longo.');
    }
    return clean;
  }

  Future<void> _active(MovementReference owner) async {
    final rows = await db.customSelect(
        'SELECT id FROM ${owner.table} WHERE id=? AND deleted_at IS NULL',
        variables: [Variable.withString(owner.id)]).get();
    if (rows.isEmpty) throw StateError('O lançamento não está disponível.');
  }

  Future<List<LocalAttachment>> list(MovementReference owner) async {
    await _active(owner);
    final rows = await db.customSelect(
        'SELECT id,name,size FROM local_attachments WHERE owner_table=? AND owner_id=? ORDER BY created_at,id',
        variables: [
          Variable.withString(owner.table),
          Variable.withString(owner.id)
        ]).get();
    return rows
        .map((r) => LocalAttachment(
            r.read<String>('id'), r.read<String>('name'), r.read<int>('size')))
        .toList();
  }

  Future<void> add(MovementReference owner, String name, Uint8List bytes) =>
      db.transaction(() async {
        await _active(owner);
        final filename = safeName(name);
        if (bytes.isEmpty || bytes.length > maxBytes) {
          throw const FormatException(
              'Selecione um arquivo não vazio de até 20 MB.');
        }
        await db.customStatement(
            'INSERT INTO local_attachments VALUES(?,?,?,?,?,?,?,?)', [
          const Uuid().v4(),
          owner.table,
          owner.id,
          filename,
          bytes.length,
          crypto.sha256.convert(bytes).toString(),
          bytes,
          DateTime.now().toUtc().millisecondsSinceEpoch
        ]);
      });
  Future<Uint8List> read(MovementReference owner, String id) async {
    await _active(owner);
    final row = await db.customSelect(
        'SELECT * FROM local_attachments WHERE id=? AND owner_table=? AND owner_id=?',
        variables: [
          Variable.withString(id),
          Variable.withString(owner.table),
          Variable.withString(owner.id)
        ]).getSingle();
    final bytes = row.read<Uint8List>('content');
    if (bytes.length != row.read<int>('size') ||
        crypto.sha256.convert(bytes).toString() != row.read<String>('sha256')) {
      throw const FormatException(
          'Arquivo corrompido. Exclua este anexo e importe uma cópia íntegra.');
    }
    return bytes;
  }

  Future<void> remove(MovementReference owner, String id) =>
      db.transaction(() async {
        await _active(owner);
        await db.customStatement(
            'DELETE FROM local_attachments WHERE id=? AND owner_table=? AND owner_id=?',
            [id, owner.table, owner.id]);
      });
  static Future<void> validate(AppDatabase db) async {
    // Read one payload at a time: a backup can hold many 20 MB files.
    final ids = await db.customSelect('SELECT id FROM local_attachments').get();
    for (final id in ids) {
      final row = await db.customSelect(
          'SELECT * FROM local_attachments WHERE id=?',
          variables: [Variable.withString(id.read<String>('id'))]).getSingle();
      final bytes = row.read<Uint8List>('content');
      if (safeName(row.read<String>('name')) != row.read<String>('name') ||
          bytes.isEmpty ||
          bytes.length > maxBytes ||
          bytes.length != row.read<int>('size') ||
          crypto.sha256.convert(bytes).toString() !=
              row.read<String>('sha256')) {
        throw const FormatException('O backup contém um anexo inválido.');
      }
    }
  }
}
