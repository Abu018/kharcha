import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../ble/kharcha_uuid.dart';

/// One BLE advertisement that matched the Kharcha service UUID.
class BleAdvertisement {
  const BleAdvertisement({required this.ephemeralId, required this.rssi});

  factory BleAdvertisement.fromMap(Map<Object?, Object?> map) {
    final rssi = map['rssi'];
    return BleAdvertisement(
      ephemeralId: (map['ephemeral_id'] as String? ?? '').toLowerCase(),
      rssi: rssi is int ? rssi : 0,
    );
  }

  final String ephemeralId;
  final int rssi;
}

/// Phone Bluetooth: advertise this user's temporary ID and scan for others.
///
/// Only Android is supported. The backend ID is passed in; this class does
/// not fetch or compute it.
class BlePresence {
  BlePresence({bool? supported}) : _supportedOverride = supported;

  static const _methods = MethodChannel('my_app/ble');
  static const _incoming = EventChannel('my_app/ble/advertisements');

  final bool? _supportedOverride;

  bool get isSupported =>
      _supportedOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  Future<bool> hasPermission() => _call('hasPermission', false);

  Future<bool> requestPermission() => _call('requestPermission', false);

  Future<bool> isBluetoothOn() => _call('isBluetoothOn', false);

  /// System prompt to turn Bluetooth on. Returns whether it is on afterwards.
  Future<bool> enableBluetooth() => _call('enableBluetooth', false);

  Future<bool> canAdvertise() => _call('canAdvertise', false);

  /// Puts [temporaryId] in Service Data and starts broadcasting.
  Future<void> startAdvertising(String temporaryId) async {
    if (decodeTemporaryId(temporaryId) == null) {
      throw const BleException('Temporary ID was not 16 hex characters.');
    }
    await _invoke('startAdvertising', {
      'temporaryId': temporaryId.trim().toLowerCase(),
      'serviceUuid': kharchaServiceUuid,
    });
  }

  Future<void> stopAdvertising() => _invoke('stopAdvertising');

  Stream<BleAdvertisement> advertisements() {
    if (!isSupported) {
      return const Stream.empty();
    }
    return _incoming
        .receiveBroadcastStream()
        .where((e) => e is Map)
        .map((e) => BleAdvertisement.fromMap(e as Map<Object?, Object?>));
  }

  Future<void> startScan() => _invoke('startScan', {
    'serviceUuid': kharchaServiceUuid,
  });

  Future<void> stopScan() => _invoke('stopScan');

  Future<void> stop() => _invoke('stop');

  Future<T> _call<T>(String method, T fallback, [Object? args]) async {
    if (!isSupported) {
      return fallback;
    }
    try {
      return await _methods.invokeMethod<T>(method, args) ?? fallback;
    } on MissingPluginException {
      return fallback;
    } on PlatformException {
      return fallback;
    }
  }

  Future<void> _invoke(String method, [Object? args]) async {
    if (!isSupported) {
      return;
    }
    try {
      await _methods.invokeMethod<void>(method, args);
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      throw BleException(e.message ?? 'Bluetooth failed.');
    }
  }
}

class BleException implements Exception {
  const BleException(this.message);
  final String message;

  @override
  String toString() => message;
}
