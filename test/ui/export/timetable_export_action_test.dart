import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/export/export_sheet.dart';
import 'package:better_betteruntis/ui/timetable/timetable_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app bar export button opens the export sheet', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timetableRepositoryProvider.overrideWithValue(
            FakeTimetableRepository(),
          ),
          activeAccountProvider.overrideWith(
            (ref) => Stream.value(demoAccount()),
          ),
        ],
        child: const MaterialApp(home: TimetableScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timetable-menu')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('export-action')));
    await tester.pumpAndSettle();
    expect(find.byType(ExportSheet), findsOneWidget);
    expect(find.text('Regular timetable'), findsOneWidget);
  });
}
