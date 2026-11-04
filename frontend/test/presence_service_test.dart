import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/temporary_id.dart';
import 'package:my_app/services/presence_service.dart';

TemporaryID _id({
  String current = 'a1b2c3d4e5f60718',
  Duration until = const Duration(hours: 1),
}) {
  final expires = DateTime.now().toUtc().add(until);
  return TemporaryID(
    id: current,
    expiresAt: expires,
    nextId: '9f8e7d6c5b4a3210',
    nextExpiresAt: expires.add(const Duration(minutes: 15)),
  );
}

void main() {
  test('start caches the backend-issued id and notify listeners', () async {
    final seen = <String?>[];
    final presence = PresenceService()..onId = (id) => seen.add(id?.id);
    addTearDown(presence.stop);

    await presence.start(() async => _id());

    expect(presence.current?.id, 'a1b2c3d4e5f60718');
    expect(seen.last, 'a1b2c3d4e5f60718');
  });

  test('ensure reuses a still-valid id without fetching again', () async {
    var fetches = 0;
    final presence = PresenceService();
    addTearDown(presence.stop);
    await presence.start(() async {
      fetches++;
      return _id();
    });

    final again = await presence.ensure(() async {
      fetches++;
      return _id(current: 'deadbeefdeadbeef');
    });

    expect(again?.id, 'a1b2c3d4e5f60718');
    expect(fetches, 1);
  });
}
