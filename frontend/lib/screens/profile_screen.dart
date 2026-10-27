import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/profile_api.dart';
import '../theme/app_theme.dart';

/// Edits the user's profile and pops with `true` once the API accepts it.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.initialFirstName,
    required this.initialLastName,
    required this.onSubmit,
    this.onLoad,
  });

  final String initialFirstName;
  final String initialLastName;
  final Future<void> Function(Profile profile) onSubmit;

  /// Fetches the saved profile so age and salary can be shown.
  final Future<Profile?> Function()? onLoad;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _firstNameController = TextEditingController(
    text: widget.initialFirstName,
  );
  late final _lastNameController = TextEditingController(
    text: widget.initialLastName,
  );
  final _ageController = TextEditingController();
  final _salaryController = TextEditingController();

  late bool _loading = widget.onLoad != null;
  bool _submitting = false;
  String? _error;

  bool get _busy => _loading || _submitting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _ageController.dispose();
    _salaryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final load = widget.onLoad;
    if (load == null) {
      return;
    }
    try {
      final profile = await load();
      if (profile != null && mounted) {
        _firstNameController.text = profile.firstName;
        _lastNameController.text = profile.lastName;
        _ageController.text = profile.age?.toString() ?? '';
        _salaryController.text = profile.salaryRupees?.toString() ?? '';
      }
    } catch (_) {
      // The name is already filled in from the session; age and salary
      // simply stay blank.
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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
        Profile(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          age: int.tryParse(_ageController.text.trim()),
          salaryRupees: int.tryParse(_salaryController.text.trim()),
        ),
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
      appBar: AppBar(
        title: const Text('Edit profile'),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.lime,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('profile-first-name-field'),
                  controller: _firstNameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'First name'),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.length < 2) {
                      return 'First name must be at least 2 characters.';
                    }
                    if (text.length > 50) {
                      return 'First name must be at most 50 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('profile-last-name-field'),
                  controller: _lastNameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Last name'),
                  validator: (value) {
                    if ((value?.trim().length ?? 0) > 50) {
                      return 'Last name must be at most 50 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('profile-age-field'),
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Age'),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return null;
                    }
                    final age = int.tryParse(text);
                    if (age == null || age < 1 || age > 120) {
                      return 'Enter an age between 1 and 120.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('profile-salary-field'),
                  controller: _salaryController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(12),
                  ],
                  textInputAction: TextInputAction.done,
                  enabled: !_busy,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Monthly salary',
                    prefixText: '₹ ',
                    helperText: 'Used to show how much of your pay you spend.',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    key: const Key('profile-error'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('profile-save-button'),
                  onPressed: _busy ? null : _submit,
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
