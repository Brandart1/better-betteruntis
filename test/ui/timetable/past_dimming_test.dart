import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/timetable/grid_background.dart';
import 'package:better_betteruntis/ui/timetable/lesson_card.dart';
import 'package:better_betteruntis/ui/timetable/lesson_layout.dart';
import 'package:better_betteruntis/ui/timetable/lesson_style.dart';
import 'package:better_betteruntis/ui/timetable/timetable_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Period _p(int id, DateTime day, {Set<PeriodFlag>? flags}) {
  final start = DateTime(day.year, day.month, day.day, 8);
  return Period(
    id: id,
    lessonId: id,
    start: start,
    end: start.add(const Duration(minutes: 50)),
    elements: const [
      ElementRef(type: ElementType.subject, id: 1, orgId: 1, inlineName: 'M'),
    ],
    flags: flags ?? const {PeriodFlag.regular},
  );
}

void main() {
  final cs = ColorScheme.fromSeed(seedColor: Colors.indigo);
  final surface = pastSurfaceOf(cs);

  test('dimmed style fades fill and text but keeps state flags', () {
    final exam = LessonStyle.of(
      cs,
      LessonBlock([
        _p(1, DateTime(2026, 11, 9), flags: {PeriodFlag.exam}),
      ]),
    );
    final d = exam.dimmed(surface);
    expect(d.exam, isTrue);
    expect(d.background, isNot(exam.background));
    expect(
      d.background,
      Color.lerp(exam.background, surface, LessonStyle.pastBackgroundFade),
    );
    expect(d.border, isNotNull);
    expect(d.border, isNot(exam.border));
    final cancelled = LessonStyle.of(
      cs,
      LessonBlock([
        _p(2, DateTime(2026, 11, 9), flags: {PeriodFlag.cancelled}),
      ]),
    ).dimmed(surface);
    expect(cancelled.cancelled, isTrue);
  });

  test('past tint is clearly visible in light and dark theme', () {
    for (final b in Brightness.values) {
      final s = ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: b);
      expect(pastTintOf(s).a, greaterThanOrEqualTo(0.1));
    }
  });

  testWidgets('past lessons are dimmed, future ones are not', (tester) async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final past = _p(1, yesterday);
    final future = _p(2, tomorrow);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
        ],
        child: MaterialApp(
          theme: ThemeData(colorScheme: cs),
          home: Scaffold(
            body: TimetableCanvas(
              days: [
                DayColumnData(yesterday, layoutDay([past]), null),
                DayColumnData(tomorrow, layoutDay([future]), null),
              ],
              names: FakeNameResolver(),
              startMinute: 7 * 60,
              endMinute: 16 * 60,
              timeColumnWidth: 40,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    LessonCard card(Period p) => tester.widget<LessonCard>(
      find.descendant(
        of: find.byKey(ValueKey('lesson-${p.id}')),
        matching: find.byType(LessonCard),
      ),
    );
    Color fill(Period p) => tester
        .widget<Material>(
          find.descendant(
            of: find.byKey(ValueKey('lesson-${p.id}')),
            matching: find.byType(Material),
          ),
        )
        .color!;

    expect(card(past).past, isTrue);
    expect(card(future).past, isFalse);
    expect(fill(future), cs.primaryContainer);
    expect(
      fill(past),
      Color.lerp(cs.primaryContainer, surface, LessonStyle.pastBackgroundFade),
    );

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<GridBackgroundPainter>()
        .single;
    expect(painter.pastColumns, 1);
    expect(painter.pastTint, pastTintOf(cs));
  });
}
