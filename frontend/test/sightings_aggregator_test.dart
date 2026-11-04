import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/nearby_sighting.dart';
import 'package:my_app/services/sightings_aggregator.dart';

void main() {
  test('counts repeats, smooths rssi, and drops stale ids', () {
    var now = DateTime.utc(2026, 11, 2, 6);
    final aggregator = SightingsAggregator(
      staleAfter: const Duration(seconds: 8),
      now: () => now,
    );

    aggregator.add('a1b2c3d4e5f60718', -50, now);
    aggregator.add('a1b2c3d4e5f60718', -60, now);
    aggregator.add('1122334455667788', -90, now);

    var rows = aggregator.snapshot(now);
    expect(rows, hasLength(2));
    expect(rows.first.ephemeralId, 'a1b2c3d4e5f60718');
    expect(rows.first.inRange, isTrue);
    expect(rows.first.seen, 2);
    expect(rows.first.signalLabel, 'Strong');
    expect(rows.last.ephemeralId, '1122334455667788');
    expect(rows.last.inRange, isFalse);

    now = now.add(const Duration(seconds: 9));
    rows = aggregator.snapshot(now);
    expect(rows, isEmpty);
  });

  test('ignores malformed ids', () {
    final aggregator = SightingsAggregator();
    aggregator.add('not-an-id', -40);
    expect(aggregator.snapshot(), isEmpty);
  });

  test('in-range threshold matches the documented radio cutoff', () {
    final at = DateTime.utc(2026);
    expect(
      NearbySighting(
        ephemeralId: 'a1b2c3d4e5f60718',
        rssi: -85,
        seen: 1,
        lastSeen: at,
      ).inRange,
      isTrue,
    );
    expect(
      NearbySighting(
        ephemeralId: 'a1b2c3d4e5f60718',
        rssi: -86,
        seen: 1,
        lastSeen: at,
      ).inRange,
      isFalse,
    );
  });
}
