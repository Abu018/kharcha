import 'package:http/http.dart' as http;

import '../models/nearby_sighting.dart';
import '../models/nearby_user.dart';
import '../models/temporary_id.dart';
import 'api_client.dart';

export 'api_client.dart' show ApiException;

/// Calls the authenticated presence routes under `/api/v1`.
class PresenceApi {
  PresenceApi({http.Client? client, String? baseUrl})
    : _api = ApiClient(client: client, baseUrl: baseUrl);

  final ApiClient _api;

  /// `GET /api/v1/presence/temporary-id`. The backend derives the ID; this
  /// only returns it. Throws [ApiException] with `statusCode` 401 when the
  /// access token is missing or expired.
  Future<TemporaryID> current({required String accessToken}) async {
    final envelope = await _api.send(
      'GET',
      '/api/v1/presence/temporary-id',
      accessToken: accessToken,
    );
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Unexpected response from the server.');
    }
    try {
      return TemporaryID.fromJson(data);
    } on FormatException {
      throw const ApiException('Temporary ID response was incomplete.');
    }
  }

  /// `POST /api/v1/presence/sightings`. Sends IDs heard over BLE; the server
  /// returns people who share a group with the caller.
  Future<List<NearbyUser>> reportSightings({
    required String accessToken,
    required List<NearbySighting> sightings,
  }) async {
    final envelope = await _api.send(
      'POST',
      '/api/v1/presence/sightings',
      accessToken: accessToken,
      body: {
        'sightings': [
          for (final s in sightings)
            {
              'ephemeral_id': s.ephemeralId,
              'rssi': s.rssi,
              'seen': s.seen,
            },
        ],
      },
    );
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Unexpected response from the server.');
    }
    final users = data['users'];
    if (users is! List) {
      return const [];
    }
    return [
      for (final item in users)
        if (item is Map<String, dynamic>) NearbyUser.fromJson(item),
    ];
  }
}
