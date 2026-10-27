import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A notification from a UPI or bank app that mentions an amount.
class PaymentNotification {
  const PaymentNotification({
    required this.ref,
    required this.app,
    required this.title,
    required this.text,
    required this.date,
  });

  factory PaymentNotification.fromMap(Map<Object?, Object?> map) {
    final date = map['date'];
    return PaymentNotification(
      ref: map['ref'] as String? ?? '',
      app: map['app'] as String? ?? '',
      title: map['title'] as String? ?? '',
      text: map['text'] as String? ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(date is int ? date : 0),
    );
  }

  /// Stable id derived from the app, text and time, used to avoid saving the
  /// same notification twice.
  final String ref;

  /// Display name of the app that posted it, e.g. `Google Pay`.
  final String app;
  final String title;
  final String text;
  final DateTime date;
}

/// Payment notifications collected by the Android notification listener.
/// Only Android supports it; elsewhere every call reports "not available".
class NotificationSource {
  static const _methods = MethodChannel('my_app/notifications');
  static const _incoming = EventChannel('my_app/notifications/incoming');

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether the user has turned on notification access for this app.
  Future<bool> hasAccess() => _call<bool>('hasAccess', false);

  /// Opens the Android settings page where notification access is granted.
  /// There is no result; check [hasAccess] when the app is resumed.
  Future<void> openSettings() => _call<void>('openSettings', null);

  /// Notifications not yet acknowledged, oldest first.
  Future<List<PaymentNotification>> pending() async {
    if (!isSupported) {
      return const [];
    }
    try {
      final raw = await _methods.invokeListMethod<Object?>('pending');
      return [
        for (final item in raw ?? const [])
          if (item is Map) PaymentNotification.fromMap(item),
      ];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Drops notifications that have been handled so they are not read again.
  Future<void> acknowledge(List<String> refs) =>
      _call<void>('acknowledge', null, {'refs': refs});

  /// Payment notifications posted while the app is open.
  Stream<PaymentNotification> incoming() {
    if (!isSupported) {
      return const Stream.empty();
    }
    return _incoming
        .receiveBroadcastStream()
        .where((e) => e is Map)
        .map((e) => PaymentNotification.fromMap(e as Map<Object?, Object?>));
  }

  Future<T> _call<T>(String method, T fallback, [Object? args]) async {
    if (!isSupported) {
      return fallback;
    }
    try {
      return await _methods.invokeMethod<T>(method, args) ?? fallback;
    } on MissingPluginException {
      return fallback;
    }
  }
}
