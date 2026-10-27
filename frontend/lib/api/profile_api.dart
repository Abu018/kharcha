import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import 'api_client.dart';

class Profile {
  const Profile({
    required this.firstName,
    required this.lastName,
    this.age,
    this.salaryRupees,
  });

  final String firstName;
  final String lastName;

  /// `null` until the user fills it in.
  final int? age;

  /// Monthly salary in whole rupees; `null` until the user fills it in.
  final int? salaryRupees;

  factory Profile.fromJson(Map<String, dynamic> json, {Profile? fallback}) {
    return Profile(
      firstName: json['first_name'] as String? ?? fallback?.firstName ?? '',
      lastName: json['last_name'] as String? ?? fallback?.lastName ?? '',
      age: (json['age'] as num?)?.toInt() ?? fallback?.age,
      salaryRupees: (json['salary'] as num?)?.toInt() ?? fallback?.salaryRupees,
    );
  }
}

/// Calls the authenticated profile routes under `/api/v1`.
class ProfileApi {
  ProfileApi({http.Client? client, String? baseUrl})
    : _api = ApiClient(client: client, baseUrl: baseUrl);

  final ApiClient _api;

  /// `GET /api/v1/profile`. Throws [ApiException] with `statusCode` 401 when
  /// the access token is missing or expired.
  Future<Profile> getProfile({required String accessToken}) async {
    final envelope = await _api.send(
      'GET',
      '/api/v1/profile',
      accessToken: accessToken,
    );
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Unexpected response from the server.');
    }
    return Profile.fromJson(data);
  }

  /// `GET /api/v1/users`: other users, by name, whose name or email
  /// contains [query]. Everyone (up to 50) when [query] is empty.
  Future<List<AppUser>> listUsers({
    required String accessToken,
    String query = '',
  }) async {
    final search = query.trim();
    final envelope = await _api.send(
      'GET',
      search.isEmpty
          ? '/api/v1/users'
          : '/api/v1/users?${Uri(queryParameters: {'q': search}).query}',
      accessToken: accessToken,
    );
    final data = envelope['data'];
    if (data is! List) {
      return const [];
    }
    return [
      for (final item in data)
        if (item is Map<String, dynamic>) AppUser.fromJson(item),
    ];
  }

  /// `PUT /api/v1/profile`. `null` age or salary leaves the saved value
  /// unchanged. Throws [ApiException] with `statusCode` 401 when the access
  /// token is missing or expired.
  Future<Profile> updateProfile({
    required String accessToken,
    required Profile profile,
  }) async {
    final envelope = await _api.send(
      'PUT',
      '/api/v1/profile',
      accessToken: accessToken,
      body: {
        'first_name': profile.firstName,
        'last_name': profile.lastName,
        'age': ?profile.age,
        'salary': ?profile.salaryRupees,
      },
    );

    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      return profile;
    }
    return Profile.fromJson(data, fallback: profile);
  }
}
