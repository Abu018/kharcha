import 'package:flutter/material.dart';

import '../api/auth_api.dart';
import '../theme/app_theme.dart';
import '../widgets/shapes.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onSubmit,
    this.onRegister,
    this.notice,
    this.initialEmail,
  });

  final Future<void> Function(String email, String password) onSubmit;
  final RegisterCallback? onRegister;

  /// Prefills the email field, e.g. with the last account used.
  final String? initialEmail;

  /// Informational message shown above the form, e.g. after the session
  /// expired.
  final String? notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;
  late String? _notice = widget.notice;

  Future<void> _openRegister(RegisterCallback onRegister) async {
    final email = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => RegisterScreen(onSubmit: onRegister)),
    );
    if (email == null || !mounted) {
      return;
    }
    setState(() {
      _emailController.text = email;
      _passwordController.clear();
      _error = null;
      _notice = 'Account created. Sign in to continue.';
    });
  }

  @override
  void dispose() {
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
      _notice = null;
    });

    try {
      await widget.onSubmit(
        _emailController.text.trim(),
        _passwordController.text,
      );
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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).height < 700
                          ? 200
                          : 300,
                    ),
                    child: const HeroCollage(),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Every rupee,\ntracked for you.',
                  style: theme.textTheme.displaySmall?.copyWith(fontSize: 34),
                ),
                const SizedBox(height: 10),
                Text(
                  'Sign in and your bank SMS turn into expenses automatically.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_notice != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.lavender,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _notice!,
                      key: const Key('login-notice'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                TextFormField(
                  key: const Key('email-field'),
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
                  key: const Key('password-field'),
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  enabled: !_submitting,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
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
                    if (value == null || value.isEmpty) {
                      return 'Enter your password.';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    key: const Key('login-error'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('sign-in-button'),
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
                      : const Text('Sign in'),
                ),
                if (widget.onRegister case final onRegister?) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('create-account-button'),
                    onPressed: _submitting
                        ? null
                        : () => _openRegister(onRegister),
                    child: Text.rich(
                      TextSpan(
                        text: 'New here? ',
                        style: const TextStyle(color: AppColors.muted),
                        children: [
                          TextSpan(
                            text: 'Create an account',
                            style: TextStyle(color: theme.colorScheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
