import 'package:http/http.dart' as http;

import 'api_client.dart';

/// Calls the authenticated push-notification routes under `/api/v1`.
class NotificationApi {
  NotificationApi({http.Client? client, String? baseUrl})
    : _api = ApiClient(client: client, baseUrl: baseUrl);

  final ApiClient _api;

  /// `POST /api/v1/token`: links this device's FCM [token] to the signed-in
  /// user. Sending the same token again only extends how long it is kept.
  Future<void> registerDeviceToken({
    required String accessToken,
    required String token,
  }) async {
    await _api.send(
      'POST',
      '/api/v1/token',
      accessToken: accessToken,
      body: {'token': token},
    );
  }
}
