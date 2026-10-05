import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:uuid/uuid.dart';

import 'schema_v1.dart';
import 'schema_v2.dart';
import 'schema_v3.dart';
import 'schema_v4.dart';
import 'schema_v5.dart';
import 'schema_v6.dart';
import 'schema_v7.dart';
import 'schema_v8.dart';
import 'schema_v9.dart';
import 'schema_v10.dart';
import 'schema_v11.dart';
import 'financial_data.dart';
import 'backup_service.dart';

/// Banco local do MVP. As migrations SQL ficam estáveis por versão; as DAOs
/// tipadas serão adicionadas pelas features sem alterar o schema publicado.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  // Raw SQL repositories need explicit Drift notifications. Drift buffers these
  // in a transaction and publishes only after commit (discarding rollbacks).
  static final _financialWrite = RegExp(
      r'^\s*(?:INSERT(?:\s+OR\s+\w+)?\s+INTO|REPLACE\s+INTO|UPDATE(?:\s+OR\s+\w+)?|DELETE\s+FROM)\s+["`\[]?(\w+)',
      caseSensitive: false);

  @override
  Future<void> customStatement(String statement, [List<Object?>? args]) async {
    await super.customStatement(statement, args);
    final table =
        _financialWrite.firstMatch(statement)?.group(1)?.toLowerCase();
    if (table != null && financialTables.contains(table)) {
      notifyUpdates({TableUpdate(table)});
    }
  }

  factory AppDatabase.open() => AppDatabase(
        LazyDatabase(() async {
          final directory = await getApplicationSupportDirectory();
          await directory.create(recursive: true);
          final file = File(p.join(directory.path, 'finapp.sqlite'));
          await protectBeforeMigration(file, directory);
          await BackupService.prepareForOpen(directory);
          return NativeDatabase.createInBackground(file);
        }),
      );

  /// Preserve a consistent copy before opening an older published database.
  static Future<void> protectBeforeMigration(
      File file, Directory directory) async {
    if (!await file.exists()) return;
    final previous = sqlite.sqlite3.open(file.path);
    try {
      final version =
          previous.select('PRAGMA user_version').single['user_version'] as int;
      if (version > 0 && version < currentSchemaVersion) {
        final folder = Directory(p.join(directory.path, 'somia-backups'));
        await folder.create(recursive: true);
        final snapshot = p.join(folder.path,
            'beforeMigration-${DateTime.now().microsecondsSinceEpoch}-${const Uuid().v4()}.sqlite');
        previous.execute('VACUUM INTO ?', [snapshot]);
      }
    } finally {
      previous.close();
    }
  }

  @override
  int get schemaVersion => currentSchemaVersion;

  static const currentSchemaVersion = 11;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (_) async {
          for (final statement in [
            ...schemaV1,
            ...schemaV2,
            ...schemaV3,
            ...schemaV4,
            ...schemaV5,
            ...schemaV6,
            ...schemaV7,
            ...schemaV8,
            ...schemaV9,
            ...schemaV10,
            ...schemaV11
          ]) {
            await customStatement(statement);
          }
          await installSyncTriggers(this);
        },
        onUpgrade: (m, from, to) async {
          for (var version = from + 1; version <= to; version++) {
            final statements = switch (version) {
              2 => schemaV2,
              3 => schemaV3,
              4 => schemaV4,
              5 => schemaV5,
              6 => schemaV6,
              7 => schemaV7,
              8 => schemaV8,
              9 => schemaV9,
              10 => schemaV10,
              11 => schemaV11,
              _ => throw StateError('Migration v$version não implementada'),
            };
            for (final statement in statements) {
              await customStatement(statement);
            }
          }
          await installSyncTriggers(this);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          if (details.wasCreated || details.hadUpgrade) {
            final violations =
                await customSelect('PRAGMA foreign_key_check').get();
            if (violations.isNotEmpty) {
              throw StateError(
                  'Integridade referencial inválida após migration');
            }
          }
        },
      );
}
