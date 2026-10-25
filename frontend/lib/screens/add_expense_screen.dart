import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/expense.dart';
import '../theme/app_theme.dart';

/// Converts a rupee amount like `450.5` into paise, or `null` if the text is
/// not a positive amount with at most two decimals.
int? parseAmountPaise(String text) {
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(text.trim());
  if (match == null) {
    return null;
  }
  final rupees = int.parse(match.group(1)!);
  final paise = int.parse((match.group(2) ?? '0').padRight(2, '0'));
  final total = rupees * 100 + paise;
  return total > 0 ? total : null;
}

/// Collects an expense and pops once the API has saved it.
class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key, required this.onSubmit});

  final Future<void> Function(ExpenseInput input) onSubmit;

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _bankController = TextEditingController();
  final _vendorController = TextEditingController();
  final _vendorUpiController = TextEditingController();

  String _type = 'debit';
  String _accountType = expenseAccountTypes.keys.first;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _bankController.dispose();
    _vendorController.dispose();
    _vendorUpiController.dispose();
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
        ExpenseInput(
          amountPaise: parseAmountPaise(_amountController.text)!,
          bankName: _bankController.text.trim(),
          accountType: _accountType,
          type: _type,
          vendor: _vendorController.text.trim(),
          vendorUpi: _vendorUpiController.text.trim(),
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
      appBar: AppBar(title: const Text('Add expense')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  key: const Key('expense-type-toggle'),
                  segments: const [
                    ButtonSegment(value: 'debit', label: Text('Spent')),
                    ButtonSegment(value: 'credit', label: Text('Received')),
                  ],
                  selected: {_type},
                  onSelectionChanged: _submitting
                      ? null
                      : (selection) => setState(() => _type = selection.first),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('expense-amount-field'),
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
                  key: const Key('expense-bank-field'),
                  controller: _bankController,
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Bank'),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'Enter the bank name.';
                    }
                    if (text.length > 100) {
                      return 'Bank name must be at most 100 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const Key('expense-account-type-field'),
                  initialValue: _accountType,
                  decoration: const InputDecoration(labelText: 'Account type'),
                  items: [
                    for (final entry in expenseAccountTypes.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(
                          () => _accountType = value ?? _accountType,
                        ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('expense-vendor-field'),
                  controller: _vendorController,
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Vendor (optional)',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) > 255
                      ? 'Vendor must be at most 255 characters.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('expense-vendor-upi-field'),
                  controller: _vendorUpiController,
                  enabled: !_submitting,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Vendor UPI ID (optional)',
                    hintText: 'name@bank',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) > 255
                      ? 'UPI ID must be at most 255 characters.'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    key: const Key('expense-error'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('expense-save-button'),
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
