// Teacher timetable wishes of 2026-11-16: colleagues' lessons of the own
// classes and subjects (faded, read-only), supervisions before the first
// lesson, colours for supervisions and room bookings, no exams in
// supervisions / lessons without a class. Tested against the demo API
// through RoutingUntisApi, like the real app.
import 'package:better_betteruntis/app/routing_api.dart';
import 'package:better_betteruntis/core/colleague_lessons.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/data/account_repository_impl.dart';
import 'package:better_betteruntis/data/name_resolver_impl.dart';
import 'package:better_betteruntis/data/secret_store.dart';
import 'package:better_betteruntis/data/teacher_tools_repository_impl.dart';
import 'package:better_betteruntis/data/timetable_repository_impl.dart'
    show TimetableRepositoryImpl;
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/settings/lesson_preview.dart';
import 'package:better_betteruntis/ui/settings/timetable_settings_screen.dart';
import 'package:better_betteruntis/ui/timetable/lesson_card.dart';
import 'package:better_betteruntis/ui/timetable/lesson_layout.dart';
import 'package:better_betteruntis/ui/timetable/lesson_style.dart';
import 'package:better_betteruntis/ui/timetable/timetable_canvas.dart';
import 'package:better_betteruntis/ui/timetable/timetable_screen.dart';
import 'package:better_betteruntis/ui/timetable/timetable_utils.dart';
import 'package:better_betteruntis/ui/timetable/viewing_target.dart';
import 'package:better_betteruntis/ui/timetable/week_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../data/fixtures.dart' show memoryDb;

const me = FakeUntisApi.demoTeacherId;
const creds = UntisCredentials.user('teacher', 'S');

Account teacherAccount() {
  final d = demoAccount();
  return Account(
    id: 'teacher',
    school: d.school, // demo.invalid: RoutingUntisApi sends it to the demo
    username: 'teacher',
    anonymous: false,
    displayName: 'Demo Teacher',
    elementType: ElementType.teacher,
    elementId: me,
  );
}

NameResolver demoSchoolNames() => NameResolverImpl(
  elements: FakeUntisApi.demoMasterData.elements,
  timeGrid: FakeUntisApi.demoMasterData.timeGrid,
);

ElementRef el(ElementType t, int id, [int? orgId]) =>
    ElementRef(type: t, id: id, orgId: orgId ?? id);

/// The demo API; class timetables can be made to fail.
class TestApi extends FakeUntisApi {
  TestApi() : super(latency: Duration.zero);

  bool failClasses = false;
  final requested = <TimetableTarget>[];

  @override
  Future<TimetableResponse> timetable({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
    required int masterDataTimestamp,
  }) {
    requested.add(target);
    if (failClasses && target.type == ElementType.klasse) {
      return Future.error(const UntisException(-8509, 'No right'));
    }
    return super.timetable(
      host: host,
      school: school,
      auth: auth,
      target: target,
      start: start,
      end: end,
      masterDataTimestamp: masterDataTimestamp,
    );
  }
}

/// Weeks straight from [api] (no database), for widget tests.
class ApiTimetables implements TimetableRepository {
  ApiTimetables(this.api);
  final UntisApi api;

  @override
  Stream<List<Period>> watchWeek(
    Account account,
    TimetableTarget target,
    DateTime weekStart,
  ) => Stream.fromFuture(
    api
        .timetable(
          host: account.host,
          school: account.school.loginName,
          auth: creds,
          target: target,
          start: weekStart,
          end: addDays(weekStart, 6),
          masterDataTimestamp: 0,
        )
        .then((r) => r.periods),
  );

  @override
  Future<void> refresh(Account a, TimetableTarget t, DateTime w) async {}

  @override
  Stream<NameResolver> watchNames(Account account) =>
      Stream.value(demoSchoolNames());

  @override
  DateTime? lastRefreshed(Account a, TimetableTarget t, DateTime w) => null;

  @override
  Future<void> discoverTeachers(
    Account account,
    DateTime weekStart, {
    void Function(int done, int total)? onProgress,
  }) async {}
}

Future<List<Period>> demoWeek(
  FakeUntisApi api,
  TimetableTarget target,
  DateTime monday,
) async => (await api.timetable(
  host: 'demo.invalid',
  school: 'demo',
  auth: creds,
  target: target,
  start: monday,
  end: addDays(monday, 6),
  masterDataTimestamp: 0,
)).periods;

const ownTarget = TimetableTarget(ElementType.teacher, me);
const classTarget = TimetableTarget(ElementType.klasse, 1);

void main() {
  final monday = DateTime(2026, 11, 16);
  DateTime day(int weekday) => addDays(monday, weekday - 1);

  group('colleague lessons (pure)', () {
    test('assignments: planned lessons of the teacher, not ones they '
        'substitute in', () async {
      final api = FakeUntisApi(latency: Duration.zero);
      final own = await demoWeek(api, ownTarget, monday);
      final a = teachingAssignments(own, me);
      expect(a, {(1, 21), (1, 24)});

      final substituteIn = Period(
        id: 1,
        lessonId: 1,
        start: DateTime(2026, 11, 16, 8),
        end: DateTime(2026, 11, 16, 9),
        elements: [
          el(ElementType.klasse, 2),
          el(ElementType.teacher, me, 99),
          el(ElementType.subject, 22),
        ],
        flags: const {PeriodFlag.irregular},
      );
      expect(teachingAssignments([substituteIn], me), isEmpty);
    });

    test('class week: only other teachers\' lessons of assigned subjects, '
        'once', () async {
      final api = FakeUntisApi(latency: Duration.zero);
      final own = await demoWeek(api, ownTarget, monday);
      final cls = await demoWeek(api, classTarget, monday);
      final seen = {for (final p in own) p.id};
      final found = colleagueLessons(
        cls,
        teachingAssignments(own, me),
        me,
        seen,
      );
      expect(
        [for (final p in found) p.id],
        [FakeUntisApi.demoPeriodId(day(4), 5)],
      );
      expect(found.single.ofType(ElementType.teacher).single.id, 13);
      // Already seen: not again.
      expect(
        colleagueLessons(cls, teachingAssignments(own, me), me, seen),
        isEmpty,
      );
      expect(isColleagueLesson(found.single, me), isTrue);
      expect(teachesLesson(found.single, me), isFalse);
    });

    test('a lesson a substitute holds is not a colleague lesson', () async {
      final api = FakeUntisApi(latency: Duration.zero);
      final own = await demoWeek(api, ownTarget, monday);
      final held = own.firstWhere(
        (p) => p.id == FakeUntisApi.demoPeriodId(day(3), 1),
      );
      expect(teachesLesson(held, me), isFalse);
      expect(isColleagueLesson(held, me), isFalse);
    });
  });

  group('exams need a class', () {
    test('supervision, room booking and Aufsichtsstunde: no exam', () async {
      final api = FakeUntisApi(latency: Duration.zero);
      final own = await demoWeek(api, ownTarget, monday);
      Period byId(DateTime d, int unit) =>
          own.firstWhere((p) => p.id == FakeUntisApi.demoPeriodId(d, unit));
      final supervision = byId(day(1), 7);
      final booking = byId(day(2), 6);
      final onCall = byId(day(5), 8);
      expect(supervision.isBreakSupervision, isTrue);
      expect(booking.isRoomBooking, isTrue);
      expect(onCall.isRoomBooking, isFalse, reason: 'no room');
      for (final p in [supervision, booking, onCall]) {
        expect(p.canHoldExam, isFalse);
      }
      expect(byId(day(1), 2).canHoldExam, isTrue);
      // A lesson whose class is missing from the data is no room booking.
      final noClass = Period(
        id: 5,
        lessonId: 5,
        start: DateTime(2026, 11, 16, 8),
        end: DateTime(2026, 11, 16, 9),
        elements: [
          el(ElementType.subject, 21),
          el(ElementType.teacher, me),
          el(ElementType.room, 31),
        ],
        flags: const {PeriodFlag.regular},
      );
      expect(noClass.isRoomBooking, isFalse);
      expect(noClass.canHoldExam, isFalse);
    });

    test('exam editor defaults: lessonsOn and courses skip them', () async {
      final api = RoutingUntisApi(
        real: FakeUntisApi(latency: Duration.zero),
        demo: FakeUntisApi(latency: Duration.zero),
      );
      final accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      final repo = TeacherToolsRepositoryImpl(
        api: api,
        accounts: accounts,
        timetables: ApiTimetables(api),
        clock: () => DateTime(2026, 11, 16, 7),
      );
      final mon = await repo.lessonsOn(teacherAccount(), day(1));
      expect(mon.any((p) => p.isBreakSupervision), isFalse);
      expect(mon, isNotEmpty);
      final fri = await repo.lessonsOn(teacherAccount(), day(5));
      expect(fri.any((p) => !p.hasClass), isFalse);
      final tue = await repo.lessonsOn(teacherAccount(), day(2));
      expect(tue.any((p) => p.isRoomBooking), isFalse);
      final courses = await repo.courses(teacherAccount());
      expect(
        courses.subjectIds,
        isNot(contains(FakeUntisApi.demoOnCallSubjectId)),
      );
    });
  });

  group('grid range', () {
    final grid = FakeUntisApi.demoMasterData.timeGrid!;

    test('starts at a supervision before the first unit, ends after the '
        'last period', () {
      final early = Period(
        id: 1,
        lessonId: 0,
        start: DateTime(2026, 11, 16, 7, 40),
        end: DateTime(2026, 11, 16, 7, 50),
        elements: [el(ElementType.teacher, me)],
        flags: const {PeriodFlag.breakSupervision},
      );
      final late = Period(
        id: 2,
        lessonId: 0,
        start: DateTime(2026, 11, 17, 16, 0),
        end: DateTime(2026, 11, 17, 17, 15),
        elements: [el(ElementType.teacher, me)],
        flags: const {PeriodFlag.regular},
      );
      final (start, end) = TimeScale.rangeFor(
        grid,
        [1, 2, 3, 4, 5],
        [early, late],
      );
      expect(start, 7 * 60 + 40);
      expect(end, 17 * 60 + 15);
      // Without them: the time grid.
      expect(TimeScale.rangeFor(grid, [1, 2, 3, 4, 5], const []), (
        8 * 60,
        8 * 60 + 5 * 50 + 45,
      ));
    });

    test(
      'week model and day view of the demo teacher start at 07:40',
      () async {
        final api = FakeUntisApi(latency: Duration.zero);
        final own = await demoWeek(api, ownTarget, monday);
        final model = WeekModel.build(monday, own, demoSchoolNames());
        expect(model.startMinute, 7 * 60 + 40);
        final (dayStart, _) = TimeScale.rangeFor(
          grid,
          [1],
          [
            for (final p in own)
              if (sameDay(p.start, day(1))) p,
          ],
        );
        expect(dayStart, 7 * 60 + 40);
      },
    );

    testWidgets('supervisions before the first unit show completely, also '
        'two with the same id', (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Period supervision(DateTime d) => Period(
        id: 777, // same id on both days
        lessonId: 0,
        start: DateTime(d.year, d.month, d.day, 7, 40),
        end: DateTime(d.year, d.month, d.day, 7, 50),
        elements: [el(ElementType.teacher, me)],
        flags: const {PeriodFlag.breakSupervision},
        lessonText: 'Gangaufsicht',
      );
      final periods = [supervision(day(1)), supervision(day(4))];
      final model = WeekModel.build(monday, periods, demoSchoolNames());
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WeekGrid(model: model, names: demoSchoolNames()),
            ),
          ),
        ),
      );
      await tester.pump();
      final cards = find.byType(LessonCard);
      expect(cards, findsNWidgets(2));
      final canvas = tester.getRect(find.byType(TimetableCanvas));
      for (final e in cards.evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        expect(r.top, greaterThanOrEqualTo(canvas.top));
        expect(r.bottom, lessThanOrEqualTo(canvas.bottom));
        expect(r.height, greaterThan(4));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('lesson style', () {
    final cs = ColorScheme.fromSeed(seedColor: Colors.indigo);
    final dark = ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: Brightness.dark,
    );
    LessonBlock block(List<ElementRef> elements, Set<PeriodFlag> flags) =>
        LessonBlock([
          Period(
            id: 1,
            lessonId: 1,
            start: DateTime(2026, 11, 16, 8),
            end: DateTime(2026, 11, 16, 9),
            elements: elements,
            flags: flags,
          ),
        ]);
    final supervision = block(
      [el(ElementType.teacher, me)],
      {PeriodFlag.breakSupervision},
    );
    final booking = block(
      [el(ElementType.teacher, me), el(ElementType.room, 34)],
      {PeriodFlag.irregular},
    );
    final lesson = block(
      [
        el(ElementType.klasse, 1),
        el(ElementType.teacher, me),
        el(ElementType.subject, 21),
        el(ElementType.room, 31),
      ],
      {PeriodFlag.regular},
    );

    test(
      'defaults: own colours in light and dark, not the substitution one',
      () {
        for (final scheme in [cs, dark]) {
          final s = LessonStyle.of(scheme, supervision);
          expect(s.background, supervisionDefaults(scheme).$1);
          expect(s.foreground, supervisionDefaults(scheme).$2);
          final b = LessonStyle.of(scheme, booking);
          expect(b.background, scheme.secondaryContainer);
          expect(b.background, isNot(scheme.tertiaryContainer));
          expect(
            LessonStyle.of(scheme, lesson).background,
            scheme.primaryContainer,
          );
        }
        expect(supervisionDefaults(cs).$1, isNot(supervisionDefaults(dark).$1));
      },
    );

    test('custom colours and border mode', () {
      const settings = TimetableSettings(
        supervisionColor: 0xFF00897B,
        roomBookingColor: 0xFF6D4C41,
        roomBookingMode: StateColorMode.border,
      );
      expect(
        LessonStyle.of(cs, supervision, settings).background,
        const Color(0xFF00897B),
      );
      final b = LessonStyle.of(cs, booking, settings);
      expect(b.border, const Color(0xFF6D4C41));
      expect(b.borderWidth, LessonStyle.stateBorderWidth);
      expect(b.background, cs.primaryContainer);
    });

    test('settings: JSON round-trip of the new fields', () {
      const s = TimetableSettings(
        supervisionColor: 0xFF00897B,
        roomBookingColor: 0xFF6D4C41,
        supervisionMode: StateColorMode.border,
        showColleagueLessons: false,
      );
      expect(TimetableSettings.fromJson(s.toJson()), s);
      expect(const TimetableSettings().showColleagueLessons, isTrue);
      expect(s, isNot(const TimetableSettings()));
    });

    test('not own: much weaker than the lesson, outlined', () {
      final normal = LessonStyle.of(cs, lesson);
      final faded = normal.notOwn(cs.surface);
      expect(faded.border, isNotNull);
      double dist(Color a, Color b) =>
          (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
      expect(
        dist(faded.background, cs.surface),
        lessThan(dist(normal.background, cs.surface) * 0.4),
      );
      // Weaker than a past lesson.
      final past = normal.dimmed(cs.surface);
      expect(
        dist(faded.background, cs.surface),
        lessThan(dist(past.background, cs.surface)),
      );
    });
  });

  group('timetable screen (demo teacher through RoutingUntisApi)', () {
    late TestApi fake;
    late InMemoryAccountRepository accounts;
    late MemorySettingsStore store;

    setUp(() {
      fake = TestApi();
      accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      store = MemorySettingsStore();
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = RoutingUntisApi(real: FakeUntisApi(), demo: fake);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timetableRepositoryProvider.overrideWithValue(ApiTimetables(api)),
            accountRepositoryProvider.overrideWithValue(accounts),
            settingsStoreProvider.overrideWithValue(store),
            nameResolverProvider.overrideWith(
              (ref) => Stream.value(demoSchoolNames()),
            ),
          ],
          child: const MaterialApp(home: TimetableScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    final thisMonday = mondayOf(DateTime.now());
    DateTime weekDay(int wd) => addDays(thisMonday, wd - 1);
    Finder card(DateTime d, int unit) =>
        find.byKey(ValueKey('lesson-${FakeUntisApi.demoPeriodId(d, unit)}'));

    BorderSide borderOf(WidgetTester tester, Finder f) {
      final m = tester.widget<Material>(
        find.descendant(of: f, matching: find.byType(Material)).first,
      );
      return (m.shape! as RoundedRectangleBorder).side;
    }

    bool notOwnCard(WidgetTester tester, Finder f) {
      final e = tester.element(
        find.descendant(of: f, matching: find.byType(LessonCard)),
      );
      final w = e.widget as LessonCard;
      return !teachesLesson(w.block.first, ViewingTarget.ownTeacherOf(e)!);
    }

    testWidgets('colleague lesson shows faded, after the own week, with one '
        'class request', (tester) async {
      await pump(tester);
      final colleague = card(weekDay(4), 5);
      expect(colleague, findsOneWidget);
      expect(notOwnCard(tester, colleague), isTrue);
      expect(borderOf(tester, colleague).width, 1.5);
      // Own maths lesson: normal, no outline.
      final own = card(weekDay(4), 0);
      expect(notOwnCard(tester, own), isFalse);
      // A lesson a substitute holds: faded the same way.
      final held = card(weekDay(3), 1);
      expect(notOwnCard(tester, held), isTrue);
      expect(borderOf(tester, held).width, 1.5);
      // Own week first, then the one assigned class.
      expect(fake.requested.first, ownTarget);
      expect(
        fake.requested.where((t) => t.type == ElementType.klasse).toSet(),
        {classTarget},
      );
    });

    testWidgets('colleague lesson opens read-only, says who teaches it', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(card(weekDay(4), 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('details-not-own')), findsOneWidget);
      expect(find.textContaining('Lea Weber teaches'), findsOneWidget);
      for (final k in [
        'details-classreg',
        'details-book-room',
        'lesson-exam-create',
        'lesson-info-edit',
      ]) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
    });

    testWidgets('lesson a substitute holds keeps the class register', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(card(weekDay(3), 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('details-not-own')), findsOneWidget);
      expect(find.textContaining('instead of you'), findsOneWidget);
      expect(find.byKey(const ValueKey('details-classreg')), findsOneWidget);
    });

    testWidgets('supervision at 07:40 shows; no exam, no class register in '
        'supervision, room booking, Aufsichtsstunde', (tester) async {
      await pump(tester);
      final supervision = card(weekDay(1), 7);
      expect(supervision, findsOneWidget);
      final canvas = tester.getRect(find.byType(TimetableCanvas).first);
      expect(tester.getRect(supervision).top, greaterThanOrEqualTo(canvas.top));
      for (final (d, unit) in [(1, 7), (2, 6), (5, 8)]) {
        await tester.tap(card(weekDay(d), unit));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('lesson-exam-create')),
          findsNothing,
          reason: 'day $d unit $unit',
        );
        expect(find.byKey(const ValueKey('details-classreg')), findsNothing);
        await tester.tapAt(const Offset(600, 20));
        await tester.pumpAndSettle();
      }
      // An ordinary own lesson still offers it.
      await tester.tap(card(weekDay(4), 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lesson-exam-create')), findsOneWidget);
      expect(find.byKey(const ValueKey('details-not-own')), findsNothing);
    });

    testWidgets('setting off: no colleague lessons, no class requests', (
      tester,
    ) async {
      store.values[TimetableSettingsNotifier.storeKey] =
          const TimetableSettings(showColleagueLessons: false).toJson();
      await pump(tester);
      expect(card(weekDay(4), 5), findsNothing);
      expect(card(weekDay(4), 0), findsOneWidget);
      expect(fake.requested.any((t) => t.type == ElementType.klasse), isFalse);
    });

    testWidgets('class timetable fails: own timetable unaffected', (
      tester,
    ) async {
      fake.failClasses = true;
      await pump(tester);
      expect(card(weekDay(4), 0), findsOneWidget);
      expect(card(weekDay(4), 5), findsNothing);
      expect(find.byIcon(Icons.cloud_off), findsNothing);
      expect(find.text('Could not load the timetable'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('class timetable (not own): nothing faded, no extra loads', (
      tester,
    ) async {
      await accounts.add(demoAccount(), 'S', FakeUntisApi.demoMasterData);
      await accounts.setActive(demoAccount().id);
      await pump(tester);
      expect(fake.requested.toSet(), {
        const TimetableTarget(ElementType.klasse, DemoIds.klasse),
      });
    });
  });

  group('settings', () {
    Future<void> pump(WidgetTester tester, Account account) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountRepositoryProvider.overrideWithValue(
              InMemoryAccountRepository(initial: [account]),
            ),
            settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
          ],
          child: const MaterialApp(home: TimetableSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('previews and colour rows for supervision and room booking', (
      tester,
    ) async {
      await pump(tester, demoAccount());
      expect(find.byType(LessonPreview), findsOneWidget);
      // 360 px: the samples scroll sideways instead of getting too thin.
      expect(find.byKey(const ValueKey('preview-scroll')), findsOneWidget);
      for (final k in ['supervision', 'roomBooking']) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('color-$k')),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.byKey(ValueKey('mode-$k')), findsOneWidget);
      }
      await tester.drag(
        find.byKey(const ValueKey('preview-scroll')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      final cs = Theme.of(tester.element(find.byType(TimetableSettingsScreen)))
          .colorScheme;
      final m = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(const ValueKey('preview-roomBooking')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(m.color, cs.secondaryContainer);
      expect(tester.takeException(), isNull);
    });

    testWidgets('colleague lessons switch: teachers only', (tester) async {
      await pump(tester, demoAccount());
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('show-cancelled')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.byKey(const ValueKey('show-colleague-lessons')),
        findsNothing,
      );

      await pump(tester, teacherAccount());
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('show-colleague-lessons')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.byKey(const ValueKey('show-colleague-lessons')),
        findsOneWidget,
      );
    });
  });

  group('own teacher timetable is never rebuilt from classes', () {
    test(
      'after another teacher was refused, supervisions still load',
      () async {
        final db = memoryDb();
        addTearDown(db.close);
        final fake = _DenyOtherTeachersApi();
        final accounts = AccountRepositoryImpl(db, MemorySecretStore());
        final acc = await accounts.add(
          teacherAccount(),
          'S',
          FakeUntisApi.demoMasterData,
        );
        final repo = TimetableRepositoryImpl(
          api: RoutingUntisApi(real: FakeUntisApi(), demo: fake),
          db: db,
          accounts: accounts,
        );
        // Another teacher: refused, built from the class timetables.
        await repo.refresh(
          acc,
          const TimetableTarget(ElementType.teacher, 12),
          monday,
        );
        expect(repo.directAccessDenied(acc, ElementType.teacher), isTrue);
        // The own one is still asked for directly and has the supervision.
        fake.ownCalls = 0;
        await repo.refresh(acc, ownTarget, monday);
        expect(fake.ownCalls, 1);
        final own = await repo.watchWeek(acc, ownTarget, monday).first;
        expect(own.any((p) => p.isBreakSupervision), isTrue);
        expect(own.any((p) => p.isRoomBooking), isTrue);
      },
    );
  });
}

class _DenyOtherTeachersApi extends FakeUntisApi {
  _DenyOtherTeachersApi() : super(latency: Duration.zero);
  int ownCalls = 0;

  @override
  Future<TimetableResponse> timetable({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
    required int masterDataTimestamp,
  }) {
    if (target.type == ElementType.teacher) {
      if (target.id != me) {
        return Future.error(
          const UntisException(UntisException.noRight, 'no right'),
        );
      }
      ownCalls++;
    }
    return super.timetable(
      host: host,
      school: school,
      auth: auth,
      target: target,
      start: start,
      end: end,
      masterDataTimestamp: masterDataTimestamp,
    );
  }
}
