/// Settings → Notifications: per account on/off (asks for the permission
/// when turned on), which kinds, how many school days ahead.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications.dart';
import '../../core/providers.dart';
import '../common/large_text.dart';
import '../shell/notification_service.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  bool _asking = false;

  Future<void> _setEnabled(String accountId, bool on) async {
    final prefs = ref.read(notificationPrefsProvider.notifier);
    if (!on) {
      prefs.update(accountId, (s) => s.copyWith(enabled: false));
      return;
    }
    setState(() => _asking = true);
    bool granted;
    try {
      granted = await ref.read(localNotifierProvider).requestPermission();
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    setState(() => _asking = false);
    if (!granted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications are not allowed for this app. Allow them in '
              "the system settings, then turn them on here.",
            ),
          ),
        );
      return;
    }
    prefs.update(accountId, (s) => s.copyWith(enabled: true));
    // First run: only records what is there now (no notification).
    unawaited(ref.read(notificationServiceProvider).check());
  }

  static String _daysLabel(int n) => switch (n) {
    0 => 'Today only',
    1 => 'Today and the next school day',
    _ => 'Today and the next $n school days',
  };

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountProvider).value;
    final theme = Theme.of(context);
    final background = ref.watch(backgroundChecksSupportedProvider);
    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const Center(child: Text('No account selected')),
      );
    }
    final s = ref.watch(
      notificationPrefsProvider.select((p) => p.of(account.id)),
    );
    final prefs = ref.read(notificationPrefsProvider.notifier);
    final how = kIsWeb
        ? 'In the browser, changes are shown inside the app while it is '
              'open (no notifications while the page is closed).'
        : background
        ? 'The app checks when you open it, every 15 minutes while it is '
              'open, and in the background about every 45 minutes (Android '
              'decides the exact time, e.g. later in battery saver).'
        : 'The app checks when you open it and every 15 minutes while it '
              'is open. There is no check while the app is closed.';

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'For ${account.label}',
              style: theme.textTheme.titleSmall,
            ),
          ),
          AdaptiveSwitchTile(
            key: const ValueKey('notifications-enabled'),
            title: const Text('Notify about changes'),
            subtitle: const Text(
              'Substitutions, cancellations, room changes and new messages',
            ),
            value: s.enabled,
            onChanged: _asking ? null : (v) => _setEnabled(account.id, v),
          ),
          AdaptiveSwitchTile(
            key: const ValueKey('notifications-timetable'),
            title: const Text('Timetable changes'),
            subtitle: const Text('In your own timetable'),
            value: s.timetable,
            onChanged: s.enabled
                ? (v) =>
                      prefs.update(account.id, (c) => c.copyWith(timetable: v))
                : null,
          ),
          AdaptiveSwitchTile(
            key: const ValueKey('notifications-messages'),
            title: const Text('New messages'),
            subtitle: const Text('Unread messages in the inbox'),
            value: s.messages,
            onChanged: s.enabled && !account.anonymous
                ? (v) =>
                      prefs.update(account.id, (c) => c.copyWith(messages: v))
                : null,
          ),
          ListTile(
            key: const ValueKey('notifications-days'),
            enabled: s.enabled && s.timetable,
            title: const Text('Days ahead'),
            subtitle: Text(_daysLabel(s.daysAhead)),
            trailing: DropdownButton<int>(
              value: s.daysAhead,
              onChanged: s.enabled && s.timetable
                  ? (v) {
                      if (v != null) {
                        prefs.update(
                          account.id,
                          (c) => c.copyWith(daysAhead: v),
                        );
                      }
                    }
                  : null,
              items: [
                for (var i = 0; i <= NotificationSettings.maxDaysAhead; i++)
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '$how\n\nEverything stays on this device: the app asks '
              'WebUntis itself with your login, nothing goes through another '
              'server. Each change is notified once; the first check only '
              'remembers what is there already.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
