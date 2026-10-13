import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:finapp/core/drive/drive_backup.dart';
import 'package:finapp/core/sync/drive_sync_api.dart';
import 'package:finapp/core/sync/sync_packet.dart';
import 'package:flutter_test/flutter_test.dart';
import '../drive/drive_backup_test.dart'
    show FakeAuth, FakeTransport, jsonResponse, metadata;

void main() {
  const session = DriveSession('same@example.com', 'token');
  const packet = SyncPacket('packet-identity-0001', 'base-identity-00001',
      'android-device-0001', 'genesis', []);
  Map<String, Object> file() => {
        ...metadata(packet.encode()),
        'appProperties': {
          'somiaSync': '1',
          'packet': packet.id,
          'base': packet.base,
          'device': packet.device,
          'kind': packet.kind,
          'sha256': packet.digest
        },
      };
  test('anexo usa objeto binário privado por base e verifica conteúdo recebido',
      () async {
    final bytes = Uint8List.fromList([0, 1, 2, 255]),
        hash = sha256.convert([0, 1, 2, 255]).toString();
    final meta = {
      ...metadata(bytes),
      'appProperties': {
        'somiaAttachment': '1',
        'base': packet.base,
        'sha256': hash
      }
    };
    final api = DriveSyncApi(DriveBackupApi(FakeAuth(),
        FakeTransport((method, uri, headers, body) async {
      if (method == 'POST') {
        expect(headers['Content-Type'], startsWith('multipart/related'));
        expect(body!, contains(255));
        expect(utf8.decode(body, allowMalformed: true),
            contains('application/octet-stream'));
        expect(utf8.decode(body, allowMalformed: true),
            contains('"somiaAttachment":"1"'));
        return jsonResponse({'id': 'created'});
      }
      if (uri.queryParameters['alt'] == 'media') {
        return DriveResponse(200, bytes);
      }
      if (uri.path == '/drive/v3/files') {
        expect(uri.queryParameters['q'], contains(packet.base));
        return jsonResponse({
          'files': [meta]
        });
      }
      return jsonResponse(meta);
    })));
    await api.uploadAttachment(session, packet.base, hash, bytes);
    final file = (await api.listAttachments(session, packet.base)).single;
    expect(await api.downloadAttachment(session, file), bytes);
    await expectLater(
        api.uploadAttachment(session, packet.base, 'wrong', bytes),
        throwsA(isA<DriveFailure>()));
  });
  test(
      'lista privada paginada separa sync de backup e propaga relógio do servidor',
      () async {
    var calls = 0;
    final now = DateTime.now().toUtc();
    final api = DriveSyncApi(
        DriveBackupApi(FakeAuth(), FakeTransport((m, u, h, b) async {
      expect(u.queryParameters['spaces'], 'appDataFolder');
      expect(u.queryParameters['q'], contains('somiaSync'));
      expect(h['Authorization'], 'Bearer token');
      calls++;
      final value = calls == 1
          ? {
              'files': [file()],
              'nextPageToken': 'next'
            }
          : {'files': []};
      if (calls == 2) expect(u.queryParameters['pageToken'], 'next');
      return DriveResponse(
          200, Uint8List.fromList(utf8.encode(jsonEncode(value))),
          serverTime: now);
    })));
    expect(await api.list(session), hasLength(1));
    expect(calls, 2);
    expect(api.serverTime, now);
  });
  test('envio preserva pacote imutável, identidade, hash e pasta privada',
      () async {
    final api = DriveSyncApi(
        DriveBackupApi(FakeAuth(), FakeTransport((m, u, h, b) async {
      expect(m, 'POST');
      expect(u.path, '/upload/drive/v3/files');
      expect(u.queryParameters['uploadType'], 'multipart');
      expect(h['Content-Type'], startsWith('multipart/related; boundary='));
      final text = utf8.decode(b!);
      expect(text, contains(utf8.decode(packet.encode())));
      expect(text, contains(packet.digest));
      expect(text, contains('"somiaSync":"1"'));
      expect(text, contains('"parents":["appDataFolder"]'));
      expect(text, contains('"packet":"${packet.id}"'));
      expect(text, isNot(contains('somiaBackup')));
      return jsonResponse({'id': 'created'});
    })));
    await api.upload(session, packet);
  });
  test(
      'download usa marcador sync e falha em lista adulterada ou página repetida',
      () async {
    final api = DriveSyncApi(
        DriveBackupApi(FakeAuth(), FakeTransport((m, u, h, b) async {
      if (u.queryParameters['alt'] == 'media') {
        return DriveResponse(200, packet.encode());
      }
      return jsonResponse(file());
    })));
    expect(
        await api.download(
            session, SyncRemoteFile.parse(Map<String, dynamic>.from(file()))),
        packet.encode());
    for (final value in [
      {
        'files': [metadata(packet.encode())]
      },
      {'files': [], 'nextPageToken': 'repeat'}
    ]) {
      final invalid = DriveSyncApi(DriveBackupApi(FakeAuth(),
          FakeTransport((m, u, h, b) async => jsonResponse(value))));
      await expectLater(invalid.list(session), throwsA(isA<DriveFailure>()));
    }
  });
}
