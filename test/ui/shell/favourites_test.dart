import 'package:better_betteruntis/core/favourites.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/shell/element_picker_screen.dart';
import 'package:better_betteruntis/ui/shell/teacher_timetable_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  late MemorySettingsStore store;

  setUp(
    () => store = MemorySettingsStore({
      // The Teachers tab's one-time notice is already accepted.
      teacherTimetableNoticeKey: '2026-11-19T00:00:00Z',
    }),
  );

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const ElementPickerScreen()),
        GoRoute(
          path: '/timetable/:type/:id',
          builder: (_, s) => Scaffold(body: Text('timetable ${s.uri}')),
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
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, String k) => tester.getTopLeft(key(k)).dy;

  testWidgets('starred teachers come first under "Favourites", stored per '
      'account', (tester) async {
    await pump(tester);
    await tap(tester, find.widgetWithText(Tab, 'Teachers'));
    expect(find.text('Favourites'), findsNothing);
    expect(
      top(tester, 'browse-teacher-1'),
      lessThan(top(tester, 'browse-teacher-2')),
    );

    await tap(tester, key('browse-star-teacher-2'));
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('All teachers'), findsOneWidget);
    expect(
      top(tester, 'browse-teacher-2'),
      lessThan(top(tester, 'browse-teacher-1')),
    );
    expect(store.values[FavouritesNotifier.storeKey], {
      demoAccount().id: ['TEACHER#2'],
    });

    // Unstarred: back in its place, no header.
    await tap(tester, key('browse-star-teacher-2'));
    expect(find.text('Favourites'), findsNothing);
    expect(
      top(tester, 'browse-teacher-1'),
      lessThan(top(tester, 'browse-teacher-2')),
    );
  });

  testWidgets('classes can be favourites, rooms have no star', (tester) async {
    await pump(tester);
    await tap(tester, key('browse-star-klasse-40'));
    expect(find.text('Favourites'), findsOneWidget);
    // Only favourites: no "All classes" header below them.
    expect(find.text('All classes'), findsNothing);
    await tap(tester, find.widgetWithText(Tab, 'Rooms'));
    expect(find.byIcon(Icons.star_border), findsNothing);
  });

  testWidgets('favourites load from the store; search still filters', (
    tester,
  ) async {
    store.values[FavouritesNotifier.storeKey] = {
      demoAccount().id: [favouriteKey(ElementType.teacher, 2)],
    };
    await pump(tester);
    await tap(tester, find.widgetWithText(Tab, 'Teachers'));
    expect(find.text('Favourites'), findsOneWidget);
    await tester.enterText(key('browse-search'), 'müller');
    await tester.pumpAndSettle();
    expect(find.text('Favourites'), findsNothing);
    expect(key('browse-teacher-1'), findsOneWidget);
  });
}
