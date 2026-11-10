import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../login/login_flow.dart' show CenteredContent;
import 'accounts_list.dart';

/// Full-page account management (for settings): switch, rename, remove, add.
class ManageAccountsScreen extends StatelessWidget {
  const ManageAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void add() => context.push('/login/add');
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: add,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add account'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            CenteredContent(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Add accounts from as many schools as you like. Tap one '
                      'to switch to it.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  AccountsList(
                    empty: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 64),
                      child: Column(
                        children: [
                          Icon(
                            Icons.group_outlined,
                            size: 56,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No accounts yet',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: add,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add your first account'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
