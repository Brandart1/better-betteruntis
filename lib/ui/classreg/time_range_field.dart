import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../timetable/timetable_utils.dart';

/// A day and a time span on it, in minutes since midnight.
class TimeRange {
  const TimeRange(this.date, this.start, this.end);

  final DateTime date;
  final int start;
  final int end;

  DateTime get startTime =>
      DateTime(date.year, date.month, date.day, start ~/ 60, start % 60);
  DateTime get endTime =>
      DateTime(date.year, date.month, date.day, end ~/ 60, end % 60);

  bool get isValid => end > start;

  TimeRange copyWith({DateTime? date, int? start, int? end}) =>
      TimeRange(date ?? this.date, start ?? this.start, end ?? this.end);
}

/// The school's lesson units of [weekday] (none for a made-up time grid).
List<TimeUnit> lessonUnitsOf(TimeGrid? grid, int weekday) =>
    grid == null || grid.isFallback ? const [] : unitsFor(grid, weekday);

/// The unit running at [now], else null.
TimeUnit? unitAt(TimeGrid? grid, DateTime now) {
  final m = minuteOfDay(now);
  for (final u in lessonUnitsOf(grid, now.weekday)) {
    if (u.start <= m && m < u.end) return u;
  }
  return null;
}

/// The first unit starting after [now] on that day, else null.
TimeUnit? nextUnitAfter(TimeGrid? grid, DateTime now) {
  final m = minuteOfDay(now);
  for (final u in lessonUnitsOf(grid, now.weekday)) {
    if (u.start > m) return u;
  }
  return null;
}

/// Picks a day (optional) and a time span on it, either as clock times or
/// as lesson numbers of the school's time grid ([grid]; without one, only
/// clock times).
class TimeRangeField extends StatefulWidget {
  const TimeRangeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.grid,
    this.showDate = true,
    this.firstDate,
  });

  final TimeRange value;
  final ValueChanged<TimeRange> onChanged;
  final TimeGrid? grid;
  final bool showDate;

  /// Earliest pickable day (default: a year back).
  final DateTime? firstDate;

  @override
  State<TimeRangeField> createState() => _TimeRangeFieldState();
}

class _TimeRangeFieldState extends State<TimeRangeField> {
  /// Lesson numbers instead of clock times.
  late bool _lessons = _units.isNotEmpty && _unitRange() != null;

  List<TimeUnit> get _units =>
      lessonUnitsOf(widget.grid, widget.value.date.weekday);

  /// Indices of the units the value starts and ends with exactly.
  (int, int)? _unitRange() {
    final units = _units;
    final s = units.indexWhere((u) => u.start == widget.value.start);
    final e = units.indexWhere((u) => u.end == widget.value.end);
    if (s < 0 || e < 0 || e < s) return null;
    return (s, e);
  }

  Future<void> _pickDate() async {
    final v = widget.value;
    final d = await showDatePicker(
      context: context,
      initialDate: v.date,
      firstDate: widget.firstDate ?? DateTime(v.date.year - 1, v.date.month, 1),
      lastDate: DateTime(v.date.year + 2, 12, 31),
    );
    if (d != null) widget.onChanged(v.copyWith(date: dateOnly(d)));
  }

  Future<void> _pickTime(bool start) async {
    final v = widget.value;
    final m = start ? v.start : v.end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t == null) return;
    final mins = t.hour * 60 + t.minute;
    if (start) {
      // Keep the length when the start moves.
      final len = v.end - v.start;
      widget.onChanged(
        v.copyWith(
          start: mins,
          end: len > 0 && mins + len < 24 * 60 ? mins + len : v.end,
        ),
      );
    } else {
      widget.onChanged(v.copyWith(end: mins));
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final units = _units;
    final range = _unitRange();
    final lessons = _lessons && units.isNotEmpty;
    final theme = Theme.of(context);
    String unitLabel(TimeUnit u) =>
        'Lesson ${u.label} (${hhmm(u.start)}–${hhmm(u.end)})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showDate)
          ListTile(
            key: const ValueKey('timerange-date'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(dateFormat(context, 'EEEE d MMMM y').format(v.date)),
            subtitle: const Text('Date'),
            onTap: _pickDate,
          ),
        if (units.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('timerange-mode-times'),
                label: const Text('Times'),
                selected: !lessons,
                onSelected: (_) => setState(() => _lessons = false),
              ),
              ChoiceChip(
                key: const ValueKey('timerange-mode-lessons'),
                label: const Text('Lessons'),
                selected: lessons,
                onSelected: (_) {
                  setState(() => _lessons = true);
                  // Snap to the lessons the time touches.
                  if (_unitRange() == null) {
                    var s = units.indexWhere((u) => u.end > v.start);
                    if (s < 0) s = 0;
                    var e = units.lastIndexWhere((u) => u.start < v.end);
                    if (e < s) e = s;
                    widget.onChanged(
                      v.copyWith(start: units[s].start, end: units[e].end),
                    );
                  }
                },
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (lessons) ...[
          _Dropdown(
            fieldKey: const ValueKey('timerange-from-lesson'),
            label: 'From lesson',
            value: range?.$1,
            items: [
              for (var i = 0; i < units.length; i++)
                DropdownMenuItem(value: i, child: Text(unitLabel(units[i]))),
            ],
            onChanged: (i) {
              if (i == null) return;
              final to = range == null || range.$2 < i ? i : range.$2;
              widget.onChanged(
                v.copyWith(start: units[i].start, end: units[to].end),
              );
            },
          ),
          const SizedBox(height: 12),
          _Dropdown(
            fieldKey: const ValueKey('timerange-to-lesson'),
            label: 'To lesson',
            value: range?.$2,
            items: [
              for (var i = range?.$1 ?? 0; i < units.length; i++)
                DropdownMenuItem(value: i, child: Text(unitLabel(units[i]))),
            ],
            onChanged: (i) {
              if (i == null) return;
              widget.onChanged(v.copyWith(end: units[i].end));
            },
          ),
        ] else
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('timerange-from'),
                onPressed: () => _pickTime(true),
                icon: const Icon(Icons.schedule),
                label: Text('From ${hhmm(v.start)}'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('timerange-to'),
                onPressed: () => _pickTime(false),
                icon: const Icon(Icons.schedule),
                label: Text('To ${hhmm(v.end)}'),
              ),
            ],
          ),
        if (!v.isValid)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'The end must be after the start.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// A labelled, controlled dropdown (its value follows the parent's).
class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final int? value;
  final List<DropdownMenuItem<int>> items;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        key: fieldKey,
        isExpanded: true,
        itemHeight: null,
        value: items.any((i) => i.value == value) ? value : null,
        items: items,
        onChanged: onChanged,
      ),
    ),
  );
}
