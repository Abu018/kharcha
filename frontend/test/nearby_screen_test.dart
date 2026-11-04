import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/nearby_sighting.dart';
import 'package:my_app/models/nearby_user.dart';
import 'package:my_app/models/temporary_id.dart';
import 'package:my_app/screens/nearby_screen.dart';
import 'package:my_app/theme/app_theme.dart';

final _own = TemporaryID(
  id: 'a1b2c3d4e5f60718',
  expiresAt: DateTime.utc(2026, 11, 2, 4, 15),
  nextId: '9f8e7d6c5b4a3210',
  nextExpiresAt: DateTime.utc(2026, 11, 2, 4, 30),
);

Widget _screen({
  bool running = false,
  bool supported = true,
  List<NearbySighting> nearby = const [],
  Future<void> Function()? onStart,
  Future<void> Function()? onStop,
}) => MaterialApp(
  theme: AppTheme.dark(),
  home: NearbyScreen(
    supported: supported,
    running: running,
    canAdvertise: true,
    ownId: _own,
    nearby: nearby,
    onStart: onStart ?? () async {},
    onStop: onStop ?? () async {},
  ),
);

void main() {
  testWidgets('shows this phone id and starts a nearby session', (tester) async {
    var started = 0;
    await tester.pumpWidget(
      _screen(onStart: () async => started++),
    );

    expect(find.byKey(const Key('nearby-own-id')), findsOneWidget);
    expect(find.text('a1b2c3d4e5f60718'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nearby-find-button')));
    await tester.pump();
    expect(started, 1);
  });

  testWidgets('lists in-range ephemeral ids heard over bluetooth', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.8125;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _screen(
        running: true,
        nearby: [
          NearbySighting(
            ephemeralId: '1122334455667788',
            rssi: -52,
            seen: 4,
            lastSeen: DateTime.utc(2026, 11, 2),
          ),
          NearbySighting(
            ephemeralId: 'aabbccddeeff0011',
            rssi: -90,
            seen: 1,
            lastSeen: DateTime.utc(2026, 11, 2),
          ),
        ],
      ),
    );

    expect(find.text('In range'), findsWidgets);
    expect(find.byKey(const Key('nearby-device-1122334455667788')), findsOneWidget);
    expect(find.byKey(const Key('nearby-device-aabbccddeeff0011')), findsOneWidget);
    expect(find.textContaining('Far'), findsOneWidget);
    expect(find.byKey(const Key('nearby-stop-button')), findsOneWidget);
  });

  testWidgets('shows the resolved name once the server maps the id', (tester) async {
    await tester.pumpWidget(
      _screen(
        running: true,
        nearby: [
          NearbySighting(
            ephemeralId: '1122334455667788',
            rssi: -52,
            seen: 4,
            lastSeen: DateTime.utc(2026, 11, 2),
            userId: 'u-amit',
            firstName: 'Amit',
            lastName: 'Shah',
            sharedGroups: const [
              NearbySharedGroup(id: 'g1', name: 'Goa trip'),
            ],
          ),
        ],
      ),
    );

    expect(find.text('Amit Shah'), findsOneWidget);
    expect(find.textContaining('Goa trip'), findsOneWidget);
  });

  testWidgets('explains when bluetooth is not available', (tester) async {
    await tester.pumpWidget(_screen(supported: false));

    expect(find.byKey(const Key('nearby-unsupported')), findsOneWidget);
    expect(find.byKey(const Key('nearby-find-button')), findsNothing);
  });
}
