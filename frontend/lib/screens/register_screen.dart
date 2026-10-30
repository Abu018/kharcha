import 'package:flutter/material.dart';

import '../api/auth_api.dart';
import '../theme/app_theme.dart';

typedef RegisterCallback = Future<void> Function({
  required String userName,
  required String firstName,
  required String lastName,
  required String email,
  required String password,
});

/// Creates an account and pops with the registered email on success.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.onSubmit});

  final RegisterCallback onSubmit;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _userNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
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

    final email = _emailController.text.trim();
    try {
      await widget.onSubmit(
        userName: _userNameController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: email,
        password: _passwordController.text,
      );
      if (mounted) {
        Navigator.of(context).pop(email);
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

  String? Function(String?) _lengthValidator(
    String label, {
    required int min,
    required int max,
  }) {
    return (value) {
      final text = value?.trim() ?? '';
      if (text.isEmpty) {
        return 'Enter your $label.';
      }
      if (text.length < min) {
        return '${label[0].toUpperCase()}${label.substring(1)} must be at least $min characters.';
      }
      if (text.length > max) {
        return '${label[0].toUpperCase()}${label.substring(1)} must be at most $max characters.';
      }
      return null;
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('register-username-field'),
                  controller: _userNameController,
                  autofillHints: const [AutofillHints.newUsername],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator: _lengthValidator('username', min: 2, max: 50),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('register-first-name-field'),
                  controller: _firstNameController,
                  autofillHints: const [AutofillHints.givenName],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'First name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: _lengthValidator('first name', min: 2, max: 50),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('register-last-name-field'),
                  controller: _lastNameController,
                  autofillHints: const [AutofillHints.familyName],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Last name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: _lengthValidator('last name', min: 1, max: 50),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('register-email-field'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) {
                      return 'Enter your email.';
                    }
                    if (!email.contains('@') || !email.contains('.')) {
                      return 'Enter a valid email.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('register-password-field'),
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  enabled: !_submitting,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: '8 to 72 characters',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: _submitting
                          ? null
                          : () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final password = value ?? '';
                    if (password.isEmpty) {
                      return 'Enter a password.';
                    }
                    if (password.length < 8 || password.length > 72) {
                      return 'Password must be 8 to 72 characters.';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    key: const Key('register-error'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('register-button'),
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
                      : const Text('Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
