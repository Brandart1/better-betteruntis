import 'package:better_betteruntis/core/favourites.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/timetable/lesson_card.dart';
import 'package:better_betteruntis/ui/timetable/timetable_screen.dart';
import 'package:better_betteruntis/ui/timetable/timetable_utils.dart';
import 'package:better_betteruntis/ui/shell/app_drawer.dart' show isWebProvider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeTimetableRepository repo;
  late List<TimetableTarget> opened;
  final weekStart = mondayOf(DateTime.now());
  final week = buildDemoWeek(weekStart, holidayFriday: true);

  setUp(() {
    repo = FakeTimetableRepository();
    opened = [];
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool web = false,
    Widget? drawer,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timetableRepositoryProvider.overrideWithValue(repo),
          activeAccountProvider.overrideWith(
            (ref) => Stream.value(demoAccount()),
          ),
          isWebProvider.overrideWithValue(web),
        ],
        child: MaterialApp(
          home: TimetableScreen(
            drawer: drawer,
            onOpenElement: (_, t) => opened.add(t),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder rich(String text) => find.textContaining(text, findRichText: true);

  testWidgets('grid shows teacher names, including inactive and inline-only', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(rich('MUE'), findsWidgets);
    expect(rich('BEC'), findsWidgets, reason: 'inactive teacher must be shown');
    expect(rich('NEU'), findsOneWidget, reason: 'inline-only teacher name');
    expect(
      find.text('Pädagogischer Tag'),
      findsOneWidget,
      reason: 'holiday block',
    );
    expect(find.textContaining('Updated 5 min ago'), findsOneWidget);
  });

  testWidgets('substituted teacher shows new name and struck original', (
    tester,
  ) async {
    await pumpScreen(tester);
    final sub = week.firstWhere((p) => p.substitutionText == 'Vertretung');
    final card = find.descendant(
      of: find.byKey(ValueKey('lesson-${sub.id}')),
      matching: find.byType(RichText),
    );
    final span = tester.widget<RichText>(card.first).text;
    expect(span.toPlainText(), contains('FIS WEB'));
    var struckWeb = false;
    span.visitChildren((s) {
      if (s is TextSpan &&
          s.text == 'WEB' &&
          s.style?.decoration == TextDecoration.lineThrough) {
        struckWeb = true;
      }
      return true;
    });
    expect(struckWeb, isTrue);
  });

  testWidgets('cancelled lesson is hatched and struck through', (tester) async {
    await pumpScreen(tester);
    final hatch = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.foregroundPainter is CancelledHatchPainter,
    );
    expect(hatch, findsOneWidget);
    final cancelled = week.firstWhere((p) => p.isCancelled);
    final card = tester.widget<LessonCard>(
      find.descendant(
        of: find.byKey(ValueKey('lesson-${cancelled.id}')),
        matching: find.byType(LessonCard),
      ),
    );
    expect(card.block.isCancelled, isTrue);
  });

  testWidgets('double lesson renders as one merged card', (tester) async {
    await pumpScreen(tester);
    final maths = week
        .where((p) => p.lessonId == DemoIds.doubleMathsLesson)
        .toList();
    expect(maths, hasLength(2));
    expect(find.byKey(ValueKey('lesson-${maths[0].id}')), findsOneWidget);
    expect(find.byKey(ValueKey('lesson-${maths[1].id}')), findsNothing);
    final card = tester.widget<LessonCard>(
      find.descendant(
        of: find.byKey(ValueKey('lesson-${maths[0].id}')),
        matching: find.byType(LessonCard),
      ),
    );
    expect(card.block.periods, hasLength(2));
  });

  testWidgets('overlapping lessons are laid out side by side', (tester) async {
    await pumpScreen(tester);
    final rel = week.firstWhere((p) => p.lessonId == 109);
    final eth = week.firstWhere((p) => p.lessonId == 110);
    final a = tester.getRect(find.byKey(ValueKey('lesson-${rel.id}')));
    final b = tester.getRect(find.byKey(ValueKey('lesson-${eth.id}')));
    expect(a.top, b.top);
    expect(a.overlaps(b), isFalse);
    expect(a.width, closeTo(b.width, 0.01));
  });

  Finder dayLabel() => find.byKey(const ValueKey('day-label'));
  Finder weekLabel() => find.byKey(const ValueKey('week-label'));

  testWidgets('tapping a day header zooms into day mode, swipe moves days', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('day-header-1')));
    await tester.pumpAndSettle();
    expect(dayLabel(), findsOneWidget);
    expect(weekLabel(), findsNothing);
    expect(find.byType(BackButton), findsNothing, reason: 'no back arrow');
    expect(
      rich('Anna Müller'),
      findsWidgets,
      reason: 'long teacher names in day view',
    );
    expect(rich('Mathematik'), findsWidgets);
    final ctx = tester.element(find.byType(TimetableScreen));
    expect(
      tester.widget<Text>(dayLabel()).data,
      dateFormat(ctx, 'EEE, d MMM').format(weekStart),
    );

    // Swipe to Tuesday.
    await tester.drag(find.byType(PageView).last, const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(dayLabel()).data,
      dateFormat(ctx, 'EEE, d MMM').format(addDays(weekStart, 1)),
    );
    expect(rich('Maria Becker'), findsWidgets);
  });

  testWidgets('day mode keeps the drawer button of the week view', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      drawer: const Drawer(child: Text('drawer-content')),
    );
    expect(find.byType(DrawerButton), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('day-header-2')));
    await tester.pumpAndSettle();
    expect(dayLabel(), findsOneWidget);
    expect(find.byType(DrawerButton), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    // The burger opens the drawer; the day view stays open behind it.
    await tester.tap(find.byType(DrawerButton));
    await tester.pumpAndSettle();
    expect(find.text('drawer-content'), findsOneWidget);
    expect(dayLabel(), findsOneWidget);

    // System back closes the drawer first, then leaves day mode.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('drawer-content'), findsNothing);
    expect(dayLabel(), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(weekLabel(), findsOneWidget);

    // Escape leaves day mode too.
    await tester.tap(find.byKey(const ValueKey('day-header-3')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(weekLabel(), findsOneWidget);
    expect(find.byType(DrawerButton), findsOneWidget);
  });

  testWidgets('pushed element timetable: back arrow leaves day mode first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timetableRepositoryProvider.overrideWithValue(repo),
          activeAccountProvider.overrideWith(
            (ref) => Stream.value(demoAccount()),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      TimetableScreen(onOpenElement: (_, t) => opened.add(t)),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('day-header-2')));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byType(DrawerButton), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(weekLabel(), findsOneWidget, reason: 'day mode left, route kept');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(TimetableScreen), findsNothing);
  });

  testWidgets('tapping the date title returns to the week overview', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('day-header-2')));
    await tester.pumpAndSettle();
    expect(dayLabel(), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('day-title')));
    await tester.pumpAndSettle();
    expect(dayLabel(), findsNothing);
    expect(weekLabel(), findsOneWidget);
    expect(find.byKey(const ValueKey('day-header-1')), findsOneWidget);

    // The day view's own header also zooms out.
    await tester.tap(find.byKey(const ValueKey('day-header-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('day-view-header')));
    await tester.pumpAndSettle();
    expect(weekLabel(), findsOneWidget);
  });

  testWidgets('system back in day mode returns to week mode', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('day-header-1')));
    await tester.pumpAndSettle();
    expect(dayLabel(), findsOneWidget);

    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue, reason: 'PopScope consumed the back press');
    expect(weekLabel(), findsOneWidget);
    expect(find.byType(TimetableScreen), findsOneWidget);
  });

  testWidgets('leaving day mode lands on the week of the current day', (
    tester,
  ) async {
    await pumpScreen(tester);
    final ctx = tester.element(find.byType(TimetableScreen));
    String label(DateTime ws) => formatWeekRange(ctx, ws, addDays(ws, 4));

    await tester.tap(find.byKey(const ValueKey('day-header-5')));
    await tester.pumpAndSettle();
    // Friday -> next Monday.
    await tester.drag(find.byType(PageView).last, const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(dayLabel()).data,
      dateFormat(ctx, 'EEE, d MMM').format(addDays(weekStart, 7)),
    );
    await tester.tap(find.byKey(const ValueKey('day-title')));
    await tester.pumpAndSettle();
    expect(find.text(label(addDays(weekStart, 7))), findsOneWidget);

    await tester.tap(find.byTooltip('Today (T)'));
    await tester.pumpAndSettle();
    expect(find.text(label(weekStart)), findsOneWidget);
  });

  testWidgets('tapping a lesson opens the sheet with teacher chips', (
    tester,
  ) async {
    await pumpScreen(tester);
    final maths = week.firstWhere(
      (p) => p.lessonId == DemoIds.doubleMathsLesson,
    );
    await tester.tap(find.byKey(ValueKey('lesson-${maths.id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Lesson 1–2'), findsOneWidget);
    final chip = find.widgetWithText(ActionChip, 'Anna Müller');
    expect(chip, findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Raum 101'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Klasse 10a'), findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(opened, [const TimetableTarget(ElementType.teacher, DemoIds.mue)]);
  });

  testWidgets('overlapping lessons open a pager in the sheet', (tester) async {
    await pumpScreen(tester);
    final rel = week.firstWhere((p) => p.lessonId == 109);
    await tester.tap(find.byKey(ValueKey('lesson-${rel.id}')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Religion'), findsOneWidget);
    await tester.drag(find.text('Religion'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Ethik'), findsOneWidget);
  });

  testWidgets('swiping the pager changes the week label', (tester) async {
    await pumpScreen(tester);
    final ctx = tester.element(find.byType(TimetableScreen));
    String label(DateTime ws) => formatWeekRange(ctx, ws, addDays(ws, 4));
    expect(find.text(label(weekStart)), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.text(label(addDays(weekStart, 7))), findsOneWidget);

    await tester.tap(find.byTooltip('Today (T)'));
    await tester.pumpAndSettle();
    expect(find.text(label(weekStart)), findsOneWidget);
  });

  testWidgets('failed refresh over cached data shows a banner', (tester) async {
    repo.refreshError = const UntisException(0, 'offline');
    await pumpScreen(tester);
    await tester.fling(rich('MUE').first, const Offset(0, 400), 1500);
    await tester.pumpAndSettle();
    expect(repo.refreshCount, 1);
    expect(find.textContaining('No connection'), findsOneWidget);
    expect(rich('MUE'), findsWidgets, reason: 'cached data still shown');
  });

  testWidgets('no data at all shows a full error state with retry', (
    tester,
  ) async {
    repo.watchError = const UntisException(0, 'offline');
    await pumpScreen(tester);
    expect(find.text('No connection'), findsOneWidget);
    repo.watchError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(rich('MUE'), findsWidgets);
  });

  testWidgets('renders at phone size in dark mode without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timetableRepositoryProvider.overrideWithValue(repo),
          activeAccountProvider.overrideWith(
            (ref) => Stream.value(demoAccount()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: TimetableScreen(onOpenElement: (_, t) => opened.add(t)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(rich('BEC'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('day-header-3')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(rich('Nina Neumann'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('day-title')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('keyboard', () {
    String weekText(WidgetTester tester, DateTime ws) => formatWeekRange(
      tester.element(find.byType(TimetableScreen)),
      ws,
      addDays(ws, 4),
    );
    String dayText(WidgetTester tester, DateTime d) => dateFormat(
      tester.element(find.byType(TimetableScreen)),
      'EEE, d MMM',
    ).format(d);

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    testWidgets('web: prev / next buttons with tooltips; apps: none', (
      tester,
    ) async {
      await pumpScreen(tester, web: true);
      final prev = find.byKey(const ValueKey('timetable-prev'));
      final next = find.byKey(const ValueKey('timetable-next'));
      expect(find.byTooltip('Previous week (←)'), findsOneWidget);
      expect(find.byTooltip('Next week (→)'), findsOneWidget);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(
        find.text(weekText(tester, addDays(weekStart, 7))),
        findsOneWidget,
      );
      await tester.tap(prev);
      await tester.pumpAndSettle();
      expect(find.text(weekText(tester, weekStart)), findsOneWidget);
      // Keys still work after clicking a button.
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        find.text(weekText(tester, addDays(weekStart, 7))),
        findsOneWidget,
      );
    });

    testWidgets('apps: no prev / next buttons', (tester) async {
      await pumpScreen(tester);
      expect(find.byKey(const ValueKey('timetable-prev')), findsNothing);
      expect(find.byKey(const ValueKey('timetable-next')), findsNothing);
    });

    testWidgets('left / right switch weeks right after load, T jumps back', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text(weekText(tester, weekStart)), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        find.text(weekText(tester, addDays(weekStart, 7))),
        findsOneWidget,
      );
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        find.text(weekText(tester, addDays(weekStart, 14))),
        findsOneWidget,
      );
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(
        find.text(weekText(tester, addDays(weekStart, 7))),
        findsOneWidget,
      );

      await press(tester, LogicalKeyboardKey.keyT);
      expect(find.text(weekText(tester, weekStart)), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(
        find.text(weekText(tester, addDays(weekStart, -7))),
        findsOneWidget,
      );
      await press(tester, LogicalKeyboardKey.home);
      expect(find.text(weekText(tester, weekStart)), findsOneWidget);
    });

    testWidgets('quick repeated presses step twice', (tester) async {
      await pumpScreen(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        find.text(weekText(tester, addDays(weekStart, 14))),
        findsOneWidget,
      );
    });

    testWidgets('left / right switch days in day mode, Escape zooms out', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('day-header-2')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(dayLabel()).data,
        dayText(tester, addDays(weekStart, 1)),
      );

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        tester.widget<Text>(dayLabel()).data,
        dayText(tester, addDays(weekStart, 2)),
      );
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(tester.widget<Text>(dayLabel()).data, dayText(tester, weekStart));

      await press(tester, LogicalKeyboardKey.escape);
      expect(dayLabel(), findsNothing);
      expect(find.text(weekText(tester, weekStart)), findsOneWidget);
    });

    testWidgets('ignored while a text field has focus', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timetableRepositoryProvider.overrideWithValue(repo),
            activeAccountProvider.overrideWith(
              (ref) => Stream.value(demoAccount()),
            ),
          ],
          child: MaterialApp(
            home: TimetableScreen(
              onOpenElement: (_, t) => opened.add(t),
              drawer: const Drawer(child: TextField(key: ValueKey('field'))),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('field')));
      await tester.enterText(find.byKey(const ValueKey('field')), 'abc');
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.keyT);
      scaffold.closeDrawer();
      await tester.pumpAndSettle();
      expect(find.text(weekText(tester, weekStart)), findsOneWidget);

      // Closing the drawer gives the keys back to the timetable.
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        find.text(weekText(tester, addDays(weekStart, 7))),
        findsOneWidget,
      );
    });

    testWidgets('ignored while a dialog is open', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byTooltip('Jump to date'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.byType(DatePickerDialog), findsOneWidget);

      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.text(weekText(tester, weekStart)), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        find.text(weekText(tester, addDays(weekStart, 7))),
        findsOneWidget,
      );
    });

    testWidgets('Escape closes the lesson sheet, then keys work again', (
      tester,
    ) async {
      await pumpScreen(tester);
      final maths = week.firstWhere(
        (p) => p.lessonId == DemoIds.doubleMathsLesson,
      );
      await tester.tap(find.byKey(ValueKey('lesson-${maths.id}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Lesson 1–2'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text(weekText(tester, weekStart)), findsOneWidget);

      await press(tester, LogicalKeyboardKey.escape);
      expect(find.textContaining('Lesson 1–2'), findsNothing);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        find.text(weekText(tester, addDays(weekStart, 7))),
        findsOneWidget,
      );
    });
  });

  testWidgets('class and teacher timetables have a favourite star; the own '
      'timetable has none', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemorySettingsStore();
    Widget app(TimetableTarget? target) => ProviderScope(
      key: ValueKey(target),
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        timetableRepositoryProvider.overrideWithValue(repo),
        activeAccountProvider.overrideWith(
          (ref) => Stream.value(demoAccount()),
        ),
      ],
      child: MaterialApp(home: TimetableScreen(target: target)),
    );
    await tester.pumpWidget(app(null));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timetable-favourite')), findsNothing);

    await tester.pumpWidget(
      app(const TimetableTarget(ElementType.teacher, DemoIds.sch)),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add to favourites'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('timetable-favourite')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove from favourites'), findsOneWidget);
    expect(store.values[FavouritesNotifier.storeKey], {
      demoAccount().id: [favouriteKey(ElementType.teacher, DemoIds.sch)],
    });

    await tester.pumpWidget(
      app(const TimetableTarget(ElementType.room, DemoIds.klasse)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timetable-favourite')), findsNothing);
  });
}
