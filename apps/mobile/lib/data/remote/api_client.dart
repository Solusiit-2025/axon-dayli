import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session_store.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message, [this.details]);

  final int statusCode;
  final String code;
  final String message;
  final Object? details;

  bool get isUnauthorized => statusCode == 401;
  bool get isNetwork => statusCode == 0;

  @override
  String toString() => message;
}

/// Klien HTTP tipis dengan refresh token otomatis.
class ApiClient {
  ApiClient({required this.store, http.Client? client}) : _client = client ?? http.Client();

  final SessionStore store;
  final http.Client _client;
  Future<bool>? _refreshing;

  static const _timeout = Duration(seconds: 25);

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) {
    return _send('GET', path, query: query);
  }

  Future<Map<String, dynamic>> post(String path, [Object? body]) {
    return _send('POST', path, body: body);
  }

  Future<Map<String, dynamic>> patch(String path, [Object? body]) {
    return _send('PATCH', path, body: body);
  }

  Future<Map<String, dynamic>> delete(String path) {
    return _send('DELETE', path);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool allowRetry = true,
  }) async {
    final base = await store.baseUrl();
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    final token = await store.accessToken();

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    late http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(0, 'TIMEOUT', 'Server tidak merespons. Cek koneksi atau alamat server.');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'NETWORK', 'Gagal menghubungi server: ${e.message}');
    } catch (e) {
      if (e.toString().contains('SocketException') || e.toString().contains('OFFLINE')) {
        throw ApiException(0, 'OFFLINE', 'Tidak ada koneksi internet.');
      }
      rethrow;
    }

    if (response.statusCode == 401 && allowRetry && path != '/auth/refresh') {
      final ok = await _refreshOnce();
      if (ok) {
        return _send(method, path, body: body, query: query, allowRetry: false);
      }
    }

    final decoded = _decode(response);

    if (response.statusCode >= 400) {
      final err = decoded['error'];
      if (err is Map) {
        throw ApiException(
          response.statusCode,
          (err['code'] ?? 'ERROR').toString(),
          (err['message'] ?? 'Terjadi kesalahan').toString(),
          err['details'],
        );
      }
      throw ApiException(response.statusCode, 'ERROR', 'Permintaan gagal (${response.statusCode})');
    }

    return decoded;
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return <String, dynamic>{};
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      return value is Map<String, dynamic> ? value : <String, dynamic>{'data': value};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<bool> _refreshOnce() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refresh = await store.refreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    try {
      final base = await store.baseUrl();
      final res = await _client
          .post(
            Uri.parse('$base/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refresh}),
          )
          .timeout(_timeout);

      if (res.statusCode != 200) return false;

      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      await store.saveTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> ping() async {
    try {
      final base = await store.baseUrl();
      final res = await _client.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
