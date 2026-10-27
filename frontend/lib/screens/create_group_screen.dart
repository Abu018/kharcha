import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/app_user.dart';
import '../theme/app_theme.dart';

/// Accent for the [index]th group or member avatar.
Color groupColor(int index) => const [
  AppColors.lavender,
  AppColors.pink,
  AppColors.peach,
  AppColors.mint,
  AppColors.blue,
  AppColors.lime,
][index % 6];

/// Stable avatar colour for a user, so they look the same everywhere.
Color userColor(AppUser user) => groupColor(user.id.hashCode.abs());

/// Collects a group name and members picked from the user list, and pops
/// with `true` once the API has created the group.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({
    super.key,
    required this.onSubmit,
    required this.onSearchUsers,
  });

  final Future<void> Function(String name, List<AppUser> members) onSubmit;

  /// Other users whose name or email contains the query; all when empty.
  final Future<List<AppUser>> Function(String query) onSearchUsers;

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  static const _debounce = Duration(milliseconds: 300);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();

  /// Picked members by ID, in the order they were picked.
  final _selected = <String, AppUser>{};

  List<AppUser> _results = const [];
  bool _searching = true;
  String? _searchError;
  Timer? _searchTimer;
  int _searchSeq = 0;

  bool _submitting = false;
  String? _membersError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_debounce, _search);
    setState(() {});
  }

  Future<void> _search() async {
    final seq = ++_searchSeq;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final users = await widget.onSearchUsers(_searchController.text.trim());
      if (mounted && seq == _searchSeq) {
        setState(() => _results = users);
      }
    } on ApiException catch (error) {
      if (mounted && seq == _searchSeq) {
        setState(() => _searchError = error.message);
      }
    } catch (_) {
      if (mounted && seq == _searchSeq) {
        setState(() => _searchError = 'Could not reach the server.');
      }
    } finally {
      if (mounted && seq == _searchSeq) {
        setState(() => _searching = false);
      }
    }
  }

  void _toggle(AppUser user) {
    setState(() {
      if (_selected.remove(user.id) == null) {
        _selected[user.id] = user;
      }
      _membersError = null;
    });
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    final nameOk = form != null && form.validate();
    if (_selected.isEmpty) {
      setState(() => _membersError = 'Pick at least one member.');
    }
    if (!nameOk || _selected.isEmpty) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        _nameController.text.trim(),
        List.of(_selected.values),
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
    final query = _searchController.text.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  key: const Key('group-error'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              FilledButton(
                key: const Key('group-create-button'),
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
                    : Text(
                        _selected.isEmpty
                            ? 'Create group'
                            : 'Create group · ${_selected.length + 1} people',
                      ),
              ),
            ],
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            TextFormField(
              key: const Key('group-name-field'),
              controller: _nameController,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Group name',
                hintText: 'Goa trip, Flatmates…',
                prefixIcon: Icon(Icons.groups_rounded),
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) {
                  return 'Give the group a name.';
                }
                if (text.length > 100) {
                  return 'Name must be at most 100 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text('Members', style: theme.textTheme.titleMedium),
                ),
                Text(
                  '${_selected.length} selected',
                  key: const Key('group-member-count'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _selected.isEmpty ? AppColors.muted : AppColors.lime,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (_membersError != null) ...[
              const SizedBox(height: 4),
              Text(
                _membersError!,
                key: const Key('group-members-error'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (_selected.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final user in _selected.values)
                    _SelectedChip(
                      key: ValueKey('group-selected-${user.id}'),
                      user: user,
                      onRemove: _submitting ? null : () => _toggle(user),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              key: const Key('group-member-search'),
              controller: _searchController,
              enabled: !_submitting,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              onSubmitted: (_) {
                _searchTimer?.cancel();
                _search();
              },
              decoration: InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.transparent,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _onQueryChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            if (_searching && _results.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_searchError != null)
              _ListMessage(
                key: const Key('group-users-error'),
                icon: Icons.cloud_off_rounded,
                text: _searchError!,
                action: TextButton(
                  onPressed: _search,
                  child: const Text('Try again'),
                ),
              )
            else if (_results.isEmpty)
              _ListMessage(
                key: const Key('group-users-empty'),
                icon: Icons.person_search_rounded,
                text: query.isEmpty
                    ? 'No one else has signed up yet.'
                    : 'No one matches "$query".',
              )
            else ...[
              if (_searching)
                const LinearProgressIndicator(minHeight: 2)
              else
                const SizedBox(height: 2),
              const SizedBox(height: 8),
              for (final user in _results) ...[
                _UserTile(
                  key: ValueKey('group-user-${user.id}'),
                  user: user,
                  selected: _selected.containsKey(user.id),
                  onTap: _submitting ? null : () => _toggle(user),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    super.key,
    required this.user,
    required this.selected,
    required this.onTap,
  });

  final AppUser user;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasName = user.displayName != user.email;

    return Material(
      color: selected ? AppColors.surfaceHigh : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? AppColors.lime : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          child: Row(
            children: [
              UserAvatar(user: user, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (hasName) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.lime : Colors.transparent,
                  border: Border.all(
                    color: selected ? AppColors.lime : AppColors.outline,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: AppColors.ink,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({super.key, required this.user, required this.onRemove});

  final AppUser user;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.outline),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UserAvatar(user: user, size: 28),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(
            user.firstName.isNotEmpty ? user.firstName : user.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        InkWell(
          customBorder: const CircleBorder(),
          onTap: onRemove,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.close_rounded, size: 16, color: AppColors.muted),
          ),
        ),
      ],
    ),
  );
}

/// A user's initials on their colour.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    required this.size,
    this.border,
  });

  final AppUser user;
  final double size;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: userColor(user),
      shape: BoxShape.circle,
      border: border == null ? null : Border.all(color: border!, width: 2),
    ),
    child: Text(
      user.initials,
      style: TextStyle(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
        fontSize: size * 0.36,
      ),
    ),
  );
}

class _ListMessage extends StatelessWidget {
  const _ListMessage({
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
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        Icon(icon, color: AppColors.muted, size: 30),
        const SizedBox(height: 8),
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
