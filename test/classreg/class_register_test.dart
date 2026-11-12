import 'package:better_betteruntis/core/class_register.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/data/class_register_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/classreg/class_register_screen.dart';
import 'package:better_betteruntis/ui/classreg/open_lessons_screen.dart';
import 'package:better_betteruntis/ui/timetable/lesson_details_sheet.dart';
import 'package:better_betteruntis/ui/timetable/lesson_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Account teacherAccount() {
  final d = demoAccount();
  return Account(
    id: 'teacher',
    school: d.school,
    username: 'teacher',
    anonymous: false,
    displayName: 'Demo Teacher',
    elementType: ElementType.teacher,
    elementId: FakeUntisApi.demoTeacherId,
  );
}

/// Wednesday 2026-11-11, 12:00.
final now = DateTime(2026, 11, 11, 12);

Period lesson(int id, DateTime start, {bool cancelled = false}) => Period(
  id: id,
  lessonId: 1,
  start: start,
  end: start.add(const Duration(minutes: 45)),
  elements: const [
    ElementRef(type: ElementType.klasse, id: 1, orgId: 1),
    ElementRef(type: ElementType.subject, id: 21, orgId: 21),
  ],
  flags: {cancelled ? PeriodFlag.cancelled : PeriodFlag.regular},
);

/// Two lessons per weekday at 08:00 and 13:00, ids yyyymmddN.
List<Period> week(TimetableTarget _, DateTime monday) => [
  for (var d = 0; d < 5; d++)
    for (final (n, h) in [(1, 8), (2, 13)])
      lesson(
        (monday.year * 10000 + monday.month * 100 + monday.day + d) * 10 + n,
        DateTime(monday.year, monday.month, monday.day + d, h),
        cancelled: d == 0 && n == 2,
      ),
];

void main() {
  late FakeUntisApi api;
  late InMemoryAccountRepository accounts;
  late ClassRegisterRepositoryImpl repo;

  setUp(() {
    api = FakeUntisApi(latency: Duration.zero);
    accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
    accounts.secrets['teacher'] = 'S';
    repo = ClassRegisterRepositoryImpl(
      api: api,
      accounts: accounts,
      timetables: FakeTimetableRepository(weekBuilder: week),
      clock: () => now,
    );
  });

  test('only teachers', () {
    expect(hasClassRegister(teacherAccount()), isTrue);
    expect(hasClassRegister(demoAccount()), isFalse);
    expect(
      () => repo.openLessons(demoAccount()),
      throwsA(isA<UntisException>()),
    );
  });

  test('save: absences, attendance check and topic for every period', () async {
    final a = teacherAccount();
    final ps = [
      lesson(11, DateTime(2026, 11, 10, 8)),
      lesson(12, DateTime(2026, 11, 10, 8, 50)),
    ];
    var data = await repo.load(a, ps);
    expect(data.students, hasLength(FakeUntisApi.demoStudents.length));
    await repo.save(
      a,
      ps,
      data,
      const ClassRegChanges(topic: 'Fractions', markAbsent: {501, 502}),
    );
    data = await repo.load(a, ps);
    for (final p in ps) {
      final r = data.periods[p.id]!;
      expect(r.absenceChecked, isTrue);
      expect(r.topic, 'Fractions');
      expect(r.absences.map((x) => x.studentId), unorderedEquals([501, 502]));
      expect(r.absences.first.start, p.start);
    }
    // Present again: deleted in both periods; unchanged topic is not resent.
    api.registerTopics.clear();
    await repo.save(a, ps, data, const ClassRegChanges(markPresent: {501}));
    data = await repo.load(a, ps);
    expect(data.periods[11]!.absences.map((x) => x.studentId), [502]);
    expect(data.periods[12]!.absences.map((x) => x.studentId), [502]);
    expect(api.registerTopics, isEmpty);
  });

  test('open lessons: past, not cancelled, incomplete, newest first', () async {
    final open = await repo.openLessons(teacherAccount(), days: 7);
    final ids = open.map((l) => l.period.id).toList();
    // From Wed 4 Nov to now (Wed 11 Nov 12:00): today's 13:00 is in the
    // future, Monday's 13:00 lessons are cancelled.
    expect(ids, isNot(contains(202611112)));
    expect(ids, isNot(contains(202611092)));
    // Today's 08:00 lesson (202611111) starts complete in the demo (id
    // divisible by 3), so yesterday's is the newest open one.
    expect(ids, isNot(contains(202611111)));
    expect(ids.first, 202611101);
    expect(open.every((l) => l.register.isIncomplete), isTrue);
    expect(
      open.every((l) => !l.period.start.isBefore(DateTime(2026, 11, 4))),
      isTrue,
    );
    // Ids divisible by 3 start complete in the demo.
    expect(ids.where((i) => i % 3 == 0), isEmpty);
    // Completing one removes it.
    final first = open.first;
    final data = await repo.load(teacherAccount(), [first.period]);
    await repo.save(
      teacherAccount(),
      [first.period],
      data,
      const ClassRegChanges(topic: 'Done'),
    );
    final again = await repo.openLessons(teacherAccount(), days: 7);
    expect(again.map((l) => l.period.id), isNot(contains(first.period.id)));
  });

  group('screens', () {
    Widget app(Widget home) => ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(accounts),
        classRegisterRepositoryProvider.overrideWithValue(repo),
        nameResolverProvider.overrideWith((ref) => Stream.value(demoNames())),
      ],
      child: MaterialApp(home: home),
    );

    testWidgets('class register: mark absent, enter topic, save', (t) async {
      final p = lesson(11, DateTime(2026, 11, 10, 8));
      await t.pumpWidget(
        app(
          ClassRegisterScreen(
            account: teacherAccount(),
            periods: [p],
            title: 'Maths',
            subtitle: 'Tue 10 Nov',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Bauer Lena'), findsOneWidget);
      expect(find.text('Not checked yet'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('classreg-student-501')));
      await t.pump();
      expect(find.text('Absent'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('classreg-topic')),
        'Algebra',
      );
      await t.tap(find.byKey(const ValueKey('classreg-save')));
      await t.pumpAndSettle();
      expect(api.registerTopics[11], 'Algebra');
      expect(api.registerChecked, contains(11));
      expect(api.registerAbsences[11]!.single.studentId, 501);
    });

    testWidgets('open lessons list', (t) async {
      final account = teacherAccount();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            accountRepositoryProvider.overrideWithValue(accounts),
            activeAccountProvider.overrideWith((ref) => Stream.value(account)),
            classRegisterRepositoryProvider.overrideWithValue(repo),
            nameResolverProvider.overrideWith(
              (ref) => Stream.value(demoNames()),
            ),
          ],
          child: const MaterialApp(home: OpenLessonsScreen()),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('open-lesson-202611101')),
        findsOneWidget,
      );
      expect(find.textContaining('Missing: attendance, topic'), findsWidgets);
    });

    testWidgets('open lessons: students get a hint, not a list', (t) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            activeAccountProvider.overrideWith(
              (ref) => Stream.value(demoAccount()),
            ),
            classRegisterRepositoryProvider.overrideWithValue(repo),
            nameResolverProvider.overrideWith(
              (ref) => Stream.value(demoNames()),
            ),
          ],
          child: const MaterialApp(home: OpenLessonsScreen()),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('Only teacher accounts have a class register.'),
        findsOneWidget,
      );
    });

    testWidgets('lesson sheet: button only with a class register', (t) async {
      final block = LessonBlock([lesson(11, DateTime(2026, 11, 10, 8))]);
      LessonBlock? opened;
      Future<void> pump(ValueChanged<LessonBlock>? cb) => t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: LessonDetailsSheet(
                blocks: [block],
                names: demoNames(),
                onOpenClassRegister: cb,
              ),
            ),
          ),
        ),
      );
      await pump(null);
      expect(find.byKey(const ValueKey('details-classreg')), findsNothing);
      await pump((b) => opened = b);
      await t.tap(find.byKey(const ValueKey('details-classreg')));
      expect(opened, same(block));
    });
  });
}
