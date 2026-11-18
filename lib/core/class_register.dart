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
    this.excuseText = '',
    this.reasonName = '',
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

  /// Text of the excuse (`excuse.text`), '' when none.
  final String excuseText;

  /// Reason name as sent inline (`absenceReason`), '' when not.
  final String reasonName;

  /// Same absence with other times, reason or note (editAbsence2017 sends
  /// the whole absence).
  ClassRegAbsence copyWith({
    DateTime? start,
    DateTime? end,
    int? Function()? reasonId,
    String? text,
  }) => ClassRegAbsence(
    id: id,
    studentId: studentId,
    start: start ?? this.start,
    end: end ?? this.end,
    reasonId: reasonId != null ? reasonId() : this.reasonId,
    text: text ?? this.text,
    excused: excused,
    excuseStatusId: excuseStatusId,
    excuseStatus: excuseStatus,
    excuseText: excuseText,
    reasonName: reasonName,
  );
}

/// What the teacher set for one pupil's absence in a lesson block: from
/// [start] to [end] (a late arrival or leaving early is a part of the
/// block), an optional reason (master data `absenceReasons`) and note.
class AbsenceDetails {
  const AbsenceDetails({
    required this.start,
    required this.end,
    this.reasonId,
    this.text = '',
  });

  final DateTime start;
  final DateTime end;
  final int? reasonId;
  final String text;

  bool get hasReasonOrText => reasonId != null || text.trim().isNotEmpty;

  /// The part of this absence inside [from]–[to], null when none.
  ({DateTime start, DateTime end})? clip(DateTime from, DateTime to) {
    final s = start.isAfter(from) ? start : from;
    final e = end.isBefore(to) ? end : to;
    return s.isBefore(e) ? (start: s, end: e) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is AbsenceDetails &&
      other.start == start &&
      other.end == end &&
      other.reasonId == reasonId &&
      other.text.trim() == text.trim();

  @override
  int get hashCode => Object.hash(start, end, reasonId, text.trim());
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
    this.homework = const [],
  });

  final int ttId;

  /// Homework (`homeWorks`) the server sent with this lesson; may be empty
  /// even when there is some (then only the timetable has it).
  final List<Homework> homework;

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

  /// Records [studentId] as absent in lesson [ttId] from [start] to [end]
  /// (createImmediateAbsence2017). Returns the new absence's id when the
  /// answer has it.
  Future<int?> createAbsence({
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

  /// Changes an absence (times, reason, note, excuse): editAbsence2017 with
  /// the whole [absence] (from the official app). Throws an
  /// [UntisException] when the server reports a conflict with another
  /// absence.
  Future<void> editAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    required ClassRegAbsence absence,
  });

  /// Absence reasons (master data `absenceReasons`) by id; empty when the
  /// server has none.
  Future<Map<int, String>> absenceReasons({
    required String host,
    required String school,
    required UntisCredentials auth,
  });

  /// Creates (`homework.id` 0) or changes homework of lesson [ttId]:
  /// submitHomeWork (from the official app). Returns the homework's id
  /// (`submittedHomeWorkId`) when the answer has it. There is no call to
  /// delete homework.
  Future<int?> submitHomework({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    required Homework homework,
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
    this.details = const {},
  });

  /// New topic, or null to leave it unchanged.
  final String? topic;

  /// Student ids to record as absent / whose absences to delete.
  final Set<int> markAbsent;
  final Set<int> markPresent;

  /// Times, reason and note per absent pupil (new or already absent) where
  /// they differ from the whole lesson without reason and note. Periods of
  /// the block outside the times get no absence (an existing one there is
  /// deleted).
  final Map<int, AbsenceDetails> details;
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
    int weeks = 4,
  });

  /// Entry reasons by id (empty when unknown or not loadable; never throws).
  Future<Map<int, String>> eventReasons(Account account);

  /// Absence reasons by id (empty when unknown or on failure).
  Future<Map<int, String>> absenceReasons(Account account);

  /// Homework of the course given in the block [periods] (assigned on its
  /// day), from the class register data and the own timetable, by due date.
  Future<List<Homework>> homework(Account account, List<Period> periods);

  /// Day of the next lesson of the same course after the block [periods]
  /// (same lesson id, else same subject and classes) within [weeks] weeks
  /// of the own timetable; null when there is none.
  Future<DateTime?> nextLessonDay(
    Account account,
    List<Period> periods, {
    int weeks = 4,
  });

  /// Creates (`id` 0) or changes [homework] given in the block [periods]
  /// (lesson id and assigned date are taken from the block) and refreshes
  /// the own timetable weeks it shows in. Returns it with its server id.
  Future<Homework> saveHomework(
    Account account,
    List<Period> periods,
    Homework homework,
  );

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
