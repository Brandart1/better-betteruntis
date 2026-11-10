import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/timetable/lesson_card.dart';
import 'package:better_betteruntis/ui/timetable/timetable_screen.dart';
import 'package:better_betteruntis/ui/timetable/timetable_utils.dart';
import 'package:flutter/material.dart';
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

  Future<void> pumpScreen(WidgetTester tester) async {
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
          home: TimetableScreen(onOpenElement: (_, t) => opened.add(t)),
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

    await tester.tap(find.byTooltip('Today'));
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

    await tester.tap(find.byTooltip('Today'));
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
}
