import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/expense.dart';
import 'package:my_app/models/nearby_sighting.dart';
import 'package:my_app/models/nearby_user.dart';
import 'package:my_app/theme/app_theme.dart';
import 'package:my_app/widgets/split_proposal_sheet.dart';

final _expense = Expense(
  id: 'tx-1',
  amountPaise: 120000,
  currency: 'INR',
  bankName: 'HDFC',
  accountType: 'savings',
  type: 'debit',
  vendor: 'Toit',
  source: 'notification',
);

final _amit = NearbySighting(
  ephemeralId: '1122334455667788',
  rssi: -52,
  seen: 3,
  lastSeen: DateTime.utc(2026, 11, 5),
  userId: 'u-amit',
  firstName: 'Amit',
  lastName: 'Shah',
  sharedGroups: const [NearbySharedGroup(id: 'g1', name: 'Goa trip')],
);

final _ravi = NearbySighting(
  ephemeralId: 'aabbccddeeff0011',
  rssi: -60,
  seen: 2,
  lastSeen: DateTime.utc(2026, 11, 5),
  userId: 'u-ravi',
  firstName: 'Ravi',
  lastName: '',
  sharedGroups: const [NearbySharedGroup(id: 'g1', name: 'Goa trip')],
);

void main() {
  testWidgets('confirms a split with selected nearby people', (tester) async {
    late SplitProposalResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showSplitProposalSheet(
                  context: context,
                  expense: _expense,
                  groupName: 'Goa trip',
                  candidates: [_amit, _ravi],
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('split-proposal-title')), findsOneWidget);
    expect(find.text('Amit Shah'), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);

    await tester.tap(find.byKey(const Key('split-person-aabbccddeeff0011')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('split-proposal-confirm')));
    await tester.pumpAndSettle();

    expect(result?.split, isTrue);
    expect(result?.selectedEphemeralIds, ['1122334455667788']);
  });

  testWidgets('keep personal dismisses without splitting', (tester) async {
    late SplitProposalResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showSplitProposalSheet(
                  context: context,
                  expense: _expense,
                  groupName: 'Goa trip',
                  candidates: [_amit],
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('split-proposal-keep')));
    await tester.pumpAndSettle();

    expect(result?.split, isFalse);
    expect(result?.selectedEphemeralIds, isEmpty);
  });
}
