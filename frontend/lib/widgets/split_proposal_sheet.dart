import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../models/nearby_sighting.dart';
import '../theme/app_theme.dart';

/// Result of the payer confirming (or skipping) a nearby split.
class SplitProposalResult {
  const SplitProposalResult({
    required this.split,
    this.selectedEphemeralIds = const [],
  });

  final bool split;
  final List<String> selectedEphemeralIds;
}

/// Asks the payer whether to split an auto-detected payment with people
/// heard over Bluetooth. Everyone starts checked; uncheck to leave them out.
Future<SplitProposalResult?> showSplitProposalSheet({
  required BuildContext context,
  required Expense expense,
  required String groupName,
  required List<NearbySighting> candidates,
}) {
  return showModalBottomSheet<SplitProposalResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => SplitProposalSheet(
      expense: expense,
      groupName: groupName,
      candidates: candidates,
    ),
  );
}

class SplitProposalSheet extends StatefulWidget {
  const SplitProposalSheet({
    super.key,
    required this.expense,
    required this.groupName,
    required this.candidates,
  });

  final Expense expense;
  final String groupName;
  final List<NearbySighting> candidates;

  @override
  State<SplitProposalSheet> createState() => _SplitProposalSheetState();
}

class _SplitProposalSheetState extends State<SplitProposalSheet> {
  late final Set<String> _selected = {
    for (final c in widget.candidates) c.ephemeralId,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = _selected.length + 1; // payer + selected friends
    final each = widget.expense.amountPaise ~/ n;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Split this payment?',
              key: const Key('split-proposal-title'),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.expense.formattedAmount} · ${widget.expense.title}\n'
              'Nearby friends in ${widget.groupName}. Uncheck anyone who '
              'should not share this bill.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final person in widget.candidates)
                    CheckboxListTile(
                      key: Key('split-person-${person.ephemeralId}'),
                      value: _selected.contains(person.ephemeralId),
                      onChanged: (on) => setState(() {
                        if (on == true) {
                          _selected.add(person.ephemeralId);
                        } else {
                          _selected.remove(person.ephemeralId);
                        }
                      }),
                      activeColor: AppColors.lime,
                      checkColor: AppColors.ink,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        person.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        person.signalLabel,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
            if (_selected.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'About ${formatPaise(each)} each · you + ${_selected.length}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('split-proposal-confirm'),
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                      SplitProposalResult(
                        split: true,
                        selectedEphemeralIds: _selected.toList(),
                      ),
                    ),
              child: const Text('Split'),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('split-proposal-keep'),
              onPressed: () => Navigator.of(context).pop(
                const SplitProposalResult(split: false),
              ),
              child: const Text('Keep personal'),
            ),
          ],
        ),
      ),
    );
  }
}
