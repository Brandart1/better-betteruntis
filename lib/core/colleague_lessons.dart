/// Lessons of "my" classes and subjects that other teachers give.
///
/// A teacher's timetable from the server only has their own lessons. Every
/// class has an assigned teacher per subject; that teacher also wants to see
/// the lessons of that class and subject that colleagues give (substitutions,
/// split courses, a colleague's regular lessons), less visibly. The
/// assignments are derived from the teacher's own planned lessons, the
/// lessons themselves come from the timetables of those classes.
///
/// Pure Dart, no Flutter.
library;

import 'models.dart';

/// A (class id, subject id) pair the teacher is assigned to.
typedef TeachingAssignment = (int klasseId, int subjectId);

/// Planned id of [e] (the current one when no original is known).
int _plannedId(ElementRef e) => e.orgId != 0 ? e.orgId : e.id;

/// (class, subject) pairs of the lessons in [own] whose PLANNED teacher is
/// [teacherId]: lessons the teacher substitutes in for someone else don't
/// count, lessons a substitute holds for them (and cancelled ones) do.
/// Supervisions and office hours are left out.
Set<TeachingAssignment> teachingAssignments(
  Iterable<Period> own,
  int teacherId,
) {
  final out = <TeachingAssignment>{};
  for (final p in own) {
    if (p.isBreakSupervision || p.isOfficeHour) continue;
    if (!p.ofType(ElementType.teacher).any((t) => t.orgId == teacherId)) {
      continue;
    }
    final classes = {
      for (final k in p.ofType(ElementType.klasse))
        if (_plannedId(k) > 0) _plannedId(k),
    };
    final subjects = {
      for (final s in p.ofType(ElementType.subject))
        if (_plannedId(s) > 0) _plannedId(s),
    };
    for (final k in classes) {
      for (final s in subjects) {
        out.add((k, s));
      }
    }
  }
  return out;
}

/// Whether [teacherId] holds [p] (is one of its current teachers). Periods
/// without any teacher element count as their own (some servers leave
/// teachers out; such a period can't be told apart).
bool teachesLesson(Period p, int teacherId) {
  final teachers = p.ofType(ElementType.teacher).toList();
  return teachers.isEmpty || teachers.any((t) => t.id == teacherId);
}

/// A lesson of someone else in [teacherId]'s own timetable that is not even
/// planned for them: a colleague's lesson of an assigned class and subject
/// (see [colleagueLessons]). False for lessons a substitute holds for them.
bool isColleagueLesson(Period p, int teacherId) =>
    !teachesLesson(p, teacherId) &&
    !p.ofType(ElementType.teacher).any((t) => t.orgId == teacherId);

/// The periods of a class week [classWeek] that belong to one of
/// [assignments] and that another teacher gives: not cancelled, no
/// supervision / office hour, at least one current teacher who isn't
/// [teacherId], and none that is. Periods whose id is in [seen] are
/// skipped; the ids of the returned periods are added to it (a lesson
/// shared by several classes comes once).
List<Period> colleagueLessons(
  Iterable<Period> classWeek,
  Set<TeachingAssignment> assignments,
  int teacherId,
  Set<int> seen,
) {
  if (assignments.isEmpty) return const [];
  final out = <Period>[];
  for (final p in classWeek) {
    if (seen.contains(p.id)) continue;
    if (p.isCancelled || p.isBreakSupervision || p.isOfficeHour) continue;
    final teachers = p.ofType(ElementType.teacher).toList();
    if (teachers.any((t) => t.id == teacherId)) continue;
    if (!teachers.any((t) => t.id != 0)) continue;
    final classes = {
      for (final k in p.ofType(ElementType.klasse)) ...[k.id, k.orgId],
    }..remove(0);
    final subjects = {
      for (final s in p.ofType(ElementType.subject)) ...[s.id, s.orgId],
    }..remove(0);
    final match = classes.any(
      (k) => subjects.any((s) => assignments.contains((k, s))),
    );
    if (!match) continue;
    seen.add(p.id);
    out.add(p);
  }
  return out;
}
