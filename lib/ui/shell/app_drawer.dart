import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_update.dart';
import '../../core/build_channel.dart';
import '../../core/class_register.dart';
import '../../core/providers.dart';
import '../accounts/account_switcher.dart';
import '../accounts/child_switcher.dart';
import '../../sync/sync_client.dart' show kSyncDisabled;
import '../../sync/sync_controller.dart' show kLatestReleaseUrl;
import '../infocenter/info_providers.dart' show urlOpenerProvider;

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, this.onHome = true});

  /// False on browsed (class/teacher/room) timetables: "My timetable" then
  /// goes back to the home timetable instead of just closing the drawer.
  final bool onHome;

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
        ChildSwitcher(onSelected: () => Navigator.of(context).pop()),
        const Divider(indent: 28, endIndent: 28),
        Consumer(
          builder: (context, ref, _) {
            // Parent accounts: whose timetable "My timetable" is.
            final child = ref.watch(
              activeAccountProvider.select((a) => a.value?.activeChild),
            );
            return ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('My timetable'),
              subtitle: child == null ? null : Text(child.displayName),
              selected: onHome,
              onTap: () {
                Navigator.of(context).pop();
                if (!onHome) context.go('/');
              },
            );
          },
        ),
        Consumer(
          builder: (context, ref, _) {
            final teacher = ref.watch(
              activeAccountProvider.select(
                (a) => a.value != null && hasClassRegister(a.value!),
              ),
            );
            if (!teacher) return const SizedBox.shrink();
            return ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Class register'),
              subtitle: const Text("Today's and past lessons"),
              onTap: () => go('/classreg'),
            );
          },
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
          subtitle: const Text('Classes, teachers, rooms'),
          onTap: () => go('/browse'),
        ),
        if (!kIsWeb)
          ListTile(
            leading: const Icon(Icons.event_repeat),
            title: const Text('Calendar sync'),
            onTap: () => go('/calendar'),
          ),
        // Also on the web: the web version syncs too (not in builds
        // without sync, e.g. the teacher web alpha).
        if (!kSyncDisabled)
          ListTile(
            key: const ValueKey('drawer-sync'),
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Sync'),
            subtitle: const Text('Notes on all your devices'),
            onTap: () => go('/sync'),
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
        ListTile(
          leading: const Icon(Icons.accessibility_new),
          title: const Text('Accessibility'),
          onTap: () => go('/accessibility'),
        ),
        ListTile(
          key: const ValueKey('drawer-whats-new'),
          leading: const Icon(Icons.new_releases_outlined),
          title: const Text("What's new"),
          subtitle: const Text('Release notes'),
          onTap: () => go('/whats-new'),
        ),
        // Web version only: point to the Android/iOS apps.
        Consumer(
          builder: (context, ref, _) => !ref.watch(isWebProvider)
              ? const SizedBox.shrink()
              : ListTile(
                  key: const ValueKey('drawer-get-app'),
                  leading: const Icon(Icons.install_mobile_outlined),
                  title: const Text('Get the app'),
                  subtitle: const Text('Android and iOS'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () {
                    Navigator.of(context).pop();
                    ref.read(urlOpenerProvider)(Uri.parse(kLatestReleaseUrl));
                  },
                ),
        ),
        if (debugToolsEnabled) ...[
          const Divider(indent: 28, endIndent: 28),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Debug: raw API data'),
            onTap: () => go('/debug'),
          ),
        ],
        const _VersionFooter(),
      ],
    );
  }
}

/// Whether this is the web version (overridable in tests).
final isWebProvider = Provider<bool>((ref) => kIsWeb);

/// "Version 0.4.4 (19) · beta" at the bottom of the drawer.
class _VersionFooter extends ConsumerWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(appVersionProvider).value;
    if (v == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
      child: Text(
        'Version $v · $buildChannel',
        key: const ValueKey('app-version'),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
