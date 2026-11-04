import 'dart:async';

import '../models/nearby_sighting.dart';
import '../models/nearby_user.dart';
import '../models/temporary_id.dart';
import 'ble_presence.dart';
import 'presence_service.dart';
import 'sightings_aggregator.dart';

/// Advertises this phone's backend ID and lists other Kharcha IDs in range.
class NearbySession {
  NearbySession({
    required this.ble,
    required this.ids,
    required this.fetchId,
    this.resolve,
    SightingsAggregator? aggregator,
    DateTime Function()? now,
  }) : _aggregator = aggregator ?? SightingsAggregator(now: now),
       _now = now ?? DateTime.now {
    ids.onId = _onIdRotated;
  }

  final BlePresence ble;
  final PresenceService ids;
  final Future<TemporaryID?> Function() fetchId;
  final Future<List<NearbyUser>?> Function(List<NearbySighting> sightings)?
  resolve;
  final SightingsAggregator _aggregator;
  final DateTime Function() _now;

  void Function()? onUpdate;

  bool running = false;
  bool canAdvertise = true;
  String? error;
  List<NearbySighting> nearby = const [];

  StreamSubscription<BleAdvertisement>? _ads;
  Timer? _sweep;
  Timer? _resolveTimer;
  var _resolved = <String, NearbyUser>{};
  bool _paused = false;
  bool _wantRunning = false;
  bool _resolving = false;

  TemporaryID? get ownId => ids.current;

  Future<void> start() async {
    error = null;
    if (running) {
      return;
    }
    if (!ble.isSupported) {
      error = 'Nearby discovery is available on Android.';
      onUpdate?.call();
      return;
    }
    if (!await ble.hasPermission() && !await ble.requestPermission()) {
      error = 'Bluetooth permission is needed to find people nearby.';
      onUpdate?.call();
      return;
    }
    if (!await ble.isBluetoothOn() && !await ble.enableBluetooth()) {
      error = 'Turn Bluetooth on to find people nearby.';
      onUpdate?.call();
      return;
    }
    final id = await ids.ensure(fetchId);
    if (id == null) {
      error = 'Could not load your temporary ID.';
      onUpdate?.call();
      return;
    }
    _wantRunning = true;
    _paused = false;
    canAdvertise = await ble.canAdvertise();
    if (canAdvertise) {
      await _advertise(id.id);
    }
    await _ads?.cancel();
    _ads = ble.advertisements().listen(_onAdvertisement, onError: (_) {});
    try {
      await ble.startScan();
    } on BleException catch (e) {
      error = e.message;
      await stop();
      return;
    }
    running = true;
    _sweep?.cancel();
    _sweep = Timer.periodic(const Duration(seconds: 2), (_) => _publish());
    _publish();
  }

  Future<void> pause() async {
    if (!running) {
      return;
    }
    _paused = true;
    await _haltRadio();
    running = false;
    onUpdate?.call();
  }

  Future<void> resume() async {
    if (!_wantRunning || !_paused) {
      return;
    }
    await start();
  }

  Future<void> stop() async {
    _wantRunning = false;
    _paused = false;
    await _haltRadio();
    running = false;
    _aggregator.clear();
    _resolved = {};
    nearby = const [];
    onUpdate?.call();
  }

  Future<void> dispose() async {
    ids.onId = null;
    await stop();
  }

  Future<void> _haltRadio() async {
    _sweep?.cancel();
    _sweep = null;
    _resolveTimer?.cancel();
    _resolveTimer = null;
    await _ads?.cancel();
    _ads = null;
    await ble.stop();
  }

  Future<void> _advertise(String temporaryId) async {
    try {
      await ble.startAdvertising(temporaryId);
    } on BleException catch (e) {
      canAdvertise = false;
      error = e.message;
      onUpdate?.call();
    }
  }

  void _onIdRotated(TemporaryID? id) {
    if (!running || id == null || !canAdvertise) {
      return;
    }
    unawaited(_advertise(id.id));
  }

  void _onAdvertisement(BleAdvertisement ad) {
    final mine = ids.current;
    if (mine != null &&
        (ad.ephemeralId == mine.id || ad.ephemeralId == mine.nextId)) {
      return;
    }
    _aggregator.add(ad.ephemeralId, ad.rssi, _now());
    _publish();
  }

  void _publish() {
    nearby = [
      for (final row in _aggregator.snapshot(_now()))
        _withIdentity(row),
    ];
    onUpdate?.call();
    _scheduleResolve();
  }

  NearbySighting _withIdentity(NearbySighting row) {
    final user = _resolved[row.ephemeralId];
    if (user == null) {
      return row;
    }
    return row.identified(
      userId: user.userId,
      firstName: user.firstName,
      lastName: user.lastName,
      sharedGroups: user.sharedGroups,
    );
  }

  /// In-range people whose ephemeral IDs the server has mapped to a user.
  List<NearbySighting> get identifiedNearby => [
    for (final s in nearby)
      if (s.inRange && s.userId != null && s.sharedGroups.isNotEmpty) s,
  ];

  void _scheduleResolve() {
    if (resolve == null ||
        nearby.isEmpty ||
        _resolveTimer != null ||
        _resolving) {
      return;
    }
    _resolveTimer = Timer(const Duration(seconds: 2), () {
      _resolveTimer = null;
      unawaited(_resolveNow());
    });
  }

  Future<void> _resolveNow() async {
    final report = resolve;
    final batch = nearby;
    if (report == null || batch.isEmpty || !running || _resolving) {
      return;
    }
    _resolving = true;
    try {
      final users = await report(batch);
      if (users == null || !running) {
        return;
      }
      _resolved = {for (final u in users) u.ephemeralId: u};
      nearby = [for (final row in _aggregator.snapshot(_now())) _withIdentity(row)];
      onUpdate?.call();
    } on Object {
      // Keep hex IDs on screen; tried again on the next scan window.
    } finally {
      _resolving = false;
    }
  }
}
