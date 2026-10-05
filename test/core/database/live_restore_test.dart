import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_manager.dart';
import 'package:finapp/core/database/backup_service.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingDatabase extends AppDatabase {
  _FailingDatabase(super.executor);
  bool failImport = false;
  @override
  Future<void> customStatement(String statement, [List<dynamic>? args]) {
    if (failImport && statement.startsWith('INSERT INTO main."transfers"')) {
      throw StateError('Falha simulada durante a substituição');
    }
    return super.customStatement(statement, args);
  }
}

class _UnreadableListStore extends LocalBackupStore {
  _UnreadableListStore(super.directory);
  bool failList = false;
  @override
  Future<List<LocalBackupCopy>> list() {
    if (failList) throw const FileSystemException('Falha simulada na listagem');
    return super.list();
  }

  @override
  Future<LocalBackupCopy> create(AppDatabase database, BackupKind kind) async {
    final copy = await super.create(database, kind);
    failList = true;
    return copy;
  }
}

Future<void> _seed(AppDatabase db, String prefix) async {
  for (final id in ['a', 'b']) {
    await db.customStatement("""INSERT INTO accounts
      (id,name,type,currency_code,initial_balance_minor,created_at,updated_at)
      VALUES (?,?,'cash','BRL',10000,1,1)""", ['$prefix$id', '$prefix$id']);
  }
  await db.customStatement(
      """INSERT INTO categories(id,name,type,created_at,updated_at)
    VALUES (?, 'Principal','expense',1,1)""", ['${prefix}parent']);
  await db.customStatement(
      """INSERT INTO categories(id,name,type,parent_id,created_at,updated_at)
    VALUES (?, 'Filha','expense',?,1,1)""",
      ['${prefix}child', '${prefix}parent']);
  await db.customStatement("""INSERT INTO transactions
    (id,description,type,planned_amount_minor,actual_amount_minor,competence_at,
     effective_at,account_id,category_id,created_at,updated_at,series_id,series_index)
    VALUES (?, 'Compra','expense',500,500,1,1,?,?,1,1,'serie',0)""",
      ['${prefix}tx', '${prefix}a', '${prefix}child']);
  await db.customStatement('''INSERT INTO transfers
    (id,source_account_id,destination_account_id,amount_minor,created_at,updated_at)
    VALUES (?,?,?,100,1,1)''',
      ['${prefix}transfer', '${prefix}a', '${prefix}b']);
  await db.customStatement("""INSERT INTO credit_cards
    (id,name,payment_account_id,closing_day,due_day,created_at,updated_at)
    VALUES (?, 'Cartão',?,25,5,1,1)""", ['${prefix}card', '${prefix}a']);
  await db.customStatement('''INSERT INTO card_limit_history
    (id,card_id,limit_minor,changed_at) VALUES (?,?,50000,1)''',
      ['${prefix}limit', '${prefix}card']);
  await db.customStatement('''INSERT INTO card_invoices
    (id,card_id,month_at,closing_at,due_at,created_at,updated_at)
    VALUES (?,?,1,1,2,1,1)''', ['${prefix}invoice', '${prefix}card']);
  await db.customStatement(
      """INSERT INTO card_entries
    (id,card_id,invoice_id,purchase_id,description,category_id,kind,amount_minor,
     posted_at,created_at,updated_at) VALUES (?,?,?,'purchase','Compra',?,'purchase',900,1,1,1)""",
      [
        '${prefix}entry',
        '${prefix}card',
        '${prefix}invoice',
        '${prefix}child'
      ]);
  await db.customStatement('''INSERT INTO card_payments
    (id,invoice_id,account_id,amount_minor,effective_at,created_at,updated_at)
    VALUES (?,?,?,900,1,1,1)''',
      ['${prefix}payment', '${prefix}invoice', '${prefix}a']);
  await db.customStatement("""INSERT INTO card_entry_history
    (id,entry_id,action,invoice_id,amount_minor,changed_at)
    VALUES (?,?,'create',?,900,1)""",
      ['${prefix}history', '${prefix}entry', '${prefix}invoice']);
  // Histórico válido que não passaria pelas regras de um novo lançamento.
  await db.customStatement('UPDATE accounts SET is_archived=1');
  await db.customStatement('UPDATE categories SET is_archived=1');
}

Future<Map<String, Object>> _data(AppDatabase db) async {
  final tables = await db
      .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
      .get();
  final result = <String, Object>{};
  for (final table in tables) {
    final name = table.read<String>('name');
    result[name] =
        (await db.customSelect('SELECT * FROM "$name" ORDER BY id').get())
            .map((row) => row.data)
            .toList();
  }
  return result;
}

void main() {
  late Directory dir;
  late _FailingDatabase db;
  late AppDatabase source;
  late BackupManager manager;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('somia-live-');
    db = _FailingDatabase(NativeDatabase(File('${dir.path}/finapp.sqlite')));
    source = AppDatabase(NativeDatabase.memory());
    manager = BackupManager(db, LocalBackupStore(dir));
    await _seed(db, 'old-');
    await _seed(source, 'new-');
  });
  tearDown(() async {
    manager.dispose();
    await source.close();
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
      'WAL, todos os registros, hierarquia e históricos; mesma conexão segue utilizável',
      () async {
    await db.customStatement('PRAGMA journal_mode=WAL');
    await db.customStatement(
        "UPDATE accounts SET name='Mudança no WAL' WHERE id='old-a'");
    final before = await _data(db);
    final expected = await _data(source);
    // SQL externo nunca é instalado na base operacional.
    await source.customStatement(
        'CREATE TRIGGER external_trigger AFTER INSERT ON accounts BEGIN DELETE FROM transfers; END');
    await manager.restore(await BackupService.export(source, dir));
    expect(await _data(db), expected);
    expect(manager.databaseRevision, 1);
    expect(manager.restorePending, isFalse);
    expect(manager.restoring, isFalse);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    expect(
        await db
            .customSelect(
                "SELECT name FROM sqlite_master WHERE name='external_trigger'")
            .get(),
        isEmpty);
    final protection =
        manager.copies.singleWhere((c) => c.kind == BackupKind.beforeRestore);
    final previous = AppDatabase(NativeDatabase(protection.file));
    try {
      expect(await _data(previous), before);
    } finally {
      await previous.close();
    }
    // Triggers locais voltam a proteger novos lançamentos.
    await expectLater(db.customStatement("""INSERT INTO transactions
      (id,description,type,planned_amount_minor,competence_at,account_id,created_at,updated_at)
      VALUES ('bad','Inválido','expense',100,1,'new-a',1,1)"""),
        throwsA(anything));
    await db.customStatement(
        "UPDATE accounts SET name='Após restauração' WHERE id='new-a'");
    expect(
        (await db
                .customSelect("SELECT name FROM accounts WHERE id='new-a'")
                .getSingle())
            .read<String>('name'),
        'Após restauração');
    await manager.restore(await BackupService.export(source, dir));
    expect(manager.databaseRevision, 2);
  });

  test('falha após exclusão e inserção parcial desfaz dados e triggers',
      () async {
    final before = await _data(db);
    final triggers = await db
        .customSelect(
            "SELECT sql FROM sqlite_master WHERE type='trigger' ORDER BY name")
        .get();
    db.failImport = true;
    await expectLater(manager.restore(await BackupService.export(source, dir)),
        throwsStateError);
    expect(await _data(db), before);
    expect(
        (await db
                .customSelect(
                    "SELECT sql FROM sqlite_master WHERE type='trigger' ORDER BY name")
                .get())
            .map((r) => r.data),
        triggers.map((r) => r.data));
    expect(manager.databaseRevision, 0);
    expect(manager.restoring, isFalse);
    db.failImport = false;
    await manager.restore(await BackupService.export(source, dir));
    expect(await _data(db), await _data(source));
  });

  test('falha de listagem após commit informa sucesso e preserva revisão',
      () async {
    final other = BackupManager(db, _UnreadableListStore(dir));
    try {
      await other.restore(await BackupService.export(source, dir));
      expect(await _data(db), await _data(source));
      expect(other.databaseRevision, 1);
      expect(other.error, contains('Dados restaurados'));
      expect(other.busy, isFalse);
    } finally {
      other.dispose();
    }
  });

  test(
      'sem espaço para proteção não altera dados; arquivo inválido não inicia substituição',
      () async {
    final before = await _data(db);
    await File('${dir.path}/somia-backups').writeAsString('bloqueio');
    await expectLater(manager.restore(await BackupService.export(source, dir)),
        throwsA(isA<FileSystemException>()));
    expect(await _data(db), before);
    expect(manager.databaseRevision, 0);
    await expectLater(
        manager.restore(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    expect(await _data(db), before);
  });
}
