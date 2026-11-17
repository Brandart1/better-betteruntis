import 'dart:async';

import 'package:better_betteruntis/app/apk_update.dart';
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

/// Never touches the platform; the test drives the events.
class _FakeUpdater implements ApkUpdater {
  int cleanups = 0;
  int cancels = 0;
  final started = <ReleaseAsset>[];
  StreamController<ApkUpdateEvent>? events;

  @override
  Stream<ApkUpdateEvent> start(ReleaseAsset apk) {
    started.add(apk);
    return (events = StreamController<ApkUpdateEvent>()).stream;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    events?.add(const ApkUpdateEvent(ApkUpdateStage.canceled));
  }

  @override
  Future<void> cleanup() async => cleanups++;
}

void main() {
  final releaseUrl = latestReleasePage;

  late int fetches;
  late List<Uri> opened;
  late _FakeUpdater updater;

  setUp(() {
    fetches = 0;
    opened = [];
    updater = _FakeUpdater();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool enabled = true,
    AppVersion? current = const AppVersion('0.4.4', '19'),
    ReleaseInfo? latest,
    bool inApp = true,
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
          inAppUpdateSupportedProvider.overrideWithValue(inApp),
          apkUpdaterProvider.overrideWithValue(updater),
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

  group('in-app update (Android)', () {
    final apk = ReleaseAsset(
      name: 'better-betteruntis-v0.4.5-beta.apk',
      url: Uri.parse('https://github.com/a.apk'),
      size: 100,
    );
    final withApk = ReleaseInfo(
      tag: 'v0.4.5-beta',
      url: latestReleasePage,
      apk: apk,
    );
    final now = find.byKey(const ValueKey('update-now'));

    testWidgets('Update now: progress, then installing', (tester) async {
      await pump(tester, latest: withApk);
      expect(updater.cleanups, 1, reason: 'old APKs removed at start');
      expect(find.byKey(const ValueKey('update-open')), findsOneWidget);
      await tester.tap(now);
      await tester.pump();
      expect(updater.started, [apk]);
      expect(find.byKey(const ValueKey('update-progress')), findsOneWidget);
      updater.events!.add(
        const ApkUpdateEvent(ApkUpdateStage.downloading, progress: 0.4),
      );
      await tester.pump();
      expect(find.text('Downloading… 40 %'), findsOneWidget);

      updater.events!.add(const ApkUpdateEvent(ApkUpdateStage.installing));
      await tester.pump();
      expect(find.byKey(const ValueKey('update-installing')), findsOneWidget);
      await updater.events!.close();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('update-installing')),
        findsOneWidget,
        reason: 'the stream ending after installing is not an error',
      );
    });

    testWidgets('installed: dialog closes', (tester) async {
      await pump(tester, latest: withApk);
      await tester.tap(now);
      await tester.pump();
      updater.events!.add(const ApkUpdateEvent(ApkUpdateStage.done));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-dialog')), findsNothing);
    });

    testWidgets('Cancel stops the download and returns to the start', (
      tester,
    ) async {
      await pump(tester, latest: withApk);
      await tester.tap(now);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('update-cancel')));
      await tester.pumpAndSettle();
      expect(updater.cancels, 1);
      expect(find.byKey(const ValueKey('update-progress')), findsNothing);
      expect(find.text('Update now'), findsOneWidget);
    });

    testWidgets('not allowed to install: explains, Try again restarts', (
      tester,
    ) async {
      await pump(tester, latest: withApk);
      await tester.tap(now);
      await tester.pump();
      updater.events!.add(const ApkUpdateEvent(ApkUpdateStage.needsPermission));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('update-needs-permission')),
        findsOneWidget,
      );
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(updater.started, [apk, apk]);
    });

    testWidgets('checksum error: message and GitHub fallback', (tester) async {
      await pump(tester, latest: withApk);
      await tester.tap(now);
      await tester.pump();
      updater.events!.add(
        const ApkUpdateEvent(
          ApkUpdateStage.failed,
          message: 'The download is damaged (checksum mismatch).',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('checksum mismatch'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('update-open')));
      await tester.pumpAndSettle();
      expect(opened, [latestReleasePage]);
    });

    testWidgets('a stream that ends while downloading is a failure', (
      tester,
    ) async {
      await pump(tester, latest: withApk);
      await tester.tap(now);
      await tester.pump();
      await updater.events!.close();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-error')), findsOneWidget);
    });

    testWidgets('iOS and other platforms keep the plain dialog', (
      tester,
    ) async {
      await pump(tester, latest: withApk, inApp: false);
      expect(now, findsNothing);
      expect(updater.cleanups, 0);
      expect(find.text('Open GitHub'), findsOneWidget);
    });

    testWidgets('Android without an APK asset: plain dialog', (tester) async {
      await pump(
        tester,
        latest: ReleaseInfo(tag: 'v0.4.5-beta', url: releaseUrl),
      );
      expect(now, findsNothing);
      expect(find.text('Open GitHub'), findsOneWidget);
    });
  });
}
