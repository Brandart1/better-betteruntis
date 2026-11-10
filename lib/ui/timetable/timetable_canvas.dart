import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import 'grid_background.dart';
import 'holiday_block.dart';
import 'lesson_card.dart';
import 'lesson_layout.dart';
import 'now_indicator.dart';
import 'timetable_utils.dart';

/// Called with the blocks overlapping the tapped one and the tapped index.
typedef LessonTapCallback = void Function(List<LessonBlock> blocks, int index);

/// Data of one displayed day column.
class DayColumnData {
  const DayColumnData(this.date, this.blocks, this.holiday);
  final DateTime date;
  final List<LessonBlock> blocks;
  final Holiday? holiday;
}

/// Time-positioned lesson area shared by the week grid and the day view:
/// a single [Stack] of absolutely positioned children over one background
/// painter, inside an always-scrollable vertical scroll view (so pull-to-
/// refresh works). Fits the viewport height unless that would make lessons
/// shorter than [minPxPerMinute].
class TimetableCanvas extends StatelessWidget {
  const TimetableCanvas({
    super.key,
    required this.days,
    required this.names,
    required this.startMinute,
    required this.endMinute,
    required this.timeColumnWidth,
    this.minPxPerMinute = 0.8,
    this.detailed = false,
    this.onLessonTap,
  });

  final List<DayColumnData> days;
  final NameResolver names;
  final int startMinute;
  final int endMinute;
  final double timeColumnWidth;
  final double minPxPerMinute;
  final bool detailed;
  final LessonTapCallback? onLessonTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final minutes = math.max(1, endMinute - startMinute);
        final ppm = math.max(minPxPerMinute, c.maxHeight / minutes);
        final scale = TimeScale(startMinute, endMinute, ppm);
        final height = math.max(c.maxHeight, scale.height);
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            width: c.maxWidth,
            height: height,
            child: _stack(context, scale, c.maxWidth, height),
          ),
        );
      },
    );
  }

  Widget _stack(
    BuildContext context,
    TimeScale scale,
    double width,
    double height,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final colW = (width - timeColumnWidth) / math.max(1, days.length);
    final today = dateOnly(DateTime.now());
    final units = days.isEmpty
        ? const <TimeUnit>[]
        : unitsFor(names.timeGrid, days.first.date.weekday);
    final todayCol = days.indexWhere((d) => sameDay(d.date, today));
    final pastCols = days.where((d) => d.date.isBefore(today)).length;
    const gap = 1.5;

    final children = <Widget>[
      Positioned.fill(
        child: CustomPaint(
          painter: GridBackgroundPainter(
            scale: scale,
            units: units,
            left: timeColumnWidth,
            columnWidth: colW,
            columns: days.length,
            pastColumns: pastCols,
            todayColumn: todayCol,
            lineColor: cs.outlineVariant.withValues(alpha: 0.5),
            pastTint: cs.onSurface.withValues(alpha: 0.04),
            todayTint: cs.primary.withValues(alpha: 0.05),
          ),
        ),
      ),
      for (final u in units)
        Positioned(
          left: 0,
          width: timeColumnWidth,
          top: scale.y(u.start),
          height: math.max(0, scale.y(u.end) - scale.y(u.start)),
          child: _UnitLabel(unit: u, large: detailed),
        ),
    ];

    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final x = timeColumnWidth + i * colW;
      if (day.holiday != null) {
        children.add(
          Positioned(
            left: x + gap,
            width: colW - 2 * gap,
            top: gap,
            height: height - 2 * gap,
            child: HolidayBlock(holiday: day.holiday!),
          ),
        );
      }
      for (final b in day.blocks) {
        final subW = colW / b.columns;
        final top = scale.yOf(b.start);
        final bottom = sameDay(b.start, b.end) ? scale.yOf(b.end) : height;
        children.add(
          Positioned(
            key: ValueKey('lesson-${b.first.id}'),
            left: x + b.column * subW + gap,
            width: math.max(0, subW - 2 * gap),
            top: top + gap,
            height: math.max(4, bottom - top - 2 * gap),
            child: LessonCard(
              block: b,
              names: names,
              detailed: detailed,
              onTap: onLessonTap == null
                  ? null
                  : () {
                      final pages = overlappingBlocks(day.blocks, b);
                      onLessonTap!(pages, pages.indexOf(b));
                    },
            ),
          ),
        );
      }
    }
    if (todayCol >= 0) {
      children.add(
        NowIndicator(
          scale: scale,
          left: timeColumnWidth + todayCol * colW,
          width: colW,
        ),
      );
    }
    return Stack(clipBehavior: Clip.hardEdge, children: children);
  }
}

class _UnitLabel extends StatelessWidget {
  const _UnitLabel({required this.unit, required this.large});
  final TimeUnit unit;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: unit.label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: large ? 14 : 12,
                color: cs.onSurface,
              ),
            ),
            TextSpan(
              text: '\n${hhmm(unit.start)}',
              style: TextStyle(
                fontSize: large ? 11 : 9,
                color: cs.onSurfaceVariant,
              ),
            ),
            if (large)
              TextSpan(
                text: '\n${hhmm(unit.end)}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
          ],
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.clip,
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
      ),
    );
  }
}
