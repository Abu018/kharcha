import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/analytics_overview.dart';

void main() {
  test('AnalyticsOverview.fromJson parses charts and tips', () {
    final overview = AnalyticsOverview.fromJson({
      'from': '2026-11-01',
      'to': '2026-11-30',
      'currency': 'INR',
      'summary': {
        'total_spent': 2845000,
        'transaction_count': 64,
        'average_transaction': 44453,
        'daily_average': 91774,
        'largest_expense': {
          'id': '8d0f6f8e-0000-0000-0000-000000000001',
          'vendor': 'Croma',
          'category': 'Shopping',
          'amount_paise': 1250000,
        },
        'previous_period': {
          'total_spent': 2510000,
          'change_percent': 13.3,
        },
      },
      'categories': [
        {
          'name': 'Groceries',
          'amount': 920000,
          'percent': 32.3,
          'count': 14,
          'change_percent': 4.1,
        },
      ],
      'merchants': [
        {
          'merchant': 'DMart',
          'category': 'Groceries',
          'amount': 410000,
          'count': 4,
        },
      ],
      'weekday_weekend': {
        'weekday_total': 2000000,
        'weekend_total': 845000,
        'weekday_daily_avg': 90000,
        'weekend_daily_avg': 140000,
        'weekend_ratio': 1.6,
      },
      'by_weekday': [
        {'label': 'Mon', 'amount': 100000},
      ],
      'by_hour': [
        {'hour': 21, 'amount': 50000},
      ],
      'personal_vs_split': {
        'personal_paise': 2500000,
        'split_paise': 345000,
      },
      'balances': {
        'you_owe_paise': 12000,
        'you_are_owed_paise': 45000,
      },
      'insights': [
        {
          'type': 'category_spike',
          'category': 'Fuel',
          'message': 'Fuel spending is up 22% compared to last period.',
          'change_percent': 22.5,
        },
      ],
    });

    expect(overview.from, '2026-11-01');
    expect(overview.summary.totalSpent, 2845000);
    expect(overview.summary.changePercent, 13.3);
    expect(overview.summary.largest?.vendor, 'Croma');
    expect(overview.categories.single.name, 'Groceries');
    expect(overview.merchants.single.merchant, 'DMart');
    expect(overview.weekdayWeekend.weekendRatio, 1.6);
    expect(overview.byHour.single.label, '9p');
    expect(overview.balances.youAreOwedPaise, 45000);
    expect(overview.insights.single.type, 'category_spike');
  });
}
