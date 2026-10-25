import 'package:http/http.dart' as http;

import '../models/auth_session.dart';
import 'api_client.dart';

export 'api_client.dart' show ApiException;

/// Calls the public auth routes: `POST /api/v1/register`,
/// `POST /api/v1/login` and `POST /api/v1/auth/refresh`.
class AuthApi {
  AuthApi({http.Client? client, String? baseUrl})
    : _api = ApiClient(client: client, baseUrl: baseUrl);

  final ApiClient _api;

  Future<void> register({
    required String userName,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    await _api.send(
      'POST',
      '/api/v1/register',
      body: {
        'user_name': userName,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'password': password,
      },
    );
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final envelope = await _api.send(
      'POST',
      '/api/v1/login',
      body: {'email': email, 'password': password},
    );
    return _session(envelope, fallbackEmail: email);
  }

  /// Exchanges [refreshToken] for a new session via
  /// `POST /api/v1/auth/refresh`. Throws an unauthorized [ApiException] when
  /// the refresh token has expired or been revoked.
  Future<AuthSession> refresh(String refreshToken) async {
    final envelope = await _api.send(
      'POST',
      '/api/v1/auth/refresh',
      body: {'refresh_token': refreshToken},
    );
    return _session(envelope, fallbackRefreshToken: refreshToken);
  }

  AuthSession _session(
    Map<String, dynamic> envelope, {
    String fallbackEmail = '',
    String fallbackRefreshToken = '',
  }) {
    final data = envelope['data'];
    final accessToken = data is Map<String, dynamic>
        ? data['access_token']
        : null;
    if (accessToken is! String || accessToken.isEmpty) {
      throw const ApiException('Sign in response did not include a token.');
    }
    final refreshToken = (data as Map<String, dynamic>)['refresh_token'];

    return AuthSession.fromAccessToken(
      accessToken,
      refreshToken: refreshToken is String && refreshToken.isNotEmpty
          ? refreshToken
          : fallbackRefreshToken,
      fallbackEmail: fallbackEmail,
    );
  }
}
