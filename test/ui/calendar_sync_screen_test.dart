import 'dart:async';

import 'package:better_betteruntis/calendar/calendar_sync_service.dart';
import 'package:better_betteruntis/calendar/device_calendar.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/calendar/calendar_sync_screen.dart';
import 'package:better_betteruntis/ui/calendar/calendar_syncs_screen.dart';
import 'package:better_betteruntis/ui/export/export_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../calendar/fake_device_calendar.dart';

void main() {
  late FakeDeviceCalendar api;
  final account = demoAccount();
  const target = TimetableTarget(ElementType.klasse, DemoIds.klasse);

  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = FakeDeviceCalendar();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showExportSheet(
                  context,
                  account: account,
                  target: target,
                  initialWeek: DateTime(2026, 11, 9),
                  elementName: '10a',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/calendar',
          builder: (_, _) => const CalendarSyncsScreen(),
        ),
        GoRoute(
          path: '/calendar/setup',
          builder: (_, s) =>
              CalendarSyncScreen(args: s.extra! as CalendarSetupArgs),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceCalendarProvider.overrideWithValue(api),
          settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
          accountRepositoryProvider.overrideWithValue(
            InMemoryAccountRepository(initial: [account]),
          ),
          activeAccountProvider.overrideWith((_) => Stream.value(account)),
          timetableRepositoryProvider.overrideWithValue(
            FakeTimetableRepository(weekBuilder: (_, w) => buildDemoWeek(w)),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.text('open')));
  }

  testWidgets('export sheet → Add to calendar → new calendars per kind', (
    tester,
  ) async {
    final c = await pump(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('export-add-to-calendar')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('export-format-ics')));
    await tester.pumpAndSettle();
    expect(find.text('Download .ics'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export-add-to-calendar')));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarSyncScreen), findsOneWidget);
    for (final s in ['regular', 'substitution', 'exam', 'cancelled']) {
      expect(find.byKey(ValueKey('calendar-choice-$s')), findsOneWidget);
    }
    expect(find.text('New calendar "10a – Exams"'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-new-hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('google-calendar-info')), findsOneWidget);

    // Cancelled lessons into the personal calendar.
    await tester.tap(find.byKey(const ValueKey('calendar-choice-cancelled')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal').last);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('calendar-save')));
      for (var i = 0; i < 50 && c.read(calendarSyncsProvider).isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      while (c.read(calendarSyncsProvider).single.lastSync == null) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(find.byType(CalendarSyncScreen), findsNothing);

    final names = {for (final x in api.cals.values) x.name};
    expect(names, {
      'Personal',
      '10a – Timetable',
      '10a – Substitutions',
      '10a – Exams',
    });
    expect(
      api.eventsIn('personal').every((e) => e.title.startsWith('Cancelled')),
      isTrue,
    );
    expect(api.eventsIn('personal'), isNotEmpty);
  });

  for (final platform in TargetPlatform.values) {
    testWidgets('Google sync note only on Android ($platform)', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await pump(tester);
        unawaited(
          GoRouter.of(tester.element(find.text('open'))).push(
            '/calendar/setup',
            extra: const CalendarSetupArgs(
              accountId: 'a',
              target: target,
              elementName: '10a',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('calendar-save')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('google-calendar-info')),
          platform == TargetPlatform.android ? findsOneWidget : findsNothing,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('no calendar access shows a message', (tester) async {
    await pump(tester);
    api.granted = false;
    GoRouter.of(tester.element(find.text('open'))).push(
      '/calendar/setup',
      extra: const CalendarSetupArgs(
        accountId: 'x',
        target: target,
        elementName: '10a',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No calendar access'), findsOneWidget);
  });
}
