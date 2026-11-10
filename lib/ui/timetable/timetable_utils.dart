/// Pure date/time helpers for the timetable UI (no widgets).
library;

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';

/// Page index that corresponds to the current week/day in "infinite" pagers.
const kPagerOrigin = 10000;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday of the week containing [d] (date only, DST-safe).
DateTime mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int minuteOfDay(DateTime d) => d.hour * 60 + d.minute;

/// Whole weeks between the Mondays of [from] and [to].
int weekOffset(DateTime from, DateTime to) =>
    (mondayOf(to).difference(mondayOf(from)).inHours / (24 * 7)).round();

String hhmm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Locale-aware [DateFormat] that falls back to the default locale when the
/// app's locale has no date symbols loaded.
DateFormat dateFormat(BuildContext context, String pattern) {
  final locale = Localizations.maybeLocaleOf(context)?.toLanguageTag();
  if (locale != null) {
    try {
      if (DateFormat.localeExists(locale)) return DateFormat(pattern, locale);
    } catch (_) {}
  }
  return DateFormat(pattern);
}

/// "10 – 14 Nov" or "27 Oct – 1 Nov" (or with years across a year boundary).
String formatWeekRange(BuildContext context, DateTime first, DateTime last) {
  final dm = dateFormat(context, 'd MMM');
  if (first.year != last.year) {
    final dmy = dateFormat(context, 'd MMM yyyy');
    return '${dmy.format(first)} – ${dmy.format(last)}';
  }
  if (first.month == last.month) {
    return '${dateFormat(context, 'd').format(first)} – ${dm.format(last)}';
  }
  return '${dm.format(first)} – ${dm.format(last)}';
}

/// "just now", "5 min ago", "3 h ago", "on 9 Nov".
String formatUpdated(BuildContext context, DateTime? then, DateTime now) {
  if (then == null) return 'Not updated yet';
  final diff = now.difference(then);
  if (diff.inMinutes < 1) return 'Updated just now';
  if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes} min ago';
  if (diff.inHours < 24) return 'Updated ${diff.inHours} h ago';
  return 'Updated on ${dateFormat(context, 'd MMM').format(then)}';
}

/// Weekdays (1 = Mon) to display: Mon–Fri plus Sat/Sun if the grid or the
/// periods contain them.
List<int> visibleWeekdays(TimeGrid grid, Iterable<Period> periods) {
  final days = {1, 2, 3, 4, 5};
  for (final d in [6, 7]) {
    if ((grid.days[d]?.isNotEmpty ?? false) ||
        periods.any((p) => p.start.weekday == d)) {
      days.add(d);
    }
  }
  return days.toList()..sort();
}

/// Units of [weekday], falling back to the first non-empty day.
List<TimeUnit> unitsFor(TimeGrid grid, int weekday) {
  final units = grid.days[weekday];
  if (units != null && units.isNotEmpty) return units;
  for (final d in [1, 2, 3, 4, 5, 6, 7]) {
    final u = grid.days[d];
    if (u != null && u.isNotEmpty) return u;
  }
  return const [];
}

/// Lesson-number label for a time span, e.g. "3" or "1–2" ("" if none).
String lessonNumbers(TimeGrid grid, DateTime start, DateTime end) {
  final s = minuteOfDay(start), e = minuteOfDay(end);
  final hit = [
    for (final u in unitsFor(grid, start.weekday))
      if (u.start < e && u.end > s) u.label,
  ];
  if (hit.isEmpty) return '';
  return hit.length == 1 ? hit.first : '${hit.first}–${hit.last}';
}

/// Holiday covering [day], if any.
Holiday? holidayOn(List<Holiday> holidays, DateTime day) {
  final d = dateOnly(day);
  for (final h in holidays) {
    if (!d.isBefore(dateOnly(h.start)) && !d.isAfter(dateOnly(h.end))) return h;
  }
  return null;
}
