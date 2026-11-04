import 'package:flutter/material.dart';

import '../models/analytics_overview.dart';
import '../models/expense.dart';
import '../theme/app_theme.dart';
import '../widgets/analytics_charts.dart';

/// Spending insights: one shared date filter drives every chart.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({
    super.key,
    this.overview,
    this.loading = false,
    this.error,
    this.dateRange,
    this.onDateRangeChanged,
    this.onRefresh,
  });

  final AnalyticsOverview? overview;
  final bool loading;
  final String? error;

  /// Inclusive range applied to all graphs. `null` = current calendar month.
  final DateTimeRange? dateRange;
  final ValueChanged<DateTimeRange?>? onDateRangeChanged;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final body = overview == null && loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.lime))
        : overview == null
        ? _Message(
            error ?? 'No insights yet. Add a few payments to see charts.',
            onRefresh: onRefresh,
          )
        : _InsightsBody(
            overview: overview!,
            dateRange: dateRange,
            onDateRangeChanged: onDateRangeChanged,
            loading: loading,
          );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Insights'),
        backgroundColor: AppColors.background,
        actions: [
          if (onRefresh != null)
            IconButton(
              key: const Key('insights-refresh'),
              tooltip: 'Refresh',
              onPressed: loading ? null : () => onRefresh?.call(),
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          _InsightsFilterBar(
            dateRange: dateRange,
            onDateRangeChanged: onDateRangeChanged,
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.lime,
              onRefresh: onRefresh ?? () async {},
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared period control for every chart on the Insights tab.
class _InsightsFilterBar extends StatelessWidget {
  const _InsightsFilterBar({
    required this.dateRange,
    required this.onDateRangeChanged,
  });

  final DateTimeRange? dateRange;
  final ValueChanged<DateTimeRange?>? onDateRangeChanged;

  @override
  Widget build(BuildContext context) {
    if (onDateRangeChanged == null) {
      return const SizedBox.shrink();
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final thisMonth = DateTimeRange(
      start: DateTime(today.year, today.month),
      end: today,
    );
    final lastMonthStart = DateTime(today.year, today.month - 1);
    final lastMonth = DateTimeRange(
      start: lastMonthStart,
      end: DateTime(today.year, today.month, 0),
    );
    final last7 = DateTimeRange(
      start: today.subtract(const Duration(days: 6)),
      end: today,
    );

    final preset = _matchPreset(dateRange, thisMonth, lastMonth, last7);

    return Material(
      color: AppColors.surface,
      child: SingleChildScrollView(
        key: const Key('insights-filter'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          children: [
            _FilterChip(
              key: const Key('insights-filter-this-month'),
              label: 'This month',
              selected: preset == _Preset.thisMonth,
              onTap: () => onDateRangeChanged!(null),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              key: const Key('insights-filter-last-month'),
              label: 'Last month',
              selected: preset == _Preset.lastMonth,
              onTap: () => onDateRangeChanged!(lastMonth),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              key: const Key('insights-filter-7d'),
              label: 'Last 7 days',
              selected: preset == _Preset.last7,
              onTap: () => onDateRangeChanged!(last7),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              key: const Key('insights-filter-custom'),
              label: preset == _Preset.custom && dateRange != null
                  ? _formatRange(dateRange!)
                  : 'Custom',
              selected: preset == _Preset.custom,
              icon: Icons.calendar_month_outlined,
              onTap: () => _pickCustom(context, dateRange ?? thisMonth),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustom(BuildContext context, DateTimeRange initial) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
      initialDateRange: initial,
      helpText: 'Filter all insights',
      saveText: 'Apply',
    );
    if (picked != null) {
      onDateRangeChanged?.call(picked);
    }
  }
}

enum _Preset { thisMonth, lastMonth, last7, custom }

_Preset _matchPreset(
  DateTimeRange? range,
  DateTimeRange thisMonth,
  DateTimeRange lastMonth,
  DateTimeRange last7,
) {
  if (range == null) {
    return _Preset.thisMonth;
  }
  bool same(DateTimeRange a, DateTimeRange b) =>
      DateUtils.isSameDay(a.start, b.start) &&
      DateUtils.isSameDay(a.end, b.end);
  if (same(range, thisMonth)) {
    return _Preset.thisMonth;
  }
  if (same(range, lastMonth)) {
    return _Preset.lastMonth;
  }
  if (same(range, last7)) {
    return _Preset.last7;
  }
  return _Preset.custom;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => FilterChip(
    selected: selected,
    showCheckmark: false,
    avatar: icon == null
        ? null
        : Icon(
            icon,
            size: 16,
            color: selected ? AppColors.ink : AppColors.muted,
          ),
    label: Text(label),
    selectedColor: AppColors.lime,
    backgroundColor: AppColors.surfaceHigh,
    labelStyle: TextStyle(
      color: selected ? AppColors.ink : Colors.white,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    ),
    side: BorderSide(color: selected ? AppColors.lime : AppColors.outline),
    onSelected: (_) => onTap(),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRefresh});

  final String text;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 80),
      Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted, fontSize: 15),
      ),
      if (onRefresh != null) ...[
        const SizedBox(height: 16),
        Center(
          child: TextButton(onPressed: onRefresh, child: const Text('Retry')),
        ),
      ],
    ],
  );
}

class _InsightsBody extends StatelessWidget {
  const _InsightsBody({
    required this.overview,
    this.dateRange,
    this.onDateRangeChanged,
    this.loading = false,
  });

  final AnalyticsOverview overview;
  final DateTimeRange? dateRange;
  final ValueChanged<DateTimeRange?>? onDateRangeChanged;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final s = overview.summary;
    final change = s.changePercent;
    final changeLabel = change == 0
        ? 'same as last period'
        : change > 0
        ? '↑ ${change.toStringAsFixed(0)}% vs last period'
        : '↓ ${(-change).toStringAsFixed(0)}% vs last period';

    final hourPoints = [
      for (final h in overview.byHour)
        NamedAmount(label: h.label, amount: h.amount),
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            key: const Key('insights-body'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                'All charts · ${_periodCaption(overview, dateRange)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This period',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.formattedTotal,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      changeLabel,
                      style: TextStyle(
                        color: change > 0
                            ? AppColors.error
                            : change < 0
                            ? AppColors.mint
                            : AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    CompareBarChart(
                      leftLabel: 'This',
                      leftPaise: s.totalSpent,
                      rightLabel: 'Last',
                      rightPaise: s.previousTotal,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _StatChip(
                            label: 'Daily avg',
                            value: s.formattedDaily,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatChip(
                            label: 'Avg payment',
                            value: s.formattedAverage,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatChip(
                            label: 'Payments',
                            value: '${s.transactionCount}',
                          ),
                        ),
                      ],
                    ),
                    if (s.largest != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Largest: ${s.largest!.formattedAmount}'
                        '${s.largest!.vendor.isEmpty ? '' : ' · ${s.largest!.vendor}'}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (overview.insights.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionTitle('Tips'),
              const SizedBox(height: 8),
              for (final tip in overview.insights)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TipCard(tip: tip),
                ),
            ],
            const SizedBox(height: 8),
            _SectionTitle('By category'),
              const SizedBox(height: 8),
              _Card(child: CategoryPieChart(categories: overview.categories)),
              const SizedBox(height: 16),
              _SectionTitle('Top vendors'),
              const SizedBox(height: 8),
              _Card(
                child: NamedBarChart(
                  points: [
                    for (final m in overview.merchants)
                      NamedAmount(label: m.merchant, amount: m.amount),
                  ],
                  accent: AppColors.peach,
                  maxBars: 5,
                ),
              ),
              const SizedBox(height: 16),
              _SectionTitle('Weekday vs weekend'),
              const SizedBox(height: 8),
              _Card(
                child: Column(
                  children: [
                    CompareBarChart(
                      leftLabel: 'Weekday',
                      leftPaise: overview.weekdayWeekend.weekdayTotal,
                      rightLabel: 'Weekend',
                      rightPaise: overview.weekdayWeekend.weekendTotal,
                      leftColor: AppColors.blue,
                      rightColor: AppColors.pink,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Daily avg · weekday ${formatPaise(overview.weekdayWeekend.weekdayDailyAvg, decimals: false)}'
                      ' · weekend ${formatPaise(overview.weekdayWeekend.weekendDailyAvg, decimals: false)}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionTitle('By day of week'),
              const SizedBox(height: 8),
              _Card(
                child: NamedBarChart(
                  points: overview.byWeekday,
                  accent: AppColors.lavender,
                  keepZeros: true,
                  maxBars: 7,
                ),
              ),
              const SizedBox(height: 16),
              _SectionTitle('Spend by hour'),
              const SizedBox(height: 8),
              _Card(
                child: NamedBarChart(
                  points: hourPoints,
                  accent: AppColors.mint,
                  keepZeros: true,
                  maxBars: 24,
                ),
              ),
              const SizedBox(height: 16),
              _SectionTitle('Personal vs split'),
              const SizedBox(height: 8),
              _Card(
                child: CompareBarChart(
                  leftLabel: 'Personal',
                  leftPaise: overview.personalVsSplit.personalPaise,
                  rightLabel: 'Split',
                  rightPaise: overview.personalVsSplit.splitPaise,
                  leftColor: AppColors.lime,
                  rightColor: AppColors.blue,
                ),
              ),
              const SizedBox(height: 16),
              _SectionTitle('Group balances'),
              const SizedBox(height: 8),
              _Card(
                child: Row(
                  children: [
                    Expanded(
                      child: _BalanceTile(
                        label: 'You owe',
                        paise: overview.balances.youOwePaise,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BalanceTile(
                        label: "You're owed",
                        paise: overview.balances.youAreOwedPaise,
                        color: AppColors.mint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.lime,
              backgroundColor: Colors.transparent,
            ),
          ),
      ],
    );
  }
}

String _periodCaption(AnalyticsOverview overview, DateTimeRange? range) {
  if (range != null) {
    return _formatRange(range);
  }
  if (overview.from.isEmpty) {
    return 'This month';
  }
  if (overview.from == overview.to) {
    return overview.from;
  }
  return '${overview.from} → ${overview.to}';
}

String _formatRange(DateTimeRange range) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String day(DateTime d) => '${d.day} ${months[d.month - 1]}';
  return DateUtils.isSameDay(range.start, range.end)
      ? day(range.start)
      : '${day(range.start)} – ${day(range.end)}';
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
  );
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ],
    ),
  );
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.tip});

  final InsightCard tip;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.outline),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_iconFor(tip.type), color: AppColors.lime, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            tip.message,
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
        ),
      ],
    ),
  );

  static IconData _iconFor(String type) => switch (type) {
    'category_spike' || 'period_spike' => Icons.trending_up_rounded,
    'category_drop' || 'period_drop' => Icons.trending_down_rounded,
    'frequent_merchant' => Icons.storefront_outlined,
    'large_transaction' => Icons.bolt_rounded,
    'weekend_spending' => Icons.weekend_outlined,
    'you_owe' || 'you_are_owed' => Icons.groups_outlined,
    _ => Icons.lightbulb_outline_rounded,
  };
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    required this.label,
    required this.paise,
    required this.color,
  });

  final String label;
  final int paise;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          formatPaise(paise, decimals: false),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ],
    ),
  );
}
