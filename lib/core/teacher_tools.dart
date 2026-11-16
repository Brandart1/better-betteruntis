/// Teacher tools beyond the class register: booking / changing the room of
/// an own lesson ("Räume buchen") and creating exams on the server.
///
/// Implemented by lib/api ([TeacherToolsApi]) and lib/data
/// ([TeacherToolsRepository]); rendered by lib/ui/classreg
/// (room_booking_screen.dart, exam_editor_screen.dart). What is confirmed and
/// what is assumed about the server calls: docs/API.md "Room booking and
/// exams (teachers)".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'interfaces.dart';
import 'models.dart';

/// An error item of the Untis Mobile API (`UMError {code, title, details}`),
/// as sent in the `errors` list of getRoomChangeData2017 /
/// submitRoomChange2017.
class TeacherToolError {
  const TeacherToolError({this.code = '', this.title = '', this.details = ''});

  final String code;
  final String title;
  final String details;

  /// What the UI shows: title and details, else the code.
  String get message {
    final parts = [title, details].where((s) => s.trim().isNotEmpty).toList();
    if (parts.isEmpty) return code.isEmpty ? 'Unknown error' : code;
    return [
      parts.join(': '),
      if (code.isNotEmpty && !parts.join().contains(code)) '($code)',
    ].join(' ');
  }
}

/// Rooms the server offers for a lesson or a time range.
class FreeRooms {
  const FreeRooms({this.roomIds = const [], this.errors = const []});

  /// Free room ids (names come from the master data).
  final List<int> roomIds;

  /// Why the room can't be changed (e.g. no right), from the server.
  final List<TeacherToolError> errors;
}

/// The server's answer to a room change.
class RoomChangeResult {
  const RoomChangeResult({this.errors = const [], this.periodCount = 0});

  final List<TeacherToolError> errors;

  /// How many updated periods the server sent back.
  final int periodCount;

  bool get ok => errors.isEmpty;
}

/// An exam type of the school (master data `examTypes`, if the server has
/// them).
class ExamType {
  const ExamType({required this.id, required this.name, this.longName = ''});

  final int id;
  final String name;
  final String longName;

  String get displayName => longName.trim().isNotEmpty ? longName : name;
}

/// An exam as entered in the exam editor.
class NewExam {
  const NewExam({
    this.examTypeId,
    this.examType = '',
    this.name = '',
    this.text = '',
    required this.start,
    required this.end,
    this.roomIds = const [],
    this.klasseIds = const [],
    this.studentIds = const [],
    this.teacherIds = const [],
    this.subjectId,
    this.lessonId,
    this.periodIds = const [],
  });

  /// Id of the chosen [ExamType]; null when typed as free text.
  final int? examTypeId;

  /// The type's name (chosen or typed).
  final String examType;
  final String name;
  final String text;
  final DateTime start;
  final DateTime end;
  final List<int> roomIds;
  final List<int> klasseIds;

  /// Empty: all pupils of [klasseIds].
  final List<int> studentIds;
  final List<int> teacherIds;
  final int? subjectId;
  final int? lessonId;

  /// Timetable ids of the teacher's own periods the exam covers (the lesson
  /// it was created from).
  final List<int> periodIds;
}

/// Optional API capability for teacher accounts. **Assumed** calls, see
/// docs/API.md.
abstract interface class TeacherToolsApi {
  /// getRoomChangeData2017 `{periodIds}`: rooms free for those periods.
  Future<FreeRooms> roomChangeData({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> periodIds,
  });

  /// getAvailableRooms2017 `{startDateTime, endDateTime}`.
  Future<FreeRooms> availableRooms({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
  });

  /// submitRoomChange2017 `{periodIds, orgRoomId, roomId}`: replaces room
  /// [orgRoomId] (0: the lesson has no room) by [roomId] in [periodIds].
  Future<RoomChangeResult> submitRoomChange({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> periodIds,
    required int orgRoomId,
    required int roomId,
  });

  /// Master data `examTypes` (empty when the server has none).
  Future<List<ExamType>> examTypes({
    required String host,
    required String school,
    required UntisCredentials auth,
  });

  /// Creates [exam]; returns its id when the server sends one.
  Future<int?> createExam({
    required String host,
    required String school,
    required UntisCredentials auth,
    required NewExam exam,
  });
}

abstract interface class TeacherToolsRepository {
  /// Rooms free during the whole block [periods] (getRoomChangeData2017,
  /// falling back to getAvailableRooms2017 for the block's time when the
  /// server doesn't know the first call).
  Future<FreeRooms> freeRoomsForLesson(Account account, List<Period> periods);

  /// Rooms free from [start] to [end] (getAvailableRooms2017).
  Future<FreeRooms> freeRoomsBetween(
    Account account,
    DateTime start,
    DateTime end,
  );

  /// Puts room [roomId] in place of [orgRoomId] for every period of the
  /// block. On success the teacher's own timetable weeks of the block are
  /// refreshed. Errors the server lists come back in the result; a failed
  /// call throws [UntisException].
  Future<RoomChangeResult> changeRoom(
    Account account,
    List<Period> periods, {
    required int orgRoomId,
    required int roomId,
  });

  /// Exam types (empty when unknown or not loadable; never throws).
  Future<List<ExamType>> examTypes(Account account);

  /// Creates [exam] and refreshes the teacher's own timetable week of it.
  Future<void> createExam(Account account, NewExam exam);

  /// Subjects the teacher teaches and the classes per subject, from their
  /// own timetable (last 2 to next 3 weeks; cached weeks first). Kept for
  /// the session. Throws [UntisException] only when no week loads.
  Future<TeacherCourses> courses(Account account);

  /// The teacher's own lessons (not cancelled, no break supervisions /
  /// office hours) on [day], in time order.
  Future<List<Period>> lessonsOn(Account account, DateTime day);
}

/// What a teacher teaches: classes by subject id (see
/// [TeacherToolsRepository.courses]).
class TeacherCourses {
  const TeacherCourses(this.classesBySubject);

  final Map<int, Set<int>> classesBySubject;

  bool get isEmpty => classesBySubject.isEmpty;

  /// Subject ids, in insertion order.
  List<int> get subjectIds => classesBySubject.keys.toList();

  Set<int> classesOf(int subjectId) => classesBySubject[subjectId] ?? const {};

  /// From [periods] (lessons with a subject; class-less lessons count with
  /// no class).
  factory TeacherCourses.of(Iterable<Period> periods) {
    final map = <int, Set<int>>{};
    for (final p in periods) {
      for (final s in p.ofType(ElementType.subject)) {
        if (s.id == 0) continue;
        final classes = map.putIfAbsent(s.id, () => <int>{});
        for (final k in p.ofType(ElementType.klasse)) {
          if (k.id != 0) classes.add(k.id);
        }
      }
    }
    return TeacherCourses(map);
  }
}

final teacherToolsRepositoryProvider = Provider<TeacherToolsRepository>(
  (ref) => throw UnimplementedError('override teacherToolsRepositoryProvider'),
);

/// The room element that a room change of [p] replaces: the first room,
/// else null (the lesson has no room).
ElementRef? bookableRoomOf(Period p) {
  for (final e in p.elements) {
    if (e.type == ElementType.room && (e.id != 0 || e.orgId != 0)) return e;
  }
  return null;
}
