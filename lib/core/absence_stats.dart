/// Absences compared with the timetable: whether an absence covers the
/// whole school day, and attendance per subject. Lessons are the
/// timetable's periods; cancelled ones don't count (nobody could attend
/// them).
library;

import 'info.dart';
import 'interfaces.dart';
import 'models.dart';

/// Periods that count as lessons one could attend: not cancelled.
bool countsAsLesson(Period p) => !p.isCancelled;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Minutes of [p] inside [a].
int overlapMinutes(Period p, AbsenceItem a) {
  final s = p.start.isAfter(a.start) ? p.start : a.start;
  final e = p.end.isBefore(a.end) ? p.end : a.end;
  final m = e.difference(s).inMinutes;
  return m > 0 ? m : 0;
}

/// How much of the school day(s) an absence covers.
class DayCoverage {
  const DayCoverage({
    required this.covered,
    required this.affected,
    required this.lessons,
  });

  /// Lessons of the absence's day(s) it covers completely.
  final int covered;

  /// Lessons it covers at least in part (late arrival, leaving early).
  final int affected;

  /// Lessons on the day(s) the absence touches.
  final int lessons;

  /// Every lesson of every day the absence touches.
  bool get wholeDay => lessons > 0 && covered == lessons;
}

/// [a] compared with [periods] (at least the lessons of the days it
/// touches; others are ignored). Null when those days have no lessons
/// (weekend, holidays, or the timetable isn't known).
DayCoverage? dayCoverage(AbsenceItem a, Iterable<Period> periods) {
  final first = _day(a.start);
  final last = _day(a.end);
  var lessons = 0;
  var covered = 0;
  var affected = 0;
  for (final p in periods) {
    if (!countsAsLesson(p)) continue;
    final d = _day(p.start);
    if (d.isBefore(first) || d.isAfter(last)) continue;
    lessons++;
    if (!p.start.isBefore(a.start) && !p.end.isAfter(a.end)) covered++;
    if (overlapMinutes(p, a) > 0) affected++;
  }
  if (lessons == 0) return null;
  return DayCoverage(covered: covered, affected: affected, lessons: lessons);
}

/// Attendance in one subject.
class SubjectAttendance {
  const SubjectAttendance({
    required this.subjectId,
    required this.lessons,
    required this.missed,
    required this.missedUnexcused,
    required this.lessonMinutes,
    required this.absentMinutes,
  });

  /// Subject element id; 0 = lessons without a subject.
  final int subjectId;

  /// Lessons held so far (not cancelled).
  final int lessons;

  /// Lessons with any absence (late arrivals and leaving early included).
  final int missed;

  /// Of [missed]: lessons with an unexcused absence.
  final int missedUnexcused;

  final int lessonMinutes;
  final int absentMinutes;

  /// Share of the lesson time attended, 0–100.
  double get attendancePercent => lessonMinutes == 0
      ? 100
      : 100 * (lessonMinutes - absentMinutes) / lessonMinutes;
}

/// Attendance per subject over [periods] that started before [now], worst
/// attendance first. A lesson's absent time counts once even if absences
/// overlap.
List<SubjectAttendance> attendanceBySubject(
  Iterable<Period> periods,
  List<AbsenceItem> absences,
  DateTime now,
) {
  final bySubject = <int, _Acc>{};
  final seen = <int>{};
  for (final p in periods) {
    if (!countsAsLesson(p) || !p.start.isBefore(now) || !seen.add(p.id)) {
      continue;
    }
    final subjects = [
      for (final e in p.elements)
        if (e.type == ElementType.subject) e.id,
    ];
    final minutes = p.end.difference(p.start).inMinutes;
    if (minutes <= 0) continue;
    var absent = 0;
    var unexcused = false;
    for (final a in absences) {
      final m = overlapMinutes(p, a);
      if (m == 0) continue;
      absent += m;
      if (!a.excused) unexcused = true;
    }
    if (absent > minutes) absent = minutes;
    for (final s in subjects.isEmpty ? const [0] : subjects.toSet()) {
      final acc = bySubject.putIfAbsent(s, _Acc.new);
      acc.lessons++;
      acc.lessonMinutes += minutes;
      acc.absentMinutes += absent;
      if (absent > 0) {
        acc.missed++;
        if (unexcused) acc.missedUnexcused++;
      }
    }
  }
  return [
    for (final MapEntry(key: id, value: a) in bySubject.entries)
      SubjectAttendance(
        subjectId: id,
        lessons: a.lessons,
        missed: a.missed,
        missedUnexcused: a.missedUnexcused,
        lessonMinutes: a.lessonMinutes,
        absentMinutes: a.absentMinutes,
      ),
  ]..sort((a, b) {
    final c = a.attendancePercent.compareTo(b.attendancePercent);
    return c != 0 ? c : b.lessons.compareTo(a.lessons);
  });
}

class _Acc {
  int lessons = 0;
  int missed = 0;
  int missedUnexcused = 0;
  int lessonMinutes = 0;
  int absentMinutes = 0;
}

/// Mondays of the weeks from [from] to [to] (both included).
List<DateTime> mondaysBetween(DateTime from, DateTime to) {
  final out = <DateTime>[];
  var m = _day(from).subtract(Duration(days: from.weekday - 1));
  m = DateTime(m.year, m.month, m.day);
  final end = _day(to);
  while (!m.isAfter(end)) {
    out.add(m);
    m = DateTime(m.year, m.month, m.day + 7);
  }
  return out;
}

/// Name of a subject for [SubjectAttendance.subjectId].
String subjectName(NameResolver? names, int id) {
  if (id == 0) return 'Without subject';
  final e = names?.element(ElementType.subject, id);
  if (e == null) return 'Subject #$id';
  return e.longName.trim().isEmpty ? e.name : e.longName;
}
