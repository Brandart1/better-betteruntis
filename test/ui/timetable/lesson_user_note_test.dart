import 'package:better_betteruntis/calendar/device_calendar.dart';
import 'package:better_betteruntis/core/lesson_notes.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/timetable/lesson_card.dart';
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
    // "Only for you, …" wraps on small screens instead of being cut off.
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('lesson-details-field')),
    );
    expect(field.decoration!.helperMaxLines, greaterThan(1));
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
    // Only a tombstone (for sync) is left.
    expect(c.read(lessonNotesProvider).values.every((n) => n.isEmpty), isTrue);
    expect(c.read(lessonNotesProvider)[period.noteKey]!.deleted, isTrue);
  });

  testWidgets('add, edit and remove homework; details and exam stay', (
    tester,
  ) async {
    final c = await pump(tester);
    expect(find.byKey(const ValueKey('lesson-user-homework')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('lesson-homework-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Add homework'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('lesson-details-field')),
      'p. 12, exercises 3-5',
    );
    await tester.tap(find.byKey(const ValueKey('lesson-details-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lesson-user-homework')), findsOneWidget);
    expect(find.text('p. 12, exercises 3-5'), findsOneWidget);
    expect(find.text('Your homework'), findsOneWidget);
    expect(find.text('Edit homework'), findsOneWidget);
    expect(
      c.read(lessonNotesProvider)[period.noteKey],
      const LessonNote(homework: 'p. 12, exercises 3-5'),
    );

    // Marking the exam keeps the homework.
    await tester.tap(find.byKey(const ValueKey('lesson-exam-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lesson-details-dismiss')));
    await tester.pumpAndSettle();
    expect(
      c.read(lessonNotesProvider)[period.noteKey],
      const LessonNote(exam: true, homework: 'p. 12, exercises 3-5'),
    );

    // Tapping the card edits it.
    await tester.tap(find.text('p. 12, exercises 3-5'));
    await tester.pumpAndSettle();
    expect(find.text('Edit homework'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('lesson-details-field')),
      'exercises 6-8',
    );
    await tester.tap(find.byKey(const ValueKey('lesson-details-save')));
    await tester.pumpAndSettle();
    expect(find.text('exercises 6-8'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lesson-homework-remove')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lesson-user-homework')), findsNothing);
    expect(find.text('Add homework'), findsOneWidget);
    expect(
      c.read(lessonNotesProvider)[period.noteKey],
      const LessonNote(exam: true),
    );
  });

  testWidgets('saving empty homework text removes it', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('lesson-homework-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lesson-details-field')),
      'Essay',
    );
    await tester.tap(find.byKey(const ValueKey('lesson-details-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lesson-homework-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lesson-details-field')),
      '  ',
    );
    await tester.tap(find.byKey(const ValueKey('lesson-details-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lesson-user-homework')), findsNothing);
    expect(c.read(lessonNotesProvider)[period.noteKey]!.deleted, isTrue);
  });

  testWidgets('a lesson with the user\'s homework shows a homework icon', (
    tester,
  ) async {
    Future<void> card(Period p) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
          ],
          child: MaterialApp(
            home: SizedBox(
              width: 200,
              height: 120,
              child: LessonCard(
                block: LessonBlock([p]),
                names: FakeNameResolver(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await card(period);
    expect(find.byKey(const ValueKey('lesson-homework-icon')), findsNothing);
    await card(
      period.withUserNote(noteKey: period.noteKey!, userHomework: 'Essay'),
    );
    expect(find.byKey(const ValueKey('lesson-homework-icon')), findsOneWidget);
    // The exam mark is unchanged by it.
    expect(find.byIcon(Icons.assignment_outlined), findsNothing);
  });
}
