import 'package:http/http.dart' as http;

import '../models/expense.dart';
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

  /// `GET /api/v1/expenses`, newest first.
  Future<List<Expense>> listExpenses({
    required String accessToken,
    int limit = 200,
  }) async {
    final envelope = await _api.send(
      'GET',
      '/api/v1/expenses?limit=$limit',
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
