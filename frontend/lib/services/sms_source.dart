import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One SMS from the device inbox.
class SmsMessageData {
  const SmsMessageData({
    required this.ref,
    required this.address,
    required this.body,
    required this.date,
  });

  factory SmsMessageData.fromMap(Map<Object?, Object?> map) {
    final date = map['date'];
    return SmsMessageData(
      ref: map['ref'] as String? ?? '',
      address: map['address'] as String? ?? '',
      body: map['body'] as String? ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(date is int ? date : 0),
    );
  }

  /// Stable id derived from sender and text, used to avoid saving the same
  /// message twice.
  final String ref;
  final String address;
  final String body;
  final DateTime date;
}

/// Access to the device's SMS. Only Android supports it; elsewhere every call
/// reports "not available".
class SmsSource {
  static const _methods = MethodChannel('my_app/sms');
  static const _incoming = EventChannel('my_app/sms/incoming');

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> hasPermission() => _call<bool>('hasPermission', false);

  /// Shows the system permission prompt. Returns whether access was granted.
  Future<bool> requestPermission() => _call<bool>('requestPermission', false);

  /// Messages received after [since], oldest first.
  Future<List<SmsMessageData>> readInbox({
    required DateTime since,
    int limit = 300,
  }) async {
    if (!isSupported) {
      return const [];
    }
    final raw = await _methods.invokeListMethod<Object?>('readInbox', {
      'since': since.millisecondsSinceEpoch,
      'limit': limit,
    });
    return [
      for (final item in raw ?? const [])
        if (item is Map) SmsMessageData.fromMap(item),
    ];
  }

  /// SMS arriving while the app is open. Requires permission.
  Stream<SmsMessageData> incoming() {
    if (!isSupported) {
      return const Stream.empty();
    }
    return _incoming
        .receiveBroadcastStream()
        .where((e) => e is Map)
        .map((e) => SmsMessageData.fromMap(e as Map<Object?, Object?>));
  }

  /// When the last successful sync for [key] (one per user) ended.
  Future<DateTime?> lastSync(String key) async {
    final value = await _call<int?>('getLastSync', null, {'key': key});
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> setLastSync(String key, DateTime value) => _call<void>(
    'setLastSync',
    null,
    {'key': key, 'value': value.millisecondsSinceEpoch},
  );

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
