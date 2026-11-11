import 'package:better_betteruntis/app/app_update.dart';
import 'package:better_betteruntis/core/build_channel.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/infocenter/info_providers.dart';
import 'package:better_betteruntis/ui/shell/app_drawer.dart';
import 'package:better_betteruntis/ui/shell/update_check.dart';
import 'package:better_betteruntis/ui/timetable/timetable_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final releaseUrl = latestReleasePage;

  late int fetches;
  late List<Uri> opened;

  setUp(() {
    fetches = 0;
    opened = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    bool enabled = true,
    AppVersion? current = const AppVersion('0.4.4', '19'),
    ReleaseInfo? latest,
  }) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateCheckEnabledProvider.overrideWithValue(enabled),
          appVersionProvider.overrideWith((ref) async => current),
          latestReleaseFetcherProvider.overrideWithValue(() async {
            fetches++;
            return latest;
          }),
          urlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(
          navigatorKey: key,
          builder: (context, child) =>
              UpdateChecker(navigatorKey: key, child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('newer release: dialog with versions, link and Open GitHub', (
    tester,
  ) async {
    await pump(
      tester,
      latest: ReleaseInfo(tag: 'v0.4.5-beta', url: releaseUrl),
    );
    expect(find.byKey(const ValueKey('update-dialog')), findsOneWidget);
    expect(
      find.text('Version 0.4.5 is available. You have 0.4.4.'),
      findsOneWidget,
    );
    expect(find.text(releaseUrl.toString()), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('update-open')));
    await tester.pumpAndSettle();
    expect(opened, [releaseUrl]);
    expect(find.byKey(const ValueKey('update-dialog')), findsNothing);
  });

  testWidgets('Later closes the dialog without opening anything', (
    tester,
  ) async {
    await pump(
      tester,
      latest: ReleaseInfo(tag: 'v0.4.5-beta', url: releaseUrl),
    );
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('update-dialog')), findsNothing);
    expect(opened, isEmpty);
  });

  testWidgets('same or older release: no dialog', (tester) async {
    await pump(
      tester,
      latest: ReleaseInfo(tag: 'v0.4.4-beta', url: releaseUrl),
    );
    expect(fetches, 1);
    expect(find.byKey(const ValueKey('update-dialog')), findsNothing);
  });

  testWidgets('lookup failed: no dialog', (tester) async {
    await pump(tester);
    expect(fetches, 1);
    expect(find.byKey(const ValueKey('update-dialog')), findsNothing);
  });

  testWidgets('disabled (web, dev builds): GitHub is not asked', (
    tester,
  ) async {
    await pump(
      tester,
      enabled: false,
      latest: ReleaseInfo(tag: 'v9.0.0-beta', url: releaseUrl),
    );
    expect(fetches, 0);
    expect(find.byKey(const ValueKey('update-dialog')), findsNothing);
  });

  testWidgets('the drawer shows the app version and channel', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith(
            (ref) async => const AppVersion('0.4.4', '19'),
          ),
          timetableRepositoryProvider.overrideWithValue(
            FakeTimetableRepository(),
          ),
          accountRepositoryProvider.overrideWithValue(
            InMemoryAccountRepository(initial: [demoAccount()]),
          ),
        ],
        child: const MaterialApp(home: TimetableScreen(drawer: AppDrawer())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('Version 0.4.4 (19) · $buildChannel'), findsOneWidget);
  });
}
