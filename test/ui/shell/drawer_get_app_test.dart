import 'package:better_betteruntis/app/app_update.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/sync/sync_controller.dart';
import 'package:better_betteruntis/ui/infocenter/info_providers.dart';
import 'package:better_betteruntis/ui/shell/app_drawer.dart';
import 'package:better_betteruntis/ui/timetable/timetable_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<Uri>> pump(WidgetTester tester, {required bool web}) async {
    final opened = <Uri>[];
    // Tall enough that the whole (lazily built) drawer list exists.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isWebProvider.overrideWithValue(web),
          urlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
          appVersionProvider.overrideWith(
            (ref) async => const AppVersion('0.5.0', '91'),
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
    return opened;
  }

  final entry = find.byKey(const ValueKey('drawer-get-app'));

  testWidgets('web: "Get the app" opens the latest release', (tester) async {
    final opened = await pump(tester, web: true);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse(kLatestReleaseUrl)]);
  });

  testWidgets('apps: no "Get the app" entry', (tester) async {
    await pump(tester, web: false);
    expect(entry, findsNothing);
  });
}
