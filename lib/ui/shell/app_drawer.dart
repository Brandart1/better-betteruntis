import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../accounts/account_switcher.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    void go(String route) {
      Navigator.of(context).pop();
      context.push(route);
    }

    return NavigationDrawer(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: AccountSwitcher(),
        ),
        const Divider(indent: 28, endIndent: 28),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('My timetable'),
          selected: true,
          onTap: () => Navigator.of(context).pop(),
        ),
        ListTile(
          leading: const Icon(Icons.inbox_outlined),
          title: const Text('Info center'),
          subtitle: const Text('Messages, homework, exams'),
          onTap: () => go('/info'),
        ),
        ListTile(
          leading: const Icon(Icons.search),
          title: const Text('Browse timetables'),
          subtitle: const Text('Classes, teachers, rooms, subjects'),
          onTap: () => go('/browse'),
        ),
        ListTile(
          leading: const Icon(Icons.manage_accounts_outlined),
          title: const Text('Manage accounts'),
          onTap: () => go('/accounts'),
        ),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Settings'),
          onTap: () => go('/settings'),
        ),
        const Divider(indent: 28, endIndent: 28),
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('Debug: raw API data'),
          onTap: () => go('/debug'),
        ),
      ],
    );
  }
}
