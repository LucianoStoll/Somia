import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/database/backup_manager.dart';
import 'package:finapp/core/database/backup_service.dart';
import 'package:finapp/core/database/local_backup_store.dart';
import 'package:finapp/core/drive/drive_backup.dart';
import 'package:finapp/core/drive/drive_backup_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuth implements DriveAuth {
  String? email = 'luciano@example.com';
  int cleared = 0;
  @override
  Future<String?> account() async => email;
  @override
  Future<DriveSession> connect() async => authorize();
  @override
  Future<DriveSession> authorize() async => DriveSession(email!, 'token');
  @override
  Future<void> disconnect() async {
    email = null;
  }

  @override
  Future<void> clearToken(String token) async {
    cleared++;
  }
}

class FakeTransport implements DriveTransport {
  FakeTransport(this.handler);
  final Future<DriveResponse> Function(
      String, Uri, Map<String, String>, Uint8List?) handler;
  @override
  Future<DriveResponse> send(String method, Uri uri,
          Map<String, String> headers, Uint8List? body) =>
      handler(method, uri, headers, body);
}

DriveResponse jsonResponse(Object value) =>
    DriveResponse(200, Uint8List.fromList(utf8.encode(jsonEncode(value))));
Map<String, Object> metadata(Uint8List bytes) => {
      'id': 'copy-1',
      'name': 'somia.sqlite',
      'createdTime': '2026-10-05T12:00:00Z',
      'size': '${bytes.length}',
      'md5Checksum': md5.convert(bytes).toString(),
      'spaces': ['appDataFolder'],
      'appProperties': {
        'somiaBackup': '1',
        'sha256': sha256.convert(bytes).toString()
      },
    };

void main() {
  const session = DriveSession('luciano@example.com', 'token');
  final bytes = Uint8List.fromList([1, 2, 3]);
  test('lista paginada usa pasta privada e ignora arquivos incompatíveis',
      () async {
    var calls = 0;
    final api = DriveBackupApi(FakeAuth(),
        FakeTransport((method, uri, headers, body) async {
      expect(headers['Authorization'], 'Bearer token');
      expect(uri.queryParameters['spaces'], 'appDataFolder');
      calls++;
      if (calls == 1) {
        return jsonResponse({
          'files': [
            metadata(bytes),
            {'id': 'other'}
          ],
          'nextPageToken': 'next'
        });
      }
      expect(uri.queryParameters['pageToken'], 'next');
      return jsonResponse({'files': []});
    }));
    expect((await api.list(session)).length, 1);
    expect(calls, 2);
  });
  test('upload multipart mantém bytes, pasta e hash sem chave API', () async {
    final api = DriveBackupApi(FakeAuth(),
        FakeTransport((method, uri, headers, body) async {
      expect(method, 'POST');
      expect(uri.queryParameters['uploadType'], 'multipart');
      expect(uri.queryParameters.containsKey('key'), isFalse);
      final text = utf8.decode(body!);
      expect(text, contains('appDataFolder'));
      expect(text, contains(sha256.convert(bytes).toString()));
      expect(text, contains(String.fromCharCodes(bytes)));
      return jsonResponse({'id': 'copy'});
    }));
    await api.upload(session, bytes);
  });
  test('401 limpa token, 403 e 429 informam limite sem reenviar', () async {
    for (final status in [401, 403, 429, 500]) {
      final auth = FakeAuth();
      var calls = 0;
      final api = DriveBackupApi(auth,
          FakeTransport((method, uri, headers, body) async {
        calls++;
        return DriveResponse(status, Uint8List(0));
      }));
      await expectLater(
          api.upload(session, bytes), throwsA(isA<DriveFailure>()));
      expect(calls, 1);
      expect(auth.cleared, status == 401 ? 1 : 0);
    }
  });
  test('download verifica metadados, tamanho e hashes', () async {
    for (final corrupted in [false, true]) {
      final api = DriveBackupApi(FakeAuth(),
          FakeTransport((method, uri, headers, body) async {
        if (uri.queryParameters['alt'] == 'media') {
          return DriveResponse(
              200, corrupted ? Uint8List.fromList([3, 2, 1]) : bytes);
        }
        return jsonResponse(metadata(bytes));
      }));
      final download = api.download(session, DriveCopy.parse(metadata(bytes)));
      if (corrupted) {
        await expectLater(download, throwsA(isA<DriveFailure>()));
      } else {
        expect(await download, bytes);
      }
    }
  });
  test('cópia alterada impede download e arquivo fora da pasta é recusado',
      () async {
    var calls = 0;
    final changed = metadata(Uint8List.fromList([9, 9, 9]));
    final api = DriveBackupApi(FakeAuth(),
        FakeTransport((method, uri, headers, body) async {
      calls++;
      return jsonResponse(changed);
    }));
    await expectLater(api.download(session, DriveCopy.parse(metadata(bytes))),
        throwsA(isA<DriveFailure>()));
    expect(calls, 1);
    expect(
        () => DriveCopy.parse({
              ...metadata(bytes),
              'spaces': ['drive']
            }),
        throwsA(isA<DriveFailure>()));
  });
  test('pagina repetida encerra com erro', () async {
    final api = DriveBackupApi(
        FakeAuth(),
        FakeTransport((method, uri, headers, body) async =>
            jsonResponse({'files': [], 'nextPageToken': 'same'})));
    await expectLater(api.list(session), throwsA(isA<DriveFailure>()));
  });

  group('proteção de restauração', () {
    late Directory directory;
    late AppDatabase db;
    late BackupManager local;
    late FakeAuth auth;
    late DriveBackupManager manager;
    late Uint8List snapshot;
    var wrongBytes = false;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('somia-drive-');
      db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('PRAGMA user_version').getSingle();
      local = BackupManager(db, LocalBackupStore(directory));
      snapshot = await local.export();
      auth = FakeAuth();
      wrongBytes = false;
      manager = DriveBackupManager(
          local,
          DriveBackupApi(auth,
              FakeTransport((method, uri, headers, body) async {
            final candidate = wrongBytes ? bytes : snapshot;
            if (uri.queryParameters['alt'] == 'media') {
              return DriveResponse(200, candidate);
            }
            if (uri.path.endsWith('copy-1')) {
              return jsonResponse(metadata(candidate));
            }
            return jsonResponse({
              'files': [metadata(candidate)]
            });
          })));
      await manager.initialize();
    });
    tearDown(() async {
      manager.dispose();
      local.dispose();
      await db.close();
      await directory.delete(recursive: true);
    });
    test('válida restaura imediatamente mantendo conexão aberta', () async {
      await db.customStatement("INSERT INTO accounts (id, name, type, currency_code, initial_balance_minor, created_at, updated_at) VALUES ('old', 'Antiga', 'cash', 'BRL', 0, 1, 1)");
      await manager.refresh();
      await manager.restore(manager.copies.single);
      expect(manager.error, isNull);
      expect(local.databaseRevision, 1);
      expect(await db.customSelect('SELECT * FROM accounts').get(), isEmpty);
      expect(await BackupService.hasPendingRestore(directory), isFalse);
      expect(
          await db.customSelect('PRAGMA user_version').getSingle(), isNotNull);
    });
    test('troca de conta invalida lista e não prepara restauração', () async {
      await manager.refresh();
      final selected = manager.copies.single;
      auth.email = 'outra@example.com';
      await manager.restore(selected);
      expect(manager.error, contains('conta mudou'));
      expect(manager.copies, isEmpty);
      expect(await BackupService.hasPendingRestore(directory), isFalse);
    });
    test('hash correto de arquivo não SQLite ainda é recusado', () async {
      wrongBytes = true;
      await manager.refresh();
      await manager.restore(manager.copies.single);
      expect(manager.error, isNotNull);
      expect(await BackupService.hasPendingRestore(directory), isFalse);
    });
    test('desconectar mantém banco e limpa somente estado remoto', () async {
      await manager.refresh();
      await manager.disconnect();
      expect(manager.email, isNull);
      expect(manager.copies, isEmpty);
      expect(
          await db.customSelect('PRAGMA user_version').getSingle(), isNotNull);
    });
  });
}
