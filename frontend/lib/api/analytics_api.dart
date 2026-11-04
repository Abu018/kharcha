import 'package:http/http.dart' as http;

import '../models/analytics_overview.dart';
import 'api_client.dart';

/// Authenticated analytics routes under `/api/v1/analytics`.
class AnalyticsApi {
  AnalyticsApi({http.Client? client, String? baseUrl})
    : _api = ApiClient(client: client, baseUrl: baseUrl);

  final ApiClient _api;

  /// `GET /api/v1/analytics/overview`. Defaults to the current month.
  Future<AnalyticsOverview> overview({
    required String accessToken,
    DateTime? from,
    DateTime? to,
  }) async {
    final params = <String, String>{
      if (from != null) 'from': _date(from),
      if (to != null) 'to': _date(to),
    };
    final query = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    final envelope = await _api.send(
      'GET',
      '/api/v1/analytics/overview$query',
      accessToken: accessToken,
    );
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Insights response was missing data.');
    }
    return AnalyticsOverview.fromJson(data);
  }

  static String _date(DateTime d) {
    final local = d.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
