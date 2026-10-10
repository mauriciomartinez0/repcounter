// HTTP access to the Rep Counter API.
//
// Every request carries the access token. When it expires the client trades
// the refresh token for a new pair once and repeats the request, so screens
// never deal with tokens. If the refresh token is no longer valid the session
// is over and [ApiClient.onSessionExpired] fires.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// An error the API answered with. [message] is in Spanish and can be shown
/// to the user as is.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message, [this.details = const {}]);

  final int status;
  final String code;
  final String message;
  final Map<String, dynamic> details;

  /// Retrying the same request later will not help (validation, conflict…).
  bool get isPermanent => status >= 400 && status < 500 && status != 401 && status != 408 && status != 429;

  @override
  String toString() => 'ApiException($status, $code): $message';
}

/// No answer from the server: no internet, timeout, DNS, TLS. Worth retrying.
class NetworkException implements Exception {
  const NetworkException([this.cause]);
  final Object? cause;

  String get message => 'Sin conexión con el servidor. Revisa tu internet.';

  @override
  String toString() => 'NetworkException($cause)';
}

class Tokens {
  const Tokens({
    required this.access,
    required this.refresh,
    required this.accessExpiresAt,
  });

  final String access;
  final String refresh;
  final DateTime accessExpiresAt;

  factory Tokens.fromAuthResponse(Map<String, dynamic> json, DateTime now) =>
      Tokens(
        access: json['accessToken'] as String,
        refresh: json['refreshToken'] as String,
        accessExpiresAt:
            now.add(Duration(seconds: (json['expiresIn'] as num).toInt())),
      );

  Map<String, dynamic> toJson() => {
        'access': access,
        'refresh': refresh,
        'accessExpiresAt': accessExpiresAt.toIso8601String(),
      };

  factory Tokens.fromJson(Map<String, dynamic> j) => Tokens(
        access: j['access'] as String,
        refresh: j['refresh'] as String,
        accessExpiresAt: DateTime.parse(j['accessExpiresAt'] as String),
      );
}

abstract class TokenStore {
  Future<Tokens?> read();
  Future<void> write(Tokens tokens);
  Future<void> clear();
}

/// Android Keystore / iOS Keychain. Tokens never go to SharedPreferences.
class SecureTokenStore implements TokenStore {
  static const _key = 'auth.tokens';
  final _storage = const FlutterSecureStorage();

  @override
  Future<Tokens?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null
          ? null
          : Tokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupted or unreadable after a restore: start signed out.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(Tokens tokens) =>
      _storage.write(key: _key, value: jsonEncode(tokens.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemoryTokenStore implements TokenStore {
  Tokens? _tokens;
  @override
  Future<Tokens?> read() async => _tokens;
  @override
  Future<void> write(Tokens tokens) async => _tokens = tokens;
  @override
  Future<void> clear() async => _tokens = null;
}

class ApiResponse {
  const ApiResponse(this.status, this.body, this.headers);
  final int status;
  final dynamic body;
  final Map<String, String> headers;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.tokens,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? clock,
  })  : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _http = httpClient ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final Uri _base;
  final http.Client _http;
  final TokenStore tokens;
  final Duration timeout;
  final DateTime Function() _clock;

  /// Called when the refresh token was rejected: the user must sign in again.
  VoidCallback? onSessionExpired;

  Future<bool>? _refreshing;

  Uri uri(String path, [Map<String, String>? query]) {
    final relative = path.startsWith('/') ? path.substring(1) : path;
    return _base.resolve(relative).replace(queryParameters: query);
  }

  Future<ApiResponse> get(String path,
          {Map<String, String>? query, Map<String, String>? headers, bool auth = true}) =>
      send('GET', path, query: query, headers: headers, auth: auth);

  Future<ApiResponse> post(String path, {Object? body, bool auth = true}) =>
      send('POST', path, body: body, auth: auth);

  Future<ApiResponse> put(String path, {Object? body}) =>
      send('PUT', path, body: body);

  Future<ApiResponse> delete(String path, {Object? body}) =>
      send('DELETE', path, body: body);

  /// Saves the tokens of a login or registration response.
  Future<void> storeAuthResponse(Map<String, dynamic> json) =>
      tokens.write(Tokens.fromAuthResponse(json, _clock()));

  Future<ApiResponse> send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    bool auth = true,
  }) async {
    if (auth) {
      final current = await tokens.read();
      // Renew a little before expiry instead of waiting for the 401.
      if (current != null &&
          _clock().isAfter(
              current.accessExpiresAt.subtract(const Duration(seconds: 30)))) {
        await _refresh();
      }
    }
    var response = await _raw(method, path, body, query, headers, auth);
    if (response.statusCode == 401 && auth && await _refresh()) {
      response = await _raw(method, path, body, query, headers, auth);
    }
    return _decode(response);
  }

  Future<http.Response> _raw(
    String method,
    String path,
    Object? body,
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
    bool auth,
  ) async {
    final request = http.Request(method, uri(path, query));
    request.headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    if (auth) {
      final current = await tokens.read();
      if (current != null) {
        request.headers['Authorization'] = 'Bearer ${current.access}';
      }
    }
    request.headers.addAll(extraHeaders ?? const {});
    try {
      final streamed = await _http.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException catch (e) {
      throw NetworkException(e);
    } on http.ClientException catch (e) {
      throw NetworkException(e);
    } on Exception catch (e) {
      // SocketException, HandshakeException… without importing dart:io.
      throw NetworkException(e);
    }
  }

  ApiResponse _decode(http.Response response) {
    dynamic body;
    if (response.bodyBytes.isNotEmpty) {
      try {
        body = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        body = null;
      }
    }
    final status = response.statusCode;
    if (status >= 400) {
      final error = body is Map && body['error'] is Map
          ? (body['error'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      throw ApiException(
        status,
        error['code'] as String? ?? 'http_$status',
        error['message'] as String? ??
            (status >= 500
                ? 'El servidor tuvo un problema. Intenta de nuevo en un momento.'
                : 'No se pudo completar la acción.'),
        error,
      );
    }
    return ApiResponse(status, body, response.headers);
  }

  /// Trades the refresh token for a new pair. Concurrent callers share one
  /// attempt, since each refresh token works only once.
  Future<bool> _refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final current = await tokens.read();
    if (current == null) return false;
    try {
      final response = await _decodeRefresh(current.refresh);
      await tokens.write(Tokens.fromAuthResponse(response, _clock()));
      return true;
    } on ApiException catch (e) {
      if (e.status == 401) {
        await tokens.clear();
        onSessionExpired?.call();
      }
      return false;
    }
  }

  Future<Map<String, dynamic>> _decodeRefresh(String refreshToken) async {
    final response = await _raw(
      'POST', '/auth/refresh', {'refreshToken': refreshToken}, null, null, false);
    return _decode(response).body as Map<String, dynamic>;
  }

  void close() => _http.close();
}
