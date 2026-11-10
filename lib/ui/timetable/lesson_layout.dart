/// Pure layout logic: merging double lessons, side-by-side columns for
/// overlapping lessons, and the vertical time scale. No widgets, so it is
/// cheap and unit-testable.
library;

import 'dart:math' as math;

import '../../core/models.dart';
import 'timetable_utils.dart';

/// Max gap (minutes) between two periods of the same lesson that still counts
/// as "touching" (covers the short breaks inside a double lesson).
const kMergeGapMinutes = 20;

/// One card in the grid: one or more merged periods.
class LessonBlock {
  LessonBlock(this.periods);

  final List<Period> periods;

  /// Sub-column inside the day column and the number of sub-columns of its
  /// overlap cluster.
  int column = 0;
  int columns = 1;

  Period get first => periods.first;
  DateTime get start => periods.first.start;
  DateTime get end => periods.last.end;
  bool get isCancelled => periods.every((p) => p.isCancelled);
  bool get isExam => periods.any((p) => p.isExam);
  bool get isIrregular => periods.any((p) => p.isIrregular);

  bool overlaps(LessonBlock o) => start.isBefore(o.end) && o.start.isBefore(end);
}

String _elementsKey(Period p) {
  final keys = [for (final e in p.elements) '${e.type.code}:${e.id}:${e.orgId}']
    ..sort();
  return keys.join(',');
}

bool _canMerge(Period a, Period b) =>
    a.lessonId == b.lessonId &&
    a.isCancelled == b.isCancelled &&
    a.isExam == b.isExam &&
    !b.start.isBefore(a.end) &&
    b.start.difference(a.end).inMinutes <= kMergeGapMinutes &&
    sameDay(a.start, b.start) &&
    _elementsKey(a) == _elementsKey(b);

/// Lays out the periods of ONE day: merges consecutive periods of the same
/// lesson and assigns side-by-side sub-columns to overlapping blocks.
List<LessonBlock> layoutDay(Iterable<Period> periods) {
  final sorted = periods.toList()
    ..sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.end.compareTo(b.end);
    });

  // Merge: attach each period to an open block of the same lesson that ends
  // right before it (not necessarily the immediately preceding period, since
  // parallel lessons interleave).
  final blocks = <LessonBlock>[];
  for (final p in sorted) {
    LessonBlock? target;
    for (var i = blocks.length - 1; i >= 0; i--) {
      final b = blocks[i];
      if (b.end.difference(p.start).inMinutes > 0) continue;
      if (_canMerge(b.periods.last, p)) {
        target = b;
        break;
      }
    }
    if (target != null) {
      target.periods.add(p);
    } else {
      blocks.add(LessonBlock([p]));
    }
  }
  blocks.sort((a, b) => a.start.compareTo(b.start));

  // Overlap clusters -> greedy column assignment.
  var cluster = <LessonBlock>[];
  var clusterEnd = DateTime(0);
  final columnEnds = <DateTime>[];
  void close() {
    for (final b in cluster) {
      b.columns = columnEnds.length;
    }
    cluster = [];
    columnEnds.clear();
  }

  for (final b in blocks) {
    if (cluster.isNotEmpty && !b.start.isBefore(clusterEnd)) close();
    var col = columnEnds.indexWhere((end) => !end.isAfter(b.start));
    if (col == -1) {
      col = columnEnds.length;
      columnEnds.add(b.end);
    } else {
      columnEnds[col] = b.end;
    }
    b.column = col;
    cluster.add(b);
    if (b.end.isAfter(clusterEnd) || cluster.length == 1) clusterEnd = b.end;
  }
  close();
  return blocks;
}

/// Blocks overlapping [tapped] (including itself), in column order — the
/// pages of the details sheet.
List<LessonBlock> overlappingBlocks(List<LessonBlock> day, LessonBlock tapped) {
  final res = [for (final b in day) if (b == tapped || b.overlaps(tapped)) b]
    ..sort((a, b) => a.column.compareTo(b.column));
  return res;
}

/// Vertical scale: minute-of-day → pixels.
class TimeScale {
  const TimeScale(this.startMinute, this.endMinute, this.pxPerMinute);

  final int startMinute;
  final int endMinute;
  final double pxPerMinute;

  int get minutes => endMinute - startMinute;
  double get height => minutes * pxPerMinute;
  double y(int minute) => (minute - startMinute) * pxPerMinute;
  double yOf(DateTime t) => y(minuteOfDay(t));

  /// Range for [weekdays]: earliest unit start → latest unit end, widened to
  /// include any period outside the grid.
  static (int, int) rangeFor(
    TimeGrid grid,
    List<int> weekdays,
    Iterable<Period> periods,
  ) {
    var start = 24 * 60, end = 0;
    for (final d in weekdays) {
      for (final u in unitsFor(grid, d)) {
        start = math.min(start, u.start);
        end = math.max(end, u.end);
      }
    }
    for (final p in periods) {
      start = math.min(start, minuteOfDay(p.start));
      end = math.max(end, sameDay(p.start, p.end) ? minuteOfDay(p.end) : 24 * 60);
    }
    if (end <= start) return (8 * 60, 16 * 60);
    return (start, end);
  }
}
