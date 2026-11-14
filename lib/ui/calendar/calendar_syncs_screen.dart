import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../calendar/calendar_sync.dart';
import '../../calendar/calendar_sync_service.dart';
import 'calendar_sync_screen.dart';

/// Drawer → "Calendar sync": every timetable kept in the device calendar.
class CalendarSyncsScreen extends ConsumerStatefulWidget {
  const CalendarSyncsScreen({super.key});

  @override
  ConsumerState<CalendarSyncsScreen> createState() =>
      _CalendarSyncsScreenState();
}

class _CalendarSyncsScreenState extends ConsumerState<CalendarSyncsScreen> {
  final _syncing = <String>{};

  Future<void> _syncNow(CalendarSync s) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _syncing.add(s.id));
    try {
      final counts = await ref.read(calendarSyncsProvider.notifier).run(s.id);
      messenger.showSnackBar(SnackBar(content: Text('$counts.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(calendarErrorText(e))));
    } finally {
      if (mounted) setState(() => _syncing.remove(s.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final syncs = ref.watch(calendarSyncsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar sync')),
      body: syncs.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No timetable is synced to your calendar yet.\n\n'
                  'Open a timetable, tap Export, choose "Calendar (.ics)" and '
                  'then "Add to calendar".',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final s in syncs)
                  ListTile(
                    key: ValueKey('calendar-sync-${s.id}'),
                    leading: const Icon(Icons.event_repeat),
                    title: Text(s.elementName),
                    subtitle: Text(
                      s.lastError ??
                          [
                            '${s.weeks} weeks',
                            if (!s.autoUpdate) 'manual',
                            if (s.lastSync case final t?)
                              'synced ${DateFormat.yMd().add_Hm().format(t)}',
                          ].join(' · '),
                      style: s.lastError == null
                          ? null
                          : TextStyle(color: theme.colorScheme.error),
                    ),
                    trailing: _syncing.contains(s.id)
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: 'Sync now',
                            icon: const Icon(Icons.sync),
                            onPressed: () => _syncNow(s),
                          ),
                    onTap: () => context.push(
                      '/calendar/setup',
                      extra: CalendarSetupArgs(
                        accountId: s.accountId,
                        target: s.target,
                        elementName: s.elementName,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
