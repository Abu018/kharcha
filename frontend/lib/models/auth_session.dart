import 'dart:convert';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.email,
    this.refreshToken = '',
    this.userId = '',
    this.userName = '',
    this.firstName = '',
    this.lastName = '',
  });

  /// Builds a session from a Keycloak access token, reading the user's
  /// details from its claims. The API has already validated the token, so
  /// the signature is not checked here.
  factory AuthSession.fromAccessToken(
    String accessToken, {
    String refreshToken = '',
    String fallbackEmail = '',
  }) {
    final claims = _decodeClaims(accessToken);
    String claim(String key) {
      final value = claims[key];
      return value is String ? value : '';
    }

    final email = claim('email');
    return AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      email: email.isNotEmpty ? email : fallbackEmail,
      userId: claim('sub'),
      userName: claim('preferred_username'),
      firstName: claim('given_name'),
      lastName: claim('family_name'),
    );
  }

  final String accessToken;
  final String refreshToken;
  final String email;
  final String userId;
  final String userName;
  final String firstName;
  final String lastName;

  String get displayName {
    final name = '$firstName $lastName'.trim();
    return name.isNotEmpty ? name : email;
  }

  AuthSession copyWith({String? firstName, String? lastName}) {
    return AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      email: email,
      userId: userId,
      userName: userName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
    );
  }

  static Map<String, dynamic> _decodeClaims(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return const {};
    }
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }
}
