import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'account_avatar.dart';
import 'accounts_sheet.dart';

/// Shows the active account; tapping opens [showAccountsSheet].
///
/// * `AccountSwitcher()` — full row for a drawer header: avatar, label,
///   school, and a hint how many accounts exist.
/// * `AccountSwitcher.avatar()` — compact avatar button for an app bar.
class AccountSwitcher extends ConsumerWidget {
  const AccountSwitcher({super.key}) : compact = false;
  const AccountSwitcher.avatar({super.key}) : compact = true;

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeAccountProvider).value;
    final count = ref.watch(accountsProvider).value?.length ?? 0;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (compact) {
      return IconButton(
        key: const ValueKey('accountSwitcher'),
        tooltip: active == null
            ? 'Accounts'
            : '${active.label} · ${active.school.displayName}',
        onPressed: () => showAccountsSheet(context),
        icon: active == null
            ? const Icon(Icons.account_circle_outlined)
            : AccountAvatar(account: active, radius: 16),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('accountSwitcher'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => showAccountsSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (active != null)
                AccountAvatar(account: active, radius: 24)
              else
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.surfaceContainerHighest,
                  child: const Icon(Icons.person_outline_rounded),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      active?.label ?? 'No account',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      active?.school.displayName ?? 'Tap to add one',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (count > 1)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Badge.count(
                    count: count,
                    backgroundColor: scheme.secondaryContainer,
                    textColor: scheme.onSecondaryContainer,
                  ),
                ),
              Icon(Icons.unfold_more_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
