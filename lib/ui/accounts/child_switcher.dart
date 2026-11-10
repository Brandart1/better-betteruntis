import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';

/// Makes [child] the active parent account's "My timetable" (persisted on
/// the account).
Future<void> selectChild(WidgetRef ref, Account account, AccountChild child) =>
    ref
        .read(accountRepositoryProvider)
        .update(account.copyWith(selectedChildId: child.id));

/// Parent accounts with several children: chips to choose whose timetable
/// "My timetable" shows. Renders nothing for everyone else.
class ChildSwitcher extends ConsumerWidget {
  const ChildSwitcher({super.key, this.onSelected});

  /// Called after a child was chosen (e.g. to close the drawer).
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider).value;
    final active = account?.activeChild;
    if (account == null || active == null || account.children.length < 2) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('child-switcher'),
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My timetable shows',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in account.children)
                ChoiceChip(
                  key: ValueKey('child-${c.id}'),
                  label: Text(c.displayName),
                  selected: c.id == active.id,
                  onSelected: (_) async {
                    if (c.id != active.id) await selectChild(ref, account, c);
                    onSelected?.call();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
