import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../calendar/calendar_sync.dart';
import '../../calendar/calendar_sync_service.dart';
import '../../calendar/device_calendar.dart';
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

  Future<void> _deleteLocal() async {
    final messenger = ScaffoldMessenger.of(context);
    final List<DeviceCalendarInfo> local;
    try {
      final api = ref.read(deviceCalendarProvider);
      await api.requestAccess();
      local = [
        for (final c in await api.calendars())
          if (c.local) c,
      ];
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(calendarErrorText(e))));
      return;
    }
    if (!mounted) return;
    if (local.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('There are no calendars on this phone.')),
      );
      return;
    }
    final ids = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _DeleteLocalDialog(calendars: local),
    );
    if (ids == null || ids.isEmpty) return;
    try {
      final removed = await ref
          .read(calendarSyncsProvider.notifier)
          .deleteCalendars(ids);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            [
              'Deleted ${ids.length} '
                  '${ids.length == 1 ? 'calendar' : 'calendars'}.',
              if (removed > 0)
                'Stopped $removed '
                    '${removed == 1 ? 'sync' : 'syncs'} without a calendar.',
            ].join(' '),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(calendarErrorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final syncs = ref.watch(calendarSyncsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar sync'),
        actions: [
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            IconButton(
              key: const ValueKey('calendar-delete-local'),
              tooltip: 'Delete calendars on this phone',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _deleteLocal,
            ),
        ],
      ),
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

/// Picks phone-only calendars to delete; all are ticked at first.
class _DeleteLocalDialog extends StatefulWidget {
  const _DeleteLocalDialog({required this.calendars});
  final List<DeviceCalendarInfo> calendars;

  @override
  State<_DeleteLocalDialog> createState() => _DeleteLocalDialogState();
}

class _DeleteLocalDialogState extends State<_DeleteLocalDialog> {
  late final _selected = {for (final c in widget.calendars) c.id};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete calendars on this phone?'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'These calendars only exist on this phone. They are deleted '
                'with all their events. Syncs using them stop adding to them.',
              ),
            ),
            for (final c in widget.calendars)
              CheckboxListTile(
                key: ValueKey('delete-local-${c.id}'),
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(c.id),
                onChanged: (v) => setState(
                  () =>
                      v == true ? _selected.add(c.id) : _selected.remove(c.id),
                ),
                secondary: c.color == null
                    ? null
                    : CircleAvatar(radius: 8, backgroundColor: Color(c.color!)),
                title: Text(c.name),
                subtitle: c.account == null ? null : Text(c.account!),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('delete-local-confirm'),
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, {..._selected}),
          child: Text('Delete (${_selected.length})'),
        ),
      ],
    );
  }
}
