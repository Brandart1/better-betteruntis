import 'package:better_betteruntis/core/class_register.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/data/class_register_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/classreg/class_register_screen.dart';
import 'package:better_betteruntis/ui/classreg/class_register_overview_screen.dart';
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
    expect(() => repo.lessons(demoAccount()), throwsA(isA<UntisException>()));
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

  test('lessons: today (upcoming too) and past, not cancelled', () async {
    final all = await repo.lessons(teacherAccount(), days: 7);
    final ids = all.map((l) => l.period.id).toList();
    // From Wed 4 Nov to the end of today (Wed 11 Nov): today's 13:00 lesson
    // is upcoming but included, Monday's 13:00 lessons are cancelled.
    expect(ids, contains(202611112));
    expect(ids, contains(202611111));
    expect(ids, isNot(contains(202611092)));
    expect(ids, isNot(contains(202611121)));
    expect(ids.first, 202611041);
    expect(ids.last, 202611112);
    // Oldest first.
    final starts = all.map((l) => l.period.start).toList();
    expect(starts, orderedEquals([...starts]..sort()));
    // The demo seeds a mix: done, attendance only, topic only, nothing.
    PeriodRegister reg(int id) =>
        all.firstWhere((l) => l.period.id == id).register;
    expect(reg(202611112).isIncomplete, isFalse); // % 4 == 0
    expect(reg(202611101).absenceChecked, isTrue); // % 4 == 1
    expect(reg(202611101).hasTopic, isFalse);
    expect(reg(202611102).absenceChecked, isFalse); // % 4 == 2
    expect(reg(202611102).hasTopic, isTrue);
    expect(reg(202611111).absenceChecked, isFalse); // % 4 == 3
    expect(reg(202611111).hasTopic, isFalse);
    // Saving shows up in the next load.
    final p = all.firstWhere((l) => l.period.id == 202611111).period;
    final data = await repo.load(teacherAccount(), [p]);
    await repo.save(
      teacherAccount(),
      [p],
      data,
      const ClassRegChanges(topic: 'Done'),
    );
    final again = await repo.lessons(teacherAccount(), days: 7);
    final r = again.firstWhere((l) => l.period.id == 202611111).register;
    expect(r.isIncomplete, isFalse);
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
      t.view.physicalSize = const Size(800, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
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

    Widget overview(Account account) => ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(accounts),
        activeAccountProvider.overrideWith((ref) => Stream.value(account)),
        classRegisterRepositoryProvider.overrideWithValue(repo),
        classRegisterClockProvider.overrideWithValue(() => now),
        nameResolverProvider.overrideWith((ref) => Stream.value(demoNames())),
      ],
      child: const MaterialApp(home: ClassRegisterOverviewScreen()),
    );
    Finder tile(int id) => find.byKey(ValueKey('classreg-lesson-$id'));

    testWidgets('class register overview: today, past, filters', (t) async {
      await t.pumpWidget(overview(teacherAccount()));
      await t.pumpAndSettle();
      expect(find.text('Class register'), findsOneWidget);
      // Today: in time order, the upcoming one included.
      expect(tile(202611111), findsOneWidget);
      expect(tile(202611112), findsOneWidget);
      expect(
        t.getTopLeft(tile(202611111)).dy,
        lessThan(t.getTopLeft(tile(202611112)).dy),
      );
      expect(find.textContaining('upcoming'), findsOneWidget);
      // Past: newest first, below today.
      expect(
        t.getTopLeft(find.byKey(const ValueKey('classreg-past'))).dy,
        greaterThan(t.getTopLeft(tile(202611112)).dy),
      );
      expect(
        t.getTopLeft(tile(202611102)).dy,
        lessThan(t.getTopLeft(tile(202611101)).dy),
      );
      // Filters.
      await t.tap(find.byKey(const ValueKey('classreg-filter-topicMissing')));
      await t.pumpAndSettle();
      expect(tile(202611101), findsOneWidget);
      expect(tile(202611102), findsNothing);
      expect(tile(202611112), findsNothing);
      await t.tap(
        find.byKey(const ValueKey('classreg-filter-attendanceMissing')),
      );
      await t.pumpAndSettle();
      expect(tile(202611102), findsOneWidget);
      expect(tile(202611101), findsNothing);
      await t.tap(find.byKey(const ValueKey('classreg-filter-done')));
      await t.pumpAndSettle();
      expect(tile(202611112), findsOneWidget);
      expect(tile(202611111), findsNothing);
      expect(find.text('No lessons today match "Done".'), findsNothing);
    });

    testWidgets('class register overview: refreshes after a lesson', (t) async {
      await t.pumpWidget(overview(teacherAccount()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('classreg-filter-topicMissing')));
      await t.pumpAndSettle();
      expect(tile(202611111), findsOneWidget);
      await t.tap(tile(202611111));
      await t.pumpAndSettle();
      expect(find.byType(ClassRegisterScreen), findsOneWidget);
      // Entered elsewhere (or by the screen) while it was open.
      api.registerTopics[202611111] = 'Fractions';
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(ClassRegisterOverviewScreen), findsOneWidget);
      expect(tile(202611111), findsNothing);
    });

    testWidgets('class register overview: very large text', (t) async {
      t.view.physicalSize = const Size(360, 740) * 3;
      t.view.devicePixelRatio = 3;
      t.platformDispatcher.textScaleFactorTestValue = 2.5;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpWidget(overview(teacherAccount()));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      // Decorative icons are dropped so the texts get the width.
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      await t.drag(find.byType(ListView), const Offset(0, -2000));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('class register overview: students get a hint', (t) async {
      await t.pumpWidget(overview(demoAccount()));
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
