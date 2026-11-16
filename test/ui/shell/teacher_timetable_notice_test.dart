import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/infocenter/info_providers.dart';
import 'package:better_betteruntis/ui/shell/element_picker_screen.dart';
import 'package:better_betteruntis/ui/shell/teacher_timetable_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  late MemorySettingsStore store;
  late ProviderContainer container;

  setUp(() => store = MemorySettingsStore());

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const ElementPickerScreen()),
        GoRoute(
          path: '/info',
          builder: (_, _) => const Scaffold(body: Text('info center')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          accountRepositoryProvider.overrideWithValue(
            InMemoryAccountRepository(initial: [demoAccount()]),
          ),
          timetableRepositoryProvider.overrideWithValue(
            FakeTimetableRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(ElementPickerScreen)),
    );
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> openTeachers(WidgetTester tester) =>
      tap(tester, find.widgetWithText(Tab, 'Teachers'));

  testWidgets('not shown until the Teachers tab is opened', (tester) async {
    await pump(tester);
    expect(key('teacher-notice-dialog'), findsNothing);
    await tap(tester, find.widgetWithText(Tab, 'Rooms'));
    expect(key('teacher-notice-dialog'), findsNothing);
  });

  testWidgets('Teachers tab: must promise before continuing; once per '
      'device', (tester) async {
    await pump(tester);
    await openTeachers(tester);
    expect(key('teacher-notice-dialog'), findsOneWidget);
    expect(find.textContaining('Gangaufsicht'), findsOneWidget);
    expect(find.textContaining('Office hours'), findsOneWidget);
    // Disabled until the box is ticked.
    await tap(tester, key('teacher-notice-accept'));
    expect(key('teacher-notice-dialog'), findsOneWidget);
    expect(store.values[teacherTimetableNoticeKey], isNull);
    await tap(tester, key('teacher-notice-promise'));
    await tap(tester, key('teacher-notice-accept'));
    expect(key('teacher-notice-dialog'), findsNothing);
    expect(store.values[teacherTimetableNoticeKey], isNotNull);

    // Back to classes and again to teachers: not asked again.
    await tap(tester, find.widgetWithText(Tab, 'Classes'));
    await openTeachers(tester);
    expect(key('teacher-notice-dialog'), findsNothing);
  });

  testWidgets('cancel goes back to the classes tab and asks next time', (
    tester,
  ) async {
    await pump(tester);
    await openTeachers(tester);
    await tap(tester, key('teacher-notice-cancel'));
    expect(key('teacher-notice-dialog'), findsNothing);
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBarView))).index,
      0,
    );
    expect(store.values[teacherTimetableNoticeKey], isNull);
    await openTeachers(tester);
    expect(key('teacher-notice-dialog'), findsOneWidget);
  });

  testWidgets('"Open office hours" opens the info center on that tab', (
    tester,
  ) async {
    await pump(tester);
    await openTeachers(tester);
    await tap(tester, key('teacher-notice-promise'));
    await tap(tester, key('teacher-notice-office-hours'));
    expect(find.text('info center'), findsOneWidget);
    expect(container.read(infoTabProvider), InfoTab.officeHours);
    expect(store.values[teacherTimetableNoticeKey], isNotNull);
  });

  testWidgets('already accepted on this device: not shown', (tester) async {
    store.values[teacherTimetableNoticeKey] = '2026-11-16T12:00:00.000Z';
    await pump(tester);
    await openTeachers(tester);
    expect(key('teacher-notice-dialog'), findsNothing);
  });
}
