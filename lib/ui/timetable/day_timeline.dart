import 'package:flutter/material.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import 'day_header.dart';
import 'lesson_layout.dart';
import 'timetable_canvas.dart';
import 'timetable_utils.dart';

/// Width of the time column in the day view.
const kDayTimeColumnWidth = 52.0;

/// Single-day, detailed version of the grid (used by the day view), with the
/// day's header on top. Tapping the header calls [onHeaderTap] (back to the
/// week overview).
class DayTimeline extends StatelessWidget {
  const DayTimeline({
    super.key,
    required this.date,
    required this.periods,
    required this.names,
    this.showCancelled = true,
    this.onHeaderTap,
    this.onLessonTap,
  });

  final DateTime date;

  /// May contain other days; filtered here.
  final List<Period> periods;
  final NameResolver names;
  final bool showCancelled;
  final VoidCallback? onHeaderTap;
  final LessonTapCallback? onLessonTap;

  @override
  Widget build(BuildContext context) {
    final dayPeriods = periods
        .where(
          (p) => sameDay(p.start, date) && (showCancelled || !p.isCancelled),
        )
        .toList();
    final blocks = layoutDay(dayPeriods);
    final holiday = holidayOn(names.holidays, date);
    final (start, end) = TimeScale.rangeFor(names.timeGrid, [
      date.weekday,
    ], dayPeriods);
    final empty = blocks.isEmpty && holiday == null;
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: kDayTimeColumnWidth),
            Expanded(
              child: DayHeader(
                key: const ValueKey('day-view-header'),
                date: date,
                isToday: sameDay(date, DateTime.now()),
                onTap: onHeaderTap,
                wide: true,
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: Stack(
            children: [
              TimetableCanvas(
                days: [DayColumnData(date, blocks, holiday)],
                names: names,
                startMinute: start,
                endMinute: end,
                timeColumnWidth: kDayTimeColumnWidth,
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
          ),
        ),
      ],
    );
  }
}
