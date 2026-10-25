import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Thrown when a request fails or the API cannot be reached.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;

  /// HTTP status, or `null` when the server was never reached.
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Sends JSON requests to the Go API.
///
/// Every response uses the envelope
/// `{ "success": bool, "message": "...", "data": ... }`.
/// [send] returns the decoded envelope on 2xx and throws [ApiException] with
/// the server's `message` otherwise.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const _timeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> send(
    String method,
    String path, {
    Object? body,
    String? accessToken,
  }) async {
    if (_baseUrl.isEmpty) {
      throw const ApiException(missingApiBaseUrlMessage);
    }
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      });
    if (body != null) {
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException('The server took too long to respond.');
    } on http.ClientException {
      throw const ApiException(
        'Could not reach the server. Check that the API is running.',
      );
    }

    final envelope = _decode(response.body);
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok) {
      throw ApiException(
        _message(envelope) ?? 'Request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (envelope == null) {
      throw ApiException(
        'The server response was not valid JSON.',
        statusCode: response.statusCode,
      );
    }
    return envelope;
  }

  Map<String, dynamic>? _decode(String body) {
    if (body.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  String? _message(Map<String, dynamic>? envelope) {
    final message = envelope?['message'] ?? envelope?['error'];
    return message is String && message.isNotEmpty ? message : null;
  }
}
