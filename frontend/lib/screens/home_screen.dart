import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/expense.dart';
import '../theme/app_theme.dart';
import '../widgets/shapes.dart';
import 'add_expense_screen.dart';
import 'profile_screen.dart';

/// Whether payments are imported from SMS on this device.
enum AutoDetectState {
  /// Not available here (web, iOS, tests).
  unsupported,

  /// Available but the user has not granted SMS access.
  off,
  on,
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.session,
    required this.onSignOut,
    required this.onUpdateProfile,
    required this.onAddExpense,
    this.expenses = const [],
    this.loading = false,
    this.loadError,
    this.onRefresh,
    this.autoDetect = AutoDetectState.unsupported,
    this.syncing = false,
    this.lastSynced,
    this.onEnableAutoDetect,
  });

  final AuthSession session;
  final VoidCallback onSignOut;
  final Future<void> Function(String firstName, String lastName)
  onUpdateProfile;
  final Future<void> Function(ExpenseInput input) onAddExpense;

  /// Newest first.
  final List<Expense> expenses;
  final bool loading;
  final String? loadError;
  final Future<void> Function()? onRefresh;

  final AutoDetectState autoDetect;
  final bool syncing;
  final DateTime? lastSynced;
  final Future<void> Function()? onEnableAutoDetect;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Filter { all, spent, received }

class _HomeScreenState extends State<HomeScreen> {
  _Filter _filter = _Filter.all;

  Future<void> _openProfile() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          initialFirstName: widget.session.firstName,
          initialLastName: widget.session.lastName,
          onSubmit: widget.onUpdateProfile,
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated')));
    }
  }

  Future<void> _openAddExpense() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(onSubmit: widget.onAddExpense),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Expense saved')));
    }
  }

  List<Expense> get _visible => switch (_filter) {
    _Filter.all => widget.expenses,
    _Filter.spent => widget.expenses.where((e) => !e.isCredit).toList(),
    _Filter.received => widget.expenses.where((e) => e.isCredit).toList(),
  };

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thisMonth = widget.expenses.where((e) {
      final when = e.when;
      return when != null && when.year == now.year && when.month == now.month;
    }).toList();
    final visible = _visible;

    final content = ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _Header(
          session: widget.session,
          onProfile: _openProfile,
          onSignOut: widget.onSignOut,
        ),
        const SizedBox(height: 20),
        _SummaryCard(month: _months[now.month - 1], expenses: thisMonth),
        if (widget.autoDetect != AutoDetectState.unsupported) ...[
          const SizedBox(height: 14),
          _AutoDetectCard(
            state: widget.autoDetect,
            syncing: widget.syncing,
            lastSynced: widget.lastSynced,
            onEnable: widget.onEnableAutoDetect,
            onSync: widget.onRefresh,
          ),
        ],
        if (thisMonth.any((e) => !e.isCredit)) ...[
          const SizedBox(height: 28),
          const _SectionTitle('Where it went'),
          const SizedBox(height: 12),
          _CategoryBreakdown(expenses: thisMonth),
        ],
        const SizedBox(height: 28),
        const _SectionTitle('Activity'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (filter, label) in [
              (_Filter.all, 'All'),
              (_Filter.spent, 'Spent'),
              (_Filter.received, 'Received'),
            ])
              _Pill(
                key: Key('filter-${filter.name}'),
                label: label,
                selected: _filter == filter,
                onTap: () => setState(() => _filter = filter),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (widget.loading && widget.expenses.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (widget.loadError != null && widget.expenses.isEmpty)
          _Message(
            key: const Key('expenses-error'),
            icon: Icons.cloud_off_rounded,
            text: widget.loadError!,
          )
        else if (visible.isEmpty)
          _Message(
            key: const Key('expenses-empty'),
            icon: Icons.receipt_long_rounded,
            text: widget.expenses.isEmpty
                ? 'No expenses yet. Tap "Add expense" or turn on auto-detect.'
                : 'Nothing here for this filter.',
          )
        else
          for (final expense in visible) ...[
            _ExpenseCard(expense: expense),
            const SizedBox(height: 10),
          ],
      ],
    );

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-expense-button'),
        onPressed: _openAddExpense,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add expense'),
      ),
      body: SafeArea(
        child: widget.onRefresh == null
            ? content
            : RefreshIndicator(
                color: AppColors.ink,
                backgroundColor: AppColors.lime,
                onRefresh: widget.onRefresh!,
                child: content,
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.session,
    required this.onProfile,
    required this.onSignOut,
  });

  final AuthSession session;
  final VoidCallback onProfile;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = session.displayName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.lavender,
            shape: BoxShape.circle,
          ),
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.displayName,
                key: const Key('signed-in-name'),
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                session.email,
                key: const Key('signed-in-email'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('edit-profile-button'),
          onPressed: onProfile,
          tooltip: 'Edit profile',
          icon: const Icon(Icons.person_outline_rounded),
        ),
        const SizedBox(width: 6),
        IconButton(
          key: const Key('sign-out-button'),
          onPressed: onSignOut,
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.month, required this.expenses});

  final String month;
  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    final spent = expenses
        .where((e) => !e.isCredit)
        .fold<int>(0, (sum, e) => sum + e.amountPaise);
    final received = expenses
        .where((e) => e.isCredit)
        .fold<int>(0, (sum, e) => sum + e.amountPaise);

    return Container(
      key: const Key('summary-card'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.lavender,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -26,
            top: -26,
            child: TargetShape(
              size: 130,
              color: AppColors.pink,
              background: AppColors.lavender,
            ),
          ),
          const Positioned(
            right: 70,
            bottom: -18,
            child: FlowerShape(size: 54, color: AppColors.lime, petals: 6),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Spent in $month',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatPaise(spent, decimals: false),
                  key: const Key('summary-spent'),
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DarkChip(
                      icon: Icons.south_west_rounded,
                      label: 'In ${formatPaise(received, decimals: false)}',
                    ),
                    _DarkChip(
                      icon: Icons.receipt_rounded,
                      label:
                          '${expenses.length} payment${expenses.length == 1 ? '' : 's'}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkChip extends StatelessWidget {
  const _DarkChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.lime),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _AutoDetectCard extends StatelessWidget {
  const _AutoDetectCard({
    required this.state,
    required this.syncing,
    required this.lastSynced,
    required this.onEnable,
    required this.onSync,
  });

  final AutoDetectState state;
  final bool syncing;
  final DateTime? lastSynced;
  final Future<void> Function()? onEnable;
  final Future<void> Function()? onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (state == AutoDetectState.off) {
      return Container(
        key: const Key('auto-detect-card'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.lime,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bolt_rounded, color: AppColors.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Detect payments automatically',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Allow SMS access and every bank or UPI payment message becomes an '
              'expense. Messages are read on this phone; only the amount, '
              'merchant and bank are saved.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('enable-auto-detect'),
              onPressed: onEnable,
              child: const Text('Turn on auto-detect'),
            ),
          ],
        ),
      );
    }

    final status = syncing
        ? 'Checking your messages…'
        : lastSynced == null
        ? 'Watching bank & UPI messages'
        : 'Last checked ${_ago(lastSynced!)}';

    return Container(
      key: const Key('auto-detect-card'),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.lime,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Auto-detect is on', style: theme.textTheme.titleSmall),
                Text(
                  status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (syncing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              key: const Key('sync-button'),
              onPressed: onSync,
              tooltip: 'Check messages now',
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surfaceHigh,
              ),
              icon: const Icon(Icons.sync_rounded),
            ),
        ],
      ),
    );
  }

  static String _ago(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) {
      return 'just now';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} min ago';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} h ago';
    }
    return _dateLabel(time);
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.expenses});

  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    final totals = <String, int>{};
    for (final e in expenses.where((e) => !e.isCredit)) {
      final category = e.category.isEmpty ? 'Unknown' : e.category;
      totals[category] = (totals[category] ?? 0) + e.amountPaise;
    }
    final total = totals.values.fold<int>(0, (a, b) => a + b);
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          for (final entry in sorted.take(5)) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  formatPaise(entry.value, decimals: false),
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${total == 0 ? 0 : (entry.value * 100 / total).round()}%',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : entry.value / total,
                minHeight: 10,
                color: AppColors.category(entry.key),
                backgroundColor: AppColors.surfaceHigh,
              ),
            ),
            if (entry != sorted.take(5).last) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.expense});

  final Expense expense;

  static IconData _icon(Expense e) {
    if (e.isCredit) {
      return Icons.south_west_rounded;
    }
    return switch (e.category.toLowerCase()) {
      'food' => Icons.restaurant_rounded,
      'groceries' => Icons.local_grocery_store_rounded,
      'transport' => Icons.directions_car_rounded,
      'shopping' => Icons.shopping_bag_rounded,
      'bills' => Icons.receipt_long_rounded,
      'entertainment' => Icons.movie_rounded,
      'health' => Icons.local_hospital_rounded,
      'transfers' => Icons.person_rounded,
      _ => Icons.payments_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final account = expenseAccountTypes[e.accountType] ?? e.accountType;
    final accent = e.isCredit ? AppColors.mint : AppColors.category(e.category);

    return Container(
      key: ValueKey('expense-${e.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            child: Icon(_icon(e), color: AppColors.ink, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (e.category.isNotEmpty && !e.isCredit)
                      _Tag(label: e.category, color: accent),
                    if (e.isAutoDetected)
                      const _Tag(
                        label: 'Auto',
                        color: AppColors.ink,
                        textColor: AppColors.lime,
                      ),
                    _Tag(
                      label: '${e.bankName} · $account',
                      color: const Color(0xFFE6E5EC),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${e.isCredit ? '+' : '-'}${e.formattedAmount}',
                style: TextStyle(
                  color: e.isCredit ? const Color(0xFF13804B) : AppColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _dateLabel(e.when),
                style: const TextStyle(color: Color(0xFF7A7A86), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.color,
    this.textColor = AppColors.ink,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: textColor,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.lime : AppColors.surface,
    shape: StadiumBorder(
      side: BorderSide(color: selected ? AppColors.lime : AppColors.outline),
    ),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.ink : Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      children: [
        Icon(icon, color: AppColors.muted, size: 32),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}

String _dateLabel(DateTime? time) {
  if (time == null) {
    return '';
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final hhmm =
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  if (day == today) {
    return 'Today, $hhmm';
  }
  if (day == today.subtract(const Duration(days: 1))) {
    return 'Yesterday, $hhmm';
  }
  final short = _months[time.month - 1].substring(0, 3);
  return time.year == now.year
      ? '${time.day} $short'
      : '${time.day} $short ${time.year}';
}
