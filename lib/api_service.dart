import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);

  @override
  String toString() => message;
}

/// Cliente do ERP: login e perguntas para a assistente Consart.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const defaultServer = 'https://erp.consart.com.br';
  static const _kServer = 'server_url';
  static const _kToken = 'token';
  static const _kUserName = 'user_name';

  String serverUrl = '';
  String? token;
  String? userName;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    serverUrl = p.getString(_kServer) ?? defaultServer;
    token = p.getString(_kToken);
    userName = p.getString(_kUserName);
  }

  Future<void> logout() async {
    token = null;
    userName = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kUserName);
  }

  static String normalizeServer(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    if (serverUrl.isEmpty) {
      throw ApiException('Configure o endereço do servidor.');
    }
    return Uri.parse('$serverUrl$path').replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (isLoggedIn) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final req = http.Request(method, _uri(path, query))
      ..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    return _execute(req, timeout: timeout);
  }

  Future<http.Response> _raw(http.BaseRequest req, Duration timeout) async {
    try {
      return await http.Response.fromStream(await req.send().timeout(timeout));
    } on TimeoutException {
      throw ApiException('Servidor não respondeu. Verifique a conexão.');
    } catch (_) {
      throw ApiException('Sem conexão com o servidor ($serverUrl).');
    }
  }

  static ApiException _error(http.Response res, Map<String, dynamic> json) {
    if (res.statusCode == 401) {
      return ApiException('Sessão expirada. Saia e entre novamente.', 401);
    }
    var msg = json['message'] ?? json['error'] ?? json['erro'];
    // Algumas rotas mandam o código em "error" e o texto em "message".
    if (msg is String && RegExp(r'^[A-Z0-9_]+$').hasMatch(msg)) {
      final detail = json['detail'];
      if (detail is String && detail.isNotEmpty) msg = '$msg: $detail';
    }
    return ApiException(
      msg is String && msg.isNotEmpty
          ? msg
          : 'Erro na requisição (${res.statusCode}).',
      res.statusCode,
    );
  }

  Future<dynamic> _execute(
    http.BaseRequest req, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final res = await _raw(req, timeout);
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {}
    final json =
        decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _error(res, json);
    }
    if (json['ok'] == false || json['success'] == false) {
      throw _error(res, json);
    }
    return decoded;
  }

  // ── Login ────────────────────────────────────────────────────────────
  Future<void> login(String server, String login, String password) async {
    final url = normalizeServer(server);
    serverUrl = url;
    final json = _map(await _send('POST', '/api/login',
        body: {'login': login.trim(), 'password': password}));
    final t = json['token'];
    if (t is! String || t.isEmpty) {
      throw ApiException('Login sem token na resposta.');
    }
    token = t;
    final user = json['user'];
    userName = user is Map ? (user['name']?.toString() ?? login) : login;

    final p = await SharedPreferences.getInstance();
    await p.setString(_kServer, url);
    await p.setString(_kToken, t);
    await p.setString(_kUserName, userName!);
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

  // ── Assistente ───────────────────────────────────────────────────────

  /// Pergunta à Consart (o ERP consulta os módulos com o Claude).
  /// [history] = conversa anterior: [{'role': 'user'|'assistant', 'text': ...}].
  Future<AssistantAnswer> ask(String text,
      {List<Map<String, String>> history = const []}) async {
    final json = await _send('POST', '/api/assistant/chat',
        body: {
          'text': text.trim(),
          if (history.isNotEmpty) 'history': history,
        },
        timeout: const Duration(seconds: 120));
    return AssistantAnswer.fromJson(_map(json));
  }
}
