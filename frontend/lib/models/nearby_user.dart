/// A shared group returned with a nearby person.
class NearbySharedGroup {
  const NearbySharedGroup({required this.id, required this.name});

  factory NearbySharedGroup.fromJson(Map<String, dynamic> json) =>
      NearbySharedGroup(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );

  final String id;
  final String name;
}

/// A person returned by `POST /api/v1/presence/sightings`.
class NearbyUser {
  const NearbyUser({
    required this.userId,
    required this.ephemeralId,
    required this.firstName,
    required this.lastName,
    required this.rssi,
    required this.seen,
    required this.inRange,
    this.sharedGroups = const [],
  });

  factory NearbyUser.fromJson(Map<String, dynamic> json) {
    final groups = json['shared_groups'];
    return NearbyUser(
      userId: json['user_id'] as String? ?? '',
      ephemeralId: (json['ephemeral_id'] as String? ?? '').toLowerCase(),
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      rssi: json['rssi'] is int ? json['rssi'] as int : 0,
      seen: json['seen'] is int ? json['seen'] as int : 0,
      inRange: json['in_range'] == true,
      sharedGroups: [
        if (groups is List)
          for (final g in groups)
            if (g is Map<String, dynamic>) NearbySharedGroup.fromJson(g),
      ].where((g) => g.id.isNotEmpty).toList(),
    );
  }

  final String userId;
  final String ephemeralId;
  final String firstName;
  final String lastName;
  final int rssi;
  final int seen;
  final bool inRange;
  final List<NearbySharedGroup> sharedGroups;

  String get displayName {
    final name = [firstName, lastName]
        .where((p) => p.trim().isNotEmpty)
        .join(' ');
    return name.isEmpty ? ephemeralId : name;
  }

  List<String> get sharedGroupNames => [
    for (final g in sharedGroups) g.name,
  ];
}
