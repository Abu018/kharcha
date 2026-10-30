// The backend sends with the Firebase Admin SDK, which targets FCM
// registration tokens (getToken/onTokenRefresh), not the installation IDs
// returned by the newer register()/onRegistered API.
// ignore_for_file: deprecated_member_use

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// A push notification that arrived while the app was open. Android and iOS
/// only show a system notification when the app is in the background.
class PushMessage {
  const PushMessage({required this.title, required this.body});

  final String title;
  final String body;
}

/// Firebase Cloud Messaging for this device. Every call quietly does nothing
/// when Firebase is not set up (no `google-services.json`), on web, or when
/// the user declines notifications.
class PushService {
  bool? _ready;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<bool> _init() async {
    if (_ready != null) {
      return _ready!;
    }
    if (!isSupported) {
      return _ready = false;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      return _ready = true;
    } catch (error) {
      debugPrint('Push notifications are off, Firebase not set up: $error');
      return _ready = false;
    }
  }

  /// Asks for notification permission (Android 13+ and iOS) and returns this
  /// device's FCM token, or `null` when push is unavailable or not allowed.
  Future<String?> getToken() async {
    if (!await _init()) {
      return null;
    }
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return null;
      }
      return await messaging.getToken();
    } catch (error) {
      debugPrint('Could not get a push token: $error');
      return null;
    }
  }

  /// New tokens issued by Firebase after [getToken], e.g. when the app's
  /// data is cleared or the old token is revoked.
  Stream<String> tokenRefreshes() async* {
    if (await _init()) {
      yield* FirebaseMessaging.instance.onTokenRefresh;
    }
  }

  /// Messages received while the app is in the foreground.
  Stream<PushMessage> foregroundMessages() async* {
    if (!await _init()) {
      return;
    }
    yield* FirebaseMessaging.onMessage
        .where((m) => m.notification != null)
        .map(
          (m) => PushMessage(
            title: m.notification!.title ?? '',
            body: m.notification!.body ?? '',
          ),
        );
  }

  /// Invalidates this device's token so the next user signing in on it gets
  /// a new one and stops receiving the previous user's notifications.
  Future<void> deleteToken() async {
    if (_ready != true) {
      return;
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      debugPrint('Could not delete the push token: $error');
    }
  }
}
