import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'drive_backup.dart';

abstract class ConfigurableDriveAuth implements DriveAuth {
  bool get configured;
  Future<void> configure(Uint8List json);
  void cancel();
}

abstract class DesktopVault {
  Future<Map<String, dynamic>> read();
  Future<void> write(Map<String, dynamic> value);
}

/// DPAPI vincula as credenciais ao usuário Windows; fora dos backups SQLite.
class WindowsDesktopVault implements DesktopVault {
  WindowsDesktopVault(this.directory);
  final Directory directory;
  static const channel = MethodChannel('somia/windows_drive');
  File get _file => File('${directory.path}/somia-drive.dpapi');
  @override
  Future<Map<String, dynamic>> read() async {
    if (!await _file.exists()) return {};
    try {
      final bytes = await channel.invokeMethod<Uint8List>('unprotect', await _file.readAsBytes());
      return jsonDecode(utf8.decode(bytes!)) as Map<String, dynamic>;
    } catch (_) {
      throw const DriveFailure('Não foi possível ler as credenciais protegidas. Importe novamente o cliente Google para reconectar.');
    }
  }
  @override
  Future<void> write(Map<String, dynamic> value) async {
    final encrypted = await channel.invokeMethod<Uint8List>('protect', Uint8List.fromList(utf8.encode(jsonEncode(value))));
    if (encrypted == null) throw const DriveFailure('Não foi possível proteger as credenciais no Windows.');
    await directory.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsBytes(encrypted, flush: true);
    await temporary.rename(_file.path);
  }
}

class DesktopClient {
  const DesktopClient(this.id, this.secret);
  final String id;
  final String? secret;
  static DesktopClient parse(Uint8List bytes) {
    if (bytes.length > 64 * 1024) throw const DriveFailure('O arquivo de configuração é muito grande.');
    try {
      final value = jsonDecode(utf8.decode(bytes));
      final installed = value['installed'];
      final id = installed['client_id'];
      final secret = installed['client_secret'];
      final redirects = installed['redirect_uris'];
      if (id is! String || !RegExp(r'^[a-zA-Z0-9-]+\.apps\.googleusercontent\.com$').hasMatch(id) ||
          (secret != null && secret is! String) || redirects is! List ||
          !redirects.any((uri) => uri is String && (uri.startsWith('http://localhost') || uri.startsWith('http://127.0.0.1')))) {
        throw const FormatException();
      }
      return DesktopClient(id, secret as String?);
    } catch (_) {
      throw const DriveFailure('Importe o JSON de um cliente OAuth do tipo App para computador, do mesmo projeto Google do Android.');
    }
  }
  Map<String, dynamic> toJson() => {'id': id, if (secret != null) 'secret': secret};
}

class DesktopOAuthCallback {
  DesktopOAuthCallback(this.timeout);
  final Duration timeout;
  HttpServer? _server;
  Completer<String>? _pending;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.completeError(const DriveFailure('Conexão cancelada.'));
  }
  Future<String> receive(String state, Future<void> Function(Uri) launch, Uri Function(Uri) buildUrl) async {
    _cancelled = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    final redirect = Uri.parse('http://127.0.0.1:${server.port}/oauth2callback');
    final pending = Completer<String>();
    _pending = pending;
    if (_cancelled) pending.completeError(const DriveFailure('Conexão cancelada.'));
    // Registra o consumidor antes de abrir o navegador, inclusive no cancelamento.
    final outcome = pending.future.timeout(timeout, onTimeout: () => throw const DriveFailure('A conexão expirou. Tente conectar novamente.'));
    final subscription = server.listen((request) async {
      try {
      final query = request.uri.queryParameters;
      final valid = request.method == 'GET' && request.uri.path == redirect.path &&
          request.headers.host == '127.0.0.1:${server.port}' && query['state'] == state;
      request.response.headers.contentType = ContentType.html;
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.headers.set('Content-Security-Policy', "default-src 'none'");
      if (!valid) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Resposta inv&aacute;lida. Volte ao Somia.');
      } else if (!pending.isCompleted) {
        if (query['error'] != null || (query['code'] ?? '').isEmpty) {
          pending.completeError(const DriveFailure('Acesso não autorizado. Conexão cancelada.'));
        } else { pending.complete(query['code']!); }
        request.response.write('Autorização recebida. Volte ao Somia para concluir.');
      }
      await request.response.close();
      } catch (_) { /* Conexões locais interrompidas não encerram a autorização. */ }
    });
    try {
      final url = buildUrl(redirect);
      // Não transmite o código recebido ao browser; somente mensagem estática.
      final launchResult = launch(url).catchError((Object _) {
        if (!pending.isCompleted) pending.completeError(const DriveFailure('Não foi possível abrir o navegador padrão.'));
      });
      final code = await outcome;
      await launchResult;
      return jsonEncode({'code': code, 'redirect': redirect.toString()});
    } finally {
      _pending = null;
      await subscription.cancel();
      await _server?.close(force: true);
      _server = null;
    }
  }
}

class WindowsDriveAuth implements ConfigurableDriveAuth {
  WindowsDriveAuth(this.vault, this.transport, {Future<void> Function(Uri)? launch,
      Duration timeout = const Duration(minutes: 3), DateTime Function()? clock})
      : launch = launch ?? _launch, callback = DesktopOAuthCallback(timeout), clock = clock ?? DateTime.now;
  final DesktopVault vault;
  final DriveTransport transport;
  final Future<void> Function(Uri) launch;
  final DesktopOAuthCallback callback;
  final DateTime Function() clock;
  Map<String, dynamic> _data = {};
  DesktopClient? _client;
  bool _cancelled = false;
  String? _access;
  DateTime? _expires;
  static const driveScope = 'https://www.googleapis.com/auth/drive.appdata';
  static const emailScope = 'https://www.googleapis.com/auth/userinfo.email';
  @override bool get configured => _client != null;
  static Future<void> _launch(Uri uri) => WindowsDesktopVault.channel.invokeMethod<void>('launch', uri.toString());
  @override void cancel() { _cancelled = true; callback.cancel(); }
  void _checkCancelled() { if (_cancelled) throw const DriveFailure('Conexão cancelada.'); }
  @override Future<void> configure(Uint8List json) async {
    final client = DesktopClient.parse(json);
    final value = {'client': client.toJson()};
    await vault.write(value);
    _data = value;
    _client = client;
    _access = null; _expires = null;
  }
  @override Future<String?> account() async {
    if (_client == null) {
      _data = await vault.read();
      final client = _data['client'];
      if (client is Map && client['id'] is String) _client = DesktopClient(client['id'] as String, client['secret'] as String?);
    }
    return _data['email'] as String?;
  }
  DesktopClient get _required => _client ?? (throw const DriveFailure('Configure o cliente Google para Windows antes de conectar.'));
  String _random() => base64Url.encode(List<int>.generate(32, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
  Future<Map<String, dynamic>> _request(Uri uri, {Map<String, String>? form, String? token}) async {
    final response = await transport.send(form == null ? 'GET' : 'POST', uri, {
      if (form != null) 'Content-Type': 'application/x-www-form-urlencoded',
      if (token != null) 'Authorization': 'Bearer $token',
    }, form == null ? null : Uint8List.fromList(utf8.encode(Uri(queryParameters: form).query)));
    if (response.status < 200 || response.status >= 300) {
      throw const DriveFailure('Não foi possível autorizar no Google. Confira o cliente Desktop, a conexão e reconecte sua conta.');
    }
    return jsonDecode(utf8.decode(response.bytes)) as Map<String, dynamic>;
  }
  Future<Map<String, dynamic>> _token(Map<String, String> grant) => _request(Uri.https('oauth2.googleapis.com', '/token'), form: {
    'client_id': _required.id, if (_required.secret != null) 'client_secret': _required.secret!, ...grant,
  });
  (String, DateTime) _parseToken(Map<String, dynamic> tokens, {bool checkScopes = false}) {
    final token = tokens['access_token'];
    final seconds = tokens['expires_in'];
    final scopes = '${tokens['scope']}'.split(' ');
    if (token is! String || token.isEmpty || seconds is! int || seconds <= 0 ||
        tokens['token_type'] != 'Bearer' || (checkScopes && (!scopes.contains(driveScope) || !scopes.contains(emailScope)))) {
      throw const DriveFailure('O Google não concedeu as permissões necessárias. Reconecte e autorize o Drive e a identificação da conta.');
    }
    return (token, clock().add(Duration(seconds: seconds)));
  }
  @override Future<DriveSession> connect() async {
    _cancelled = false;
    await account();
    _checkCancelled();
    final client = _required;
    final verifier = _random();
    final state = _random();
    final challenge = base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    final result = jsonDecode(await callback.receive(state, launch, (redirect) => Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': client.id, 'redirect_uri': redirect.toString(), 'response_type': 'code',
      'scope': '$driveScope $emailScope', 'state': state, 'code_challenge': challenge,
      'code_challenge_method': 'S256', 'access_type': 'offline', 'prompt': 'consent select_account',
    }))) as Map<String, dynamic>;
    _checkCancelled();
    final tokens = await _token({'grant_type': 'authorization_code', 'code': result['code'] as String,
      'redirect_uri': result['redirect'] as String, 'code_verifier': verifier});
    _checkCancelled();
    final (access, expiry) = _parseToken(tokens, checkScopes: true);
    final identity = await _request(Uri.https('www.googleapis.com', '/oauth2/v3/userinfo'), token: access);
    final email = identity['email'];
    final refresh = tokens['refresh_token'];
    if (email is! String || email.isEmpty || identity['email_verified'] != true || refresh is! String || refresh.isEmpty) {
      throw const DriveFailure('Não foi possível identificar a conta ou manter sua autorização. Reconecte.');
    }
    _checkCancelled();
    final value = {'client': client.toJson(), 'email': email, 'refresh': refresh};
    await vault.write(value);
    _data = value; _access = access; _expires = expiry;
    return DriveSession(email, access);
  }
  @override Future<DriveSession> authorize() async {
    final email = await account();
    if (email == null || _data['refresh'] is! String) throw const DriveFailure('Conecte a conta Google no Windows.');
    if (_access == null || _expires == null || !clock().add(const Duration(minutes: 1)).isBefore(_expires!)) {
      final tokens = await _token({'grant_type': 'refresh_token', 'refresh_token': _data['refresh'] as String});
      final (access, expiry) = _parseToken(tokens);
      _access = access; _expires = expiry;
    }
    return DriveSession(email, _access!);
  }
  @override Future<void> clearToken(String token) async { if (_access == token) { _access = null; _expires = null; } }
  @override Future<void> disconnect() async {
    final value = <String, dynamic>{if (_client != null) 'client': _client!.toJson()};
    await vault.write(value);
    _data = value; _access = null; _expires = null;
  }
}
