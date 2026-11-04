import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/api/presence_api.dart';
import 'package:my_app/models/nearby_sighting.dart';

http.Response envelope(int status, String message, [Object? data]) {
  return http.Response(
    jsonEncode({'success': status < 400, 'message': message, 'data': ?data}),
    status,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  group('PresenceApi.current', () {
    test('reads the backend-issued id and expiry', () async {
      late http.Request captured;
      final api = PresenceApi(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          captured = request;
          return envelope(200, 'temporary id', {
            'temporary_id': 'a1b2c3d4e5f60718',
            'expires_at': '2026-11-02T04:15:00Z',
            'next_temporary_id': '9f8e7d6c5b4a3210',
            'next_expires_at': '2026-11-02T04:30:00Z',
          });
        }),
      );

      final id = await api.current(accessToken: 'token');

      expect(captured.method, 'GET');
      expect(
        captured.url.toString(),
        'http://example.test/api/v1/presence/temporary-id',
      );
      expect(captured.headers['Authorization'], 'Bearer token');
      expect(id.id, 'a1b2c3d4e5f60718');
      expect(id.expiresAt, DateTime.utc(2026, 11, 2, 4, 15));
      expect(id.nextId, '9f8e7d6c5b4a3210');
      expect(id.nextExpiresAt, DateTime.utc(2026, 11, 2, 4, 30));
    });

    test('throws when the envelope has no data', () async {
      final api = PresenceApi(
        baseUrl: 'http://example.test',
        client: MockClient((_) async => envelope(200, 'temporary id')),
      );

      expect(
        () => api.current(accessToken: 'token'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Unexpected response from the server.',
          ),
        ),
      );
    });
  });

  group('PresenceApi.reportSightings', () {
    test('posts heard ids and reads eligible people', () async {
      late http.Request captured;
      final api = PresenceApi(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          captured = request;
          return envelope(200, 'nearby users', {
            'users': [
              {
                'user_id': '52d0da55-3e16-4c32-bf18-d3cca9d33633',
                'ephemeral_id': '1122334455667788',
                'first_name': 'Amit',
                'last_name': 'Shah',
                'rssi': -58,
                'seen': 4,
                'in_range': true,
                'shared_groups': [
                  {'id': 'g1', 'name': 'Goa trip'},
                ],
              },
            ],
          });
        }),
      );

      final users = await api.reportSightings(
        accessToken: 'token',
        sightings: [
          NearbySighting(
            ephemeralId: '1122334455667788',
            rssi: -58,
            seen: 4,
            lastSeen: DateTime.utc(2026, 11, 2),
          ),
        ],
      );

      expect(captured.method, 'POST');
      expect(
        captured.url.toString(),
        'http://example.test/api/v1/presence/sightings',
      );
      expect(jsonDecode(captured.body), {
        'sightings': [
          {
            'ephemeral_id': '1122334455667788',
            'rssi': -58,
            'seen': 4,
          },
        ],
      });
      expect(users, hasLength(1));
      expect(users.single.displayName, 'Amit Shah');
      expect(users.single.inRange, isTrue);
      expect(users.single.sharedGroups.single.name, 'Goa trip');
      expect(users.single.sharedGroups.single.id, 'g1');
    });
  });
}
