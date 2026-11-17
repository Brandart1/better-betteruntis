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
  const FreeRooms({
    this.roomIds = const [],
    this.errors = const [],
    this.partlyFree = const {},
    this.slotCount = 1,
  });

  /// Free room ids (names come from the master data).
  final List<int> roomIds;

  /// Why the room can't be changed (e.g. no right), from the server.
  final List<TeacherToolError> errors;

  /// Repeated bookings: rooms free on some of the [slotCount] dates only,
  /// with on how many ([roomIds] are free on all of them).
  final Map<int, int> partlyFree;

  /// How many dates (time slots) were asked.
  final int slotCount;
}

/// The server's answer to a room change.
class RoomChangeResult {
  const RoomChangeResult({
    this.errors = const [],
    this.periodCount = 0,
    this.roomIds,
  });

  final List<TeacherToolError> errors;

  /// How many updated periods the server sent back.
  final int periodCount;

  /// The lesson's rooms as the server answered a REST room change (null
  /// when the answer had none, or for submitRoomChange2017).
  final List<int>? roomIds;

  bool get ok => errors.isEmpty;
}

/// A lesson's notes for teachers ("Notizen für Lehrkräfte", REST
/// `notesStaff`): only teachers see them, unlike the lesson info
/// ([Period.infoText], "notes for pupils").
class StaffNotes {
  const StaffNotes({this.text = '', this.editable = true});

  final String text;

  /// False when the server's `permissions` lack WRITE_NOTES_STAFF.
  final bool editable;
}

/// An exam type choice. The official app has no master-data exam types: an
/// exam's type is a plain string, so the choices are the distinct types of
/// the exams loaded (negative ids, only the name matters).
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
  /// [orgRoomId] — the room the lesson has **now** — by [roomId] in
  /// [periodIds]. [orgRoomId] 0 adds [roomId], [roomId] 0 removes
  /// [orgRoomId] (as the official app's room service sends a missing room).
  /// See [RoomEdit].
  Future<RoomChangeResult> submitRoomChange({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> periodIds,
    required int orgRoomId,
    required int roomId,
  });

  /// submitPeriodInfo2017 `{periodId, periodInfo}` → `{success}` (from the
  /// official app): the lesson info everyone sees ("Info zur Stunde", the
  /// period's `text.info`). '' removes it. Returns `success`.
  Future<bool> submitPeriodInfo({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int periodId,
    required String text,
  });

  /// `GET view/v2/calendar-entry/{periodId}/detail`: the notes for teachers
  /// of a lesson (REST only; **assumed** that the calendar-entry id is the
  /// period id). Throws [UntisException] when the server refuses.
  Future<StaffNotes> lessonStaffNotes({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int periodId,
  });

  /// `PATCH view/v1/calendar-entry/{periodId}` (or `…/block` with
  /// [wholeBlock]) `{"notesStaff": {"value": text}}`. Returns the notes the
  /// server sent back, or null when its answer has none.
  Future<StaffNotes?> submitStaffNotes({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int periodId,
    required String text,
    bool wholeBlock = false,
  });

  /// Books room [RoomBookingRequest.roomId] from start to end without a
  /// lesson (**guessed** endpoint, docs/API.md "Room bookings without a
  /// lesson (assumed)"). Errors in a 2xx answer come back in the result;
  /// a failed call throws [UntisException].
  Future<RoomBookingResult> createRoomBooking({
    required String host,
    required String school,
    required UntisCredentials auth,
    required RoomBookingRequest booking,
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

/// The REST room change of the official app, kept apart from
/// [TeacherToolsApi] so the routing wrapper can add it later; the repository
/// uses it when the api implements it and falls back to
/// [TeacherToolsApi.submitRoomChange] otherwise.
abstract interface class RoomPatchApi {
  /// `PATCH view/v1/calendar-entry/{periodId}` (or `…/block` with
  /// [wholeBlock]) `{"rooms": {"value": roomIds}}`: [roomIds] is the
  /// **complete** list of rooms the lesson shall have. Returns null when the
  /// server doesn't know the call (404/405: older servers) so the caller can
  /// fall back to submitRoomChange2017; throws [UntisException] otherwise.
  Future<RoomChangeResult?> patchLessonRooms({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int periodId,
    required List<int> roomIds,
    bool wholeBlock = false,
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

  /// Like [freeRoomsBetween], for any account (the free-room filter in
  /// Browse → Rooms). Throws [UntisException] when the server refuses.
  Future<FreeRooms> freeRoomsAt(Account account, DateTime start, DateTime end);

  /// Rooms free during every slot (getAvailableRooms2017 per slot); rooms
  /// free on some slots only are in [FreeRooms.partlyFree].
  Future<FreeRooms> freeRoomsForSlots(Account account, List<TimeSlot> slots);

  /// The teacher's own lessons (not cancelled, no supervisions, office
  /// hours or room bookings) overlapping any of [slots].
  Future<List<Period>> lessonsDuring(Account account, List<TimeSlot> slots);

  /// Books [roomId] for every slot, without a lesson. Refused (throws
  /// [UntisException]) when the teacher has a lesson during one of them.
  /// Stops at the first slot the server refuses; returns what happened per
  /// slot sent. Refreshes the own timetable weeks afterwards.
  Future<List<RoomBookingOutcome>> bookRoom(
    Account account, {
    required int roomId,
    required List<TimeSlot> slots,
    String text = '',
  });

  /// Puts room [roomId] in place of [orgRoomId] (the room the lesson has
  /// now; 0 adds [roomId], [roomId] 0 removes [orgRoomId] — see [RoomEdit])
  /// for every period of the block. On success the teacher's own timetable weeks of the block are
  /// refreshed. Errors the server lists come back in the result; a failed
  /// call throws [UntisException].
  Future<RoomChangeResult> changeRoom(
    Account account,
    List<Period> periods, {
    required int orgRoomId,
    required int roomId,
  });

  /// Sets the lesson info everyone sees ("Info zur Stunde") of every period
  /// of the block to [text] ('' removes it), then refreshes the teacher's own
  /// timetable week. Throws [UntisException] when the server refuses.
  Future<void> setLessonInfo(
    Account account,
    List<Period> periods,
    String text,
  );

  /// The notes for teachers of the block [periods] (those of its first
  /// period). Throws [UntisException] when the server refuses.
  Future<StaffNotes> staffNotes(Account account, List<Period> periods);

  /// Sets the notes for teachers of the block [periods] to [text] ('' removes
  /// them): one PATCH, for the whole block when it has several periods.
  /// Returns the notes as saved. Throws [UntisException] when refused.
  Future<StaffNotes> setStaffNotes(
    Account account,
    List<Period> periods,
    String text,
  );

  /// Exam types (empty when unknown or not loadable; never throws).
  Future<List<ExamType>> examTypes(Account account);

  /// Creates [exam] and refreshes the teacher's own timetable week of it.
  Future<void> createExam(Account account, NewExam exam);

  /// Subjects the teacher teaches and the classes per subject, from their
  /// own timetable (last 2 to next 3 weeks; cached weeks first). Kept for
  /// the session. Throws [UntisException] only when no week loads.
  Future<TeacherCourses> courses(Account account);

  /// The teacher's own lessons (not cancelled, no break supervisions /
  /// office hours, at least one class: see [Period.canHoldExam]) on [day],
  /// in time order.
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

/// The rooms [p] has now (not removed ones), in order.
List<ElementRef> currentRoomsOf(Period p) => [
  for (final e in p.elements)
    if (e.type == ElementType.room && e.id != 0) e,
];

/// The clock the teacher tools compare lesson times with (overridden in
/// tests).
final teacherToolsClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

enum RoomEditKind { replace, add, remove }

/// What the room row of the lesson sheet asks for: replace or remove
/// [room] (a room the lesson has now), or add one ([room] null).
class RoomAction {
  const RoomAction.replace(ElementRef this.room) : kind = RoomEditKind.replace;
  const RoomAction.remove(ElementRef this.room) : kind = RoomEditKind.remove;
  const RoomAction.add() : kind = RoomEditKind.add, room = null;

  final RoomEditKind kind;
  final ElementRef? room;
}

/// One room edit of a lesson, as submitRoomChange2017 params. From the
/// official app: its room service sends `orgRoomId` = the room replaced and
/// `roomId` = the new one, 0 for a missing one; its calendar API replaces
/// the id of a room the lesson has now. So [orgRoomId] is always a
/// **current** room (`ElementRef.id`), never the planned one.
class RoomEdit {
  const RoomEdit._(this.kind, this.orgRoomId, this.roomId);

  /// [current] (a room the lesson has now) becomes [room].
  const RoomEdit.replace(int current, int room)
    : this._(RoomEditKind.replace, current, room);

  /// [room] in addition to the lesson's rooms (`orgRoomId` 0, assumed).
  const RoomEdit.add(int room) : this._(RoomEditKind.add, 0, room);

  /// [current] is dropped (`roomId` 0, assumed).
  const RoomEdit.remove(int current) : this._(RoomEditKind.remove, current, 0);

  final RoomEditKind kind;
  final int orgRoomId;
  final int roomId;

  @override
  bool operator ==(Object other) =>
      other is RoomEdit &&
      other.kind == kind &&
      other.orgRoomId == orgRoomId &&
      other.roomId == roomId;

  @override
  int get hashCode => Object.hash(kind, orgRoomId, roomId);

  /// The complete room list the lesson shall have after this edit, from the
  /// room ids it has [current]ly (REST calendar PATCH): add appends, remove
  /// drops, replace swaps in place.
  List<int> apply(List<int> current) {
    final out = <int>[
      for (final id in current)
        if (!(kind == RoomEditKind.remove && id == orgRoomId)) id,
    ];
    switch (kind) {
      case RoomEditKind.add:
        if (!out.contains(roomId)) out.add(roomId);
      case RoomEditKind.replace:
        final i = out.indexOf(orgRoomId);
        if (i < 0) {
          if (!out.contains(roomId)) out.add(roomId);
        } else if (out.contains(roomId)) {
          out.removeAt(i);
        } else {
          out[i] = roomId;
        }
      case RoomEditKind.remove:
        break;
    }
    return out;
  }

  @override
  String toString() => 'RoomEdit.${kind.name}($orgRoomId → $roomId)';
}

/// A time span of a booking or a free-room search.
class TimeSlot {
  const TimeSlot(this.start, this.end);
  final DateTime start;
  final DateTime end;

  bool overlaps(DateTime s, DateTime e) => start.isBefore(e) && end.isAfter(s);

  @override
  bool operator ==(Object other) =>
      other is TimeSlot && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TimeSlot($start – $end)';
}

/// How often a room booking repeats.
enum BookingRepeat { once, daily, weekly, biweekly, everyNDays }

/// At most this many dates per booking.
const maxBookingSlots = 60;

/// The dates of a booking from [start] to [end] (same day), repeated
/// [repeat] until [until] (inclusive; ignored for [BookingRepeat.once]).
/// [BookingRepeat.daily] and [BookingRepeat.everyNDays] skip Saturdays and
/// Sundays. At most [maxBookingSlots] dates.
List<TimeSlot> bookingSlots({
  required DateTime start,
  required DateTime end,
  BookingRepeat repeat = BookingRepeat.once,
  int everyDays = 2,
  DateTime? until,
}) {
  final first = TimeSlot(start, end);
  if (repeat == BookingRepeat.once || until == null) return [first];
  final step = switch (repeat) {
    BookingRepeat.once || BookingRepeat.daily => 1,
    BookingRepeat.weekly => 7,
    BookingRepeat.biweekly => 14,
    BookingRepeat.everyNDays => everyDays < 1 ? 1 : everyDays,
  };
  final skipWeekend =
      repeat == BookingRepeat.daily || repeat == BookingRepeat.everyNDays;
  final last = DateTime(until.year, until.month, until.day);
  final out = <TimeSlot>[];
  for (var i = 0; out.length < maxBookingSlots; i += step) {
    final day = DateTime(start.year, start.month, start.day + i);
    if (day.isAfter(last)) break;
    if (skipWeekend && day.weekday > 5) continue;
    out.add(
      TimeSlot(
        DateTime(day.year, day.month, day.day, start.hour, start.minute),
        DateTime(day.year, day.month, day.day, end.hour, end.minute),
      ),
    );
  }
  return out.isEmpty ? [first] : out;
}

/// A room booking without a lesson, as sent to the server.
class RoomBookingRequest {
  const RoomBookingRequest({
    required this.roomId,
    required this.start,
    required this.end,
    this.text = '',
    this.teacherId,
  });

  final int roomId;
  final DateTime start;
  final DateTime end;

  /// What the room is booked for (optional).
  final String text;

  /// The booking teacher (their own element id).
  final int? teacherId;
}

/// The server's answer to a room booking.
class RoomBookingResult {
  const RoomBookingResult({this.errors = const [], this.id});

  final List<TeacherToolError> errors;

  /// The booking's id, when the server sends one.
  final int? id;

  bool get ok => errors.isEmpty;
}

/// What happened to one slot of [TeacherToolsRepository.bookRoom].
class RoomBookingOutcome {
  const RoomBookingOutcome(this.slot, {this.error});

  final TimeSlot slot;

  /// Null: booked.
  final String? error;

  bool get ok => error == null;
}
