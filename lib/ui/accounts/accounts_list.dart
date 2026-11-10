import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import 'account_avatar.dart';

/// Returns [a] with [profileName] set, or cleared when null/empty.
/// (Account.copyWith can't clear a field.)
Account withProfileName(Account a, String? profileName) {
  final p = profileName?.trim();
  return Account(
    id: a.id,
    school: a.school,
    username: a.username,
    anonymous: a.anonymous,
    displayName: a.displayName,
    profileName: (p?.isEmpty ?? true) ? null : p,
    elementType: a.elementType,
    elementId: a.elementId,
    klassenIds: a.klassenIds,
    rights: a.rights,
    masterDataTimestamp: a.masterDataTimestamp,
    hostOverride: a.hostOverride,
  );
}

String _schoolKey(School s) =>
    '${s.loginName.toLowerCase()}@${s.host.toLowerCase()}';

/// Secondary line under an account's label.
String accountSubtitle(Account a) {
  if (a.anonymous) return 'Public timetable';
  final hasProfile = a.profileName?.trim().isNotEmpty ?? false;
  return hasProfile ? '${a.displayName} · ${a.username}' : a.username;
}

/// Accounts grouped by school, with the active one checked. Tapping an
/// account makes it active; the trailing menu renames or deletes it.
class AccountsList extends ConsumerWidget {
  const AccountsList({super.key, this.onSelected, this.empty});

  /// Called after an account was made active (e.g. to close the sheet).
  final ValueChanged<Account>? onSelected;

  /// Shown when there are no accounts.
  final Widget? empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final activeId = ref.watch(activeAccountProvider).value?.id;
    return accounts.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          "Couldn't load accounts.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
      data: (list) {
        if (list.isEmpty) return empty ?? const SizedBox.shrink();
        final groups = groupBy(list, (Account a) => _schoolKey(a.school));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final group in groups.values) ...[
              _SchoolHeader(school: group.first.school),
              for (final a in group)
                _AccountTile(
                  account: a,
                  active: a.id == activeId,
                  onTap: () async {
                    await ref.read(accountRepositoryProvider).setActive(a.id);
                    onSelected?.call(a);
                  },
                ),
            ],
          ],
        );
      },
    );
  }
}

class _SchoolHeader extends StatelessWidget {
  const _SchoolHeader({required this.school});
  final School school;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(
            Icons.school_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              school.displayName,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Action { rename, delete }

class _AccountTile extends ConsumerWidget {
  const _AccountTile({
    required this.account,
    required this.active,
    required this.onTap,
  });

  final Account account;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: ValueKey('account-${account.id}'),
      selected: active,
      selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: onTap,
      leading: AccountAvatar(account: account),
      title: Text(account.label, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${accountSubtitle(account)}\n${account.school.displayName}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active)
            Icon(
              Icons.check_circle_rounded,
              color: scheme.primary,
              semanticLabel: 'Active',
            ),
          PopupMenuButton<_Action>(
            tooltip: 'Account options',
            onSelected: (action) => switch (action) {
              _Action.rename => renameAccount(context, ref, account),
              _Action.delete => confirmDeleteAccount(context, ref, account),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _Action.rename,
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Rename'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _Action.delete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Remove'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Prompts for a new profile name and saves it. Empty resets to the
/// display name.
Future<void> renameAccount(
  BuildContext context,
  WidgetRef ref,
  Account account,
) async {
  final repo = ref.read(accountRepositoryProvider);
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(account: account),
  );
  if (name == null) return;
  await repo.update(withProfileName(account, name));
}

/// Asks for confirmation, then deletes the account. Returns true if deleted.
Future<bool> confirmDeleteAccount(
  BuildContext context,
  WidgetRef ref,
  Account account,
) async {
  final repo = ref.read(accountRepositoryProvider);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: const Icon(Icons.person_remove_outlined),
        title: const Text('Remove account?'),
        content: Text(
          '${account.label} at ${account.school.displayName} will be removed '
          'from this device, including its offline timetable. You can add it '
          'again anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      );
    },
  );
  if (ok != true) return false;
  await repo.delete(account.id);
  // Last account gone: back to the welcome screen (the router's redirect
  // may do this too; going twice is harmless).
  final remaining = await repo.watchAccounts().first.timeout(
    const Duration(seconds: 2),
    onTimeout: () => const [],
  );
  if (remaining.isEmpty && context.mounted) {
    GoRouter.maybeOf(context)?.go('/login');
  }
  return true;
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.account});
  final Account account;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _ctrl = TextEditingController(text: widget.account.profileName);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename profile'),
    content: TextField(
      key: const ValueKey('renameField'),
      controller: _ctrl,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: 'Profile name',
        hintText: widget.account.displayName,
        helperText: 'Leave empty to use "${widget.account.displayName}"',
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _ctrl.text),
        child: const Text('Save'),
      ),
    ],
  );
}
