import 'app_user.dart';
import 'expense.dart';

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

/// An expense split inside a group, from `GET`/`POST /groups/{id}/expenses`.
class GroupExpense {
  const GroupExpense({
    required this.id,
    required this.groupId,
    required this.name,
    required this.amountPaise,
    this.paidBy = '',
    this.description = '',
    this.createdAt,
  });

  factory GroupExpense.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    final amount = json['amount'];
    return GroupExpense(
      id: text('id'),
      groupId: text('group_id'),
      name: text('name'),
      amountPaise: amount is num ? amount.toInt() : 0,
      paidBy: text('paid_by'),
      description: text('description'),
      createdAt: DateTime.tryParse(text('created_at'))?.toLocal(),
    );
  }

  final String id;
  final String groupId;
  final String name;
  final int amountPaise;
  final String paidBy;
  final String description;
  final DateTime? createdAt;

  String get title => name.isNotEmpty ? name : description;

  String get formattedAmount => formatPaise(amountPaise);
}
