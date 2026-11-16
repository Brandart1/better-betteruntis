import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/class_register.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/teacher_tools.dart';
import '../timetable/timetable_utils.dart';
import 'room_booking_screen.dart';
import 'time_range_field.dart';

/// Books a room without a lesson (drawer → "Book a room", teachers): time
/// (clock times or lessons), how often, then the rooms free on every date.
/// Denied when the teacher has a lesson during one of the dates.
class FreeRoomBookingScreen extends ConsumerStatefulWidget {
  const FreeRoomBookingScreen({super.key});

  @override
  ConsumerState<FreeRoomBookingScreen> createState() =>
      _FreeRoomBookingScreenState();
}

class _FreeRoomBookingScreenState extends ConsumerState<FreeRoomBookingScreen> {
  TimeRange? _range;
  BookingRepeat _repeat = BookingRepeat.once;
  final _everyDays = TextEditingController(text: '2');
  DateTime? _until;
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _done;

  DateTime get _now => ref.read(teacherToolsClockProvider)();

  @override
  void dispose() {
    _everyDays.dispose();
    _text.dispose();
    super.dispose();
  }

  /// Default: the next lesson of today (or the next school day's first).
  TimeRange _initial(TimeGrid? grid) {
    final now = _now;
    var day = dateOnly(now);
    final next = nextUnitAfter(grid, now);
    if (next != null && day.weekday <= 5) {
      return TimeRange(day, next.start, next.end);
    }
    do {
      day = addDays(day, 1);
    } while (day.weekday > 5);
    final units = lessonUnitsOf(grid, day.weekday);
    if (units.isNotEmpty) {
      return TimeRange(day, units.first.start, units.first.end);
    }
    return TimeRange(day, 8 * 60, 9 * 60);
  }

  List<TimeSlot> _slots(TimeRange r) => bookingSlots(
    start: r.startTime,
    end: r.endTime,
    repeat: _repeat,
    everyDays: int.tryParse(_everyDays.text.trim()) ?? 2,
    until: _until ?? addDays(r.date, 28),
  );

  String _when(TimeRange r, List<TimeSlot> slots) {
    final f = dateFormat(context, 'EEE d MMM');
    final first = '${f.format(r.date)}, ${hhmm(r.start)}–${hhmm(r.end)}';
    if (slots.length <= 1) return first;
    return '$first · ${slots.length} dates until '
        '${f.format(slots.last.start)}';
  }

  Future<void> _find(Account account, NameResolver? names) async {
    final r = _range;
    if (r == null || !r.isValid) return;
    final slots = _slots(r);
    if (!slots.first.start.isAfter(_now)) {
      setState(() {
        _error = 'That time has already started. Pick a later time.';
        _done = null;
      });
      return;
    }
    final repo = ref.read(teacherToolsRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    try {
      final lessons = await repo.lessonsDuring(account, slots);
      if (!mounted) return;
      if (lessons.isNotEmpty) {
        final f = dateFormat(context, 'EEE d MMM');
        setState(() {
          _busy = false;
          _error =
              'You have a lesson at that time, so this booking is not '
              'possible (change the room of the lesson instead):\n'
              '${lessons.take(5).map((p) => '• ${f.format(p.start)} ${hhmm(minuteOfDay(p.start))}–${hhmm(minuteOfDay(p.end))} ${_subject(p, names)}').join('\n')}'
              '${lessons.length > 5 ? '\n… and ${lessons.length - 5} more' : ''}';
        });
        return;
      }
      setState(() => _busy = false);
      final when = _when(r, slots);
      final roomId = await pickFreeRoom(
        context,
        title: 'Free rooms',
        subtitle: slots.length > 1
            ? '$when\nOnly rooms free on every date are listed.'
            : when,
        load: () => repo.freeRoomsForSlots(account, slots),
      );
      if (roomId == null || !mounted) return;
      final name =
          names?.longName(
            ElementRef(type: ElementType.room, id: roomId, orgId: roomId),
          ) ??
          '#$roomId';
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Book $name?'),
          content: Text(when),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('freebook-confirm'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Book'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _busy = true);
      final out = await repo.bookRoom(
        account,
        roomId: roomId,
        slots: slots,
        text: _text.text,
      );
      if (!mounted) return;
      final booked = out.where((o) => o.ok).length;
      final failed = out.where((o) => !o.ok).toList();
      final f = dateFormat(context, 'EEE d MMM');
      setState(() {
        _busy = false;
        if (booked > 0) {
          _done = booked == 1
              ? 'Booked $name. The server accepted the booking.'
              : 'Booked $name on $booked dates.';
        }
        if (failed.isNotEmpty) {
          _error =
              'Could not book ${f.format(failed.first.slot.start)}: '
              '${failed.first.error}'
              '${booked + failed.length < slots.length ? '\nThe later dates were not sent.' : ''}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = teacherToolErrorText(e);
      });
    }
  }

  static String _subject(Period p, NameResolver? names) {
    final s = p.ofType(ElementType.subject).toList();
    if (s.isEmpty || names == null) return p.lessonText;
    return s.map((e) => names.longName(e, original: e.id == 0)).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountProvider).value;
    final names = ref.watch(nameResolverProvider).value;
    final teacher = account != null && hasClassRegister(account);
    if (!teacher) {
      return Scaffold(
        appBar: AppBar(title: const Text('Book a room')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Only teacher accounts can book rooms.'),
        ),
      );
    }
    final range = _range ??= _initial(names?.timeGrid);
    final slots = range.isValid ? _slots(range) : const <TimeSlot>[];
    final theme = Theme.of(context);
    final f = dateFormat(context, 'EEE d MMM y');
    final until = _until ?? addDays(range.date, 28);
    return Scaffold(
      appBar: AppBar(title: const Text('Book a room')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('When', style: theme.textTheme.titleSmall),
          TimeRangeField(
            value: range,
            grid: names?.timeGrid,
            firstDate: dateOnly(_now),
            onChanged: (v) => setState(() {
              _range = v;
              _done = null;
            }),
          ),
          const SizedBox(height: 16),
          Text('Repeat', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (r, label) in const [
                (BookingRepeat.once, 'Once'),
                (BookingRepeat.daily, 'Daily'),
                (BookingRepeat.weekly, 'Weekly'),
                (BookingRepeat.biweekly, 'Every 2 weeks'),
                (BookingRepeat.everyNDays, 'Every n days'),
              ])
                ChoiceChip(
                  key: ValueKey('freebook-repeat-${r.name}'),
                  label: Text(label),
                  selected: _repeat == r,
                  onSelected: (_) => setState(() => _repeat = r),
                ),
            ],
          ),
          if (_repeat == BookingRepeat.everyNDays) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('freebook-every'),
              controller: _everyDays,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Every … days',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (_repeat != BookingRepeat.once) ...[
            ListTile(
              key: const ValueKey('freebook-until'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_repeat),
              title: Text(f.format(until)),
              subtitle: Text(
                [
                  'Until',
                  if (_repeat == BookingRepeat.daily ||
                      _repeat == BookingRepeat.everyNDays)
                    'weekends skipped',
                  '${slots.length} ${slots.length == 1 ? 'date' : 'dates'}',
                  if (slots.length >= maxBookingSlots)
                    'at most $maxBookingSlots',
                ].join(' · '),
              ),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: until,
                  firstDate: range.date,
                  lastDate: DateTime(range.date.year + 1, 12, 31),
                );
                if (d != null) setState(() => _until = dateOnly(d));
              },
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('freebook-text'),
            controller: _text,
            decoration: const InputDecoration(
              labelText: 'What for (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('freebook-find'),
            onPressed: _busy || !range.isValid
                ? null
                : () => _find(account, names),
            icon: const Icon(Icons.search),
            label: const Text('Find free rooms'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(key: ValueKey('freebook-busy')),
            ),
          if (_done != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _done!,
                key: const ValueKey('freebook-done'),
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ErrorBox(_error!, key: const ValueKey('freebook-error')),
            ),
          const SizedBox(height: 16),
          Text(
            'Bookings without a lesson are new in the app: if the server '
            'refuses, the Debug log has the request and the answer.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
