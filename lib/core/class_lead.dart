/// Class teacher dashboard ("Klassenvorstand"): for each class the teacher
/// leads, the open absences (excused from here with the [ExcuseSheet] of
/// the Excuses screen), the pupils absent most often and the class
/// register entries of the range.
///
/// Data, like the official app's class-teacher dashboard tile: JSON-RPC
/// `getClassregData2017` once per class (`{klasseId, startDate, endDate}` ->
/// `{absences, classRegEvents, referencedStudents}`), excusing with
/// `submitExcuse2017`. Which classes: `userData.klassenIds` of a teacher
/// login ([Account.klassenIds]), what the official app runs the tile for.
/// Not yet seen with a real teacher account (docs/API.md "Class teacher
/// dashboard").
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'class_register.dart';
import 'excuses.dart';
import 'interfaces.dart';
import 'models.dart';

/// One getClassregData2017 answer, mapped.
class ClassLeadData {
  const ClassLeadData({
    this.absences = const [],
    this.events = const [],
    this.students = const {},
  });

  /// Every absence of the class in the range (any excuse status).
  final List<ExcuseAbsence> absences;

  /// Class register entries; [ClassRegEvent.isClassWide] for the class.
  final List<ClassRegEvent> events;

  /// `referencedStudents`: names by id.
  final Map<int, String> students;
}

/// Optional API capability: getClassregData2017.
abstract interface class ClassLeadApi {
  /// Absences and class register entries of [klasseId] from [start] to
  /// [end] (days, inclusive); [meta] maps the excuse statuses.
  Future<ClassLeadData> classLeadData({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int klasseId,
    required DateTime start,
    required DateTime end,
    required ExcuseMeta meta,
  });
}

/// A pupil and their absences in the range.
class PupilAbsenceCount {
  const PupilAbsenceCount({
    this.studentId,
    required this.name,
    required this.absences,
    required this.open,
    required this.minutes,
  });

  final int? studentId;
  final String name;

  /// Absences (records, not lessons).
  final int absences;

  /// Of these, not yet excused or refused.
  final int open;

  /// Absent time, summed.
  final int minutes;
}

/// The pupils of [absences] by how often they were absent (then by absent
/// time, then name), at most [limit].
List<PupilAbsenceCount> pupilsByAbsences(
  List<ExcuseAbsence> absences, {
  int limit = 5,
}) {
  final groups = <Object, List<ExcuseAbsence>>{};
  for (final a in absences) {
    final key = a.studentId ?? a.studentName;
    (groups[key] ??= []).add(a);
  }
  final out = [
    for (final list in groups.values)
      PupilAbsenceCount(
        studentId: list.first.studentId,
        name: list.first.studentName.isEmpty ? 'Pupil' : list.first.studentName,
        absences: list.length,
        open: list.where((a) => a.type == ExcuseStatusType.open).length,
        minutes: list.fold(
          0,
          (s, a) =>
              s +
              (a.end.isAfter(a.start)
                  ? a.end.difference(a.start).inMinutes
                  : 0),
        ),
      ),
  ];
  out.sort((a, b) {
    var c = b.absences.compareTo(a.absences);
    if (c == 0) c = b.minutes.compareTo(a.minutes);
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return out.take(limit).toList();
}

/// What the dashboard shows for one class.
class ClassLeadDashboard {
  const ClassLeadDashboard({
    required this.klasse,
    required this.range,
    required this.start,
    required this.end,
    required this.meta,
    this.absences = const [],
    this.events = const [],
    this.eventsAvailable = true,
  });

  final ExcuseClass klasse;
  final ExcuseRange range;
  final DateTime start;
  final DateTime end;

  /// For the excuse sheet.
  final ExcuseMeta meta;

  /// Newest first, any status.
  final List<ExcuseAbsence> absences;

  /// Newest first.
  final List<ClassRegEvent> events;

  /// False: getClassregData2017 failed and the absences came from the
  /// Excuses list; there are no entries then.
  final bool eventsAvailable;

  /// Not yet excused (or refused), newest first.
  List<ExcuseAbsence> get open => [
    for (final a in absences)
      if (a.type == ExcuseStatusType.open) a,
  ];

  List<PupilAbsenceCount> get topPupils => pupilsByAbsences(absences);

  /// With [saved] in place of the absence of the same id.
  ClassLeadDashboard withAbsence(ExcuseAbsence saved) => ClassLeadDashboard(
    klasse: klasse,
    range: range,
    start: start,
    end: end,
    meta: meta,
    absences: [for (final a in absences) a.id == saved.id ? saved : a],
    events: events,
    eventsAvailable: eventsAvailable,
  );
}

/// The ranges the dashboard offers.
const classLeadRanges = [
  ExcuseRange.last14,
  ExcuseRange.last30,
  ExcuseRange.schoolYear,
];

abstract interface class ClassLeadRepository {
  /// The classes [account] leads, by name; empty for none (and for
  /// accounts without a class register).
  Future<List<ExcuseClass>> classes(Account account);

  /// The dashboard of [klasse] for [range]. Throws [UntisException].
  Future<ClassLeadDashboard> dashboard(
    Account account,
    ExcuseClass klasse, {
    ExcuseRange range = ExcuseRange.last14,
  });
}

/// Whether [account] leads a class (drawer entry): a teacher login whose
/// user data lists classes.
bool leadsClass(Account account) =>
    hasClassRegister(account) && account.klassenIds.any((k) => k > 0);

final classLeadRepositoryProvider = Provider<ClassLeadRepository>(
  (ref) => throw UnimplementedError('override classLeadRepositoryProvider'),
);
