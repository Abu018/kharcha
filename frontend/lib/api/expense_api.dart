import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import '../models/expense.dart';
import '../models/expense_group.dart';
import '../models/spending_chart.dart';
import 'api_client.dart';

/// Calls the authenticated expense routes under `/api/v1`. Every method
/// throws [ApiException] with `statusCode` 401 when the access token is
/// missing or expired.
class ExpenseApi {
  ExpenseApi({http.Client? client, String? baseUrl})
    : _api = ApiClient(client: client, baseUrl: baseUrl);

  final ApiClient _api;

  /// `POST /api/v1/expense`. Returns the saved transaction, or `null` when an
  /// expense with the same `sourceRef` was already recorded.
  Future<Expense?> createExpense({
    required String accessToken,
    required ExpenseInput input,
  }) async {
    final envelope = await _api.send(
      'POST',
      '/api/v1/expense',
      accessToken: accessToken,
      body: input.toJson(),
    );

    final data = envelope['data'];
    if (data is Map<String, dynamic>) {
      return Expense.fromJson(data);
    }
    if (input.sourceRef != null) {
      return null;
    }
    throw const ApiException('Save response did not include the expense.');
  }

  /// `POST /api/v1/create-group`. The signed-in user becomes the group's
  /// owner and [members] are added to it.
  Future<ExpenseGroup> createGroup({
    required String accessToken,
    required String name,
    required List<AppUser> members,
  }) async {
    final envelope = await _api.send(
      'POST',
      '/api/v1/create-group',
      accessToken: accessToken,
      body: {
        'name': name,
        'userIDs': [for (final m in members) m.id],
      },
    );
    final data = envelope['data'];
    final id = data is Map<String, dynamic> ? data['id'] : null;
    if (id is! String || id.isEmpty) {
      throw const ApiException('Create group response did not include the group.');
    }
    return ExpenseGroup(id: id, name: name, members: members);
  }

  /// `GET /api/v1/expenses/monthly`: how much was spent in each month of
  /// [year] (the current year when omitted), Jan to Dec.
  Future<SpendingChart> monthlySpending({
    required String accessToken,
    int? year,
  }) async {
    final query = year == null ? '' : '?year=$year';
    final envelope = await _api.send(
      'GET',
      '/api/v1/expenses/monthly$query',
      accessToken: accessToken,
    );
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Monthly spending response was empty.');
    }
    return SpendingChart.fromJson(data);
  }

  /// `GET /api/v1/expenses`, newest first. [startDate] and [endDate] are
  /// inclusive calendar days; leave them out for no bound.
  Future<List<Expense>> listExpenses({
    required String accessToken,
    int limit = 200,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final query = Uri(
      queryParameters: {
        'limit': '$limit',
        if (startDate != null) 'start_date': _day(startDate),
        if (endDate != null) 'end_date': _day(endDate),
      },
    ).query;
    final envelope = await _api.send(
      'GET',
      '/api/v1/expenses?$query',
      accessToken: accessToken,
    );
    final data = envelope['data'];
    if (data is! List) {
      return const [];
    }
    return [
      for (final item in data)
        if (item is Map<String, dynamic>) Expense.fromJson(item),
    ];
  }
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
