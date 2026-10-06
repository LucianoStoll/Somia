import 'dart:async';
import 'dart:convert';
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
import 'schema_v12.dart';
import 'schema_v13.dart';
import 'financial_data.dart';
import 'backup_service.dart';

/// Banco local do MVP. As migrations SQL ficam estáveis por versão; as DAOs
/// tipadas serão adicionadas pelas features sem alterar o schema publicado.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  // Keep financial notifications separate from Drift invalidation, which can
  // also occur after rollback. Zones isolate concurrent and nested transactions.
  final _financialChanges = StreamController<void>.broadcast();
  final _writeZoneKey = Object();
  Stream<void> get financialChanges => _financialChanges.stream;
  static final _financialWrite = RegExp(
      r'^\s*(?:INSERT(?:\s+OR\s+\w+)?\s+INTO|REPLACE\s+INTO|UPDATE(?:\s+OR\s+\w+)?|DELETE\s+FROM)\s+["`\[]?(\w+)',
      caseSensitive: false);

  @override
  Future<void> customStatement(String statement, [List<Object?>? args]) async {
    await super.customStatement(statement, args);
    _recordFinancialWrite(statement);
  }

  void _recordFinancialWrite(String statement) {
    final table =
        _financialWrite.firstMatch(statement)?.group(1)?.toLowerCase();
    if (table != null && financialTables.contains(table)) {
      final writes = Zone.current[_writeZoneKey] as _FinancialWrites?;
      if (writes != null) {
        writes.changed = true;
      } else {
        _financialChanges.add(null);
      }
    }
  }

  @override
  Future<int> customUpdate(String query,
      {List<Variable> variables = const [],
      Set<ResultSetImplementation>? updates,
      UpdateKind? updateKind}) async {
    final changed = await super.customUpdate(query,
        variables: variables, updates: updates, updateKind: updateKind);
    if (changed > 0) _recordFinancialWrite(query);
    return changed;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action,
      {bool requireNew = false}) async {
    final parent = Zone.current[_writeZoneKey] as _FinancialWrites?;
    final writes = _FinancialWrites();
    final result = await super.transaction(
        () => runZoned(action, zoneValues: {_writeZoneKey: writes}),
        requireNew: requireNew);
    if (writes.changed) {
      if (parent != null) {
        parent.changed = true;
      } else {
        _financialChanges.add(null);
      }
    }
    return result;
  }

  @override
  Future<void> close() async {
    await super.close();
    await _financialChanges.close();
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

  static const currentSchemaVersion = 13;

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
            ...schemaV11,
            ...schemaV12,
            ...schemaV13,
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
              12 => schemaV12,
              13 => schemaV13,
              _ => throw StateError('Migration v$version não implementada'),
            };
            for (final statement in statements) {
              await customStatement(statement);
            }
          }
          if (from < 13) {
            // Requeue unsent v11/v12 packets with new identities: an earlier upload
            // may already exist remotely with the original content hash.
            final uploads =
                await customSelect('SELECT * FROM sync_uploads').get();
            for (final row in uploads) {
              final packet = jsonDecode(row.read<String>('payload'))
                  as Map<String, dynamic>;
              packet['schema'] = 13;
              packet['id'] = const Uuid().v4();
              for (final entry in packet['entries'] as List) {
                if (from < 12 &&
                    ['transactions', 'card_entries'].contains(entry['table']) &&
                    entry['data'] != null) {
                  entry['data']['allocations_json'] = '[]';
                }
              }
              await customStatement(
                'UPDATE sync_uploads SET packet_id=?,payload=? WHERE packet_id=?',
                [
                  packet['id'],
                  jsonEncode(packet),
                  row.read<String>('packet_id')
                ],
              );
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

class _FinancialWrites {
  bool changed = false;
}
