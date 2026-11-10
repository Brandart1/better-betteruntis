import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'accounts_list.dart';

/// Bottom sheet listing all accounts grouped by school, with switch, rename,
/// remove, "Add account" and "Manage accounts".
Future<void> showAccountsSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 480),
  builder: (context) => const AccountsSheet(),
);

class AccountsSheet extends StatelessWidget {
  const AccountsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final router = GoRouter.maybeOf(context);
    void openRoute(String location) {
      Navigator.pop(context);
      router?.push(location);
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Accounts', style: theme.textTheme.titleLarge),
          ),
          AccountsList(
            onSelected: (_) => Navigator.pop(context),
            empty: const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No accounts yet.', textAlign: TextAlign.center),
            ),
          ),
          const Divider(height: 24),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.person_add_alt_1_outlined),
            ),
            title: const Text('Add account'),
            subtitle: const Text('Another person or another school'),
            onTap: () => openRoute('/login/add'),
          ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: const SizedBox(
              width: 40,
              child: Icon(Icons.manage_accounts_outlined),
            ),
            title: const Text('Manage accounts'),
            onTap: () => openRoute('/accounts'),
          ),
        ],
      ),
    );
  }
}
