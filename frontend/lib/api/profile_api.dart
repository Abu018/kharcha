import 'package:http/http.dart' as http;

import 'api_client.dart';

class ProfileUpdate {
  const ProfileUpdate({required this.firstName, required this.lastName});

  final String firstName;
  final String lastName;
}

/// Calls the authenticated profile routes under `/api/v1`.
class ProfileApi {
  ProfileApi({http.Client? client, String? baseUrl})
    : _api = ApiClient(client: client, baseUrl: baseUrl);

  final ApiClient _api;

  /// `PUT /api/v1/profile`. Throws [ApiException] with `statusCode` 401 when
  /// the access token is missing or expired.
  Future<ProfileUpdate> updateProfile({
    required String accessToken,
    required String firstName,
    required String lastName,
  }) async {
    final envelope = await _api.send(
      'PUT',
      '/api/v1/profile',
      accessToken: accessToken,
      body: {'first_name': firstName, 'last_name': lastName},
    );

    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      return ProfileUpdate(firstName: firstName, lastName: lastName);
    }
    return ProfileUpdate(
      firstName: data['first_name'] as String? ?? firstName,
      lastName: data['last_name'] as String? ?? lastName,
    );
  }
}
