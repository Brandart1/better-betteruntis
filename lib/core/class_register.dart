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
    this.imageUrl,
  });

  final int id;
  final String firstName;
  final String lastName;
  final int? klasseId;

  /// Photo URL sent with the pupil, if any (key unknown, see
  /// `PupilPhotoApi` in pupil_photos.dart).
  final String? imageUrl;

  /// Up to two initials ("Bauer Lena" -> "LB"), '' when there are none.
  String get initials {
    String first(String s) {
      final t = s.trim();
      if (t.isEmpty || t.startsWith('#')) return '';
      return String.fromCharCode(t.runes.first).toUpperCase();
    }

    return '${first(firstName)}${first(lastName)}';
  }

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
    this.excuseStatusId,
    this.excuseStatus = '',
  });

  final int id;
  final int studentId;
  final DateTime start;
  final DateTime end;
  final int? reasonId;
  final String text;
  final bool excused;

  /// Excuse status (master data `excuseStatuses`) when the school set one.
  final int? excuseStatusId;

  /// Excuse status name as sent inline ('' when not).
  final String excuseStatus;
}

/// Class register data of one lesson (one timetable id).
class PeriodRegister {
  const PeriodRegister({
    required this.ttId,
    this.absenceChecked = false,
    this.studentIds = const [],
    this.absences = const [],
    this.topic = '',
    this.events = const [],
  });

  final int ttId;

  /// Class register entries ("Klassenbucheinträge") recorded in this lesson.
  final List<ClassRegEvent> events;

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

  /// Names of the class register entry reasons (master data `eventReasons`)
  /// by id; empty when the server has none.
  Future<Map<int, String>> eventReasons({
    required String host,
    required String school,
    required UntisCredentials auth,
  });

  /// Creates a class register entry in lesson [ttId], for [studentId] or
  /// (null) the whole class. **Assumed** call, see docs/API.md.
  Future<void> createClassRegEvent({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    int? studentId,
    int? eventReasonId,
    required String text,
  });
}

/// A class register entry ("Klassenbucheintrag"): a remark about one pupil
/// or the whole class, optionally with a reason (master data
/// `eventReasons`).
class ClassRegEvent {
  const ClassRegEvent({
    this.id,
    this.ttId,
    this.studentId,
    this.studentName = '',
    this.reasonId,
    this.reasonName = '',
    this.text = '',
    this.date,
    this.author = '',
  });

  final int? id;

  /// The lesson it was found in (null when the server did not say).
  final int? ttId;

  /// Null for an entry about the whole class.
  final int? studentId;

  /// Name as sent inline by the server ('' when not).
  final String studentName;
  final int? reasonId;

  /// Reason name as sent inline by the server ('' when not).
  final String reasonName;
  final String text;
  final DateTime? date;

  /// Who wrote it, as sent inline ('' when not).
  final String author;

  bool get isClassWide => studentId == null && studentName.isEmpty;

  /// Copy that belongs to lesson [lessonTtId]; [fallbackDate] is used when
  /// the entry has no date of its own.
  ClassRegEvent inLesson(int lessonTtId, DateTime fallbackDate) =>
      ClassRegEvent(
        id: id,
        ttId: ttId ?? lessonTtId,
        studentId: studentId,
        studentName: studentName,
        reasonId: reasonId,
        reasonName: reasonName,
        text: text,
        date: date ?? fallbackDate,
        author: author,
      );
}

/// A new class register entry, as entered in the app.
class NewClassRegEvent {
  const NewClassRegEvent({this.studentId, this.reasonId, required this.text});

  /// Null: the whole class.
  final int? studentId;
  final int? reasonId;
  final String text;
}

/// Earlier lessons of the same course as a lesson block (see
/// [ClassRegisterRepository.courseHistory]).
class CourseHistory {
  const CourseHistory({
    this.topics = const [],
    this.events = const [],
    this.students = const {},
    this.lessonsLoaded = 0,
  });

  /// The latest earlier lessons that have a topic, newest first.
  final List<ClassRegLesson> topics;

  /// Entries found in the loaded earlier lessons, newest first (each with
  /// its `ttId` and a date).
  final List<ClassRegEvent> events;

  /// Pupils the server referenced in those lessons.
  final Map<int, ClassRegStudent> students;

  /// How many earlier lessons were looked at.
  final int lessonsLoaded;
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

/// One of the teacher's own lessons with its class register state.
class ClassRegLesson {
  const ClassRegLesson(
    this.period,
    this.register, {
    this.substitutedBy,
    this.registerMissing = false,
  });
  final Period period;
  final PeriodRegister register;

  /// The teacher who held this lesson instead of the account's teacher
  /// (see `substituteOf` in absence_summary.dart); null for own lessons and
  /// lessons the teacher substituted in.
  final ElementRef? substitutedBy;

  /// The server sent no class register for it ([register] is empty).
  final bool registerMissing;

  bool get isSubstituted => substitutedBy != null;
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

  /// Earlier lessons of the same course as [periods] (same lesson id, else
  /// same subject and classes) from the teacher's own timetable, going back
  /// at most [weeks] weeks: the latest [topics] lessons with a topic and the
  /// entries found in the loaded lessons.
  Future<CourseHistory> courseHistory(
    Account account,
    List<Period> periods, {
    int topics = 5,
    int weeks = 6,
  });

  /// Entry reasons by id (empty when unknown or not loadable; never throws).
  Future<Map<int, String>> eventReasons(Account account);

  /// Creates [event] in the first period of the block [periods].
  Future<void> createEvent(
    Account account,
    List<Period> periods,
    NewClassRegEvent event,
  );

  /// The teacher's own lessons (not cancelled) from [days] days ago up to
  /// the end of today, upcoming ones of today included, each with its
  /// register, oldest first. Lessons the server has no register for are
  /// left out. Filtering (missing attendance / topic) is up to the caller.
  Future<List<ClassRegLesson>> lessons(Account account, {int days = 14});
}

final classRegisterRepositoryProvider = Provider<ClassRegisterRepository>(
  (ref) => throw UnimplementedError('override classRegisterRepositoryProvider'),
);

/// Whether [account] gets the class register features: a signed-in teacher.
bool hasClassRegister(Account account) =>
    !account.anonymous &&
    account.elementType == ElementType.teacher &&
    account.elementId > 0;
