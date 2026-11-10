import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/shell/app_drawer.dart';
import 'package:better_betteruntis/ui/timetable/timetable_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Account _parent({List<AccountChild>? children}) {
  final base = demoAccount();
  return Account(
    id: 'parent',
    school: base.school,
    username: 'parent',
    anonymous: false,
    displayName: 'Demo Parent',
    elementType: ElementType.unknown,
    elementId: 2001,
    children: children ?? FakeUntisApi.demoChildren,
  );
}

void main() {
  late List<TimetableTarget> requested;
  late FakeTimetableRepository timetables;

  setUp(() {
    requested = [];
    timetables = FakeTimetableRepository(
      weekBuilder: (t, w) {
        requested.add(t);
        return buildDemoWeek(w);
      },
    );
  });

  Future<InMemoryAccountRepository> pump(
    WidgetTester tester,
    Account account,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final accounts = InMemoryAccountRepository(initial: [account]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timetableRepositoryProvider.overrideWithValue(timetables),
          accountRepositoryProvider.overrideWithValue(accounts),
        ],
        child: const MaterialApp(home: TimetableScreen(drawer: AppDrawer())),
      ),
    );
    await tester.pumpAndSettle();
    return accounts;
  }

  testWidgets('parent: "My timetable" is the first child', (tester) async {
    await pump(tester, _parent());
    expect(requested, isNotEmpty);
    expect(
      requested.toSet(),
      {const TimetableTarget(ElementType.student, 1001)},
      reason: 'never the unknown parent element',
    );
    expect(find.byKey(const ValueKey('child-label')), findsOneWidget);
    expect(find.text('Demo Child One'), findsOneWidget);
  });

  testWidgets('switching the child in the drawer persists it', (tester) async {
    final accounts = await pump(tester, _parent());
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('child-switcher')), findsOneWidget);
    requested.clear();
    await tester.tap(find.byKey(const ValueKey('child-1002')));
    await tester.pumpAndSettle();
    expect(accounts.active!.selectedChildId, 1002);
    expect(requested, contains(const TimetableTarget(ElementType.student, 1002)));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('child-label'))).data,
      'Demo Child Two',
    );
  });

  testWidgets('one child: no switcher', (tester) async {
    await pump(
      tester,
      _parent(children: [FakeUntisApi.demoChildren.first]),
    );
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('child-switcher')), findsNothing);
  });

  testWidgets('no children: a message instead of a broken timetable', (
    tester,
  ) async {
    await pump(tester, _parent(children: const []));
    expect(find.byKey(const ValueKey('no-personal-timetable')), findsOneWidget);
    expect(find.byKey(const ValueKey('browse-timetables')), findsOneWidget);
    expect(requested, isEmpty);
  });

  testWidgets('student: own element as before, no child label', (
    tester,
  ) async {
    await pump(tester, demoAccount());
    expect(requested.toSet(), {
      const TimetableTarget(ElementType.klasse, DemoIds.klasse),
    });
    expect(find.byKey(const ValueKey('child-label')), findsNothing);
  });

  test('fake API: parent logins', () async {
    final api = FakeUntisApi(latency: Duration.zero);
    final r = await api.login(
      school: FakeUntisApi.schools.first,
      username: 'parent',
      passwordOrKey: 'x',
    );
    expect(r.elementType, ElementType.unknown);
    expect(r.children, hasLength(2));
    final none = await api.login(
      school: FakeUntisApi.schools.first,
      username: 'parent-nochild',
      passwordOrKey: 'x',
    );
    expect(none.children, isEmpty);
  });
}
