import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../calendar/calendar_sync.dart';
import '../../calendar/calendar_sync_service.dart';
import '../../calendar/device_calendar.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../export/export_model.dart';

/// What to set up: a timetable of an account (new or existing sync).
class CalendarSetupArgs {
  const CalendarSetupArgs({
    required this.accountId,
    required this.target,
    required this.elementName,
  });
  final String accountId;
  final TimetableTarget target;
  final String elementName;
}

bool get _android => defaultTargetPlatform == TargetPlatform.android;

/// Where new calendars end up and how to make them visible.
String get newCalendarHint => _android
    ? 'A new calendar only exists on this phone (account '
          '"$kCalendarAccountName"). In Google Calendar, open the menu and '
          'turn it on under "$kCalendarAccountName" if it is not shown.'
    : 'New calendars are created in iCloud, or on this device without '
          'iCloud.';

String calendarStateLabel(LessonStatus s) => switch (s) {
  LessonStatus.regular => 'Regular lessons',
  LessonStatus.substitution => 'Substitutions',
  LessonStatus.exam => 'Exams',
  LessonStatus.cancelled => 'Cancelled lessons',
};

/// "Add to calendar": per lesson state a new calendar, an existing one or
/// none; how many weeks; automatic updates.
class CalendarSyncScreen extends ConsumerStatefulWidget {
  const CalendarSyncScreen({super.key, required this.args});

  final CalendarSetupArgs args;

  @override
  ConsumerState<CalendarSyncScreen> createState() => _CalendarSyncScreenState();
}

class _CalendarSyncScreenState extends ConsumerState<CalendarSyncScreen> {
  static const _weekOptions = [2, 4, 8, 12];

  late final CalendarSync? _existing = ref
      .read(calendarSyncsProvider.notifier)
      .forTarget(widget.args.accountId, widget.args.target);
  late Future<List<DeviceCalendarInfo>> _calendars = _loadCalendars();

  /// Back from creating a calendar on the web: list it.
  late final _lifecycle = AppLifecycleListener(
    onResume: () {
      if (mounted) setState(() => _calendars = _loadCalendars());
    },
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  late final Map<LessonStatus, CalendarChoice> _choices = {
    for (final s in LessonStatus.values)
      s: _existing == null
          ? const NewCalendar()
          : switch (_existing.calendars[s]) {
              final String id => ExistingCalendar(id),
              null => const SkipCalendar(),
            },
  };
  late int _weeks = _existing?.weeks ?? 4;
  late bool _auto = _existing?.autoUpdate ?? true;
  bool _busy = false;
  String? _error;

  Future<List<DeviceCalendarInfo>> _loadCalendars() async {
    final api = ref.read(deviceCalendarProvider);
    await api.requestAccess();
    return api.calendars();
  }

  Future<void> _save(List<DeviceCalendarInfo> calendars) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final known = {for (final c in calendars) c.id};
    // Calendars removed meanwhile count as "don't add".
    final choices = {
      for (final e in _choices.entries)
        e.key: switch (e.value) {
          ExistingCalendar(:final id) when !known.contains(id) =>
            const SkipCalendar(),
          final c => c,
        },
    };
    if (choices.values.every((c) => c is SkipCalendar)) {
      setState(() => _error = 'Choose a calendar for at least one kind.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final a = widget.args;
    final draft =
        _existing?.copyWith(
          elementName: a.elementName,
          weeks: _weeks,
          autoUpdate: _auto,
        ) ??
        CalendarSync(
          id: '${a.accountId}:${a.target.type.apiName}:${a.target.id}',
          accountId: a.accountId,
          target: a.target,
          elementName: a.elementName,
          weeks: _weeks,
          autoUpdate: _auto,
        );
    try {
      final counts = await ref
          .read(calendarSyncsProvider.notifier)
          .save(draft, choices);
      final created = choices.values.any((c) => c is NewCalendar);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            created && _android
                ? '$counts. If the new calendars are missing in Google '
                      'Calendar, turn on "$kCalendarAccountName" in its menu.'
                : '$counts.',
          ),
          duration: Duration(seconds: created ? 8 : 4),
        ),
      );
      if (mounted) router.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = calendarErrorText(e);
        });
      }
    }
  }

  Future<void> _remove() async {
    final existing = _existing;
    if (existing == null) return;
    final router = GoRouter.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop calendar sync?'),
        content: const Text(
          'Calendars created for this timetable are deleted. Lessons added '
          'to your own calendars are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop sync'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await ref.read(calendarSyncsProvider.notifier).remove(existing.id);
    if (mounted) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = calendarColors(ref.watch(timetableSettingsProvider));
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'Add to calendar' : 'Calendar sync'),
      ),
      body: FutureBuilder<List<DeviceCalendarInfo>>(
        future: _calendars,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  calendarErrorText(snap.error!),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final calendars = snap.data;
          if (calendars == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'Lessons of ${widget.args.elementName} are added to your '
                  'calendar. Changes like substitutions and cancellations '
                  'are updated whenever you open the app.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (_android) ...[
                  const SizedBox(height: 12),
                  const GoogleCalendarInfo(),
                ],
                const SizedBox(height: 16),
                for (final s in LessonStatus.values)
                  _StateRow(
                    key: ValueKey('calendar-choice-${s.name}'),
                    label: calendarStateLabel(s),
                    newName: defaultCalendarName(widget.args.elementName, s),
                    newColor: colors[s]!,
                    calendars: calendars,
                    value: _choices[s]!,
                    onChanged: (c) => setState(() => _choices[s] = c),
                  ),
                if (_choices.values.any((c) => c is NewCalendar))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      newCalendarHint,
                      key: const ValueKey('calendar-new-hint'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Weeks ahead', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: [
                    for (final w in _weekOptions)
                      ButtonSegment(value: w, label: Text('$w')),
                  ],
                  selected: {_weeks},
                  onSelectionChanged: (v) => setState(() => _weeks = v.first),
                ),
                SwitchListTile(
                  key: const ValueKey('calendar-auto'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep up to date'),
                  subtitle: const Text(
                    'Update the calendar when the app is opened',
                  ),
                  value: _auto,
                  onChanged: (v) => setState(() => _auto = v),
                ),
                if (_existing?.lastSync case final t?)
                  Text(
                    'Last synced ${DateFormat.yMd().add_Hm().format(t)}',
                    style: theme.textTheme.bodySmall,
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('calendar-save'),
                  onPressed: _busy ? null : () => _save(calendars),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.event_available),
                  label: Text(
                    _existing == null ? 'Add to calendar' : 'Save and sync',
                  ),
                ),
                if (_existing != null)
                  TextButton.icon(
                    key: const ValueKey('calendar-remove'),
                    onPressed: _busy ? null : _remove,
                    icon: const Icon(Icons.event_busy),
                    label: const Text('Stop sync'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final int? color;
  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color == null ? null : Color(color!),
      border: Border.all(color: Theme.of(context).colorScheme.outline),
    ),
  );
}

class _StateRow extends StatelessWidget {
  const _StateRow({
    super.key,
    required this.label,
    required this.newName,
    required this.newColor,
    required this.calendars,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String newName;
  final int newColor;
  final List<DeviceCalendarInfo> calendars;
  final CalendarChoice value;
  final ValueChanged<CalendarChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final known = {for (final c in calendars) c.id};
    final selected = switch (value) {
      ExistingCalendar(:final id) when !known.contains(id) =>
        const SkipCalendar(),
      final v => v,
    };
    DropdownMenuItem<CalendarChoice> item(
      CalendarChoice v,
      int? color,
      String text,
    ) => DropdownMenuItem(
      value: v,
      child: Row(
        children: [
          _Dot(color),
          const SizedBox(width: 12),
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<CalendarChoice>(
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          item(const NewCalendar(), newColor, 'New calendar "$newName"'),
          for (final c in calendars)
            item(
              ExistingCalendar(c.id),
              c.color,
              [
                c.name,
                if (c.account != null && c.account != c.name) '(${c.account})',
                if (c.hidden) '· turned off in calendar app',
              ].join(' '),
            ),
          item(const SkipCalendar(), null, "Don't add"),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// Google's page for creating a calendar (not possible in the Android app).
final kGoogleCreateCalendarUrl = Uri.parse(
  'https://calendar.google.com/calendar/r/settings/createcalendar',
);

/// Android: how to get calendars that sync with the Google account.
class GoogleCalendarInfo extends StatelessWidget {
  const GoogleCalendarInfo({super.key});

  /// A browser tab, not the external handler: the Google Calendar app would
  /// catch the link and can't create calendars.
  static Future<void> _openCreatePage() async {
    try {
      if (await launchUrl(
        kGoogleCreateCalendarUrl,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return;
      }
    } catch (_) {}
    await launchUrl(
      kGoogleCreateCalendarUrl,
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
    return Card.outlined(
      key: const ValueKey('google-calendar-info'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sync with your Google account',
              style: theme.textTheme.titleSmall,
            ),
            point(
              Icons.phone_android,
              '"New calendar" only creates a calendar on this phone. It is '
              'not synced to your Google account or other devices.',
            ),
            point(
              Icons.add_circle_outline,
              'For synced calendars, create them in Google Calendar on the '
              'web (this is not possible in the Google Calendar app), then '
              'come back and choose them below.',
            ),
            point(
              Icons.sync,
              'Make sure sync is on: Google Calendar app → Settings → tap '
              'the calendar → Sync.',
            ),
            point(
              Icons.palette_outlined,
              'Set the colours of Google calendars in Google Calendar. The '
              'app can only colour calendars it created itself.',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: const ValueKey('google-create-calendar'),
                onPressed: _openCreatePage,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Create calendar on the web'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
