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

  static void validateMetadata(Map<String, Object?> row) {
    if (!['transactions', 'transfers', 'card_entries']
            .contains(row['owner_table']) ||
        row['owner_id'] is! String ||
        (row['owner_id'] as String).isEmpty ||
        row['name'] is! String ||
        safeName(row['name'] as String) != row['name'] ||
        row['size'] is! int ||
        (row['size'] as int) <= 0 ||
        (row['size'] as int) > maxBytes ||
        row['sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(row['sha256'] as String)) {
      throw const FormatException('Metadados de anexo inválidos.');
    }
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
        'SELECT id,name,size FROM attachment_manifest WHERE owner_table=? AND owner_id=? ORDER BY created_at,id',
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
        final filename = safeName(name),
            hash = crypto.sha256.convert(bytes).toString();
        await cache(hash, bytes.length, bytes);
        await db.customStatement(
            'INSERT INTO attachment_manifest VALUES(?,?,?,?,?,?,?)', [
          const Uuid().v4(),
          owner.table,
          owner.id,
          filename,
          bytes.length,
          hash,
          DateTime.now().toUtc().millisecondsSinceEpoch
        ]);
      });
  static void checkBytes(String hash, int size, Uint8List bytes) {
    if (bytes.isEmpty ||
        bytes.length > maxBytes ||
        bytes.length != size ||
        crypto.sha256.convert(bytes).toString() != hash) {
      throw const FormatException(
          'Anexo incompleto ou corrompido. Sincronize novamente ou importe uma cópia íntegra.');
    }
  }

  Future<void> cache(String hash, int size, Uint8List bytes) async {
    checkBytes(hash, size, bytes);
    await db.customStatement(
        'INSERT OR REPLACE INTO attachment_blobs VALUES(?,?,?,0)',
        [hash, size, bytes]);
  }

  Future<bool> hasCached(String hash, int size) async {
    final rows = await db.customSelect(
        'SELECT size,needs_refresh FROM attachment_blobs WHERE id=?',
        variables: [Variable.withString(hash)]).get();
    return rows.isNotEmpty &&
        rows.single.read<int>('size') == size &&
        rows.single.read<int>('needs_refresh') == 0;
  }

  Future<Uint8List?> cached(String hash, int size) async {
    final rows = await db.customSelect(
        'SELECT content,needs_refresh FROM attachment_blobs WHERE id=?',
        variables: [Variable.withString(hash)]).get();
    if (rows.isEmpty) return null;
    final bytes = rows.single.read<Uint8List>('content');
    try {
      checkBytes(hash, size, bytes);
    } on FormatException {
      await db.customStatement(
          'UPDATE attachment_blobs SET needs_refresh=1 WHERE id=?', [hash]);
      rethrow;
    }
    if (rows.single.read<int>('needs_refresh') == 1) {
      await db.customStatement(
          'UPDATE attachment_blobs SET needs_refresh=0 WHERE id=?', [hash]);
    }
    return bytes;
  }

  Future<Uint8List> read(MovementReference owner, String id) async {
    await _active(owner);
    final row = await db.customSelect(
        'SELECT * FROM attachment_manifest WHERE id=? AND owner_table=? AND owner_id=?',
        variables: [
          Variable.withString(id),
          Variable.withString(owner.table),
          Variable.withString(owner.id)
        ]).getSingle();
    validateMetadata(row.data);
    final bytes =
        await cached(row.read<String>('sha256'), row.read<int>('size'));
    if (bytes == null) {
      throw const FormatException(
          'O arquivo ainda não está disponível. Conclua a sincronização dos anexos.');
    }
    return bytes;
  }

  Future<void> remove(MovementReference owner, String id) =>
      db.transaction(() async {
        await _active(owner);
        await db.customStatement(
            'DELETE FROM attachment_manifest WHERE id=? AND owner_table=? AND owner_id=?',
            [id, owner.table, owner.id]);
        await collectUnused();
      });
  Future<void> purgeOwner(String table, String id) async {
    await db.customStatement(
        'DELETE FROM attachment_manifest WHERE owner_table=? AND owner_id=?',
        [table, id]);
    await collectUnused();
  }

  Future<void> collectUnused() async {
    // Immutable pending uploads can still reference a removed file. Keep it until ack.
    await db.customStatement(
        '''DELETE FROM attachment_blobs WHERE id NOT IN (SELECT sha256 FROM attachment_manifest)
      AND NOT EXISTS(SELECT 1 FROM sync_uploads u WHERE instr(u.payload,attachment_blobs.id)>0)''');
  }

  static Future<void> validate(AppDatabase db) async {
    final repo = AttachmentsRepository(db);
    // Older sync generations could leave inaccessible files without an owner.
    // Preserve those archives locally, but never attach them to another base.
    for (final id
        in await db.customSelect('SELECT id FROM local_attachments').get()) {
      final row = await db.customSelect(
          'SELECT * FROM local_attachments WHERE id=?',
          variables: [Variable.withString(id.read<String>('id'))]).getSingle();
      if (safeName(row.read<String>('name')) != row.read<String>('name')) {
        throw const FormatException('Arquivo legado inválido.');
      }
      checkBytes(row.read<String>('sha256'), row.read<int>('size'),
          row.read<Uint8List>('content'));
    }

    final manifests =
        await db.customSelect('SELECT * FROM attachment_manifest').get();
    for (final row in manifests) {
      validateMetadata(row.data);
      if (await repo.cached(
              row.read<String>('sha256'), row.read<int>('size')) ==
          null) {
        throw const FormatException('O backup contém um anexo sem conteúdo.');
      }
    }
    final hashes = await db
        .customSelect('SELECT id AS sha256,size FROM attachment_blobs')
        .get();
    for (final row in hashes) {
      await repo.cached(row.read<String>('sha256'), row.read<int>('size'));
    }
  }
}
