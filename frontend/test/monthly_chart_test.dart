import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/spending_chart.dart';
import 'package:my_app/widgets/monthly_chart.dart';

void main() {
  test('parses GET /expenses/monthly', () {
    final chart = SpendingChart.fromJson({
      'title': 'Spent in 2026',
      'xAxis': {'label': 'Month'},
      'yAxis': {'label': 'Spent (₹)'},
      'series': [
        {'x': 'Jan', 'y': 1000},
        {'x': 'Feb', 'y': 20000},
      ],
    });
    expect(chart.title, 'Spent in 2026');
    expect(chart.xLabel, 'Month');
    expect(chart.points.map((p) => p.label), ['Jan', 'Feb']);
    expect(chart.points.map((p) => p.paise), [1000, 20000]);
    expect(chart.totalPaise, 21000);
  });

  test('y-axis steps round up to 1, 2 or 5 times a power of ten', () {
    expect(niceStep(0), 250);
    expect(niceStep(120), 250);
    expect(niceStep(300), 500);
    expect(niceStep(800), 1000);
    expect(niceStep(1200), 2000);
    expect(niceStep(4200), 5000);
    expect(niceStep(37000), 50000);
  });

  test('y-axis labels are short', () {
    expect(compactRupees(0), '0');
    expect(compactRupees(500), '500');
    expect(compactRupees(2000), '2k');
    expect(compactRupees(2500), '2.5k');
    expect(compactRupees(150000), '1.5L');
  });
}
