import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/analytics_overview.dart';
import '../models/expense.dart';
import '../theme/app_theme.dart';
import 'monthly_chart.dart';

/// Donut pie of spend by category.
class CategoryPieChart extends StatelessWidget {
  const CategoryPieChart({super.key, required this.categories});

  final List<CategorySpend> categories;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const _EmptyChart(label: 'No category data yet');
    }
    final total = categories.fold<int>(0, (s, c) => s + c.amount);
    if (total <= 0) {
      return const _EmptyChart(label: 'No spending this period');
    }

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 48,
              sections: [
                for (final c in categories)
                  PieChartSectionData(
                    value: c.amount.toDouble(),
                    color: AppColors.category(c.name),
                    radius: 42,
                    title: c.percent >= 8 ? '${c.percent.round()}%' : '',
                    titleStyle: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final c in categories.take(6))
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.category(c.name),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${c.name} · ${formatPaise(c.amount, decimals: false)}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Vertical bars for named amounts (vendors, weekdays, hour buckets).
class NamedBarChart extends StatelessWidget {
  const NamedBarChart({
    super.key,
    required this.points,
    this.accent = AppColors.lavender,
    this.colors,
    this.maxBars = 8,
    this.keepZeros = false,
  });

  final List<NamedAmount> points;
  final Color accent;

  /// Optional per-bar colours; falls back to [accent].
  final List<Color>? colors;
  final int maxBars;

  /// When true, zero-amount bars stay (useful for hour-of-day).
  final bool keepZeros;

  @override
  Widget build(BuildContext context) {
    final filtered = keepZeros
        ? points
        : points.where((p) => p.amount > 0).toList();
    final display = (filtered.isEmpty ? points : filtered).take(maxBars).toList();
    if (display.isEmpty) {
      return const _EmptyChart(label: 'Nothing to chart yet');
    }

    final highest =
        display.fold<int>(0, (m, p) => math.max(m, p.amount)) / 100;
    final step = niceStep(highest / 4);
    final maxY = step * 4;

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          barGroups: [
            for (var i = 0; i < display.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: display[i].amount / 100,
                    width: display.length > 10 ? 8 : 14,
                    color: colors != null && i < colors!.length
                        ? colors![i]
                        : accent,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(5),
                    ),
                  ),
                ],
              ),
          ],
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: step,
                reservedSize: 36,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(
                    compactRupees(value),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= display.length) {
                    return const SizedBox.shrink();
                  }
                  // For dense hour charts, label every 3rd bar.
                  if (display.length > 12 && i % 3 != 0) {
                    return const SizedBox.shrink();
                  }
                  final label = display[i].label;
                  final short = label.length > 6
                      ? '${label.substring(0, 5)}…'
                      : label;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      short,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: step,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: AppColors.outline, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.card,
              getTooltipItem: (group, _, rod, _) {
                final p = display[group.x.toInt()];
                return BarTooltipItem(
                  '${p.label}\n${formatPaise(p.amount, decimals: false)}',
                  const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Two-bar comparison (this month vs last, weekday vs weekend, personal vs split).
class CompareBarChart extends StatelessWidget {
  const CompareBarChart({
    super.key,
    required this.leftLabel,
    required this.leftPaise,
    required this.rightLabel,
    required this.rightPaise,
    this.leftColor = AppColors.lime,
    this.rightColor = AppColors.lavender,
  });

  final String leftLabel;
  final int leftPaise;
  final String rightLabel;
  final int rightPaise;
  final Color leftColor;
  final Color rightColor;

  @override
  Widget build(BuildContext context) {
    return NamedBarChart(
      points: [
        NamedAmount(label: leftLabel, amount: leftPaise),
        NamedAmount(label: rightLabel, amount: rightPaise),
      ],
      colors: [leftColor, rightColor],
      keepZeros: true,
      maxBars: 2,
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    child: Center(
      child: Text(label, style: const TextStyle(color: AppColors.muted)),
    ),
  );
}
