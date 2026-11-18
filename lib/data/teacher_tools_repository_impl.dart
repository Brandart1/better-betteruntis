import 'dart:async';

import '../core/class_register.dart';
import '../core/info.dart';
import '../core/interfaces.dart';
import '../core/models.dart';
import '../core/teacher_tools.dart';

/// [TeacherToolsRepository] on top of [TeacherToolsApi]. Free rooms are
/// always loaded fresh; after a room change or a new exam the teacher's own
/// timetable weeks involved are refreshed so the change shows.
class TeacherToolsRepositoryImpl implements TeacherToolsRepository {
  TeacherToolsRepositoryImpl({
    required this.api,
    required this.accounts,
    required this.timetables,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final DateTime Function() clock;

  final UntisApi api;
  final AccountRepository accounts;
  final TimetableRepository timetables;

  TeacherToolsApi get _api {
    final Object a = api;
    if (a is TeacherToolsApi) return a;
    throw const UntisException(-1, 'Not supported here.');
  }

  void _check(Account a) {
    if (!hasClassRegister(a)) {
      throw const UntisException(
        UntisException.noRight,
        'Only teacher accounts can book rooms or create exams.',
      );
    }
  }

  static bool _methodMissing(UntisException e) =>
      e.code == -32601 || e.message.toLowerCase().contains('method not found');

  @override
  Future<FreeRooms> freeRoomsForLesson(Account account, List<Period> periods) {
    _check(account);
    return _wrap(() async {
      if (periods.isEmpty) return const FreeRooms();
      final auth = await accounts.credentials(account.id);
      try {
        return await _api.roomChangeData(
          host: account.host,
          school: account.school.loginName,
          auth: auth,
          periodIds: [for (final p in periods) p.id],
        );
      } on UntisException catch (e) {
        if (!_methodMissing(e)) rethrow;
      }
      final (start, end) = _span(periods);
      return _api.availableRooms(
        host: account.host,
        school: account.school.loginName,
        auth: auth,
        start: start,
        end: end,
      );
    });
  }

  @override
  Future<FreeRooms> freeRoomsBetween(
    Account account,
    DateTime start,
    DateTime end,
  ) {
    _check(account);
    return _wrap(() async {
      final auth = await accounts.credentials(account.id);
      return _api.availableRooms(
        host: account.host,
        school: account.school.loginName,
        auth: auth,
        start: start,
        end: end,
      );
    });
  }

  @override
  Future<FreeRooms> freeRoomsAt(
    Account account,
    DateTime start,
    DateTime end,
  ) => _wrap(() async {
    if (!end.isAfter(start)) {
      throw const UntisException(-1, 'The end must be after the start.');
    }
    final auth = await accounts.credentials(account.id);
    return _api.availableRooms(
      host: account.host,
      school: account.school.loginName,
      auth: auth,
      start: start,
      end: end,
    );
  });

  @override
  Future<FreeRooms> freeRoomsForSlots(Account account, List<TimeSlot> slots) {
    _check(account);
    return _wrap(() async {
      if (slots.isEmpty) return const FreeRooms(slotCount: 0);
      final auth = await accounts.credentials(account.id);
      final count = <int, int>{};
      final order = <int>[];
      final errors = <TeacherToolError>[];
      for (final s in slots) {
        final r = await _api.availableRooms(
          host: account.host,
          school: account.school.loginName,
          auth: auth,
          start: s.start,
          end: s.end,
        );
        for (final e in r.errors) {
          if (!errors.any((x) => x.message == e.message)) errors.add(e);
        }
        for (final id in r.roomIds) {
          if (!count.containsKey(id)) order.add(id);
          count[id] = (count[id] ?? 0) + 1;
        }
      }
      return FreeRooms(
        roomIds: [
          for (final id in order)
            if (count[id] == slots.length) id,
        ],
        partlyFree: {
          for (final id in order)
            if (count[id]! < slots.length) id: count[id]!,
        },
        errors: errors,
        slotCount: slots.length,
      );
    });
  }

  @override
  Future<List<Period>> lessonsDuring(Account account, List<TimeSlot> slots) {
    _check(account);
    return _wrap(() async {
      final mondays = {for (final s in slots) _mondayOf(s.start)};
      final out = <Period>[];
      for (final m in mondays) {
        for (final p in await _ownWeek(account, m)) {
          // Own room bookings aren't lessons (a second room may be wanted).
          if (!_isLesson(p) || p.isRoomBooking) continue;
          if (slots.any((s) => s.overlaps(p.start, p.end)) &&
              !out.any((q) => q.id == p.id)) {
            out.add(p);
          }
        }
      }
      return out..sort((a, b) => a.start.compareTo(b.start));
    });
  }

  @override
  Future<List<RoomBookingOutcome>> bookRoom(
    Account account, {
    required int roomId,
    required List<TimeSlot> slots,
    String text = '',
  }) {
    _check(account);
    return _wrap(() async {
      if (slots.isEmpty) throw const UntisException(-1, 'No time selected.');
      if (roomId <= 0) throw const UntisException(-1, 'No room selected.');
      for (final s in slots) {
        if (!s.end.isAfter(s.start)) {
          throw const UntisException(-1, 'The end must be after the start.');
        }
      }
      final busy = await lessonsDuring(account, slots);
      if (busy.isNotEmpty) {
        throw UntisException(
          -1,
          'You have a lesson at that time (${busy.length == 1 ? '1 lesson' : '${busy.length} lessons'}). '
          'Change the room of that lesson instead.',
        );
      }
      final auth = await accounts.credentials(account.id);
      final out = <RoomBookingOutcome>[];
      for (final s in slots) {
        try {
          final r = await _api.createRoomBooking(
            host: account.host,
            school: account.school.loginName,
            auth: auth,
            booking: RoomBookingRequest(
              roomId: roomId,
              start: s.start,
              end: s.end,
              text: text.trim(),
              teacherId: account.elementType == ElementType.teacher
                  ? account.elementId
                  : null,
            ),
          );
          if (!r.ok) {
            out.add(
              RoomBookingOutcome(
                s,
                error: r.errors.map((e) => e.message).join('\n'),
              ),
            );
            break;
          }
          out.add(RoomBookingOutcome(s));
        } on UntisException catch (e) {
          // The first refusal stops the rest (the same error each time).
          if (out.isEmpty) rethrow;
          out.add(RoomBookingOutcome(s, error: e.message));
          break;
        }
      }
      if (out.any((o) => o.ok)) {
        await _refresh(account, [
          for (final o in out)
            if (o.ok) o.slot.start,
        ]);
      }
      return out;
    });
  }

  @override
  Future<RoomChangeResult> changeRoom(
    Account account,
    List<Period> periods, {
    required int orgRoomId,
    required int roomId,
  }) {
    _check(account);
    return _wrap(() async {
      if (periods.isEmpty) {
        throw const UntisException(-1, 'No lesson selected.');
      }
      final auth = await accounts.credentials(account.id);
      RoomChangeResult? result;
      final Object a = api;
      if (a is RoomPatchApi) {
        // The official app's way: PATCH the complete room list (one call,
        // for the whole block when it has several periods).
        final edit = roomId == 0
            ? RoomEdit.remove(orgRoomId)
            : orgRoomId == 0
            ? RoomEdit.add(roomId)
            : RoomEdit.replace(orgRoomId, roomId);
        result = await a.patchLessonRooms(
          host: account.host,
          school: account.school.loginName,
          auth: auth,
          periodId: periods.first.id,
          roomIds: edit.apply([
            for (final r in currentRoomsOf(periods.first)) r.id,
          ]),
          wholeBlock: periods.length > 1,
        );
      }
      // Older servers without the REST calendar API: JSON-RPC.
      result ??= await _api.submitRoomChange(
        host: account.host,
        school: account.school.loginName,
        auth: auth,
        periodIds: [for (final p in periods) p.id],
        orgRoomId: orgRoomId,
        roomId: roomId,
      );
      if (result.ok) {
        await _refresh(account, [for (final p in periods) p.start]);
      }
      return result;
    });
  }

  @override
  Future<void> setLessonInfo(
    Account account,
    List<Period> periods,
    String text,
  ) {
    _check(account);
    return _wrap(() async {
      if (periods.isEmpty) {
        throw const UntisException(-1, 'No lesson selected.');
      }
      final auth = await accounts.credentials(account.id);
      for (final p in periods) {
        final ok = await _api.submitPeriodInfo(
          host: account.host,
          school: account.school.loginName,
          auth: auth,
          periodId: p.id,
          text: text.trim(),
        );
        if (!ok) {
          throw const UntisException(
            -1,
            'The server did not save the lesson info.',
          );
        }
      }
      await _refresh(account, [for (final p in periods) p.start]);
    });
  }

  @override
  Future<StaffNotes> staffNotes(Account account, List<Period> periods) {
    _check(account);
    return _wrap(() async {
      if (periods.isEmpty) {
        throw const UntisException(-1, 'No lesson selected.');
      }
      final auth = await accounts.credentials(account.id);
      return _api.lessonStaffNotes(
        host: account.host,
        school: account.school.loginName,
        auth: auth,
        periodId: periods.first.id,
      );
    });
  }

  @override
  Future<StaffNotes> setStaffNotes(
    Account account,
    List<Period> periods,
    String text,
  ) {
    _check(account);
    return _wrap(() async {
      if (periods.isEmpty) {
        throw const UntisException(-1, 'No lesson selected.');
      }
      final auth = await accounts.credentials(account.id);
      // Notes for teachers aren't part of the timetable: nothing to refresh.
      final saved = await _api.submitStaffNotes(
        host: account.host,
        school: account.school.loginName,
        auth: auth,
        periodId: periods.first.id,
        text: text.trim(),
        wholeBlock: periods.length > 1,
      );
      return saved ?? StaffNotes(text: text.trim());
    });
  }

  /// Exam types per account, loaded once per session.
  final _examTypes = <String, List<ExamType>>{};

  @override
  Future<List<ExamType>> examTypes(Account account) async {
    final cached = _examTypes[account.id];
    if (cached != null) return cached;
    try {
      _check(account);
      final auth = await accounts.credentials(account.id);
      // The school's types with their ids (the website sends the id; the
      // Untis Platform call may refuse a teacher's token) …
      final official = await _api.examTypes(
        host: account.host,
        school: account.school.loginName,
        auth: auth,
      );
      if (official.isNotEmpty) return _examTypes[account.id] = official;
      // … else the type names of the exams we can load (the official app's
      // master data has none: an exam's type is a plain string there).
      final types = await _typesFromExams(account, auth);
      if (types.isEmpty) return const [];
      return _examTypes[account.id] = types;
    } catch (_) {
      return const [];
    }
  }

  /// Fallback when the master data has no exam types: the type names of the
  /// school's exams the teacher can see (half a year back, three months
  /// ahead). They get negative ids, so only the name is sent.
  Future<List<ExamType>> _typesFromExams(
    Account account,
    UntisCredentials auth,
  ) async {
    final Object a = api;
    final target = account.personalTarget;
    if (a is! InfoCenterApi || target == null) return const [];
    final today = clock();
    final exams = await a.exams(
      host: account.host,
      school: account.school.loginName,
      auth: auth,
      target: target,
      start: today.subtract(const Duration(days: 183)),
      end: today.add(const Duration(days: 92)),
    );
    final names = <String>{
      for (final e in exams)
        if (e.examType.trim().isNotEmpty) e.examType.trim(),
    }.toList()..sort((x, y) => x.toLowerCase().compareTo(y.toLowerCase()));
    return [
      for (var i = 0; i < names.length; i++)
        ExamType(id: -(i + 1), name: names[i]),
    ];
  }

  @override
  Future<void> createExam(Account account, NewExam exam) {
    _check(account);
    return _wrap(() async {
      if (exam.name.trim().isEmpty && exam.examType.trim().isEmpty) {
        throw const UntisException(-1, 'Enter a name or an exam type.');
      }
      if (!exam.end.isAfter(exam.start)) {
        throw const UntisException(-1, 'The end must be after the start.');
      }
      final auth = await accounts.credentials(account.id);
      await _api.createExam(
        host: account.host,
        school: account.school.loginName,
        auth: auth,
        exam: exam,
      );
      await _refresh(account, [exam.start]);
    });
  }

  final _courses = <String, TeacherCourses>{};

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  static bool _isLesson(Period p) =>
      !p.isCancelled &&
      !p.flags.contains(PeriodFlag.breakSupervision) &&
      !p.flags.contains(PeriodFlag.officeHour);

  Future<List<Period>> _ownWeek(Account account, DateTime monday) => timetables
      .watchWeek(
        account,
        TimetableTarget(account.elementType, account.elementId),
        monday,
      )
      .first
      .timeout(const Duration(seconds: 20));

  @override
  Future<TeacherCourses> courses(Account account) {
    _check(account);
    return _wrap(() async {
      final cached = _courses[account.id];
      if (cached != null) return cached;
      final now = _mondayOf(clock());
      final periods = <Period>[];
      Object? error;
      var loaded = 0;
      for (var w = -2; w <= 3; w++) {
        try {
          periods.addAll(
            await _ownWeek(
              account,
              DateTime(now.year, now.month, now.day + 7 * w),
            ),
          );
          loaded++;
        } catch (e) {
          error ??= e;
        }
      }
      if (loaded == 0) {
        if (error is UntisException) throw error;
        throw const UntisException(0, 'Timetable not available.');
      }
      // Exam subjects: only lessons with a class (no "Aufsichtsstunde").
      final c = TeacherCourses.of(
        periods.where((p) => _isLesson(p) && p.canHoldExam),
      );
      if (!c.isEmpty) _courses[account.id] = c;
      return c;
    });
  }

  @override
  Future<List<Period>> lessonsOn(Account account, DateTime day) {
    _check(account);
    return _wrap(() async {
      final week = await _ownWeek(account, _mondayOf(day));
      return [
        for (final p in week)
          // Exam periods: no supervisions or lessons without a class.
          if (_isLesson(p) &&
              p.canHoldExam &&
              p.start.year == day.year &&
              p.start.month == day.month &&
              p.start.day == day.day)
            p,
      ]..sort((a, b) => a.start.compareTo(b.start));
    });
  }

  /// Refreshes the own timetable weeks of [days]; failures are ignored (the
  /// change itself went through).
  Future<void> _refresh(Account account, List<DateTime> days) async {
    final target = TimetableTarget(account.elementType, account.elementId);
    final mondays = {for (final d in days) _mondayOf(d)};
    for (final m in mondays) {
      try {
        await timetables.refresh(account, target, m);
      } catch (_) {}
    }
  }

  static (DateTime, DateTime) _span(List<Period> periods) {
    var start = periods.first.start;
    var end = periods.first.end;
    for (final p in periods) {
      if (p.start.isBefore(start)) start = p.start;
      if (p.end.isAfter(end)) end = p.end;
    }
    return (start, end);
  }

  static Future<T> _wrap<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on UntisException {
      rethrow;
    } catch (e) {
      throw UntisException(-1, 'Internal error: $e');
    }
  }
}
