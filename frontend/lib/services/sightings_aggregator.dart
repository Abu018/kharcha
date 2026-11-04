import '../ble/kharcha_uuid.dart';
import '../models/nearby_sighting.dart';

/// Collapses raw BLE callbacks into one row per ephemeral ID.
class SightingsAggregator {
  SightingsAggregator({
    this.staleAfter = const Duration(seconds: 8),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration staleAfter;
  final DateTime Function() _now;
  final _byId = <String, NearbySighting>{};

  void add(String ephemeralId, int rssi, [DateTime? at]) {
    final id = ephemeralId.trim().toLowerCase();
    if (decodeTemporaryId(id) == null) {
      return;
    }
    final when = at ?? _now();
    final previous = _byId[id];
    _byId[id] = previous == null
        ? NearbySighting(
            ephemeralId: id,
            rssi: rssi,
            seen: 1,
            lastSeen: when,
          )
        : previous.hear(rssi, when);
  }

  void clear() => _byId.clear();

  /// Drops IDs not heard recently and sorts in-range, strongest first.
  List<NearbySighting> snapshot([DateTime? at]) {
    final when = at ?? _now();
    _byId.removeWhere(
      (_, sighting) => when.difference(sighting.lastSeen) > staleAfter,
    );
    final rows = _byId.values.toList()
      ..sort((a, b) {
        final range = (b.inRange ? 1 : 0) - (a.inRange ? 1 : 0);
        if (range != 0) {
          return range;
        }
        return b.rssi.compareTo(a.rssi);
      });
    return List.unmodifiable(rows);
  }
}
