import 'package:better_betteruntis/core/class_register.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/data/class_register_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/classreg/class_register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'class_register_test.dart' show lesson, now, teacherAccount, week;

void main() {
  late FakeUntisApi api;
  late InMemoryAccountRepository accounts;
  late FakeTimetableRepository timetables;
  late ClassRegisterRepositoryImpl repo;

  setUp(() {
    api = FakeUntisApi(latency: Duration.zero);
    accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
    accounts.secrets['teacher'] = 'S';
    timetables = FakeTimetableRepository(weekBuilder: week);
    repo = ClassRegisterRepositoryImpl(
      api: api,
      accounts: accounts,
      timetables: timetables,
      clock: () => now,
    );
  });

  // Tue 10 Nov 2026, a double lesson 08:00 / 08:50 (ids like week()).
  List<Period> block() => [
    lesson(202611101, DateTime(2026, 11, 10, 8)),
    lesson(202611103, DateTime(2026, 11, 10, 8, 50)),
  ];

  Homework draft({int id = 0, String text = ' Page 12 ', DateTime? due}) =>
      Homework(
        id: id,
        lessonId: 0,
        startDate: DateTime(2026, 1, 1),
        endDate: due ?? DateTime(2026, 11, 11),
        text: text,
        remark: ' Check ',
      );

  test('save: given in the first period, lesson and date from it', () async {
    final a = teacherAccount();
    final refreshes = timetables.refreshCount;
    final saved = await repo.saveHomework(a, block(), draft());
    final call = api.submitHomeworkCalls.single;
    expect(call.ttId, 202611101);
    expect(call.homework.id, 0);
    expect(call.homework.lessonId, 1);
    expect(call.homework.startDate, DateTime(2026, 11, 10));
    expect(call.homework.endDate, DateTime(2026, 11, 11));
    expect(call.homework.text, 'Page 12');
    expect(call.homework.remark, 'Check');
    expect(saved.id, greaterThan(0));
    // The own timetable week is refreshed so the lesson shows it.
    expect(timetables.refreshCount, greaterThan(refreshes));

    var list = await repo.homework(a, block());
    expect(list.single.id, saved.id);
    expect(list.single.text, 'Page 12');

    // Editing keeps the id and creates nothing new.
    await repo.saveHomework(
      a,
      block(),
      saved.copyWith(text: 'Page 13', completed: true),
    );
    expect(api.submitHomeworkCalls.last.homework.id, saved.id);
    list = await repo.homework(a, block());
    expect(list.single.text, 'Page 13');
    expect(list.single.completed, isTrue);
    expect(api.submittedHomework, hasLength(1));

    // Another lesson of the course (next day) did not give it.
    final other = [lesson(202611111, DateTime(2026, 11, 11, 8))];
    expect(await repo.homework(a, other), isEmpty);
  });

  test('save: refused without text, due before the lesson, substitute', () {
    final a = teacherAccount();
    expect(
      repo.saveHomework(a, block(), draft(text: '  ')),
      throwsA(isA<UntisException>()),
    );
    expect(
      repo.saveHomework(a, block(), draft(due: DateTime(2026, 11, 9))),
      throwsA(isA<UntisException>()),
    );
    final substituted = Period(
      id: 202611101,
      lessonId: 1,
      start: DateTime(2026, 11, 10, 8),
      end: DateTime(2026, 11, 10, 8, 45),
      elements: const [
        ElementRef(type: ElementType.klasse, id: 1, orgId: 1),
        ElementRef(
          type: ElementType.teacher,
          id: 12,
          orgId: FakeUntisApi.demoTeacherId,
        ),
      ],
      flags: const {PeriodFlag.irregular},
    );
    expect(
      () => repo.saveHomework(a, [substituted], draft()),
      throwsA(isA<UntisException>()),
    );
    expect(api.submitHomeworkCalls, isEmpty);
  });

  test('next lesson of the course: a later day, over weekends', () async {
    final a = teacherAccount();
    expect(await repo.nextLessonDay(a, block()), DateTime(2026, 11, 11));
    // Friday's lessons: the next one is Monday's (its 13:00 is cancelled,
    // 08:00 is not).
    expect(
      await repo.nextLessonDay(a, [
        lesson(202611132, DateTime(2026, 11, 13, 13)),
      ]),
      DateTime(2026, 11, 16),
    );
  });

  testWidgets('screen: add homework, due the next lesson by default', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(accounts),
          classRegisterRepositoryProvider.overrideWithValue(repo),
          nameResolverProvider.overrideWith((ref) => Stream.value(demoNames())),
        ],
        child: MaterialApp(
          home: ClassRegisterScreen(
            account: teacherAccount(),
            periods: block(),
            title: 'Maths',
            subtitle: 'Tue 10 Nov',
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('No homework given in this lesson.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('classreg-new-homework')));
    await t.pumpAndSettle();
    expect(find.text('New homework'), findsOneWidget);
    expect(
      find.text('Wed 11 Nov (next lesson of this course)'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('homework-no-delete')), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('homework-text')),
      'Worksheet 3',
    );
    await t.enterText(
      find.byKey(const ValueKey('homework-remark')),
      'Collect on Friday',
    );
    await t.tap(find.byKey(const ValueKey('homework-save')));
    await t.pumpAndSettle();
    final call = api.submitHomeworkCalls.single;
    expect(call.ttId, 202611101);
    expect(call.homework.text, 'Worksheet 3');
    expect(call.homework.remark, 'Collect on Friday');
    expect(call.homework.endDate, DateTime(2026, 11, 11));
    expect(call.homework.completed, isFalse);
    // Back on the class register screen, listed.
    expect(find.text('Homework saved'), findsOneWidget);
    expect(find.text('Worksheet 3'), findsOneWidget);
    expect(
      find.text('Due Wed 11 Nov\nRemark: Collect on Friday'),
      findsOneWidget,
    );

    // Edit: mark as done.
    await t.tap(find.text('Worksheet 3'));
    await t.pumpAndSettle();
    expect(find.text('Edit homework'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('homework-done')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('homework-save')));
    await t.pumpAndSettle();
    expect(api.submitHomeworkCalls, hasLength(2));
    expect(api.submitHomeworkCalls.last.homework.completed, isTrue);
    expect(
      api.submitHomeworkCalls.last.homework.id,
      api.submittedHomework.keys.single,
    );
    expect(find.textContaining('Due Wed 11 Nov · done'), findsOneWidget);
  });
}
