/// Another user of the app, as listed when picking group members.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.firstName = '',
    this.lastName = '',
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['user_id'] as String? ?? '',
    email: json['email'] as String? ?? '',
    firstName: json['first_name'] as String? ?? '',
    lastName: json['last_name'] as String? ?? '',
  );

  final String id;
  final String email;
  final String firstName;
  final String lastName;

  String get displayName {
    final name = '$firstName $lastName'.trim();
    return name.isNotEmpty ? name : email;
  }

  String get initials {
    final letters = displayName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return letters.isEmpty ? '?' : letters;
  }
}
