/// Teacher absence summaries ("Fehlzeiten"): how often pupils of a lesson
/// were absent, per pupil or for the whole class, in three scopes: this
/// lesson, the subject (all lessons of this course) and all subjects.
///
/// The aggregation here is pure (tested in test/classreg); the data layer
/// ([AbsenceSummaryRepository], lib/data/absence_summary_repository_impl.dart)
/// collects the absences. What is assumed about the server calls:
/// docs/API.md "Absence summaries (teachers)".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'class_register.dart';
import 'interfaces.dart';
import 'models.dart';

/// What a summary counts.
enum AbsenceSummaryScope {
  /// The lesson block that was opened (one lesson or a double lesson).
  lesson('Lesson'),

  /// Every lesson of this course (same lesson id, else same subject and
  /// classes) in the teacher's own timetable.
  subject('Subject'),

  /// All absences of the class(es), every subject.
  all('All subjects');

  const AbsenceSummaryScope(this.label);
  final String label;
}

/// Excuse state of an absence.
enum ExcuseState {
  excused('Excused'),

  /// The school set a status that is not "excused".
  unexcused('Unexcused'),

  /// No excuse decided yet.
  open('Open');

  const ExcuseState(this.label);
  final String label;
}

/// One absence of a pupil, as counted in a summary.
class SummaryAbsence {
  const SummaryAbsence({
    this.id,
    this.studentId,
    this.studentName = '',
    required this.start,
    required this.end,
    this.lessons = 1,
    this.state = ExcuseState.open,
    this.late = false,
    this.reason = '',
    this.text = '',
    this.label = '',
  });

  final int? id;
  final int? studentId;

  /// Name as sent inline by the server ('' when not).
  final String studentName;
  final DateTime start;
  final DateTime end;

  /// Lessons this absence covers (periods, or time-grid units for the
  /// all-subjects scope); 0 for a late arrival.
  final int lessons;
  final ExcuseState state;

  /// Came late: absent from the lesson's start, but not until its end.
  final bool late;
  final String reason;
  final String text;

  /// Where it happened, e.g. the subject ('' when unknown).
  final String label;
}

/// The absences of one pupil.
class PupilAbsenceSummary {
  const PupilAbsenceSummary({
    this.studentId,
    required this.name,
    required this.sortKey,
    this.absences = const [],
  });

  final int? studentId;
  final String name;
  final String sortKey;

  /// Newest first.
  final List<SummaryAbsence> absences;

  int _lessons(bool Function(SummaryAbsence a) where) => absences
      .where((a) => !a.late && where(a))
      .fold(0, (s, a) => s + a.lessons);

  /// Absent lessons (late arrivals not counted).
  int get lessons => _lessons((_) => true);
  int get excusedLessons => _lessons((a) => a.state == ExcuseState.excused);
  int get unexcusedLessons => _lessons((a) => a.state == ExcuseState.unexcused);
  int get openLessons => _lessons((a) => a.state == ExcuseState.open);
  int get lateCount => absences.where((a) => a.late).length;
  bool get hasAbsences => absences.isNotEmpty;
}

/// Result of [AbsenceSummaryRepository.summary].
class AbsenceSummary {
  const AbsenceSummary({
    required this.scope,
    required this.from,
    required this.to,
    this.pupils = const [],
    this.lessonsLooked = 0,
    this.lessonsSkipped = 0,
    this.truncated = false,
    this.approximate = false,
  });

  final AbsenceSummaryScope scope;

  /// The days counted (inclusive).
  final DateTime from;
  final DateTime to;

  /// Sorted by name; pupils without absences are included when known.
  final List<PupilAbsenceSummary> pupils;

  /// Lessons whose class register was read (lesson / subject scope).
  final int lessonsLooked;

  /// Lessons the server gave no class register for (e.g. lessons a
  /// substitute held, when the server does not share them).
  final int lessonsSkipped;

  /// Not every week of the range was looked at (see [maxSummaryWeeks]).
  final bool truncated;

  /// Lesson counts come from the time grid (all-subjects scope), not from
  /// lessons in the timetable.
  final bool approximate;

  int _sum(int Function(PupilAbsenceSummary p) f) =>
      pupils.fold(0, (s, p) => s + f(p));

  int get lessons => _sum((p) => p.lessons);
  int get excusedLessons => _sum((p) => p.excusedLessons);
  int get unexcusedLessons => _sum((p) => p.unexcusedLessons);
  int get openLessons => _sum((p) => p.openLessons);
  int get lateCount => _sum((p) => p.lateCount);
  int get pupilsWithAbsences => pupils.where((p) => p.hasAbsences).length;
}

/// The subject scope reads at most this many weeks of the own timetable.
const maxSummaryWeeks = 45;

abstract interface class AbsenceSummaryRepository {
  /// Absences of the pupils of the lesson block [periods] in [scope], from
  /// [from] to [to] (days, inclusive; default: the current school year up
  /// to today). [onProgress] reports steps done / total for the slow
  /// subject scope. Throws [UntisException].
  Future<AbsenceSummary> summary(
    Account account,
    List<Period> periods, {
    required AbsenceSummaryScope scope,
    DateTime? from,
    DateTime? to,
    void Function(int done, int total)? onProgress,
  });

  /// The school year that contains [day] (today when null), from master
  /// data; null when the school sends none.
  Future<SchoolYear?> schoolYear(Account account, {DateTime? day});
}

final absenceSummaryRepositoryProvider = Provider<AbsenceSummaryRepository>(
  (ref) =>
      throw UnimplementedError('override absenceSummaryRepositoryProvider'),
);

/// An absence of a whole class, as the class absence list (all subjects)
/// returns it.
class ClassAbsenceRecord {
  const ClassAbsenceRecord({
    required this.id,
    this.studentId,
    this.studentName = '',
    this.klasseId,
    required this.start,
    required this.end,
    this.state = ExcuseState.open,
    this.reason = '',
    this.text = '',
    this.late = false,
  });

  final int id;
  final int? studentId;
  final String studentName;
  final int? klasseId;
  final DateTime start;
  final DateTime end;
  final ExcuseState state;
  final String reason;
  final String text;

  /// The server marked it as a late arrival.
  final bool late;
}

/// Optional API capability: all absences of a class (every subject).
/// **Assumed** calls, see docs/API.md.
abstract interface class ClassAbsencesApi {
  Future<List<ClassAbsenceRecord>> classAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int klasseId,
    required DateTime start,
    required DateTime end,
  });
}

// ---- Aggregation (pure) ---------------------------------------------------

/// Whether [p] has a class register: not cancelled, no break supervision
/// or office hour.
bool isRegisterLesson(Period p) =>
    !p.isCancelled &&
    !p.flags.contains(PeriodFlag.breakSupervision) &&
    !p.flags.contains(PeriodFlag.officeHour);

Set<int> _idsOf(Period p, ElementType t) => {
  for (final e in p.elements)
    if (e.type == t && e.id != 0) e.id,
};

/// Same subject(s) and class(es); false when [ref] has no subject.
bool sameSubjectAndClasses(Period ref, Period p) {
  final subjects = _idsOf(ref, ElementType.subject);
  if (subjects.isEmpty) return false;
  final classes = _idsOf(ref, ElementType.klasse);
  final ps = _idsOf(p, ElementType.subject);
  final pc = _idsOf(p, ElementType.klasse);
  return ps.length == subjects.length &&
      ps.containsAll(subjects) &&
      pc.length == classes.length &&
      pc.containsAll(classes);
}

/// The lessons of [candidates] that belong to the course of [ref]: same
/// lesson id when any candidate has it, else same subject(s) and class(es).
List<Period> courseLessons(Period ref, Iterable<Period> candidates) {
  final lessons = [
    for (final p in candidates)
      if (isRegisterLesson(p)) p,
  ];
  if (ref.lessonId > 0) {
    final same = [
      for (final p in lessons)
        if (p.lessonId == ref.lessonId) p,
    ];
    if (same.isNotEmpty) return same;
  }
  return [
    for (final p in lessons)
      if (sameSubjectAndClasses(ref, p)) p,
  ];
}

/// Excuse state of a class register absence.
ExcuseState excuseStateOf(ClassRegAbsence a) => a.excused
    ? ExcuseState.excused
    : (a.excuseStatusId != null || a.excuseStatus.isNotEmpty)
    ? ExcuseState.unexcused
    : ExcuseState.open;

/// [a] as recorded in lesson [p]: a late arrival when it starts with the
/// lesson but ends before the lesson ends.
SummaryAbsence summaryAbsenceOf(
  Period p,
  ClassRegAbsence a, {
  String label = '',
  String reason = '',
}) {
  const slack = Duration(minutes: 1);
  final late =
      !a.start.isAfter(p.start.add(slack)) &&
      a.end.isBefore(p.end.subtract(slack)) &&
      a.end.isAfter(p.start);
  return SummaryAbsence(
    id: a.id,
    studentId: a.studentId,
    start: a.start.isBefore(p.start) ? p.start : a.start,
    end: a.end.isAfter(p.end) ? p.end : a.end,
    lessons: late ? 0 : 1,
    state: excuseStateOf(a),
    late: late,
    reason: reason,
    text: a.text,
    label: label,
  );
}

/// Units of [grid] that [start]..[end] overlaps, day by day. When the grid
/// is the fallback or has no units for a day, the minutes are divided by 45
/// (at least 1).
int unitsCovered(DateTime start, DateTime end, TimeGrid grid) {
  if (!end.isAfter(start)) return 0;
  var count = 0;
  for (
    var day = DateTime(start.year, start.month, start.day);
    day.isBefore(end);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    final dayStart = day.isBefore(start) ? start : day;
    final next = DateTime(day.year, day.month, day.day + 1);
    final dayEnd = end.isBefore(next) ? end : next;
    final from = dayStart.difference(day).inMinutes;
    final to = dayEnd.difference(day).inMinutes;
    if (to <= from) continue;
    final units = grid.isFallback ? null : grid.days[day.weekday];
    if (units == null || units.isEmpty) {
      // Only weekdays count when guessing.
      if (day.weekday <= 5) {
        final n = ((to - from) / 45).round();
        count += n < 1 ? 1 : n;
      }
      continue;
    }
    count += units.where((u) => u.start < to && u.end > from).length;
  }
  return count;
}

/// Groups [absences] per pupil. Every pupil of [roster] is included (also
/// without absences); absences of other pupils are grouped by id, else by
/// name. Sorted by name, each pupil's absences newest first.
List<PupilAbsenceSummary> groupByPupil(
  Iterable<SummaryAbsence> absences,
  Map<int, ClassRegStudent> roster,
) {
  final byKey = <String, List<SummaryAbsence>>{
    for (final id in roster.keys) 'id:$id': [],
  };
  final names = <String, String>{};
  final ids = <String, int?>{for (final id in roster.keys) 'id:$id': id};
  for (final a in absences) {
    final String key;
    if (a.studentId != null) {
      key = 'id:${a.studentId}';
      ids[key] = a.studentId;
    } else {
      final n = a.studentName.trim();
      if (n.isEmpty) continue;
      key = 'name:${n.toLowerCase()}';
      ids[key] = null;
    }
    (byKey[key] ??= []).add(a);
    if (a.studentName.trim().isNotEmpty) {
      names.putIfAbsent(key, () => a.studentName.trim());
    }
  }
  final out = <PupilAbsenceSummary>[];
  for (final e in byKey.entries) {
    final id = ids[e.key];
    final s = id == null ? null : roster[id];
    final name = s?.displayName ?? names[e.key] ?? '#$id';
    out.add(
      PupilAbsenceSummary(
        studentId: id,
        name: name,
        sortKey: s?.sortKey ?? name.toLowerCase(),
        absences: e.value..sort((a, b) => b.start.compareTo(a.start)),
      ),
    );
  }
  return out..sort((a, b) => a.sortKey.compareTo(b.sortKey));
}

/// Keeps the records of [roster]'s pupils (by id, else by name) when the
/// roster is known; all records otherwise.
List<ClassAbsenceRecord> recordsOfRoster(
  List<ClassAbsenceRecord> records,
  Map<int, ClassRegStudent> roster,
) {
  if (roster.isEmpty) return records;
  String norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-zäöüß0-9]+'), ' ').trim();
  final names = <String>{
    for (final s in roster.values) ...[
      norm('${s.lastName} ${s.firstName}'),
      norm('${s.firstName} ${s.lastName}'),
    ],
  };
  return [
    for (final r in records)
      if (r.studentId != null
          ? roster.containsKey(r.studentId)
          : names.contains(norm(r.studentName)))
        r,
  ];
}

/// Substitutions: the teacher element that replaced teacher [teacherId] in
/// [p], when [p] is a lesson of that teacher held by someone else (their
/// entry struck through: `orgId` = [teacherId], `id` = the substitute).
/// When the teacher was only removed, an added teacher is returned if
/// there is one, else the removed element (`id` 0: substitute unknown).
/// Null when [teacherId] teaches [p] (also when they substitute in it).
ElementRef? substituteOf(Period p, int teacherId) {
  final teachers = p.ofType(ElementType.teacher).toList();
  if (teachers.any((e) => e.id == teacherId)) return null;
  for (final e in teachers) {
    if (e.orgId == teacherId && e.id > 0) return e;
  }
  for (final e in teachers) {
    if (e.orgId == teacherId && e.id == 0) {
      return teachers.where((t) => t.orgId == 0 && t.id > 0).firstOrNull ?? e;
    }
  }
  return null;
}

/// Whether every period of the block [periods] was held by a substitute
/// instead of teacher [teacherId].
bool heldBySubstitute(List<Period> periods, int teacherId) =>
    periods.isNotEmpty &&
    periods.every((p) => substituteOf(p, teacherId) != null);
