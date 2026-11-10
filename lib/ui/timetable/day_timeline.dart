import 'package:flutter/material.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import 'lesson_layout.dart';
import 'timetable_canvas.dart';
import 'timetable_utils.dart';

/// Single-day, detailed version of the grid (used by the day view).
class DayTimeline extends StatelessWidget {
  const DayTimeline({
    super.key,
    required this.date,
    required this.periods,
    required this.names,
    this.onLessonTap,
  });

  final DateTime date;

  /// May contain other days; filtered here.
  final List<Period> periods;
  final NameResolver names;
  final LessonTapCallback? onLessonTap;

  @override
  Widget build(BuildContext context) {
    final dayPeriods = periods.where((p) => sameDay(p.start, date)).toList();
    final blocks = layoutDay(dayPeriods);
    final holiday = holidayOn(names.holidays, date);
    final (start, end) =
        TimeScale.rangeFor(names.timeGrid, [date.weekday], dayPeriods);
    final empty = blocks.isEmpty && holiday == null;
    return Stack(
      children: [
        TimetableCanvas(
          days: [DayColumnData(date, blocks, holiday)],
          names: names,
          startMinute: start,
          endMinute: end,
          timeColumnWidth: 52,
          minPxPerMinute: 1.4,
          detailed: true,
          onLessonTap: onLessonTap,
        ),
        if (empty)
          IgnorePointer(
            child: Center(
              child: Text(
                'No lessons',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
