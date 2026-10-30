import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/expense_group.dart';
import '../theme/app_theme.dart';
import 'add_expense_screen.dart';

/// Lists a group's expenses and adds new ones.
class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.group,
    required this.currentUserId,
    required this.onLoad,
    required this.onAdd,
  });

  final ExpenseGroup group;
  final String currentUserId;
  final Future<List<GroupExpense>> Function() onLoad;
  final Future<GroupExpense> Function(int amountPaise, String description)
  onAdd;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  List<GroupExpense> _expenses = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.onLoad();
      if (mounted) {
        setState(() => _expenses = list);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not reach the server.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openAdd() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddGroupExpenseScreen(onSubmit: widget.onAdd),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Expense saved')));
      await _load();
    }
  }

  String _paidBy(GroupExpense expense) {
    if (expense.paidBy == widget.currentUserId) {
      return 'You';
    }
    for (final member in widget.group.members) {
      if (member.id == expense.paidBy) {
        return member.firstName.isNotEmpty
            ? member.firstName
            : member.displayName;
      }
    }
    return 'Someone';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.group.name)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-group-expense-button'),
        heroTag: 'add-group-expense',
        onPressed: _openAdd,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add expense'),
      ),
      body: RefreshIndicator(
        color: AppColors.lime,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
          children: [
            _GroupHeader(group: widget.group),
            const SizedBox(height: 24),
            Text('Expenses', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_loading && _expenses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _expenses.isEmpty)
              _Message(
                key: const Key('group-expense-error'),
                icon: Icons.cloud_off_rounded,
                text: _error!,
                action: TextButton(
                  onPressed: _load,
                  child: const Text('Try again'),
                ),
              )
            else if (_expenses.isEmpty)
              const _Message(
                key: Key('group-expense-empty'),
                icon: Icons.receipt_long_rounded,
                text: 'No expenses yet. Tap "Add expense" to split one.',
              )
            else
              for (final expense in _expenses) ...[
                _ExpenseTile(expense: expense, paidBy: _paidBy(expense)),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final ExpenseGroup group;

  @override
  Widget build(BuildContext context) {
    final members = group.members.length + 1;
    final names = group.members
        .map((m) => m.firstName.isNotEmpty ? m.firstName : m.displayName)
        .join(', ');

    return Container(
      key: const Key('group-detail-header'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.lavender,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.name,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            names.isEmpty
                ? '$members member${members == 1 ? '' : 's'}'
                : 'You, $names',
            style: const TextStyle(color: AppColors.ink, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense, required this.paidBy});

  final GroupExpense expense;
  final String paidBy;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('group-expense-${expense.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.mint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.receipt_long_rounded, color: AppColors.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Paid by $paidBy',
                  style: const TextStyle(
                    color: Color(0xFF7A7A86),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            expense.formattedAmount,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.mint,
          child: Icon(icon, color: AppColors.ink, size: 26),
        ),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
        ?action,
      ],
    ),
  );
}

/// Amount and description for a group expense; pops with `true` after save.
class AddGroupExpenseScreen extends StatefulWidget {
  const AddGroupExpenseScreen({super.key, required this.onSubmit});

  final Future<GroupExpense> Function(int amountPaise, String description)
  onSubmit;

  @override
  State<AddGroupExpenseScreen> createState() => _AddGroupExpenseScreenState();
}

class _AddGroupExpenseScreenState extends State<AddGroupExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        parseAmountPaise(_amountController.text)!,
        _descriptionController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not reach the server.');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Add group expense')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('group-expense-amount-field'),
                  controller: _amountController,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                  ),
                  validator: (value) => parseAmountPaise(value ?? '') == null
                      ? 'Enter an amount like 450 or 450.50.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('group-expense-description-field'),
                  controller: _descriptionController,
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'What for?',
                    hintText: 'Dinner, rent, taxi…',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'Say what this expense is for.';
                    }
                    if (text.length > 255) {
                      return 'Description must be at most 255 characters.';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    key: const Key('group-expense-save-error'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('group-expense-save-button'),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.ink,
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
