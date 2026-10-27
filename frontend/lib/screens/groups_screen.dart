import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/expense_group.dart';
import '../theme/app_theme.dart';
import '../widgets/shapes.dart';
import 'create_group_screen.dart';

/// Lists the user's groups and creates new ones.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({
    super.key,
    required this.onCreateGroup,
    required this.onSearchUsers,
    this.groups = const [],
  });

  final Future<void> Function(String name, List<AppUser> members)
  onCreateGroup;
  final Future<List<AppUser>> Function(String query) onSearchUsers;

  /// Newest first.
  final List<ExpenseGroup> groups;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateGroupScreen(
          onSubmit: widget.onCreateGroup,
          onSearchUsers: widget.onSearchUsers,
        ),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Group created')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = widget.groups;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-group-button'),
        heroTag: 'new-group',
        onPressed: _openCreate,
        icon: const Icon(Icons.group_add_rounded),
        label: const Text('New group'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
          children: [
            Text('Groups', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              'Split expenses with friends, flatmates and family.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 20),
            _GroupsBanner(count: groups.length, onCreate: _openCreate),
            const SizedBox(height: 28),
            Text('Your groups', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (groups.isEmpty)
              const _EmptyGroups()
            else
              for (final (index, group) in groups.indexed) ...[
                _GroupCard(
                  group: group,
                  color: groupColor(groups.length - 1 - index),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _GroupsBanner extends StatelessWidget {
  const _GroupsBanner({required this.count, required this.onCreate});

  final int count;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('groups-banner'),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.lime,
      borderRadius: BorderRadius.circular(28),
    ),
    child: Stack(
      children: [
        const Positioned(
          right: -30,
          top: -30,
          child: FlowerShape(size: 120, color: AppColors.mint, petals: 6),
        ),
        const Positioned(
          right: 60,
          bottom: -20,
          child: TargetShape(
            size: 56,
            color: AppColors.ink,
            background: AppColors.lime,
            rings: 2,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count == 0
                    ? 'Start a group'
                    : '$count group${count == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Pick friends from the list and track\nshared spending together.',
                style: TextStyle(color: AppColors.ink, fontSize: 13),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const Key('groups-banner-create'),
                onPressed: onCreate,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  foregroundColor: AppColors.lime,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Add people'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.color});

  final ExpenseGroup group;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final members = group.members.length + 1;
    final initial = group.name.trim().isEmpty
        ? '?'
        : group.name.trim().substring(0, 1).toUpperCase();
    final names = group.members
        .map((m) => m.firstName.isNotEmpty ? m.firstName : m.displayName)
        .join(', ');

    return Container(
      key: ValueKey('group-${group.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              initial,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
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
                  names.isEmpty
                      ? '$members member${members == 1 ? '' : 's'}'
                      : 'You, $names',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7A7A86),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _AvatarStack(users: group.members),
        ],
      ),
    );
  }
}

/// Up to three overlapping member avatars, then `+N`.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.users});

  final List<AppUser> users;

  @override
  Widget build(BuildContext context) {
    final shown = users.take(3).toList();
    final extra = users.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    if (count == 0) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: 30 + (count - 1) * 20,
      height: 30,
      child: Stack(
        children: [
          for (final (i, user) in shown.indexed)
            Positioned(
              left: i * 20,
              child: UserAvatar(user: user, size: 30, border: AppColors.card),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * 20,
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E2E8),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.card, width: 2),
                ),
                child: Text(
                  '+$extra',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('groups-empty'),
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(24),
    ),
    child: const Column(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: AppColors.lavender,
          child: Icon(Icons.groups_rounded, color: AppColors.ink, size: 30),
        ),
        SizedBox(height: 14),
        Text(
          'No groups yet',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        SizedBox(height: 6),
        Text(
          'Tap "New group" and pick friends from the list.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}
