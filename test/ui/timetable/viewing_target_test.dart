import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/timetable/lesson_card.dart';
import 'package:better_betteruntis/ui/timetable/lesson_layout.dart';
import 'package:better_betteruntis/ui/timetable/viewing_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _room = 101;
const _otherRoom = 102;

final _names = FakeNameResolver(elements: const [
  MasterElement(type: ElementType.subject, id: 1, name: 'M', longName: 'Mathe'),
  MasterElement(type: ElementType.klasse, id: 2, name: '5A', longName: '5A'),
  MasterElement(type: ElementType.room, id: _room, name: 'R101', longName: 'R101'),
  MasterElement(type: ElementType.room, id: _otherRoom, name: 'R102', longName: 'R102'),
]);

Period _p({ElementRef? room, ElementRef? teacher, bool cancelled = false}) => Period(
  id: 1,
  lessonId: 1,
  start: DateTime(2026, 11, 16, 8),
  end: DateTime(2026, 11, 16, 8, 50),
  elements: [
    const ElementRef(type: ElementType.subject, id: 1, orgId: 1),
    const ElementRef(type: ElementType.klasse, id: 2, orgId: 2),
    teacher ?? const ElementRef(type: ElementType.teacher, id: -5, orgId: -5, inlineName: 'ABC'),
    room ?? const ElementRef(type: ElementType.room, id: _room, orgId: _room),
  ],
  flags: {cancelled ? PeriodFlag.cancelled : PeriodFlag.regular},
);

Future<String> _cardText(WidgetTester tester, Period p, TimetableTarget? viewing) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [settingsStoreProvider.overrideWithValue(MemorySettingsStore())],
    child: MaterialApp(
      home: ViewingTarget(
        target: viewing,
        child: SizedBox(
          width: 120,
          height: 120,
          child: LessonCard(block: LessonBlock([p]), names: _names),
        ),
      ),
    ),
  ));
  await tester.pump();
  return tester.widget<RichText>(find.byType(RichText).first).text.toPlainText();
}

void main() {
  const roomView = TimetableTarget(ElementType.room, _room);

  testWidgets('room timetable shows teacher and class, not the room', (tester) async {
    final t = await _cardText(tester, _p(), roomView);
    expect(t, contains('ABC'));
    expect(t, contains('5A'));
    expect(t, isNot(contains('R101')));
  });

  testWidgets('room moved elsewhere: class hidden', (tester) async {
    final t = await _cardText(
      tester,
      _p(room: const ElementRef(type: ElementType.room, id: _otherRoom, orgId: _room)),
      roomView,
    );
    expect(t, isNot(contains('5A')));
  });

  testWidgets('room dropped: class hidden', (tester) async {
    final t = await _cardText(
      tester,
      _p(room: const ElementRef(type: ElementType.room, id: 0, orgId: _room)),
      roomView,
    );
    expect(t, isNot(contains('5A')));
  });

  testWidgets('cancelled lesson: class hidden', (tester) async {
    final t = await _cardText(tester, _p(cancelled: true), roomView);
    expect(t, isNot(contains('5A')));
    expect(t, contains('ABC'));
  });

  testWidgets('room moved INTO this room keeps the class', (tester) async {
    final t = await _cardText(
      tester,
      _p(room: const ElementRef(type: ElementType.room, id: _room, orgId: _otherRoom)),
      roomView,
    );
    expect(t, contains('5A'));
  });

  testWidgets('teacher timetable shows class and room', (tester) async {
    final t = await _cardText(tester, _p(), const TimetableTarget(ElementType.teacher, -5));
    expect(t, contains('5A'));
    expect(t, contains('R101'));
  });

  testWidgets('own timetable unchanged: teacher and room', (tester) async {
    final t = await _cardText(tester, _p(), null);
    expect(t, contains('ABC'));
    expect(t, contains('R101'));
  });

  testWidgets('room moved elsewhere: the room change is shown', (tester) async {
    final t = await _cardText(
      tester,
      _p(room: const ElementRef(type: ElementType.room, id: _otherRoom, orgId: _room)),
      roomView,
    );
    expect(t, contains('R102'));
    expect(t, contains('R101'));
  });

  testWidgets('teacher substituted in their own timetable: shown', (tester) async {
    final t = await _cardText(
      tester,
      _p(
        teacher: const ElementRef(
          type: ElementType.teacher,
          id: -6,
          orgId: -5,
          inlineName: 'XYZ',
          orgInlineName: 'ABC',
        ),
      ),
      const TimetableTarget(ElementType.teacher, -5),
    );
    expect(t, contains('XYZ'));
  });

  testWidgets('class swapped in the class timetable: shown', (tester) async {
    final p = _p();
    final swapped = p.copyWithElements([
      for (final e in p.elements)
        e.type == ElementType.klasse
            ? const ElementRef(type: ElementType.klasse, id: 3, orgId: 2, inlineName: '5B', orgInlineName: '5A')
            : e,
    ]);
    final t = await _cardText(tester, swapped, const TimetableTarget(ElementType.klasse, 2));
    expect(t, contains('5A'));
  });

  testWidgets('several classes: shown in the class timetable', (tester) async {
    final p = _p();
    final shared = p.copyWithElements([
      ...p.elements,
      const ElementRef(type: ElementType.klasse, id: 3, orgId: 3, inlineName: '5B'),
    ]);
    final t = await _cardText(tester, shared, const TimetableTarget(ElementType.klasse, 2));
    expect(t, contains('5A'));
    expect(t, contains('5B'));
  });

  testWidgets('single class: not repeated in its own timetable', (tester) async {
    final t = await _cardText(tester, _p(), const TimetableTarget(ElementType.klasse, 2));
    expect(t, isNot(contains('5A')));
  });
}
