import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:finapp/core/drive/drive_backup.dart';
import 'package:finapp/core/drive/windows_drive_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'drive_backup_test.dart' show FakeTransport, jsonResponse;

class MemoryVault implements DesktopVault {
  Map<String, dynamic> data = {};
  @override Future<Map<String, dynamic>> read() async => Map.of(data);
  @override Future<void> write(Map<String, dynamic> value) async { data = Map.of(value); }
}
Uint8List config() => Uint8List.fromList(utf8.encode(jsonEncode({'installed': {
  'client_id': 'test-desktop.apps.googleusercontent.com', 'client_secret': 'desktop-client',
  'redirect_uris': ['http://localhost'],
}})));
Future<void> callback(Uri url, {bool deny = false, String? overrideState}) async {
  final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
  final client = HttpClient();
  try {
    final request = await client.getUrl(redirect.replace(queryParameters: {
      'state': overrideState ?? url.queryParameters['state']!,
      if (deny) 'error': 'access_denied' else 'code': 'one-use-code',
    }));
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, overrideState == null ? 200 : 400);
  } finally { client.close(force: true); }
}
void main() {
  test('cliente Android/web é rejeitado sem alterar configuração', () async {
    final vault = MemoryVault();
    final auth = WindowsDriveAuth(vault, FakeTransport((m, u, h, b) async => jsonResponse({})));
    await auth.configure(config());
    final previous = Map.of(vault.data);
    await expectLater(auth.configure(Uint8List.fromList(utf8.encode('{"web":{}}'))), throwsA(isA<DriveFailure>()));
    expect(vault.data, previous);
    expect(auth.configured, isTrue);
  });
  test('navegador recebe PKCE, token troca verificador; vault guarda refresh, não acesso', () async {
    final vault = MemoryVault();
    Uri? authorization;
    var tokenCalls = 0;
    final auth = WindowsDriveAuth(vault, FakeTransport((method, uri, headers, body) async {
      if (uri.host == 'oauth2.googleapis.com') {
        tokenCalls++;
        final form = Uri.splitQueryString(utf8.decode(body!));
        expect(form['grant_type'], 'authorization_code');
        expect(form['code'], 'one-use-code');
        expect(base64Url.encode(sha256.convert(utf8.encode(form['code_verifier']!)).bytes).replaceAll('=', ''), authorization!.queryParameters['code_challenge']);
        return jsonResponse({'access_token': 'access', 'refresh_token': 'refresh', 'expires_in': 3600,
          'token_type': 'Bearer', 'scope': '${WindowsDriveAuth.driveScope} ${WindowsDriveAuth.emailScope}'});
      }
      expect(headers['Authorization'], 'Bearer access');
      return jsonResponse({'email': 'luciano@example.com', 'email_verified': true});
    }), launch: (url) async { authorization = url; await callback(url); });
    await auth.configure(config());
    final session = await auth.connect();
    expect(authorization!.host, 'accounts.google.com');
    expect(authorization!.queryParameters['code_challenge_method'], 'S256');
    expect(Uri.parse(authorization!.queryParameters['redirect_uri']!).host, '127.0.0.1');
    expect(session.email, 'luciano@example.com');
    expect(vault.data['refresh'], 'refresh');
    expect(jsonEncode(vault.data), isNot(contains('"access"')));
    expect((await auth.authorize()).token, 'access');
    expect(tokenCalls, 1);
    await auth.disconnect();
    expect(vault.data.containsKey('refresh'), isFalse);
    expect(vault.data.containsKey('client'), isTrue);
  });
  test('restaura sessão e renova token; limpar acesso força nova renovação', () async {
    final vault = MemoryVault()..data = {'client': {'id': 'test.apps.googleusercontent.com'}, 'email': 'luciano@example.com', 'refresh': 'saved'};
    var calls = 0;
    final auth = WindowsDriveAuth(vault, FakeTransport((method, uri, headers, body) async {
      calls++;
      final form = Uri.splitQueryString(utf8.decode(body!));
      expect(form['grant_type'], 'refresh_token');
      expect(form['refresh_token'], 'saved');
      return jsonResponse({'access_token': 'new-$calls', 'expires_in': 3600, 'token_type': 'Bearer'});
    }));
    expect(await auth.account(), 'luciano@example.com');
    expect((await auth.authorize()).token, 'new-1');
    await auth.clearToken('new-1');
    expect((await auth.authorize()).token, 'new-2');
    expect(calls, 2);
  });
  test('permissão negada preserva conta anterior; servidor encerra', () async {
    final vault = MemoryVault();
    final auth = WindowsDriveAuth(vault, FakeTransport((m, u, h, b) async => throw StateError('não deve trocar token')), launch: (url) => callback(url, deny: true));
    await auth.configure(config());
    await expectLater(auth.connect(), throwsA(isA<DriveFailure>()));
    expect(vault.data.containsKey('refresh'), isFalse);
  });
  test('state incorreto é ignorado e callback correto ainda conclui', () async {
    final flow = DesktopOAuthCallback(const Duration(seconds: 3));
    final result = await flow.receive('expected', (url) async {
      await callback(url, overrideState: 'wrong'); await callback(url);
    }, (redirect) => Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {'redirect_uri': redirect.toString(), 'state': 'expected'}));
    expect(jsonDecode(result)['code'], 'one-use-code');
  });
  test('cancelamento, falha do navegador e timeout não ficam pendentes', () async {
    for (final kind in ['cancel', 'browser', 'timeout']) {
      final flow = DesktopOAuthCallback(const Duration(milliseconds: 60));
      await expectLater(flow.receive('state', (_) async {
        if (kind == 'cancel') flow.cancel();
        if (kind == 'browser') throw StateError('browser');
      }, (redirect) => Uri.https('accounts.google.com', '/o/oauth2/v2/auth')), throwsA(isA<DriveFailure>()));
    }
  });
}
