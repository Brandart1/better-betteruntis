/// Teacher class register ("Klassenbuch"): absences and lesson topic
/// ("Lehrstoff") per lesson, plus the list of past lessons that still miss
/// them.
///
/// Implemented by lib/api ([ClassRegisterApi]) and lib/data
/// ([ClassRegisterRepository]); rendered by lib/ui/classreg. What is
/// confirmed and what is assumed about the server calls: docs/API.md
/// "Class register (teachers)".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'interfaces.dart';
import 'models.dart';

/// A pupil of a lesson (`referencedStudents` of getPeriodData2017).
class ClassRegStudent {
  const ClassRegStudent({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.klasseId,
  });

  final int id;
  final String firstName;
  final String lastName;
  final int? klasseId;

  /// "Last First", which is how class lists are usually sorted.
  String get sortKey => '${lastName.toLowerCase()} ${firstName.toLowerCase()}';
  String get displayName =>
      [lastName, firstName].where((s) => s.isNotEmpty).join(' ');
}

/// An absence recorded in one lesson.
class ClassRegAbsence {
  const ClassRegAbsence({
    required this.id,
    required this.studentId,
    required this.start,
    required this.end,
    this.reasonId,
    this.text = '',
    this.excused = false,
  });

  final int id;
  final int studentId;
  final DateTime start;
  final DateTime end;
  final int? reasonId;
  final String text;
  final bool excused;
}

/// Class register data of one lesson (one timetable id).
class PeriodRegister {
  const PeriodRegister({
    required this.ttId,
    this.absenceChecked = false,
    this.studentIds = const [],
    this.absences = const [],
    this.topic = '',
  });

  final int ttId;

  /// Whether the teacher already confirmed the attendance check.
  final bool absenceChecked;
  final List<int> studentIds;
  final List<ClassRegAbsence> absences;

  /// The lesson topic ("Lehrstoff"), '' when none is entered.
  final String topic;

  bool get hasTopic => topic.trim().isNotEmpty;

  /// Something still has to be entered for this lesson.
  bool get isIncomplete => !absenceChecked || !hasTopic;
}

/// Result of [ClassRegisterApi.periodData].
class PeriodRegisterData {
  const PeriodRegisterData({this.periods = const {}, this.students = const {}});

  /// By timetable id. Lessons the server left out are missing.
  final Map<int, PeriodRegister> periods;
  final Map<int, ClassRegStudent> students;
}

/// Optional API capability for teacher accounts.
abstract interface class ClassRegisterApi {
  /// getPeriodData2017 for [ttIds] (timetable period ids).
  Future<PeriodRegisterData> periodData({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> ttIds,
  });

  Future<void> submitLessonTopic({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    required String topic,
  });

  /// Records [studentId] as absent in lesson [ttId] from [start] to [end].
  Future<void> createAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    required int studentId,
    required DateTime start,
    required DateTime end,
  });

  Future<void> deleteAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int absenceId,
  });

  /// Confirms the attendance check of [ttIds].
  Future<void> submitAbsencesChecked({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> ttIds,
  });
}

/// What the class register screen saves for one lesson block.
class ClassRegChanges {
  const ClassRegChanges({
    this.topic,
    this.markAbsent = const {},
    this.markPresent = const {},
  });

  /// New topic, or null to leave it unchanged.
  final String? topic;

  /// Student ids to record as absent / whose absences to delete.
  final Set<int> markAbsent;
  final Set<int> markPresent;
}

/// A past lesson of the teacher with what is still missing.
class OpenLesson {
  const OpenLesson(this.period, this.register);
  final Period period;
  final PeriodRegister register;
}

abstract interface class ClassRegisterRepository {
  /// Data for [periods] (one lesson block, e.g. a double lesson).
  Future<PeriodRegisterData> load(Account account, List<Period> periods);

  /// Saves [changes] for every period of the block and confirms the
  /// attendance check of all of them.
  Future<void> save(
    Account account,
    List<Period> periods,
    PeriodRegisterData current,
    ClassRegChanges changes,
  );

  /// The teacher's own past lessons of the last [days] days (not cancelled)
  /// whose attendance check or topic is missing, newest first.
  Future<List<OpenLesson>> openLessons(Account account, {int days = 14});
}

final classRegisterRepositoryProvider = Provider<ClassRegisterRepository>(
  (ref) => throw UnimplementedError('override classRegisterRepositoryProvider'),
);

/// Whether [account] gets the class register features: a signed-in teacher.
bool hasClassRegister(Account account) =>
    !account.anonymous &&
    account.elementType == ElementType.teacher &&
    account.elementId > 0;
