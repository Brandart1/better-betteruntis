import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/timetable/week_data_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const note = ValueKey('slow-first-load-note');
  const latency = Duration(seconds: 1);

  Future<void> pumpLoading(WidgetTester tester, ElementType type) async {
    final account = demoAccount();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timetableRepositoryProvider.overrideWithValue(
            FakeTimetableRepository(latency: latency),
          ),
          accountRepositoryProvider.overrideWithValue(
            InMemoryAccountRepository(initial: [account]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WeekDataView(
              account: account,
              target: TimetableTarget(type, 1),
              weekStart: DateTime(2026, 11, 9),
              builder: (_, _, _) => ListView(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  }

  for (final type in [ElementType.teacher, ElementType.room]) {
    testWidgets('${type.name}: note below the spinner until loaded', (
      tester,
    ) async {
      await pumpLoading(tester, type);
      expect(find.byKey(note), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(note)).dy,
        greaterThan(
          tester.getBottomLeft(find.byType(CircularProgressIndicator)).dy,
        ),
      );

      await tester.pump(latency);
      await tester.pump();
      expect(find.byKey(note), findsNothing);
    });
  }

  testWidgets('class: spinner without the note', (tester) async {
    await pumpLoading(tester, ElementType.klasse);
    expect(find.byKey(note), findsNothing);
    await tester.pump(latency);
    await tester.pump();
  });
}
