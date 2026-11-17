import 'dart:async';

import '../core/absence_summary.dart';
import '../core/class_register.dart';
import '../core/interfaces.dart';
import '../core/models.dart';

/// [ClassRegisterRepository] on top of [ClassRegisterApi]. Nothing is
/// cached: class register data is always loaded fresh, since another device
/// (or the web client) may have changed it.
class ClassRegisterRepositoryImpl implements ClassRegisterRepository {
  ClassRegisterRepositoryImpl({
    required this.api,
    required this.accounts,
    required this.timetables,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final UntisApi api;
  final AccountRepository accounts;
  final TimetableRepository timetables;
  final DateTime Function() clock;

  /// getPeriodData2017 is asked for at most this many lessons at once.
  static const chunkSize = 40;

  ClassRegisterApi get _api {
    final Object a = api;
    if (a is ClassRegisterApi) return a;
    throw const UntisException(-1, 'Class register is not supported here.');
  }

  void _check(Account a) {
    if (!hasClassRegister(a)) {
      throw const UntisException(
        UntisException.noRight,
        'Only teacher accounts have a class register.',
      );
    }
  }

  /// Lessons of [periods] a substitute held instead of the account's teacher
  /// are read-only: their class register belongs to the substitute.
  void _checkWritable(Account a, List<Period> periods) {
    if (heldBySubstitute(periods, a.elementId)) {
      throw const UntisException(
        UntisException.noRight,
        'A substitute held this lesson; only they can change its class '
        'register.',
      );
    }
  }

  /// [_periodData] for lessons a substitute held instead of the account's
  /// teacher ([substituted]) and the others ([own]) separately: the server
  /// may refuse the substitute's lessons to the original teacher, which
  /// must not break the rest. Lessons whose data could not be read are
  /// simply missing.
  Future<PeriodRegisterData> _periodDataSplit(
    Account a,
    List<Period> lessons,
  ) async {
    final own = <int>[];
    final substituted = <int>[];
    for (final p in lessons) {
      (substituteOf(p, a.elementId) == null ? own : substituted).add(p.id);
    }
    final d = await _periodData(a, own);
    if (substituted.isEmpty) return d;
    try {
      final s = await _periodData(a, substituted);
      return PeriodRegisterData(
        periods: {...d.periods, ...s.periods},
        students: {...s.students, ...d.students},
      );
    } on UntisException catch (e) {
      if (e.isNetwork || e.isTimeout) rethrow;
      return d;
    }
  }

  Future<PeriodRegisterData> _periodData(Account a, List<int> ids) async {
    final auth = await accounts.credentials(a.id);
    final periods = <int, PeriodRegister>{};
    final students = <int, ClassRegStudent>{};
    for (var i = 0; i < ids.length; i += chunkSize) {
      final d = await _api.periodData(
        host: a.host,
        school: a.school.loginName,
        auth: auth,
        ttIds: ids.sublist(i, (i + chunkSize).clamp(0, ids.length)),
      );
      periods.addAll(d.periods);
      students.addAll(d.students);
    }
    return PeriodRegisterData(periods: periods, students: students);
  }

  @override
  Future<PeriodRegisterData> load(Account account, List<Period> periods) {
    _check(account);
    return _wrapAsync(
      () => _periodData(account, [for (final p in periods) p.id]),
    );
  }

  @override
  Future<void> save(
    Account account,
    List<Period> periods,
    PeriodRegisterData current,
    ClassRegChanges changes,
  ) {
    _check(account);
    _checkWritable(account, periods);
    return _wrapAsync(() async {
      final auth = await accounts.credentials(account.id);
      final host = account.host;
      final school = account.school.loginName;
      for (final p in periods) {
        final reg = current.periods[p.id];
        final absences = reg?.absences ?? const <ClassRegAbsence>[];
        // Pupils who are (or become) absent with their own times, reason
        // or note: their absence in this period is the part of those times
        // inside it — created, changed or (none left) deleted.
        for (final MapEntry(key: s, value: d) in changes.details.entries) {
          if (changes.markPresent.contains(s)) continue;
          final part = d.clip(p.start, p.end);
          final mine = absences.where((a) => a.studentId == s).toList();
          if (part == null) {
            for (final a in mine) {
              await _api.deleteAbsence(
                host: host,
                school: school,
                auth: auth,
                absenceId: a.id,
              );
            }
            continue;
          }
          ClassRegAbsence? target = mine.firstOrNull;
          if (target == null) {
            final id = await _api.createAbsence(
              host: host,
              school: school,
              auth: auth,
              ttId: p.id,
              studentId: s,
              start: part.start,
              end: part.end,
            );
            if (!d.hasReasonOrText) continue;
            target = id != null
                ? ClassRegAbsence(
                    id: id,
                    studentId: s,
                    start: part.start,
                    end: part.end,
                  )
                : await _findAbsence(auth, account, p.id, s);
            if (target == null) continue;
          }
          final changed = target.copyWith(
            start: part.start,
            end: part.end,
            reasonId: () => d.reasonId,
            text: d.text.trim(),
          );
          if (changed.start != target.start ||
              changed.end != target.end ||
              changed.reasonId != target.reasonId ||
              changed.text != target.text.trim()) {
            await _api.editAbsence(
              host: host,
              school: school,
              auth: auth,
              ttId: p.id,
              absence: changed,
            );
          }
          // More than one absence of the pupil in this period: keep one.
          for (final a in mine.skip(1)) {
            await _api.deleteAbsence(
              host: host,
              school: school,
              auth: auth,
              absenceId: a.id,
            );
          }
        }
        for (final s in changes.markAbsent) {
          if (changes.details.containsKey(s)) continue;
          if (absences.any((a) => a.studentId == s)) continue;
          await _api.createAbsence(
            host: host,
            school: school,
            auth: auth,
            ttId: p.id,
            studentId: s,
            start: p.start,
            end: p.end,
          );
        }
        for (final a in absences) {
          if (!changes.markPresent.contains(a.studentId)) continue;
          await _api.deleteAbsence(
            host: host,
            school: school,
            auth: auth,
            absenceId: a.id,
          );
        }
      }
      await _api.submitAbsencesChecked(
        host: host,
        school: school,
        auth: auth,
        ttIds: [for (final p in periods) p.id],
      );
      final topic = changes.topic;
      if (topic != null) {
        for (final p in periods) {
          await _api.submitLessonTopic(
            host: host,
            school: school,
            auth: auth,
            ttId: p.id,
            topic: topic,
          );
        }
      }
    });
  }

  @override
  Future<List<ClassRegLesson>> lessons(Account account, {int days = 14}) {
    _check(account);
    return _wrapAsync(() async {
      final target = TimetableTarget(account.elementType, account.elementId);
      final now = clock();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final from = DateTime(today.year, today.month, today.day - days);
      final periods = <Period>[];
      for (
        var monday = _mondayOf(from);
        !monday.isAfter(today);
        monday = DateTime(monday.year, monday.month, monday.day + 7)
      ) {
        periods.addAll(
          (await _week(account, target, monday)).where(
            (p) =>
                !p.start.isBefore(from) &&
                p.start.isBefore(tomorrow) &&
                _isLesson(p),
          ),
        );
      }
      if (periods.isEmpty) return const <ClassRegLesson>[];
      final data = await _periodDataSplit(account, periods);
      return [
        for (final p in periods)
          if (substituteOf(p, account.elementId) case final sub?)
            // Held by a substitute: listed even without data, never missing.
            ClassRegLesson(
              p,
              data.periods[p.id] ?? PeriodRegister(ttId: p.id),
              substitutedBy: sub,
              registerMissing: !data.periods.containsKey(p.id),
            )
          else if (data.periods[p.id] case final r?)
            ClassRegLesson(p, r),
      ]..sort((a, b) => a.period.start.compareTo(b.period.start));
    });
  }

  // ---- Previous topics and class register entries -------------------------

  /// Entry reasons per account, loaded once per session.
  final _eventReasons = <String, Map<int, String>>{};

  @override
  Future<CourseHistory> courseHistory(
    Account account,
    List<Period> periods, {
    int topics = 5,
    int weeks = 6,
  }) {
    _check(account);
    return _wrapAsync(() async {
      if (periods.isEmpty) return const CourseHistory();
      final ref = periods.reduce((a, b) => b.start.isBefore(a.start) ? b : a);
      final blockIds = {for (final p in periods) p.id};
      final target = TimetableTarget(account.elementType, account.elementId);
      // Double lessons count twice, so look at a few more than [topics].
      final want = topics * 3;
      final sameLesson = <Period>[];
      final sameSubject = <Period>[];
      List<Period> found() => sameLesson.isNotEmpty ? sameLesson : sameSubject;
      Object? error;
      var loadedWeeks = 0;
      final refMonday = _mondayOf(ref.start);
      for (var w = 0; w < weeks && found().length < want; w++) {
        final monday = DateTime(
          refMonday.year,
          refMonday.month,
          refMonday.day - 7 * w,
        );
        final List<Period> week;
        try {
          week = await timetables
              .watchWeek(account, target, monday)
              .first
              .timeout(const Duration(seconds: 20));
        } catch (e) {
          error ??= e;
          continue;
        }
        loadedWeeks++;
        for (final p in week) {
          if (blockIds.contains(p.id) ||
              !p.start.isBefore(ref.start) ||
              !_isLesson(p)) {
            continue;
          }
          if (ref.lessonId > 0 && p.lessonId == ref.lessonId) {
            sameLesson.add(p);
          } else if (_sameSubjectAndClasses(ref, p)) {
            sameSubject.add(p);
          }
        }
      }
      if (loadedWeeks == 0) {
        if (error is UntisException) throw error;
        throw const UntisException(0, 'Timetable not available.');
      }
      final candidates = [...found()]
        ..sort((a, b) => b.start.compareTo(a.start));
      if (candidates.length > want) {
        candidates.removeRange(want, candidates.length);
      }
      if (candidates.isEmpty) return const CourseHistory();
      // Lessons a substitute held are included (their topics too).
      final data = await _periodDataSplit(account, candidates);
      final withTopic = <ClassRegLesson>[];
      final events = <ClassRegEvent>[];
      final seenEvents = <int>{};
      for (final p in candidates) {
        final r = data.periods[p.id];
        if (r == null) continue;
        // A double lesson has the same topic twice: keep it once.
        final prev = withTopic.isEmpty ? null : withTopic.last;
        if (r.hasTopic &&
            withTopic.length < topics &&
            !(prev != null &&
                _sameDay(prev.period.start, p.start) &&
                prev.register.topic.trim() == r.topic.trim())) {
          withTopic.add(
            ClassRegLesson(
              p,
              r,
              substitutedBy: substituteOf(p, account.elementId),
            ),
          );
        }
        for (final e in r.events) {
          if (e.id != null && !seenEvents.add(e.id!)) continue;
          events.add(e.inLesson(p.id, p.start));
        }
      }
      events.sort((a, b) => b.date!.compareTo(a.date!));
      return CourseHistory(
        topics: withTopic,
        events: events,
        students: data.students,
        lessonsLoaded: candidates.length,
      );
    });
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static Set<int> _idsOf(Period p, ElementType t) => {
    for (final e in p.elements)
      if (e.type == t) e.id,
  };

  /// Same subject(s) and same class(es); false when [ref] has no subject.
  static bool _sameSubjectAndClasses(Period ref, Period p) {
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

  /// [studentId]'s absence in [ttId] as the server has it now (when the
  /// create answer had no id).
  Future<ClassRegAbsence?> _findAbsence(
    UntisCredentials auth,
    Account account,
    int ttId,
    int studentId,
  ) async {
    final d = await _api.periodData(
      host: account.host,
      school: account.school.loginName,
      auth: auth,
      ttIds: [ttId],
    );
    return d.periods[ttId]?.absences
        .where((a) => a.studentId == studentId)
        .firstOrNull;
  }

  final _absenceReasons = <String, Map<int, String>>{};

  @override
  Future<Map<int, String>> absenceReasons(Account account) async {
    final cached = _absenceReasons[account.id];
    if (cached != null) return cached;
    try {
      _check(account);
      final auth = await accounts.credentials(account.id);
      final r = await _api.absenceReasons(
        host: account.host,
        school: account.school.loginName,
        auth: auth,
      );
      return _absenceReasons[account.id] = r;
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<Map<int, String>> eventReasons(Account account) async {
    final cached = _eventReasons[account.id];
    if (cached != null) return cached;
    try {
      _check(account);
      final auth = await accounts.credentials(account.id);
      final r = await _api.eventReasons(
        host: account.host,
        school: account.school.loginName,
        auth: auth,
      );
      return _eventReasons[account.id] = r;
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<void> createEvent(
    Account account,
    List<Period> periods,
    NewClassRegEvent event,
  ) {
    _check(account);
    _checkWritable(account, periods);
    return _wrapAsync(() async {
      if (periods.isEmpty) {
        throw const UntisException(-1, 'No lesson selected.');
      }
      if (event.text.trim().isEmpty && event.reasonId == null) {
        throw const UntisException(-1, 'Enter a text or choose a reason.');
      }
      final first = periods.reduce((a, b) => b.start.isBefore(a.start) ? b : a);
      final auth = await accounts.credentials(account.id);
      await _api.createClassRegEvent(
        host: account.host,
        school: account.school.loginName,
        auth: auth,
        ttId: first.id,
        studentId: event.studentId,
        eventReasonId: event.reasonId,
        text: event.text.trim(),
      );
    });
  }

  /// Lessons with a class register: not cancelled, no supervision / office
  /// hour, and a class (room bookings and on-call "Aufsichtsstunden"
  /// without a class have none).
  static bool _isLesson(Period p) =>
      !p.isCancelled &&
      !p.flags.contains(PeriodFlag.breakSupervision) &&
      !p.flags.contains(PeriodFlag.officeHour) &&
      p.hasClass;

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// Fresh week if the server answers, else the cached one.
  Future<List<Period>> _week(
    Account a,
    TimetableTarget target,
    DateTime monday,
  ) async {
    Object? error;
    try {
      await timetables.refresh(a, target, monday);
    } catch (e) {
      error = e;
    }
    try {
      return await timetables
          .watchWeek(a, target, monday)
          .first
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      throw error ?? const UntisException(0, 'Timetable not available.');
    }
  }

  static Future<T> _wrapAsync<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on UntisException {
      rethrow;
    } catch (e) {
      throw UntisException(-1, 'Internal error: $e');
    }
  }
}
