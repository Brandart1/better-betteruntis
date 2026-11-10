import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/timetable/lesson_details_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<TimetableTarget>> _tapChip(WidgetTester tester, ElementRef ref) async {
  final opened = <TimetableTarget>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [settingsStoreProvider.overrideWithValue(MemorySettingsStore())],
    child: MaterialApp(
      home: Scaffold(
        body: ElementChip(element: ref, names: FakeNameResolver(), onOpen: opened.add),
      ),
    ),
  ));
  await tester.tap(find.byType(ActionChip));
  await tester.pump();
  return opened;
}

void main() {
  testWidgets('name-only teacher chip (REST, negative id) opens its timetable', (tester) async {
    const ref = ElementRef(
      type: ElementType.teacher,
      id: -77,
      orgId: -77,
      inlineName: 'ABC',
      inlineLongName: 'Alpha Beta',
    );
    expect(find.text('Alpha Beta'), findsNothing);
    final opened = await _tapChip(tester, ref);
    expect(find.textContaining('Alpha Beta', findRichText: true), findsOneWidget);
    expect(opened, [const TimetableTarget(ElementType.teacher, -77)]);
  });

  testWidgets('chip with no element at all is not tappable', (tester) async {
    const ref = ElementRef(type: ElementType.teacher, id: 0, orgId: 0);
    final opened = await _tapChip(tester, ref);
    expect(opened, isEmpty);
  });
}
