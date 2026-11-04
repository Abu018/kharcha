import 'dart:async';

import 'package:fake_async/fake_async.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/nearby_user.dart';
import 'package:my_app/models/temporary_id.dart';
import 'package:my_app/services/ble_presence.dart';
import 'package:my_app/services/nearby_session.dart';
import 'package:my_app/services/presence_service.dart';

class _FakeBle extends BlePresence {
  _FakeBle() : super(supported: true);

  String? advertised;
  var scanStarted = false;
  var permission = true;
  var bluetoothOn = true;
  var advertise = true;
  final ads = StreamController<BleAdvertisement>.broadcast();

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<bool> isBluetoothOn() async => bluetoothOn;

  @override
  Future<bool> enableBluetooth() async => bluetoothOn;

  @override
  Future<bool> canAdvertise() async => advertise;

  @override
  Future<void> startAdvertising(String temporaryId) async {
    advertised = temporaryId;
  }

  @override
  Future<void> stopAdvertising() async => advertised = null;

  @override
  Stream<BleAdvertisement> advertisements() => ads.stream;

  @override
  Future<void> startScan() async => scanStarted = true;

  @override
  Future<void> stopScan() async => scanStarted = false;

  @override
  Future<void> stop() async {
    advertised = null;
    scanStarted = false;
  }
}

TemporaryID _own() {
  final expires = DateTime.now().toUtc().add(const Duration(hours: 1));
  return TemporaryID(
    id: 'a1b2c3d4e5f60718',
    expiresAt: expires,
    nextId: '9f8e7d6c5b4a3210',
    nextExpiresAt: expires.add(const Duration(minutes: 15)),
  );
}

void main() {
  test('advertises the backend id and lists other phones in range', () async {
    final ble = _FakeBle();
    addTearDown(ble.ads.close);
    final presence = PresenceService();
    addTearDown(presence.stop);
    final session = NearbySession(
      ble: ble,
      ids: presence,
      fetchId: () async => _own(),
    );
    addTearDown(session.dispose);

    await session.start();

    expect(session.running, isTrue);
    expect(ble.advertised, 'a1b2c3d4e5f60718');
    expect(ble.scanStarted, isTrue);

    ble.ads.add(
      const BleAdvertisement(ephemeralId: 'a1b2c3d4e5f60718', rssi: -40),
    );
    ble.ads.add(
      const BleAdvertisement(ephemeralId: '1122334455667788', rssi: -52),
    );
    await Future<void>.delayed(Duration.zero);

    expect(session.nearby, hasLength(1));
    expect(session.nearby.single.ephemeralId, '1122334455667788');
    expect(session.nearby.single.inRange, isTrue);
  });

  test('resolves heard ids to people who share a group', () {
    fakeAsync((async) {
      final ble = _FakeBle();
      addTearDown(ble.ads.close);
      final presence = PresenceService();
      addTearDown(presence.stop);
      final session = NearbySession(
        ble: ble,
        ids: presence,
        fetchId: () async => _own(),
        resolve: (sightings) async => [
          NearbyUser(
            userId: 'u-amit',
            ephemeralId: sightings.single.ephemeralId,
            firstName: 'Amit',
            lastName: 'Shah',
            rssi: -52,
            seen: 1,
            inRange: true,
            sharedGroups: const [
              NearbySharedGroup(id: 'g1', name: 'Goa trip'),
            ],
          ),
        ],
      );
      addTearDown(session.dispose);

      unawaited(session.start());
      async.flushMicrotasks();
      ble.ads.add(
        const BleAdvertisement(ephemeralId: '1122334455667788', rssi: -52),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(session.nearby, hasLength(1));
      expect(session.nearby.single.displayName, 'Amit Shah');
      expect(session.nearby.single.sharedGroups.single.name, 'Goa trip');
      expect(session.identifiedNearby, hasLength(1));
    });
  });

  test('asks for bluetooth when it is off', () async {
    final ble = _FakeBle()..bluetoothOn = false;
    addTearDown(ble.ads.close);
    final session = NearbySession(
      ble: ble,
      ids: PresenceService(),
      fetchId: () async => _own(),
    );
    addTearDown(session.dispose);

    await session.start();

    expect(session.running, isFalse);
    expect(session.error, contains('Turn Bluetooth on'));
    expect(ble.advertised, isNull);
  });
}
