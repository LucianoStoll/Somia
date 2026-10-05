import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

const maxDriveBackupBytes = 64 * 1024 * 1024;

class DriveFailure implements Exception {
  const DriveFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class DriveSession {
  const DriveSession(this.email, this.token);
  final String email;
  final String token;
}

abstract class DriveAuth {
  Future<String?> account();
  Future<DriveSession> connect();
  Future<DriveSession> authorize();
  Future<void> disconnect();
  Future<void> clearToken(String token);
}

class AndroidDriveAuth implements DriveAuth {
  static const _channel = MethodChannel('somia/drive_auth');
  @override
  Future<String?> account() => _channel.invokeMethod<String>('account');
  Future<DriveSession> _session(String method) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(method);
      if (result == null || result['email'] is! String || result['token'] is! String) {
        throw const DriveFailure('Reconecte sua conta Google.');
      }
      return DriveSession(result['email'] as String, result['token'] as String);
    } on PlatformException catch (error) {
      throw DriveFailure(error.message ?? 'Não foi possível conectar ao Google.');
    }
  }

  @override
  Future<DriveSession> connect() => _session('connect');
  @override
  Future<DriveSession> authorize() => _session('authorize');
  @override
  Future<void> disconnect() => _channel.invokeMethod<void>('disconnect');
  @override
  Future<void> clearToken(String token) =>
      _channel.invokeMethod<void>('clearToken', {'token': token});
}

class DriveResponse {
  const DriveResponse(this.status, this.bytes);
  final int status;
  final Uint8List bytes;
}

abstract class DriveTransport {
  Future<DriveResponse> send(String method, Uri uri, Map<String, String> headers,
      Uint8List? body);
}

/// Cada requisição fecha a conexão e limita tempo e bytes recebidos.
class IoDriveTransport implements DriveTransport {
  @override
  Future<DriveResponse> send(String method, Uri uri, Map<String, String> headers,
      Uint8List? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      return await (() async {
        final request = await client.openUrl(method, uri);
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        if (body != null) request.add(body);
        final response = await request.close();
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxDriveBackupBytes) {
            throw const DriveFailure('A cópia excede o limite de 64 MB.');
          }
          bytes.add(chunk);
        }
        return DriveResponse(response.statusCode, bytes.takeBytes());
      })().timeout(const Duration(seconds: 90));
    } on SocketException {
      throw const DriveFailure('Sem conexão com o Drive. Tente novamente.');
    } on TimeoutException {
      throw const DriveFailure('O Drive demorou a responder. Confira a lista antes de repetir um envio.');
    } finally {
      client.close(force: true);
    }
  }
}

class DriveCopy {
  const DriveCopy({required this.id, required this.name, required this.createdAt,
    required this.size, required this.md5Hash, required this.sha256Hash});
  final String id;
  final String name;
  final DateTime createdAt;
  final int size;
  final String md5Hash;
  final String sha256Hash;

  static DriveCopy parse(Map<String, dynamic> file) {
    final properties = file['appProperties'];
    final spaces = file['spaces'];
    final size = int.tryParse('${file['size']}');
    final created = DateTime.tryParse('${file['createdTime']}');
    if (properties is! Map || properties['somiaBackup'] != '1' ||
        properties['sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(properties['sha256'] as String) ||
        spaces is! List || !spaces.contains('appDataFolder') ||
        file['trashed'] == true || file['id'] is! String ||
        file['name'] is! String || created == null || size == null ||
        size <= 0 || size > maxDriveBackupBytes || file['md5Checksum'] is! String) {
      throw const DriveFailure('Cópia do Drive inválida ou incompatível.');
    }
    return DriveCopy(id: file['id'] as String, name: file['name'] as String,
        createdAt: created, size: size, md5Hash: file['md5Checksum'] as String,
        sha256Hash: properties['sha256'] as String);
  }
}

class DriveBackupApi {
  DriveBackupApi(this.auth, this.transport);
  final DriveAuth auth;
  final DriveTransport transport;
  static const _fields = 'id,name,createdTime,size,md5Checksum,appProperties,spaces,trashed';

  Future<Uint8List> _request(DriveSession session, String method, String path,
      Map<String, String> query, {Uint8List? body, String? contentType}) async {
    final response = await transport.send(method, Uri.https('www.googleapis.com', path, query), {
      'Authorization': 'Bearer ${session.token}',
      if (contentType != null) 'Content-Type': contentType,
    }, body);
    if (response.status == 401) {
      await auth.clearToken(session.token);
      throw const DriveFailure('A autorização expirou. Reconecte a conta Google.');
    }
    if (response.status == 403 || response.status == 429) {
      throw const DriveFailure('O Drive recusou o acesso ou atingiu um limite. Confira a API habilitada, a permissão e o espaço da conta. Tente novamente mais tarde.');
    }
    if (response.status == 404) throw const DriveFailure('Esta cópia não está mais disponível no Drive. Atualize a lista.');
    if (response.status < 200 || response.status >= 300) {
      throw const DriveFailure('Não foi possível concluir no Drive. Confira a lista antes de repetir um envio.');
    }
    return response.bytes;
  }

  Map<String, dynamic> _json(Uint8List bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) throw const DriveFailure('Resposta inválida do Drive.');
    return value;
  }

  Future<List<DriveCopy>> list(DriveSession session) async {
    final copies = <DriveCopy>[];
    final seen = <String>{};
    String? page;
    do {
      final response = _json(await _request(session, 'GET', '/drive/v3/files', {
        'spaces': 'appDataFolder', 'q': "trashed = false and appProperties has { key='somiaBackup' and value='1' }",
        'fields': 'nextPageToken,files($_fields)', 'pageSize': '100',
        'orderBy': 'createdTime desc', if (page != null) 'pageToken': page,
      }));
      final files = response['files'];
      if (files is! List) throw const DriveFailure('Lista inválida do Drive.');
      for (final file in files) {
        if (file is! Map<String, dynamic>) continue;
        try { copies.add(DriveCopy.parse(file)); } on DriveFailure { /* Ignora outras versões ou cópias incompletas. */ }
      }
      page = response['nextPageToken'] as String?;
      if (page != null && (!seen.add(page) || seen.length > 100)) {
        throw const DriveFailure('Não foi possível carregar todas as cópias. Tente novamente.');
      }
    } while (page != null);
    return copies;
  }

  Future<void> upload(DriveSession session, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxDriveBackupBytes) {
      throw const DriveFailure('O backup deve ter até 64 MB.');
    }
    final boundary = 'somia-${const Uuid().v4()}';
    final metadata = jsonEncode({
      'name': 'somia-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.sqlite',
      'parents': ['appDataFolder'],
      'appProperties': {'somiaBackup': '1', 'sha256': sha256.convert(bytes).toString()},
    });
    final body = BytesBuilder(copy: false)
      ..add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n--$boundary\r\nContent-Type: application/vnd.sqlite3\r\n\r\n'))
      ..add(bytes)..add(utf8.encode('\r\n--$boundary--\r\n'));
    await _request(session, 'POST', '/upload/drive/v3/files', {'uploadType': 'multipart', 'fields': 'id'},
        body: body.takeBytes(), contentType: 'multipart/related; boundary=$boundary');
  }

  Future<Uint8List> download(DriveSession session, DriveCopy selected) async {
    final path = '/drive/v3/files/${Uri.encodeComponent(selected.id)}';
    final fresh = DriveCopy.parse(_json(await _request(session, 'GET', path, {'fields': _fields})));
    if (fresh.id != selected.id || fresh.sha256Hash != selected.sha256Hash || fresh.size != selected.size) {
      throw const DriveFailure('A cópia mudou. Atualize a lista antes de restaurar.');
    }
    final bytes = await _request(session, 'GET', path, {'alt': 'media'});
    if (bytes.length != fresh.size || md5.convert(bytes).toString() != fresh.md5Hash ||
        sha256.convert(bytes).toString() != fresh.sha256Hash) {
      throw const DriveFailure('A cópia está incompleta ou corrompida. Os dados atuais foram mantidos.');
    }
    return bytes;
  }
}
