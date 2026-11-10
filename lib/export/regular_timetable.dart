/// Derives the planned, repeating timetable from a few concrete weeks.
///
/// Pure Dart: no Flutter, no I/O.
///
/// 1. Every period is normalized to its PLANNED form: substituted and removed
///    elements are reverted to their original ([ElementRef.orgId]), elements
///    that were only added are dropped, cancellation/irregular flags and
///    one-off texts are cleared (cancelled lessons are still planned ones).
///    Exams and purely additional periods (no element with an original) are
///    dropped entirely.
/// 2. Per week, a weekday is "sampled" only if it is not a holiday and has at
///    least one period. For each weekday and time slot (start, end) every
///    sampled week votes for the set of normalized lessons it had there
///    (possibly "nothing"); a week whose only periods in that slot were
///    dropped (exam, added lesson) abstains.
/// 3. The most frequent content wins; ties go to the earliest week.
library;

import '../core/models.dart';

/// One concrete week used as a sample.
class SampleWeek {
  const SampleWeek(this.weekStart, this.periods);

  /// Monday of the week.
  final DateTime weekStart;
  final List<Period> periods;
}

/// Returns the regular timetable as periods dated in the week of
/// `weeks.first.weekStart` (only weekday and time of day are meaningful).
List<Period> deriveRegularTimetable(
  List<SampleWeek> weeks, {
  List<Holiday> holidays = const [],
}) {
  if (weeks.isEmpty) return const [];
  final ordered = [...weeks]
    ..sort((a, b) => a.weekStart.compareTo(b.weekStart));
  final reference = _dateOnly(ordered.first.weekStart);

  // weekday -> slot -> list of (week index, content key, periods)
  final votes = <int, Map<_Slot, List<_Vote>>>{};
  // weekday -> weeks that sampled it; (weekday, slot) -> weeks abstaining.
  final sampled = <int, Set<int>>{};
  final abstainedBy = <(int, _Slot), Set<int>>{};

  for (var w = 0; w < ordered.length; w++) {
    final week = ordered[w];
    final byDay = <int, List<Period>>{};
    for (final p in week.periods) {
      byDay.putIfAbsent(p.start.weekday, () => []).add(p);
    }
    for (final MapEntry(key: day, value: dayPeriods) in byDay.entries) {
      if (_isHoliday(holidays, dayPeriods.first.start)) continue;

      final normalized = <_Slot, List<Period>>{};
      final abstain = <_Slot>{};
      for (final p in dayPeriods) {
        final slot = _Slot.of(p);
        final n = normalizePlanned(p);
        if (n == null) {
          abstain.add(slot);
        } else {
          normalized.putIfAbsent(slot, () => []).add(n);
        }
      }
      final dayVotes = votes.putIfAbsent(day, () => {});
      // Slots seen in this week.
      for (final MapEntry(key: slot, value: ps) in normalized.entries) {
        dayVotes.putIfAbsent(slot, () => []).add(_Vote(w, ps));
      }
      for (final slot in abstain) {
        dayVotes.putIfAbsent(slot, () => []);
      }
      // Weeks that sampled this day vote "nothing" for slots they lack.
      sampled.putIfAbsent(day, () => {}).add(w);
      for (final slot in abstain) {
        abstainedBy.putIfAbsent((day, slot), () => {}).add(w);
      }
    }
  }

  final out = <Period>[];
  for (final MapEntry(key: day, value: slots) in votes.entries) {
    final sampledWeeks = sampled[day] ?? const <int>{};
    for (final MapEntry(key: slot, value: slotVotes) in slots.entries) {
      final voted = {for (final v in slotVotes) v.week};
      final abstained = abstainedBy[(day, slot)] ?? const <int>{};
      final all = [
        ...slotVotes,
        for (final w in sampledWeeks)
          if (!voted.contains(w) && !abstained.contains(w)) _Vote(w, const []),
      ];
      if (all.isEmpty) continue;
      // Count per content key; remember earliest week per key.
      final count = <String, int>{};
      final first = <String, _Vote>{};
      for (final v in all) {
        count[v.key] = (count[v.key] ?? 0) + 1;
        final f = first[v.key];
        if (f == null || v.week < f.week) first[v.key] = v;
      }
      String? best;
      for (final k in count.keys) {
        if (best == null ||
            count[k]! > count[best]! ||
            (count[k] == count[best] && first[k]!.week < first[best]!.week)) {
          best = k;
        }
      }
      final winner = first[best]!;
      final date = DateTime(
        reference.year,
        reference.month,
        reference.day + day - 1,
      );
      for (final p in winner.periods) {
        out.add(_moveTo(p, date));
      }
    }
  }
  out.sort((a, b) {
    final c = a.start.compareTo(b.start);
    if (c != 0) return c;
    final d = a.end.compareTo(b.end);
    return d != 0 ? d : plannedSignature(a).compareTo(plannedSignature(b));
  });
  return out;
}

/// The planned form of [p], or null when it is not part of the planned
/// timetable (exam, or every element only added).
Period? normalizePlanned(Period p) {
  if (p.isExam) return null;
  if (p.elements.isNotEmpty && p.elements.every((e) => e.orgId == 0)) {
    return null;
  }
  final elements = <ElementRef>[
    for (final e in p.elements)
      if (e.change == ElementChange.regular)
        e
      else if (e.change != ElementChange.added)
        ElementRef(
          type: e.type,
          id: e.orgId,
          orgId: e.orgId,
          // A removed element's inline names describe the original.
          inlineName: e.id == 0
              ? (e.orgInlineName ?? e.inlineName)
              : e.orgInlineName,
          inlineLongName: e.id == 0
              ? (e.orgInlineLongName ?? e.inlineLongName)
              : e.orgInlineLongName,
        ),
  ];
  return Period(
    id: p.id,
    lessonId: p.lessonId,
    start: p.start,
    end: p.end,
    elements: elements,
    flags: const {PeriodFlag.regular},
    lessonText: p.lessonText,
    foreColor: p.foreColor,
    backColor: p.backColor,
  );
}

/// Identity of a planned lesson: subject, teachers, rooms and classes.
String plannedSignature(Period p) {
  final keys = [
    for (final e in p.elements)
      if (e.type != ElementType.unknown && e.type != ElementType.student)
        '${e.type.code}:${e.id}',
  ]..sort();
  return keys.join(',');
}

class _Slot {
  const _Slot(this.start, this.end);
  factory _Slot.of(Period p) => _Slot(
    p.start.hour * 60 + p.start.minute,
    p.end.difference(p.start).inMinutes + p.start.hour * 60 + p.start.minute,
  );
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is _Slot && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(start, end);
}

class _Vote {
  _Vote(this.week, this.periods)
    : key = (periods.map(plannedSignature).toList()..sort()).join('|');
  final int week;
  final List<Period> periods;
  final String key;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _isHoliday(List<Holiday> holidays, DateTime day) {
  final d = _dateOnly(day);
  for (final h in holidays) {
    if (!d.isBefore(_dateOnly(h.start)) && !d.isAfter(_dateOnly(h.end))) {
      return true;
    }
  }
  return false;
}

Period _moveTo(Period p, DateTime date) {
  DateTime at(DateTime t) =>
      DateTime(date.year, date.month, date.day, t.hour, t.minute);
  final dur = p.end.difference(p.start);
  final start = at(p.start);
  return Period(
    id: p.id,
    lessonId: p.lessonId,
    start: start,
    end: start.add(dur),
    elements: p.elements,
    flags: p.flags,
    lessonText: p.lessonText,
    foreColor: p.foreColor,
    backColor: p.backColor,
  );
}
