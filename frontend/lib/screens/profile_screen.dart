import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';

/// Edits the user's name and pops with `true` once the API accepts it.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.initialFirstName,
    required this.initialLastName,
    required this.onSubmit,
  });

  final String initialFirstName;
  final String initialLastName;
  final Future<void> Function(String firstName, String lastName) onSubmit;

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

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
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
        _firstNameController.text.trim(),
        _lastNameController.text.trim(),
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
      appBar: AppBar(title: const Text('Edit profile')),
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
                  enabled: !_submitting,
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
                  textInputAction: TextInputAction.done,
                  enabled: !_submitting,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'Last name'),
                  validator: (value) {
                    if ((value?.trim().length ?? 0) > 50) {
                      return 'Last name must be at most 50 characters.';
                    }
                    return null;
                  },
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
