import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/analytics_overview.dart';
import 'package:my_app/screens/insights_screen.dart';
import 'package:my_app/theme/app_theme.dart';

void main() {
  testWidgets('InsightsScreen shows shared filter and chart sections', (
    tester,
  ) async {
    final overview = AnalyticsOverview.fromJson({
      'from': '2026-11-01',
      'to': '2026-11-30',
      'summary': {
        'total_spent': 100000,
        'transaction_count': 2,
        'average_transaction': 50000,
        'daily_average': 20000,
        'previous_period': {'total_spent': 80000, 'change_percent': 25},
      },
      'categories': [
        {
          'name': 'Food',
          'amount': 60000,
          'percent': 60,
          'count': 1,
          'change_percent': 10,
        },
        {
          'name': 'Transport',
          'amount': 40000,
          'percent': 40,
          'count': 1,
          'change_percent': -5,
        },
      ],
      'merchants': [
        {
          'merchant': 'Swiggy',
          'category': 'Food',
          'amount': 60000,
          'count': 1,
        },
      ],
      'weekday_weekend': {
        'weekday_total': 70000,
        'weekend_total': 30000,
        'weekday_daily_avg': 14000,
        'weekend_daily_avg': 15000,
        'weekend_ratio': 1.1,
      },
      'by_weekday': [
        for (final d in ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'])
          {'label': d, 'amount': d == 'Fri' ? 40000 : 10000},
      ],
      'by_hour': [
        for (var h = 0; h < 24; h++) {'hour': h, 'amount': h == 20 ? 50000 : 0},
      ],
      'personal_vs_split': {
        'personal_paise': 80000,
        'split_paise': 20000,
      },
      'balances': {'you_owe_paise': 0, 'you_are_owed_paise': 15000},
      'insights': [
        {
          'type': 'period_spike',
          'message': 'Spending is up 25% vs the previous period.',
          'change_percent': 25,
        },
      ],
    });

    DateTimeRange? range;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: InsightsScreen(
          overview: overview,
          dateRange: range,
          onDateRangeChanged: (value) => range = value,
        ),
      ),
    );

    expect(find.byKey(const Key('insights-filter')), findsOneWidget);
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Last month'), findsOneWidget);
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.textContaining('↑ 25%'), findsOneWidget);
    expect(find.textContaining('All charts'), findsOneWidget);

    final bodyScrollable = find.descendant(
      of: find.byKey(const Key('insights-body')),
      matching: find.byType(Scrollable),
    );

    Future<void> expectAfterScroll(Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: bodyScrollable,
      );
      expect(finder, findsOneWidget);
    }

    await expectAfterScroll(
      find.text('Spending is up 25% vs the previous period.'),
    );
    await expectAfterScroll(find.text('By category'));
    await expectAfterScroll(find.text('Top vendors'));
    await expectAfterScroll(find.text('Weekday vs weekend'));
    await expectAfterScroll(find.text('Spend by hour'));
    await expectAfterScroll(find.text('Personal vs split'));
    await expectAfterScroll(find.text('Group balances'));
  });

  testWidgets('filter chip notifies parent', (tester) async {
    DateTimeRange? range;
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: InsightsScreen(
          overview: AnalyticsOverview.fromJson({
            'from': '2026-11-01',
            'to': '2026-11-30',
            'summary': {
              'total_spent': 0,
              'transaction_count': 0,
              'average_transaction': 0,
              'daily_average': 0,
              'previous_period': {'total_spent': 0, 'change_percent': 0},
            },
            'categories': [],
            'merchants': [],
            'weekday_weekend': {
              'weekday_total': 0,
              'weekend_total': 0,
              'weekday_daily_avg': 0,
              'weekend_daily_avg': 0,
              'weekend_ratio': 0,
            },
            'by_weekday': const [],
            'by_hour': const [],
            'personal_vs_split': {'personal_paise': 0, 'split_paise': 0},
            'balances': {'you_owe_paise': 0, 'you_are_owed_paise': 0},
            'insights': const [],
          }),
          dateRange: range,
          onDateRangeChanged: (value) {
            range = value;
            calls++;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('insights-filter-last-month')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(range, isNotNull);
  });
}
