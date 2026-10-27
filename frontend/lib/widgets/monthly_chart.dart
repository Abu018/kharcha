import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../models/spending_chart.dart';
import '../theme/app_theme.dart';

/// Bar chart of spending per month. The x-axis always shows every month of
/// the chart; the y-axis has four equal steps rounded to a readable amount.
class MonthlyChart extends StatelessWidget {
  const MonthlyChart({super.key, required this.chart, this.highlight});

  final SpendingChart chart;

  /// Index of the bar to draw in the accent colour, e.g. the current month.
  final int? highlight;

  static const _steps = 4;

  @override
  Widget build(BuildContext context) {
    final points = chart.points;
    final highest = points.fold<int>(0, (m, p) => math.max(m, p.paise)) / 100;
    final step = niceStep(highest / _steps);
    final maxY = step * _steps;

    return Container(
      key: const Key('monthly-chart'),
      padding: const EdgeInsets.fromLTRB(12, 18, 18, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: AspectRatio(
        aspectRatio: 1.5,
        child: BarChart(
          BarChartData(
            minY: 0,
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            barGroups: [
              for (var i = 0; i < points.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: points[i].paise / 100,
                      width: 14,
                      color: i == highlight
                          ? AppColors.lime
                          : AppColors.lavender,
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
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(
                      compactRupees(value),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        i >= 0 && i < points.length
                            ? points[i].label.substring(
                                0,
                                math.min(1, points[i].label.length),
                              )
                            : '',
                        style: TextStyle(
                          color: i == highlight
                              ? Colors.white
                              : AppColors.muted,
                          fontSize: 11,
                          fontWeight: i == highlight
                              ? FontWeight.w700
                              : FontWeight.w500,
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
                getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                  '${points[group.x].label}\n'
                  '${formatPaise((rod.toY * 100).round(), decimals: false)}',
                  const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounds [raw] rupees up to 1, 2 or 5 times a power of ten, so axis labels
/// land on amounts like ₹500 or ₹2,000. At least ₹250 so an empty year still
/// has a sensible scale.
double niceStep(double raw) {
  if (raw <= 250) {
    return 250;
  }
  final magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  for (final m in const [1, 2, 5, 10]) {
    if (raw <= m * magnitude) {
      return m * magnitude;
    }
  }
  return 10 * magnitude;
}

/// `0`, `500`, `2k`, `1.5L`: short rupee labels for the y-axis.
String compactRupees(double rupees) {
  String trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  if (rupees >= 100000) {
    return '${trim(rupees / 100000)}L';
  }
  if (rupees >= 1000) {
    return '${trim(rupees / 1000)}k';
  }
  return trim(rupees);
}
