/// Row model shared by the XLSX grid and the PDF: the distinct time-grid
/// units of the exported weekdays, plus extra rows for lessons outside them.
library;

import '../core/models.dart';
import 'export_model.dart';

class GridRow {
  const GridRow(this.label, this.start, this.end);
  final String label;
  final int start;
  final int end;

  bool overlaps(int s, int e) => start < e && end > s;
}

/// Sorted distinct units of [weekdays] (falling back to any day's units),
/// extended by rows for lessons that hit no unit at all.
List<GridRow> gridRows(
  TimeGrid grid,
  List<int> weekdays,
  List<ExportLesson> lessons,
) {
  final seen = <(int, int)>{};
  final rows = <GridRow>[];
  void addUnits(Iterable<TimeUnit> units) {
    for (final u in units) {
      if (seen.add((u.start, u.end))) {
        rows.add(GridRow(u.label, u.start, u.end));
      }
    }
  }

  for (final d in weekdays) {
    addUnits(grid.days[d] ?? const []);
  }
  if (rows.isEmpty) {
    for (final u in grid.days.values) {
      addUnits(u);
    }
  }
  for (final l in lessons) {
    if (!rows.any((r) => r.overlaps(l.start, l.end)) &&
        seen.add((l.start, l.end))) {
      rows.add(GridRow('', l.start, l.end));
    }
  }
  rows.sort((a, b) {
    final c = a.start.compareTo(b.start);
    return c != 0 ? c : a.end.compareTo(b.end);
  });
  return rows;
}

/// Text lines of a lesson in a grid cell: subject, teachers, rooms (and
/// classes for teacher/room timetables), plus the state when not regular.
List<String> cellLines(ExportLesson l, {required bool showClasses}) => [
  l.subjectLabel,
  if (l.teachersShort.isNotEmpty) l.teachersShort.join(', '),
  if (l.rooms.isNotEmpty) l.rooms.join(', '),
  if (showClasses && l.classes.isNotEmpty) l.classes.join(', '),
  if (l.status != LessonStatus.regular)
    l.replaced.isEmpty || l.status != LessonStatus.substitution
        ? l.status.label
        : '${l.status.label} (was ${l.replaced.join(', ')})',
];
