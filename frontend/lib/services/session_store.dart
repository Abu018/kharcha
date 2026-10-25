import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the user signed in across app restarts.
///
/// Only the refresh token is stored (encrypted by the platform keystore),
/// never the password. The last email is kept to prefill the sign-in form.
class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _refreshTokenKey = 'refresh_token';
  static const _emailKey = 'last_email';

  Future<String?> refreshToken() => _read(_refreshTokenKey);

  Future<String?> lastEmail() => _read(_emailKey);

  Future<void> save({required String refreshToken, String? email}) async {
    await _write(_refreshTokenKey, refreshToken);
    if (email != null && email.isNotEmpty) {
      await _write(_emailKey, email);
    }
  }

  /// Forgets the session but keeps the email for the next sign in.
  Future<void> clear() async {
    try {
      await _storage.delete(key: _refreshTokenKey);
    } on PlatformException {
      // Nothing stored or storage unavailable; either way it is gone.
    } on MissingPluginException {
      // Not available on this platform, e.g. in widget tests.
    }
  }

  Future<String?> _read(String key) async {
    try {
      final value = await _storage.read(key: key);
      return value == null || value.isEmpty ? null : value;
    } on PlatformException {
      // Keystore entries are lost on some reinstalls; treat as signed out.
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException {
      // The user just has to sign in again next time.
    } on MissingPluginException {
      // Not available on this platform, e.g. in widget tests.
    }
  }
}
