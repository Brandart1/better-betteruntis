import 'package:better_betteruntis/calendar/device_calendar.dart';
import 'package:better_betteruntis/core/lesson_notes.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/timetable/lesson_details_sheet.dart';
import 'package:better_betteruntis/ui/timetable/lesson_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../calendar/fake_device_calendar.dart';

void main() {
  final period = applyLessonNotes(
    [
      Period(
        id: 1,
        lessonId: 7,
        start: DateTime(2026, 11, 16, 8),
        end: DateTime(2026, 11, 16, 8, 50),
        elements: const [
          ElementRef(type: ElementType.subject, id: DemoIds.m, orgId: 0),
        ],
        flags: const {PeriodFlag.regular},
      ),
    ],
    'acc',
    const {},
  ).single;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
          deviceCalendarProvider.overrideWithValue(FakeDeviceCalendar()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LessonDetailsSheet(
              blocks: [
                LessonBlock([period]),
              ],
              names: FakeNameResolver(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(LessonDetailsSheet)),
    );
  }

  testWidgets('mark as exam with details, then remove the custom exam', (
    tester,
  ) async {
    final c = await pump(tester);
    expect(find.text('Custom exam'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('lesson-exam-add')));
    await tester.pumpAndSettle();
    expect(find.text('Exam details'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('lesson-details-field')),
      'mündliche Wiederholung',
    );
    await tester.tap(find.byKey(const ValueKey('lesson-details-save')));
    await tester.pumpAndSettle();

    expect(find.text('Custom exam'), findsOneWidget);
    expect(find.text('mündliche Wiederholung'), findsOneWidget);
    expect(
      c.read(lessonNotesProvider)[period.noteKey],
      const LessonNote(exam: true, text: 'mündliche Wiederholung'),
    );

    await tester.tap(find.byKey(const ValueKey('lesson-exam-remove')));
    await tester.pumpAndSettle();
    expect(find.text('Custom exam'), findsNothing);
    expect(find.byKey(const ValueKey('lesson-exam-add')), findsOneWidget);
    // The details stay.
    expect(find.text('mündliche Wiederholung'), findsOneWidget);
  });

  testWidgets('exam details can be skipped', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('lesson-exam-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lesson-details-dismiss')));
    await tester.pumpAndSettle();
    expect(find.text('Custom exam'), findsOneWidget);
    expect(
      c.read(lessonNotesProvider)[period.noteKey],
      const LessonNote(exam: true),
    );
  });

  testWidgets('add, edit and remove lesson details', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('lesson-details-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Add lesson details'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('lesson-details-field')),
      'Pages 12-14',
    );
    await tester.tap(find.byKey(const ValueKey('lesson-details-save')));
    await tester.pumpAndSettle();
    expect(find.text('Pages 12-14'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lesson-details-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Edit lesson details'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('lesson-details-field')),
      'Pages 12-16',
    );
    await tester.tap(find.byKey(const ValueKey('lesson-details-save')));
    await tester.pumpAndSettle();
    expect(find.text('Pages 12-16'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lesson-details-remove')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lesson-user-note')), findsNothing);
    expect(c.read(lessonNotesProvider), isEmpty);
  });
}
