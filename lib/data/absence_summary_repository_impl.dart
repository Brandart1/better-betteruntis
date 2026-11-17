import 'dart:async';
import 'dart:math' as math;

import '../core/absence_summary.dart';
import '../core/class_register.dart';
import '../core/interfaces.dart';
import '../core/models.dart';

/// [AbsenceSummaryRepository] on top of [ClassRegisterApi] (lesson and
/// subject scope: getPeriodData2017 of the course's lessons in the own
/// timetable) and [ClassAbsencesApi] (all subjects: the class absence
/// list). Nothing is cached.
class AbsenceSummaryRepositoryImpl implements AbsenceSummaryRepository {
  AbsenceSummaryRepositoryImpl({
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

  ClassRegisterApi get _register {
    final Object a = api;
    if (a is ClassRegisterApi) return a;
    throw const UntisException(-1, 'Class register is not supported here.');
  }

  ClassAbsencesApi get _classes {
    final Object a = api;
    if (a is ClassAbsencesApi) return a;
    throw const UntisException(
      -1,
      'Class absence lists are not supported here.',
    );
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  Future<NameResolver?> _names(Account a) async {
    try {
      return await timetables
          .watchNames(a)
          .first
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SchoolYear?> schoolYear(Account account, {DateTime? day}) async =>
      _yearOf((await _names(account))?.schoolYears ?? const [], day ?? clock());

  static SchoolYear? _yearOf(List<SchoolYear> years, DateTime day) {
    final d = _day(day);
    for (final y in years) {
      if (!d.isBefore(_day(y.start)) && !d.isAfter(_day(y.end))) return y;
    }
    // Holidays between two years: the latest one that started already.
    SchoolYear? best;
    for (final y in years) {
      if (!y.start.isAfter(d) &&
          (best == null || y.start.isAfter(best.start))) {
        best = y;
      }
    }
    return best;
  }

  @override
  Future<AbsenceSummary> summary(
    Account account,
    List<Period> periods, {
    required AbsenceSummaryScope scope,
    DateTime? from,
    DateTime? to,
    void Function(int done, int total)? onProgress,
  }) async {
    if (!hasClassRegister(account)) {
      throw const UntisException(
        UntisException.noRight,
        'Only teacher accounts have a class register.',
      );
    }
    if (periods.isEmpty) {
      throw const UntisException(-1, 'No lesson selected.');
    }
    try {
      return await switch (scope) {
        AbsenceSummaryScope.lesson => _lesson(account, periods),
        AbsenceSummaryScope.subject => _range(
          account,
          from,
          to,
        ).then((r) => _subject(account, periods, r.$1, r.$2, onProgress)),
        AbsenceSummaryScope.all => _range(
          account,
          from,
          to,
        ).then((r) => _all(account, periods, r.$1, r.$2)),
      };
    } on UntisException {
      rethrow;
    } catch (e) {
      throw UntisException(-1, 'Internal error: $e');
    }
  }

  /// [from]/[to] as days; default: the school year (else since 1 September)
  /// up to today.
  Future<(DateTime, DateTime)> _range(
    Account a,
    DateTime? from,
    DateTime? to,
  ) async {
    final today = _day(clock());
    var start = from == null ? null : _day(from);
    if (start == null) {
      final y = await schoolYear(a);
      start = y != null
          ? _day(y.start)
          : DateTime(today.month >= 8 ? today.year : today.year - 1, 9, 1);
    }
    final end = _day(to ?? today);
    if (end.isBefore(start)) {
      throw const UntisException(-1, 'The end must not be before the start.');
    }
    return (start, end);
  }

  Future<PeriodRegisterData> _periodData(
    Account a,
    UntisCredentials auth,
    List<int> ids, {
    void Function()? onChunk,
  }) async {
    final periods = <int, PeriodRegister>{};
    final students = <int, ClassRegStudent>{};
    for (var i = 0; i < ids.length; i += chunkSize) {
      final d = await _register.periodData(
        host: a.host,
        school: a.school.loginName,
        auth: auth,
        ttIds: ids.sublist(i, math.min(i + chunkSize, ids.length)),
      );
      periods.addAll(d.periods);
      students.addAll(d.students);
      onChunk?.call();
    }
    return PeriodRegisterData(periods: periods, students: students);
  }

  /// Pupils of [regs] (their `studentIds`, else every referenced pupil).
  static Map<int, ClassRegStudent> _roster(
    Iterable<PeriodRegister> regs,
    Map<int, ClassRegStudent> students,
  ) {
    final ids = {for (final r in regs) ...r.studentIds};
    if (ids.isEmpty) return {...students};
    return {
      for (final id in ids)
        id:
            students[id] ??
            ClassRegStudent(id: id, firstName: '', lastName: '#$id'),
    };
  }

  Future<AbsenceSummary> _lesson(Account a, List<Period> periods) async {
    final auth = await accounts.credentials(a.id);
    final data = await _periodData(a, auth, [for (final p in periods) p.id]);
    final regs = [for (final p in periods) ?data.periods[p.id]];
    return AbsenceSummary(
      scope: AbsenceSummaryScope.lesson,
      from: _day(periods.first.start),
      to: _day(periods.last.start),
      pupils: groupByPupil([
        for (final p in periods)
          for (final x in data.periods[p.id]?.absences ?? const [])
            summaryAbsenceOf(p, x),
      ], _roster(regs, data.students)),
      lessonsLooked: regs.length,
      lessonsSkipped: periods.length - regs.length,
    );
  }

  Future<AbsenceSummary> _subject(
    Account a,
    List<Period> block,
    DateTime from,
    DateTime to,
    void Function(int done, int total)? onProgress,
  ) async {
    final ref = block.reduce((x, y) => y.start.isBefore(x.start) ? y : x);
    final target = TimetableTarget(a.elementType, a.elementId);
    final now = clock();
    final endExclusive = DateTime(to.year, to.month, to.day + 1);
    final mondays = <DateTime>[
      for (
        var m = _mondayOf(from);
        m.isBefore(endExclusive);
        m = DateTime(m.year, m.month, m.day + 7)
      )
        m,
    ];
    var truncated = false;
    if (mondays.length > maxSummaryWeeks) {
      // Keep the latest weeks.
      mondays.removeRange(0, mondays.length - maxSummaryWeeks);
      truncated = true;
    }
    final start = truncated && mondays.first.isAfter(from)
        ? mondays.first
        : from;
    final seen = <int>{};
    final all = <Period>[];
    Object? error;
    var loaded = 0;
    for (var i = 0; i < mondays.length; i++) {
      onProgress?.call(i, mondays.length + 1);
      final List<Period> week;
      try {
        week = await timetables
            .watchWeek(a, target, mondays[i])
            .first
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        error ??= e;
        continue;
      }
      loaded++;
      for (final p in week) {
        if (p.start.isBefore(start) ||
            !p.start.isBefore(endExclusive) ||
            p.start.isAfter(now) ||
            !seen.add(p.id)) {
          continue;
        }
        all.add(p);
      }
    }
    if (loaded == 0) {
      if (error is UntisException) throw error;
      throw const UntisException(0, 'Timetable not available.');
    }
    final lessons = courseLessons(ref, all)
      ..sort((x, y) => x.start.compareTo(y.start));
    final own = [
      for (final p in lessons)
        if (substituteOf(p, a.elementId) == null) p.id,
    ];
    final substituted = [
      for (final p in lessons)
        if (substituteOf(p, a.elementId) != null) p.id,
    ];
    final chunks =
        (own.length + chunkSize - 1) ~/ chunkSize +
        (substituted.length + chunkSize - 1) ~/ chunkSize;
    final total = mondays.length + chunks;
    var done = mondays.length;
    void step() => onProgress?.call(++done, total);
    onProgress?.call(done, total);
    final auth = await accounts.credentials(a.id);
    final data = await _periodData(a, auth, own, onChunk: step);
    final periods = {...data.periods};
    final students = {...data.students};
    // Lessons a substitute held: the server may not share them with the
    // original teacher; they must not break the summary.
    if (substituted.isNotEmpty) {
      try {
        final d = await _periodData(a, auth, substituted, onChunk: step);
        periods.addAll(d.periods);
        students.addAll(d.students);
      } on UntisException catch (e) {
        if (e.isNetwork || e.isTimeout) rethrow;
      }
    }
    final regs = [for (final p in lessons) ?periods[p.id]];
    return AbsenceSummary(
      scope: AbsenceSummaryScope.subject,
      from: start,
      to: to,
      pupils: groupByPupil([
        for (final p in lessons)
          for (final x in periods[p.id]?.absences ?? const [])
            summaryAbsenceOf(p, x),
      ], _roster(regs, students)),
      lessonsLooked: regs.length,
      lessonsSkipped: lessons.length - regs.length,
      truncated: truncated,
    );
  }

  Future<AbsenceSummary> _all(
    Account a,
    List<Period> block,
    DateTime from,
    DateTime to,
  ) async {
    final klassen = {
      for (final p in block)
        for (final k in p.ofType(ElementType.klasse))
          if (k.id > 0) k.id,
    };
    if (klassen.isEmpty) {
      throw const UntisException(-1, 'This lesson has no class.');
    }
    final auth = await accounts.credentials(a.id);
    // The lesson's pupils: only they are listed (a course may be a group of
    // a class, or pupils of several classes).
    // A block without real lessons (the class dashboard's whole-class
    // summary, ids <= 0): every pupil of the class.
    var roster = const <int, ClassRegStudent>{};
    if (block.any((p) => p.id > 0)) {
      try {
        final data = await _periodData(a, auth, [
          for (final p in block)
            if (p.id > 0) p.id,
        ]);
        roster = _roster([
          for (final p in block) ?data.periods[p.id],
        ], data.students);
      } on UntisException catch (e) {
        if (e.isNetwork || e.isTimeout) rethrow;
      }
    }
    final records = <int, ClassAbsenceRecord>{};
    for (final k in klassen) {
      final List<ClassAbsenceRecord> list;
      try {
        list = await _classes.classAbsences(
          host: a.host,
          school: a.school.loginName,
          auth: auth,
          klasseId: k,
          start: from,
          end: to,
        );
      } on UntisException catch (e) {
        if (isClassListRefusal(e)) {
          throw const UntisException(
            UntisException.noRight,
            'Only the class teacher can see all absences of the class. '
            'Lesson and Subject still work.',
          );
        }
        rethrow;
      }
      for (final r in list) {
        records[r.id] = r;
      }
    }
    final grid = (await _names(a))?.timeGrid ?? TimeGrid.fallback();
    return AbsenceSummary(
      scope: AbsenceSummaryScope.all,
      from: from,
      to: to,
      pupils: groupByPupil([
        for (final r in recordsOfRoster(records.values.toList(), roster))
          SummaryAbsence(
            id: r.id,
            studentId: r.studentId,
            studentName: r.studentName,
            start: r.start,
            end: r.end,
            lessons: r.late
                ? 0
                : math.max(1, unitsCovered(r.start, r.end, grid)),
            state: r.state,
            late: r.late,
            reason: r.reason,
            text: r.text,
          ),
      ], roster),
      approximate: true,
    );
  }
}

/// The server's refusal of a class's whole absence list to a teacher who
/// isn't its class teacher ("invalid user role", or no right).
bool isClassListRefusal(UntisException e) =>
    e.code == UntisException.noRight ||
    e.message.toLowerCase().contains('role');
