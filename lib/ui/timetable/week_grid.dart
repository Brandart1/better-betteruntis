import 'package:flutter/material.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import 'day_header.dart';
import 'lesson_layout.dart';
import 'timetable_canvas.dart';
import 'timetable_utils.dart';

/// Width of the left time-grid column in the week grid.
const kTimeColumnWidth = 40.0;

/// Precomputed, widget-free model of one week (merge + overlap layout).
class WeekModel {
  WeekModel._(this.days, this.startMinute, this.endMinute);

  factory WeekModel.build(
    DateTime weekStart,
    List<Period> allPeriods,
    NameResolver names, {
    bool showCancelled = true,
  }) {
    final periods = showCancelled
        ? allPeriods
        : allPeriods.where((p) => !p.isCancelled).toList();
    final grid = names.timeGrid;
    final weekdays = visibleWeekdays(grid, periods);
    final holidays = names.holidays;
    final days = [
      for (final wd in weekdays)
        () {
          final date = addDays(weekStart, wd - 1);
          return DayColumnData(
            date,
            layoutDay(periods.where((p) => sameDay(p.start, date))),
            holidayOn(holidays, date),
          );
        }(),
    ];
    final (start, end) = TimeScale.rangeFor(grid, weekdays, periods);
    return WeekModel._(days, start, end);
  }

  final List<DayColumnData> days;
  final int startMinute;
  final int endMinute;

  List<int> get weekdays => [for (final d in days) d.date.weekday];
}

/// Week timetable: day headers on top, time-positioned lesson cards below.
class WeekGrid extends StatelessWidget {
  const WeekGrid({
    super.key,
    required this.model,
    required this.names,
    this.onDayTap,
    this.onLessonTap,
  });

  final WeekModel model;
  final NameResolver names;
  final ValueChanged<DateTime>? onDayTap;
  final LessonTapCallback? onLessonTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: kTimeColumnWidth),
            for (final d in model.days)
              Expanded(
                child: DayHeader(
                  key: ValueKey('day-header-${d.date.weekday}'),
                  date: d.date,
                  isToday: sameDay(d.date, today),
                  onTap: onDayTap == null ? null : () => onDayTap!(d.date),
                ),
              ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: RepaintBoundary(
            child: TimetableCanvas(
              days: model.days,
              names: names,
              startMinute: model.startMinute,
              endMinute: model.endMinute,
              timeColumnWidth: kTimeColumnWidth,
              onLessonTap: onLessonTap,
            ),
          ),
        ),
      ],
    );
  }
}
