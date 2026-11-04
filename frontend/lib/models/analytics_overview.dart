import 'expense.dart';

/// `GET /api/v1/analytics/overview` — spending insights for the Insights tab.
class AnalyticsOverview {
  const AnalyticsOverview({
    required this.from,
    required this.to,
    required this.summary,
    required this.categories,
    required this.merchants,
    required this.weekdayWeekend,
    required this.byWeekday,
    required this.byHour,
    required this.personalVsSplit,
    required this.balances,
    required this.insights,
  });

  factory AnalyticsOverview.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(Object? raw) => [
      if (raw is List)
        for (final item in raw)
          if (item is Map<String, dynamic>) item,
    ];

    return AnalyticsOverview(
      from: json['from'] is String ? json['from'] as String : '',
      to: json['to'] is String ? json['to'] as String : '',
      summary: AnalyticsSummary.fromJson(
        json['summary'] is Map<String, dynamic>
            ? json['summary'] as Map<String, dynamic>
            : const {},
      ),
      categories: [
        for (final m in maps(json['categories'])) CategorySpend.fromJson(m),
      ],
      merchants: [
        for (final m in maps(json['merchants'])) MerchantSpend.fromJson(m),
      ],
      weekdayWeekend: WeekdayWeekend.fromJson(
        json['weekday_weekend'] is Map<String, dynamic>
            ? json['weekday_weekend'] as Map<String, dynamic>
            : const {},
      ),
      byWeekday: [
        for (final m in maps(json['by_weekday'])) NamedAmount.fromJson(m),
      ],
      byHour: [for (final m in maps(json['by_hour'])) HourAmount.fromJson(m)],
      personalVsSplit: PersonalVsSplit.fromJson(
        json['personal_vs_split'] is Map<String, dynamic>
            ? json['personal_vs_split'] as Map<String, dynamic>
            : const {},
      ),
      balances: GroupBalances.fromJson(
        json['balances'] is Map<String, dynamic>
            ? json['balances'] as Map<String, dynamic>
            : const {},
      ),
      insights: [
        for (final m in maps(json['insights'])) InsightCard.fromJson(m),
      ],
    );
  }

  final String from;
  final String to;
  final AnalyticsSummary summary;
  final List<CategorySpend> categories;
  final List<MerchantSpend> merchants;
  final WeekdayWeekend weekdayWeekend;
  final List<NamedAmount> byWeekday;
  final List<HourAmount> byHour;
  final PersonalVsSplit personalVsSplit;
  final GroupBalances balances;
  final List<InsightCard> insights;
}

class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totalSpent,
    required this.transactionCount,
    required this.averageTransaction,
    required this.dailyAverage,
    required this.previousTotal,
    required this.changePercent,
    this.largest,
  });

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) {
    final prev = json['previous_period'];
    final largest = json['largest_expense'];
    return AnalyticsSummary(
      totalSpent: _int(json['total_spent']),
      transactionCount: _int(json['transaction_count']),
      averageTransaction: _int(json['average_transaction']),
      dailyAverage: _int(json['daily_average']),
      previousTotal: prev is Map ? _int(prev['total_spent']) : 0,
      changePercent: prev is Map ? _double(prev['change_percent']) : 0,
      largest: largest is Map<String, dynamic>
          ? LargestExpense.fromJson(largest)
          : null,
    );
  }

  final int totalSpent;
  final int transactionCount;
  final int averageTransaction;
  final int dailyAverage;
  final int previousTotal;
  final double changePercent;
  final LargestExpense? largest;

  String get formattedTotal => formatPaise(totalSpent, decimals: false);
  String get formattedDaily => formatPaise(dailyAverage, decimals: false);
  String get formattedAverage =>
      formatPaise(averageTransaction, decimals: false);
}

class LargestExpense {
  const LargestExpense({
    required this.id,
    required this.vendor,
    required this.category,
    required this.amountPaise,
  });

  factory LargestExpense.fromJson(Map<String, dynamic> json) => LargestExpense(
    id: json['id'] is String ? json['id'] as String : '',
    vendor: json['vendor'] is String ? json['vendor'] as String : '',
    category: json['category'] is String ? json['category'] as String : '',
    amountPaise: _int(json['amount_paise']),
  );

  final String id;
  final String vendor;
  final String category;
  final int amountPaise;

  String get formattedAmount => formatPaise(amountPaise, decimals: false);
}

class CategorySpend {
  const CategorySpend({
    required this.name,
    required this.amount,
    required this.percent,
    required this.count,
    required this.changePercent,
  });

  factory CategorySpend.fromJson(Map<String, dynamic> json) => CategorySpend(
    name: json['name'] is String ? json['name'] as String : '',
    amount: _int(json['amount']),
    percent: _double(json['percent']),
    count: _int(json['count']),
    changePercent: _double(json['change_percent']),
  );

  final String name;
  final int amount;
  final double percent;
  final int count;
  final double changePercent;
}

class MerchantSpend {
  const MerchantSpend({
    required this.merchant,
    required this.category,
    required this.amount,
    required this.count,
  });

  factory MerchantSpend.fromJson(Map<String, dynamic> json) => MerchantSpend(
    merchant: json['merchant'] is String ? json['merchant'] as String : '',
    category: json['category'] is String ? json['category'] as String : '',
    amount: _int(json['amount']),
    count: _int(json['count']),
  );

  final String merchant;
  final String category;
  final int amount;
  final int count;
}

class WeekdayWeekend {
  const WeekdayWeekend({
    required this.weekdayTotal,
    required this.weekendTotal,
    required this.weekdayDailyAvg,
    required this.weekendDailyAvg,
    required this.weekendRatio,
  });

  factory WeekdayWeekend.fromJson(Map<String, dynamic> json) => WeekdayWeekend(
    weekdayTotal: _int(json['weekday_total']),
    weekendTotal: _int(json['weekend_total']),
    weekdayDailyAvg: _int(json['weekday_daily_avg']),
    weekendDailyAvg: _int(json['weekend_daily_avg']),
    weekendRatio: _double(json['weekend_ratio']),
  );

  final int weekdayTotal;
  final int weekendTotal;
  final int weekdayDailyAvg;
  final int weekendDailyAvg;
  final double weekendRatio;
}

class NamedAmount {
  const NamedAmount({required this.label, required this.amount});

  factory NamedAmount.fromJson(Map<String, dynamic> json) => NamedAmount(
    label: json['label'] is String ? json['label'] as String : '',
    amount: _int(json['amount']),
  );

  final String label;
  final int amount;
}

class HourAmount {
  const HourAmount({required this.hour, required this.amount});

  factory HourAmount.fromJson(Map<String, dynamic> json) => HourAmount(
    hour: _int(json['hour']),
    amount: _int(json['amount']),
  );

  final int hour;
  final int amount;

  String get label {
    final h = hour % 24;
    final suffix = h < 12 ? 'a' : 'p';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '$hour12$suffix';
  }
}

class PersonalVsSplit {
  const PersonalVsSplit({
    required this.personalPaise,
    required this.splitPaise,
  });

  factory PersonalVsSplit.fromJson(Map<String, dynamic> json) =>
      PersonalVsSplit(
        personalPaise: _int(json['personal_paise']),
        splitPaise: _int(json['split_paise']),
      );

  final int personalPaise;
  final int splitPaise;
}

class GroupBalances {
  const GroupBalances({
    required this.youOwePaise,
    required this.youAreOwedPaise,
  });

  factory GroupBalances.fromJson(Map<String, dynamic> json) => GroupBalances(
    youOwePaise: _int(json['you_owe_paise']),
    youAreOwedPaise: _int(json['you_are_owed_paise']),
  );

  final int youOwePaise;
  final int youAreOwedPaise;
}

class InsightCard {
  const InsightCard({
    required this.type,
    required this.message,
    this.category,
    this.merchant,
    this.changePercent,
  });

  factory InsightCard.fromJson(Map<String, dynamic> json) => InsightCard(
    type: json['type'] is String ? json['type'] as String : '',
    message: json['message'] is String ? json['message'] as String : '',
    category: json['category'] is String ? json['category'] as String : null,
    merchant: json['merchant'] is String ? json['merchant'] as String : null,
    changePercent: json['change_percent'] is num
        ? (json['change_percent'] as num).toDouble()
        : null,
  );

  final String type;
  final String message;
  final String? category;
  final String? merchant;
  final double? changePercent;
}

int _int(Object? v) => v is num ? v.toInt() : 0;

double _double(Object? v) => v is num ? v.toDouble() : 0;
