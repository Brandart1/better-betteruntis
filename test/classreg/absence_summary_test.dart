import 'package:better_betteruntis/api/absence_summary_parsers.dart';
import 'package:better_betteruntis/api/class_register_parsers.dart';
import 'package:better_betteruntis/core/absence_summary.dart';
import 'package:better_betteruntis/core/class_register.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/data/absence_summary_repository_impl.dart';
import 'package:better_betteruntis/data/class_register_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/classreg/absence_summary_screen.dart';
import 'package:better_betteruntis/ui/classreg/class_register_overview_screen.dart';
import 'package:better_betteruntis/ui/classreg/class_register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'class_register_test.dart' show teacherAccount;

const _me = FakeUntisApi.demoTeacherId; // 11
const _sub = 12;

/// Wednesday 2026-11-11, 12:00.
final _now = DateTime(2026, 11, 11, 12);

ElementRef _teacher({int id = _me, int orgId = _me}) =>
    ElementRef(type: ElementType.teacher, id: id, orgId: orgId);

Period _lesson(
  int id,
  DateTime start, {
  ElementRef? teacher,
  int lessonId = 1,
  int subject = 21,
}) => Period(
  id: id,
  lessonId: lessonId,
  start: start,
  end: start.add(const Duration(minutes: 45)),
  elements: [
    const ElementRef(type: ElementType.klasse, id: 1, orgId: 1),
    ElementRef(type: ElementType.subject, id: subject, orgId: subject),
    teacher ?? _teacher(),
  ],
  flags: const {PeriodFlag.regular},
);

int _id(DateTime d, int n) => (d.year * 10000 + d.month * 100 + d.day) * 10 + n;

/// Per weekday: maths (course 1) at 08:00 and German (course 2) at 13:00.
/// Wednesdays' maths is held by substitute 12; on Thursdays teacher 11
/// substitutes in a physics lesson of teacher 13.
List<Period> _week(TimetableTarget _, DateTime monday) => [
  for (var d = 0; d < 5; d++) ...[
    _lesson(
      _id(DateTime(monday.year, monday.month, monday.day + d), 1),
      DateTime(monday.year, monday.month, monday.day + d, 8),
      teacher: d == 2 ? _teacher(id: _sub) : null,
    ),
    _lesson(
      _id(DateTime(monday.year, monday.month, monday.day + d), 2),
      DateTime(monday.year, monday.month, monday.day + d, 13),
      lessonId: 2,
      subject: 22,
      teacher: d == 3 ? _teacher(orgId: 13) : null,
    ),
  ],
];

/// Lets getPeriodData2017 fail for some ids (like a server that does not
/// share a substitute's lesson with the original teacher).
class _PickyApi extends FakeUntisApi {
  _PickyApi() : super(latency: Duration.zero);
  final refused = <int>{};
  final calls = <List<int>>[];

  @override
  Future<PeriodRegisterData> periodData({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> ttIds,
  }) {
    calls.add(ttIds);
    if (ttIds.any(refused.contains)) {
      throw const UntisException(UntisException.noRight, 'No right');
    }
    return super.periodData(
      host: host,
      school: school,
      auth: auth,
      ttIds: ttIds,
    );
  }
}

void main() {
  group('parsers', () {
    test('classic class absence list', () {
      final r = parseClassAbsenceRecords({
        'data': {
          'absences': [
            {
              'id': 5,
              'studentId': 501,
              'studentName': 'Bauer Lena',
              'startDate': 20261110,
              'startTime': 800,
              'endDate': 20261110,
              'endTime': 1335,
              'isExcused': true,
              'excuseStatus': 'entsch.',
              'reason': 'Krankheit',
              'text': 'Fever',
            },
            {
              'id': 6,
              'studentName': 'Fischer Jonas',
              'startDate': 20261111,
              'startTime': 750,
              'endDate': 20261111,
              'endTime': 800,
              'excuse': {'excuseStatus': 'nicht entsch.', 'isExcused': false},
              'isLate': true,
            },
            {
              'id': 7,
              'student': {'id': 503, 'firstName': 'Mia', 'lastName': 'Hofmann'},
              'startDate': '2026-11-12',
              'endDate': '2026-11-12',
              'excuseStatus': 'offen',
            },
            {'id': 8}, // no start: dropped
            'garbage',
          ],
        },
      });
      expect(r.map((a) => a.id), [5, 6, 7]);
      expect(r[0].studentId, 501);
      expect(r[0].start, DateTime(2026, 11, 10, 8));
      expect(r[0].end, DateTime(2026, 11, 10, 13, 35));
      expect(r[0].state, ExcuseState.excused);
      expect(r[0].reason, 'Krankheit');
      expect(r[0].text, 'Fever');
      expect(r[1].studentId, isNull);
      expect(r[1].studentName, 'Fischer Jonas');
      expect(r[1].state, ExcuseState.unexcused);
      expect(r[1].late, isTrue);
      expect(r[2].studentId, 503);
      expect(r[2].studentName, 'Hofmann Mia');
      expect(r[2].state, ExcuseState.open);
    });

    test('getStudentAbsences2017 shape and garbage', () {
      final r = parseClassAbsenceRecords({
        'absences': [
          {
            'id': 1,
            'studentId': '502',
            'startDateTime': '2026-11-10T08:00',
            'endDateTime': '2026-11-10T08:45',
            'excused': false,
            'excuseStatusId': 2,
          },
        ],
      });
      expect(r.single.studentId, 502);
      expect(r.single.state, ExcuseState.unexcused);
      expect(r.single.end, DateTime(2026, 11, 10, 8, 45));
      expect(parseClassAbsenceRecords(null), isEmpty);
      expect(parseClassAbsenceRecords('x'), isEmpty);
      expect(parseClassAbsenceRecords({'data': 3}), isEmpty);
    });

    test('class register absence: excuse status', () {
      final a = parseClassRegAbsence({
        'id': 1,
        'studentId': 501,
        'startDateTime': '2026-11-10T08:00',
        'endDateTime': '2026-11-10T08:45',
        'excuse': {'excuseStatusId': 3, 'excuseStatus': 'offen'},
      })!;
      expect(a.excuseStatusId, 3);
      expect(a.excuseStatus, 'offen');
      expect(excuseStateOf(a), ExcuseState.unexcused);
      final b = parseClassRegAbsence({
        'id': 2,
        'studentId': 501,
        'startDateTime': '2026-11-10T08:00',
        'endDateTime': '2026-11-10T08:45',
      })!;
      expect(excuseStateOf(b), ExcuseState.open);
    });
  });

  group('aggregation', () {
    final p = _lesson(1, DateTime(2026, 11, 10, 8));
    ClassRegAbsence abs(
      int student,
      DateTime s,
      DateTime e, {
      bool ex = false,
    }) => ClassRegAbsence(
      id: student,
      studentId: student,
      start: s,
      end: e,
      excused: ex,
    );

    test('late arrival vs. absent lesson', () {
      final whole = summaryAbsenceOf(p, abs(1, p.start, p.end));
      expect((whole.late, whole.lessons), (false, 1));
      final late = summaryAbsenceOf(
        p,
        abs(1, p.start, p.start.add(const Duration(minutes: 10))),
      );
      expect((late.late, late.lessons), (true, 0));
      // Left early: counts as an absent lesson.
      final left = summaryAbsenceOf(
        p,
        abs(1, p.start.add(const Duration(minutes: 30)), p.end),
      );
      expect((left.late, left.lessons), (false, 1));
      // A whole-day absence is clipped to the lesson.
      final day = summaryAbsenceOf(
        p,
        abs(1, DateTime(2026, 11, 10, 7), DateTime(2026, 11, 10, 16)),
      );
      expect((day.start, day.end, day.lessons), (p.start, p.end, 1));
    });

    test('units covered by the time grid', () {
      final grid = TimeGrid({
        for (var d = 1; d <= 5; d++)
          d: [
            for (var i = 0; i < 6; i++)
              TimeUnit(label: '$i', start: 480 + i * 50, end: 525 + i * 50),
          ],
      });
      // 08:00–09:35 covers units 0 and 1.
      expect(
        unitsCovered(
          DateTime(2026, 11, 10, 8),
          DateTime(2026, 11, 10, 9, 35),
          grid,
        ),
        2,
      );
      // Tue 08:00 to Wed 09:00: 6 + 2 units.
      expect(
        unitsCovered(
          DateTime(2026, 11, 10, 8),
          DateTime(2026, 11, 11, 9),
          grid,
        ),
        8,
      );
      // Over a weekend: no units on Sat/Sun.
      expect(
        unitsCovered(DateTime(2026, 11, 14), DateTime(2026, 11, 16), grid),
        0,
      );
      // Fallback grid: minutes / 45, at least 1.
      expect(
        unitsCovered(
          DateTime(2026, 11, 10, 8),
          DateTime(2026, 11, 10, 8, 10),
          TimeGrid.fallback(),
        ),
        1,
      );
      expect(
        unitsCovered(
          DateTime(2026, 11, 10, 8),
          DateTime(2026, 11, 10, 8),
          grid,
        ),
        0,
      );
    });

    test('group by pupil: roster, names, totals, sorting', () {
      const roster = {
        2: ClassRegStudent(id: 2, firstName: 'Zoe', lastName: 'Adler'),
        1: ClassRegStudent(id: 1, firstName: 'Max', lastName: 'Zander'),
        3: ClassRegStudent(id: 3, firstName: 'Ida', lastName: 'Berg'),
      };
      final d = DateTime(2026, 11, 10, 8);
      final pupils = groupByPupil([
        SummaryAbsence(
          studentId: 1,
          start: d,
          end: d,
          state: ExcuseState.excused,
        ),
        SummaryAbsence(
          studentId: 1,
          start: d.add(const Duration(days: 1)),
          end: d,
          lessons: 2,
          state: ExcuseState.unexcused,
        ),
        SummaryAbsence(studentId: 2, start: d, end: d, lessons: 0, late: true),
        SummaryAbsence(studentName: 'Neu Nina', start: d, end: d),
        SummaryAbsence(studentName: 'neu nina', start: d, end: d),
      ], roster);
      expect(pupils.map((p) => p.name), [
        'Adler Zoe',
        'Berg Ida',
        'Neu Nina',
        'Zander Max',
      ]);
      final zander = pupils.last;
      expect(zander.lessons, 3);
      expect(zander.excusedLessons, 1);
      expect(zander.unexcusedLessons, 2);
      expect(zander.absences.first.lessons, 2); // newest first
      expect(pupils[0].lessons, 0);
      expect(pupils[0].lateCount, 1);
      expect(pupils[1].hasAbsences, isFalse);
      expect(pupils[2].openLessons, 2);
      final s = AbsenceSummary(
        scope: AbsenceSummaryScope.subject,
        from: d,
        to: d,
        pupils: pupils,
      );
      expect(s.lessons, 5);
      expect(s.lateCount, 1);
      expect(s.pupilsWithAbsences, 3);
    });

    test('records of the roster only', () {
      const roster = {
        1: ClassRegStudent(id: 1, firstName: 'Max', lastName: 'Zander'),
      };
      final d = DateTime(2026, 11, 10);
      final records = [
        ClassAbsenceRecord(id: 1, studentId: 1, start: d, end: d),
        ClassAbsenceRecord(id: 2, studentId: 9, start: d, end: d),
        ClassAbsenceRecord(id: 3, studentName: 'Zander, Max', start: d, end: d),
        ClassAbsenceRecord(id: 4, studentName: 'Other Kid', start: d, end: d),
      ];
      expect(recordsOfRoster(records, roster).map((r) => r.id), [1, 3]);
      expect(recordsOfRoster(records, const {}), hasLength(4));
    });

    test('substitute of a lesson', () {
      final d = DateTime(2026, 11, 10, 8);
      expect(substituteOf(_lesson(1, d), _me), isNull);
      expect(
        substituteOf(_lesson(1, d, teacher: _teacher(id: _sub)), _me)!.id,
        _sub,
      );
      // Teacher 11 substitutes for 13: their own lesson now.
      expect(
        substituteOf(_lesson(1, d, teacher: _teacher(orgId: 13)), _me),
        isNull,
      );
      // Removed, someone added: that one.
      final removed = _lesson(1, d, teacher: _teacher(id: 0)).copyWithElements([
        ..._lesson(1, d, teacher: _teacher(id: 0)).elements,
        _teacher(id: 14, orgId: 0),
      ]);
      expect(substituteOf(removed, _me)!.id, 14);
      expect(substituteOf(_lesson(1, d, teacher: _teacher(id: 0)), _me)!.id, 0);
      expect(
        heldBySubstitute([_lesson(1, d, teacher: _teacher(id: _sub))], _me),
        isTrue,
      );
      expect(heldBySubstitute([], _me), isFalse);
    });
  });

  group('repository', () {
    late _PickyApi api;
    late InMemoryAccountRepository accounts;
    late AbsenceSummaryRepositoryImpl repo;
    late ClassRegisterRepositoryImpl register;
    final timetables = FakeTimetableRepository(weekBuilder: _week);

    setUp(() {
      api = _PickyApi();
      accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      repo = AbsenceSummaryRepositoryImpl(
        api: api,
        accounts: accounts,
        timetables: timetables,
        clock: () => _now,
      );
      register = ClassRegisterRepositoryImpl(
        api: api,
        accounts: accounts,
        timetables: timetables,
        clock: () => _now,
      );
    });

    Future<void> absent(int ttId, int student, {int minutes = 45}) async {
      final day = DateTime(
        ttId ~/ 100000,
        (ttId ~/ 1000) % 100,
        (ttId ~/ 10) % 100,
      );
      final start = DateTime(
        day.year,
        day.month,
        day.day,
        ttId % 10 == 1 ? 8 : 13,
      );
      await api.createAbsence(
        host: 'h',
        school: 's',
        auth: const UntisCredentials.user('u', 's'),
        ttId: ttId,
        studentId: student,
        start: start,
        end: start.add(Duration(minutes: minutes)),
      );
    }

    test('lesson scope', () async {
      final p = _lesson(202611101, DateTime(2026, 11, 10, 8));
      await absent(p.id, 501);
      final s = await repo.summary(teacherAccount(), [
        p,
      ], scope: AbsenceSummaryScope.lesson);
      expect(s.pupils, hasLength(FakeUntisApi.demoStudents.length));
      expect(s.pupils.first.name, 'Bauer Lena');
      expect(s.lessons, 1);
      expect(s.pupilsWithAbsences, 1);
      expect(s.lessonsLooked, 1);
    });

    test('subject scope: the course since the range start, substitute '
        'lessons included, other courses not', () async {
      await absent(202611101, 501); // Tue maths
      await absent(202611111, 501); // Wed maths, held by the substitute
      await absent(202611091, 502, minutes: 10); // Mon maths, late
      await absent(202611102, 501); // Tue German: other course
      await absent(202611121, 501); // Thu maths: after now
      final progress = <(int, int)>[];
      final s = await repo.summary(
        teacherAccount(),
        [_lesson(202611101, DateTime(2026, 11, 10, 8))],
        scope: AbsenceSummaryScope.subject,
        from: DateTime(2026, 11, 2),
        onProgress: (d, t) => progress.add((d, t)),
      );
      expect(s.from, DateTime(2026, 11, 2));
      expect(s.to, DateTime(2026, 11, 11));
      // Mon 2 – Fri 6, Mon 9 – Wed 11 (until 12:00): 8 maths lessons.
      expect(s.lessonsLooked, 8);
      final lena = s.pupils.firstWhere((p) => p.studentId == 501);
      expect(lena.lessons, 2);
      final jonas = s.pupils.firstWhere((p) => p.studentId == 502);
      expect((jonas.lessons, jonas.lateCount), (0, 1));
      expect(progress.last.$1, progress.last.$2);
      // Substituted lessons are asked for separately.
      expect(
        api.calls.any((c) => c.contains(202611111) && c.length == 2),
        isTrue,
      );
    });

    test('subject scope: a refused substitute lesson is skipped', () async {
      api.refused.addAll([202611041, 202611111]);
      await absent(202611101, 501);
      final s = await repo.summary(
        teacherAccount(),
        [_lesson(202611101, DateTime(2026, 11, 10, 8))],
        scope: AbsenceSummaryScope.subject,
        from: DateTime(2026, 11, 2),
      );
      expect(s.lessonsLooked, 6);
      expect(s.lessonsSkipped, 2);
      expect(s.lessons, 1);
    });

    test('subject scope: default range without school years', () async {
      final s = await repo.summary(teacherAccount(), [
        _lesson(202611101, DateTime(2026, 11, 10, 8)),
      ], scope: AbsenceSummaryScope.subject);
      expect(s.from, DateTime(2026, 9, 1));
      expect(s.truncated, isFalse);
    });

    test(
      'all subjects: class absence list, counted by the time grid',
      () async {
        final s = await repo.summary(
          teacherAccount(),
          [_lesson(202611101, DateTime(2026, 11, 10, 8))],
          scope: AbsenceSummaryScope.all,
          from: DateTime(2026, 11, 2),
          to: DateTime(2026, 11, 6),
        );
        expect(s.approximate, isTrue);
        expect(s.pupils, hasLength(FakeUntisApi.demoStudents.length));
        expect(s.lessons + s.lateCount, greaterThan(0));
        for (final p in s.pupils) {
          for (final a in p.absences) {
            expect(a.start.isBefore(DateTime(2026, 11, 7)), isTrue);
          }
        }
      },
    );

    test('all subjects of a whole class (no lesson): no period data', () async {
      final s = await repo.summary(
        teacherAccount(),
        [_lesson(0, DateTime(2026, 11, 10, 8))],
        scope: AbsenceSummaryScope.all,
        from: DateTime(2026, 11, 2),
        to: DateTime(2026, 11, 6),
      );
      expect(api.calls, isEmpty);
      expect(s.pupils, isNotEmpty);
    });

    test('errors: not a teacher, end before start', () async {
      final p = _lesson(1, DateTime(2026, 11, 10, 8));
      expect(
        () =>
            repo.summary(demoAccount(), [p], scope: AbsenceSummaryScope.lesson),
        throwsA(isA<UntisException>()),
      );
      expect(
        () => repo.summary(
          teacherAccount(),
          [p],
          scope: AbsenceSummaryScope.all,
          from: DateTime(2026, 11, 10),
          to: DateTime(2026, 11, 1),
        ),
        throwsA(isA<UntisException>()),
      );
    });

    test('class register: substituted lessons in the overview', () async {
      api.refused.add(202611041);
      final lessons = await register.lessons(teacherAccount(), days: 7);
      final wed = lessons.firstWhere((l) => l.period.id == 202611111);
      expect(wed.isSubstituted, isTrue);
      expect(wed.substitutedBy!.id, _sub);
      // Refused by the server: still listed, without data.
      final refused = lessons.firstWhere((l) => l.period.id == 202611041);
      expect(refused.registerMissing, isTrue);
      // Teacher 11 substituting for 13 (Thursday German): an own lesson.
      final thu = lessons.firstWhere((l) => l.period.id == 202611052);
      expect(thu.isSubstituted, isFalse);
      expect(ClassRegFilter.attendanceMissing.matchesLesson(wed), isFalse);
      expect(ClassRegFilter.topicMissing.matchesLesson(wed), isFalse);
      expect(ClassRegFilter.done.matchesLesson(wed), isFalse);
      expect(ClassRegFilter.all.matchesLesson(wed), isTrue);
    });

    test('class register: substitute lessons are read-only, own '
        'substitutions editable', () async {
      final wed = _week(
        const TimetableTarget(ElementType.teacher, _me),
        DateTime(2026, 11, 9),
      ).firstWhere((p) => p.id == 202611111);
      final data = await register.load(teacherAccount(), [wed]);
      expect(
        () => register.save(
          teacherAccount(),
          [wed],
          data,
          const ClassRegChanges(topic: 'x'),
        ),
        throwsA(isA<UntisException>()),
      );
      expect(
        () => register.createEvent(teacherAccount(), [
          wed,
        ], const NewClassRegEvent(text: 'x')),
        throwsA(isA<UntisException>()),
      );
      final thu = _lesson(
        202611052,
        DateTime(2026, 11, 12, 13),
        teacher: _teacher(orgId: 13),
      );
      await register.save(
        teacherAccount(),
        [thu],
        await register.load(teacherAccount(), [thu]),
        const ClassRegChanges(topic: 'Mine'),
      );
      expect(api.registerTopics[202611052], 'Mine');
    });

    test('previous topics include what a substitute entered', () async {
      api.registerTopics[202611111] = 'Substitute topic';
      api.registerTopics[202611101] = 'Own topic';
      final h = await register.courseHistory(teacherAccount(), [
        _lesson(202611121, DateTime(2026, 11, 12, 8)),
      ]);
      final sub = h.topics.firstWhere((l) => l.period.id == 202611111);
      expect(sub.register.topic, 'Substitute topic');
      expect(sub.substitutedBy!.id, _sub);
      // Refused: the own lessons still come.
      api.refused.add(202611111);
      final h2 = await register.courseHistory(teacherAccount(), [
        _lesson(202611121, DateTime(2026, 11, 12, 8)),
      ]);
      expect(h2.topics.map((l) => l.register.topic), contains('Own topic'));
      expect(h2.topics.any((l) => l.period.id == 202611111), isFalse);
    });
  });

  group('screens', () {
    late _PickyApi api;
    late InMemoryAccountRepository accounts;
    late ClassRegisterRepositoryImpl register;
    late AbsenceSummaryRepositoryImpl summaries;
    final timetables = FakeTimetableRepository(weekBuilder: _week);

    setUp(() {
      api = _PickyApi();
      accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      register = ClassRegisterRepositoryImpl(
        api: api,
        accounts: accounts,
        timetables: timetables,
        clock: () => _now,
      );
      summaries = AbsenceSummaryRepositoryImpl(
        api: api,
        accounts: accounts,
        timetables: timetables,
        clock: () => _now,
      );
    });

    Widget app(Widget home, {double textScale = 1}) => ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(accounts),
        activeAccountProvider.overrideWith(
          (ref) => Stream.value(teacherAccount()),
        ),
        classRegisterRepositoryProvider.overrideWithValue(register),
        absenceSummaryRepositoryProvider.overrideWithValue(summaries),
        classRegisterClockProvider.overrideWithValue(() => _now),
        nameResolverProvider.overrideWith((ref) => Stream.value(demoNames())),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 740),
            textScaler: TextScaler.linear(textScale),
          ),
          child: home,
        ),
      ),
    );

    testWidgets('read-only class register of a substitute lesson', (t) async {
      final wed = _lesson(
        202611111,
        DateTime(2026, 11, 11, 8),
        teacher: _teacher(id: _sub),
      );
      api.registerTopics[wed.id] = 'Worksheet';
      await t.pumpWidget(
        app(
          ClassRegisterScreen(
            account: teacherAccount(),
            periods: [wed],
            title: 'Maths',
            subtitle: 'Wed 11 Nov',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('classreg-substitute-note')),
        findsOneWidget,
      );
      expect(find.textContaining('Entered by substitute'), findsOneWidget);
      expect(find.byKey(const ValueKey('classreg-save')), findsNothing);
      final field = t.widget<TextField>(
        find.byKey(const ValueKey('classreg-topic')),
      );
      expect(field.readOnly, isTrue);
      expect(field.controller!.text, 'Worksheet');
      await t.tap(
        find.byKey(const ValueKey('classreg-student-501')),
        warnIfMissed: false,
      );
      await t.pump();
      expect(find.text('Absent'), findsNothing);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('classreg-new-entry')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final newEntry = t.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('classreg-new-entry')),
      );
      expect(newEntry.onPressed, isNull);
    });

    testWidgets('own substitution stays editable', (t) async {
      final thu = _lesson(
        202611052,
        DateTime(2026, 11, 12, 13),
        teacher: _teacher(orgId: 13),
      );
      await t.pumpWidget(
        app(
          ClassRegisterScreen(
            account: teacherAccount(),
            periods: [thu],
            title: 'German',
            subtitle: 'Thu 12 Nov',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('classreg-substitute-note')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('classreg-save')), findsOneWidget);
    });

    testWidgets('overview: substituted lesson is not missing', (t) async {
      api.registerTopics[202611111] = 'Worksheet';
      await t.pumpWidget(app(const ClassRegisterOverviewScreen()));
      await t.pumpAndSettle();
      final tile = find.byKey(const ValueKey('classreg-lesson-202611111'));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(
          of: tile,
          matching: find.textContaining('Substituted by'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.textContaining('Topic: Worksheet'),
        ),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('classreg-filter-topicMissing')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('classreg-lesson-202611111')),
        findsNothing,
      );
    });

    testWidgets('summary: per pupil, whole class, scopes, pupil list', (
      t,
    ) async {
      final p = _lesson(202611101, DateTime(2026, 11, 10, 8));
      await api.createAbsence(
        host: 'h',
        school: 's',
        auth: const UntisCredentials.user('u', 's'),
        ttId: p.id,
        studentId: 501,
        start: p.start,
        end: p.end,
      );
      await t.pumpWidget(
        app(
          AbsenceSummaryScreen(
            account: teacherAccount(),
            periods: [p],
            title: 'Maths',
          ),
        ),
      );
      await t.pumpAndSettle();
      final lena = find.byKey(const ValueKey('summary-pupil-501'));
      expect(lena, findsOneWidget);
      expect(
        find.descendant(of: lena, matching: find.text('1 lesson · 1 open')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('summary-pupil-502')),
          matching: find.text('No absences'),
        ),
        findsOneWidget,
      );
      await t.tap(lena);
      await t.pumpAndSettle();
      expect(find.textContaining('08:00 – 08:45'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('summary-group-klasse')));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('summary-class-lessons')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('summary-scope-subject')));
      await t.pumpAndSettle();
      expect(find.textContaining('Counted from'), findsOneWidget);
      expect(find.byKey(const ValueKey('summary-range')), findsOneWidget);
    });

    testWidgets('summary: error with retry', (t) async {
      final p = _lesson(202611101, DateTime(2026, 11, 10, 8));
      api.refused.add(p.id);
      await t.pumpWidget(
        app(
          AbsenceSummaryScreen(
            account: teacherAccount(),
            periods: [p],
            title: 'Maths',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('summary-error')), findsOneWidget);
      api.refused.clear();
      await t.tap(find.byKey(const ValueKey('summary-retry')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('summary-pupil-501')), findsOneWidget);
    });

    for (final scale in [2.0, 2.5]) {
      testWidgets('summary: large text ${scale * 100} % does not overflow', (
        t,
      ) async {
        t.view.physicalSize = const Size(360, 740) * t.view.devicePixelRatio;
        addTearDown(t.view.resetPhysicalSize);
        final p = _lesson(202611101, DateTime(2026, 11, 10, 8));
        await t.pumpWidget(
          app(
            AbsenceSummaryScreen(
              account: teacherAccount(),
              periods: [p],
              title: 'Mathematik',
              initialScope: AbsenceSummaryScope.subject,
            ),
            textScale: scale,
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        // Chips instead of a squeezed segmented button.
        expect(find.byType(SegmentedButton<AbsenceSummaryScope>), findsNothing);
        expect(find.byKey(const ValueKey('summary-scope-all')), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('summary-group-klasse')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
