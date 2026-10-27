import 'app_user.dart';

/// A group of users who share expenses.
class ExpenseGroup {
  const ExpenseGroup({
    required this.id,
    required this.name,
    this.members = const [],
  });

  final String id;
  final String name;

  /// Users added when the group was created, not counting its creator.
  final List<AppUser> members;
}
