import 'package:better_betteruntis/core/absence_stats.dart';
import 'package:better_betteruntis/core/info.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/dev/fake_info.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/infocenter/absences_tab.dart';
import 'package:better_betteruntis/ui/infocenter/info_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const maths = 21, german = 22;

Period lesson(
  int id,
  DateTime start, {
  int subject = maths,
  bool cancelled = false,
}) => Period(
  id: id,
  lessonId: subject,
  start: start,
  end: start.add(const Duration(minutes: 50)),
  elements: [
    ElementRef(type: ElementType.subject, id: subject, orgId: subject),
  ],
  flags: {cancelled ? PeriodFlag.cancelled : PeriodFlag.regular},
);

/// Mon–Fri: maths 8:00 and 9:00, German 10:00 (cancelled on Wednesdays).
List<Period> week(TimetableTarget _, DateTime monday) => [
  for (var d = 0; d < 5; d++) ...[
    for (final (n, h, s) in [(1, 8, maths), (2, 9, maths), (3, 10, german)])
      lesson(
        (monday.month * 100 + monday.day + d) * 10 + n,
        DateTime(monday.year, monday.month, monday.day + d, h),
        subject: s,
        cancelled: d == 2 && n == 3,
      ),
  ],
];

AbsenceItem absence(
  int id,
  DateTime start,
  DateTime end, {
  bool excused = true,
}) => AbsenceItem(id: id, start: start, end: end, excused: excused);

void main() {
  // Monday 2026-11-09.
  final mon = DateTime(2026, 11, 9);
  DateTime at(int day, int h, [int m = 0]) =>
      DateTime(mon.year, mon.month, mon.day + day, h, m);
  final lessons = week(const TimetableTarget(ElementType.klasse, 1), mon);

  group('whole day or partial', () {
    test('every lesson of the day: whole day', () {
      final c = dayCoverage(absence(1, at(1, 7, 45), at(1, 11)), lessons)!;
      expect(c.wholeDay, isTrue);
      expect((c.covered, c.lessons), (3, 3));
    });

    test('a cancelled lesson doesn\'t count', () {
      // Wednesday: German at 10:00 is cancelled.
      final c = dayCoverage(absence(1, at(2, 8), at(2, 9, 50)), lessons)!;
      expect(c.wholeDay, isTrue);
      expect(c.lessons, 2);
    });

    test('late arrival: partial, one lesson affected', () {
      final c = dayCoverage(absence(1, at(1, 8), at(1, 8, 20)), lessons)!;
      expect(c.wholeDay, isFalse);
      expect((c.covered, c.affected, c.lessons), (0, 1, 3));
    });

    test('over several days: whole only if every day is covered', () {
      expect(
        dayCoverage(absence(1, at(0, 7), at(1, 12)), lessons)!.wholeDay,
        isTrue,
      );
      final c = dayCoverage(absence(1, at(0, 7), at(1, 9)), lessons)!;
      expect(c.wholeDay, isFalse);
      expect((c.covered, c.lessons), (4, 6));
    });

    test('no lessons that day: unknown', () {
      expect(dayCoverage(absence(1, at(5, 8), at(5, 12)), lessons), isNull);
    });
  });

  group('attendance by subject', () {
    test('lessons so far, missed ones and attended time', () {
      final stats = attendanceBySubject(
        lessons,
        [
          absence(1, at(1, 7, 45), at(1, 11)), // Tue: all three
          absence(2, at(3, 8), at(3, 8, 25), excused: false), // Thu: late
        ],
        at(4, 0), // Friday morning: Mon–Thu are over.
      );
      final m = stats.firstWhere((s) => s.subjectId == maths);
      final g = stats.firstWhere((s) => s.subjectId == german);
      expect((m.lessons, m.missed, m.missedUnexcused), (8, 3, 1));
      expect(m.absentMinutes, 50 + 50 + 25);
      expect(m.attendancePercent, closeTo(100 * (400 - 125) / 400, 0.001));
      // Wednesday's German lesson was cancelled.
      expect((g.lessons, g.missed), (3, 1));
      expect(g.attendancePercent, closeTo(100 * 100 / 150, 0.001));
      // Worst attendance first.
      expect(stats.first.subjectId, german);
    });

    test('overlapping absences count a lesson\'s time once', () {
      final stats = attendanceBySubject(
        [lesson(1, at(0, 8))],
        [absence(1, at(0, 8), at(0, 9)), absence(2, at(0, 8), at(0, 8, 30))],
        at(1, 0),
      );
      expect(stats.single.attendancePercent, 0);
    });

    test('mondays of a range', () {
      expect(mondaysBetween(at(2, 10), at(8, 0)), [mon, at(7, 0)]);
    });
  });

  group('screens', () {
    final now = DateTime.now();
    final thisMonday = DateTime(
      now.year,
      now.month,
      now.day - (now.weekday - 1),
    );
    final base = DateTime(
      thisMonday.year,
      thisMonday.month,
      thisMonday.day - 14,
    );
    DateTime on(int day, int h, [int m = 0]) =>
        DateTime(base.year, base.month, base.day + day, h, m);
    final items = [
      absence(1, on(1, 7, 45), on(1, 11)),
      absence(2, on(3, 8), on(3, 8, 20), excused: false),
    ];

    Future<FakeTimetableRepository> pump(
      WidgetTester tester,
      Widget child,
    ) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final timetables = FakeTimetableRepository(weekBuilder: week);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            infoCenterRepositoryProvider.overrideWithValue(
              FakeInfoCenterRepository(absences: items),
            ),
            timetableRepositoryProvider.overrideWithValue(timetables),
            nameResolverProvider.overrideWith(
              (ref) => Stream<NameResolver>.value(
                FakeNameResolver(
                  elements: const [
                    MasterElement(
                      type: ElementType.subject,
                      id: maths,
                      name: 'M',
                      longName: 'Mathematik',
                    ),
                    MasterElement(
                      type: ElementType.subject,
                      id: german,
                      name: 'D',
                      longName: 'Deutsch',
                    ),
                  ],
                ),
              ),
            ),
            absenceFilterProvider.overrideWith(
              () =>
                  SessionValue(const AbsenceFilter(range: AbsenceRange.days30)),
            ),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        ),
      );
      await tester.pumpAndSettle();
      return timetables;
    }

    testWidgets('absences show whole day or partial', (tester) async {
      final timetables = await pump(
        tester,
        AbsencesTab(account: demoAccount()),
      );
      expect(find.byKey(const ValueKey('absence-1-whole')), findsOneWidget);
      expect(find.text('Whole day'), findsOneWidget);
      expect(find.byKey(const ValueKey('absence-2-partial')), findsOneWidget);
      expect(find.text('Partial · 1 of 3 lessons'), findsOneWidget);
      // Only the week with the absences is loaded.
      expect(timetables.weekRequests, [base]);
    });

    testWidgets('by subject: attendance per subject', (tester) async {
      await pump(tester, AbsencesTab(account: demoAccount()));
      await tester.tap(find.byKey(const ValueKey('absences-by-subject')));
      await tester.pumpAndSettle();
      expect(find.text('Absences by subject'), findsOneWidget);
      expect(find.text('Mathematik'), findsOneWidget);
      expect(find.text('Deutsch'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('absences-subject-total')),
        findsOneWidget,
      );
      expect(find.textContaining('Missed 3 of'), findsOneWidget); // maths
      expect(find.textContaining('1 unexcused'), findsOneWidget);
      expect(find.textContaining('Missed 1 of'), findsOneWidget); // German
    });

    testWidgets('by subject: no timetable, a message instead', (tester) async {
      final t = await pump(tester, AbsencesTab(account: demoAccount()));
      t.refreshError = const UntisException(0, 'offline');
      await tester.tap(find.byKey(const ValueKey('absences-by-subject')));
      await tester.pumpAndSettle();
      expect(find.text('Could not load the timetable'), findsOneWidget);
    });
  });
}
