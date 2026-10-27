/// One bar of a [SpendingChart]: [label] on the x-axis (e.g. `Jan`) and the
/// amount spent in paise.
class ChartPoint {
  const ChartPoint({required this.label, required this.paise});

  final String label;
  final int paise;
}

/// `GET /api/v1/expenses/monthly`: spending per month of one year.
class SpendingChart {
  const SpendingChart({
    required this.title,
    required this.xLabel,
    required this.yLabel,
    required this.points,
  });

  factory SpendingChart.fromJson(Map<String, dynamic> json) {
    String label(Object? axis) =>
        axis is Map && axis['label'] is String ? axis['label'] as String : '';

    final series = json['series'];
    return SpendingChart(
      title: json['title'] is String ? json['title'] as String : '',
      xLabel: label(json['xAxis']),
      yLabel: label(json['yAxis']),
      points: [
        if (series is List)
          for (final p in series)
            if (p is Map)
              ChartPoint(
                label: p['x'] is String ? p['x'] as String : '',
                paise: p['y'] is num ? (p['y'] as num).toInt() : 0,
              ),
      ],
    );
  }

  final String title;
  final String xLabel;
  final String yLabel;

  /// Jan to Dec, in order.
  final List<ChartPoint> points;

  int get totalPaise => points.fold(0, (sum, p) => sum + p.paise);
}
