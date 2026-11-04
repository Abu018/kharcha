import 'nearby_user.dart';

/// One other Kharcha phone heard over BLE during a nearby session.
class NearbySighting {
  const NearbySighting({
    required this.ephemeralId,
    required this.rssi,
    required this.seen,
    required this.lastSeen,
    this.userId,
    this.firstName,
    this.lastName,
    this.sharedGroups = const [],
  });

  /// Temporary ID copied from the other phone's advertisement.
  final String ephemeralId;

  /// Smoothed RSSI in dBm. Closer to zero is stronger.
  final int rssi;
  final int seen;
  final DateTime lastSeen;

  /// Filled after `POST /presence/sightings` resolves the ID.
  final String? userId;
  final String? firstName;
  final String? lastName;
  final List<NearbySharedGroup> sharedGroups;

  String get displayName {
    final name = [firstName, lastName]
        .whereType<String>()
        .where((p) => p.trim().isNotEmpty)
        .join(' ');
    return name.isEmpty ? ephemeralId : name;
  }

  /// Rough radio closeness. Not a measured distance.
  bool get inRange => rssi >= inRangeRssi;

  String get signalLabel {
    if (rssi >= -55) {
      return 'Strong';
    }
    if (rssi >= -70) {
      return 'Fair';
    }
    if (rssi >= -85) {
      return 'Weak';
    }
    return 'Faint';
  }

  NearbySighting hear(int rssi, DateTime at) => NearbySighting(
    ephemeralId: ephemeralId,
    rssi: ((this.rssi * 7) + (rssi * 3)) ~/ 10,
    seen: seen + 1,
    lastSeen: at,
    userId: userId,
    firstName: firstName,
    lastName: lastName,
    sharedGroups: sharedGroups,
  );

  NearbySighting identified({
    required String userId,
    required String firstName,
    required String lastName,
    List<NearbySharedGroup> sharedGroups = const [],
  }) => NearbySighting(
    ephemeralId: ephemeralId,
    rssi: rssi,
    seen: seen,
    lastSeen: lastSeen,
    userId: userId,
    firstName: firstName,
    lastName: lastName,
    sharedGroups: sharedGroups,
  );

  /// Heard at least this strongly counts as in range (~10 m in open space).
  static const inRangeRssi = -85;
}
