import 'dart:async';

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
    return _wrapAsync(() async {
      final auth = await accounts.credentials(account.id);
      final host = account.host;
      final school = account.school.loginName;
      for (final p in periods) {
        final reg = current.periods[p.id];
        final absences = reg?.absences ?? const <ClassRegAbsence>[];
        for (final s in changes.markAbsent) {
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
  Future<List<OpenLesson>> openLessons(Account account, {int days = 14}) {
    _check(account);
    return _wrapAsync(() async {
      final target = TimetableTarget(account.elementType, account.elementId);
      final now = clock();
      final today = DateTime(now.year, now.month, now.day);
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
                !p.start.isBefore(from) && p.end.isBefore(now) && _isLesson(p),
          ),
        );
      }
      if (periods.isEmpty) return const <OpenLesson>[];
      final data = await _periodData(account, [for (final p in periods) p.id]);
      final open = [
        for (final p in periods)
          if (data.periods[p.id] case final r? when r.isIncomplete)
            OpenLesson(p, r),
      ]..sort((a, b) => b.period.start.compareTo(a.period.start));
      return open;
    });
  }

  static bool _isLesson(Period p) =>
      !p.isCancelled &&
      !p.flags.contains(PeriodFlag.breakSupervision) &&
      !p.flags.contains(PeriodFlag.officeHour);

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
