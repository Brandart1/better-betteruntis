import 'dart:async';
import 'dart:io';

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
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeInstaller implements ApkInstaller {
  bool allowed = true;
  final results = <InstallResult>[];
  final installed = <String>[];
  int settingsOpened = 0;
  Completer<InstallResult>? hold;

  @override
  Future<bool> canRequestInstalls() async => allowed;

  @override
  Future<void> openInstallSettings() async => settingsOpened++;

  @override
  Future<InstallResult> install(File apk) {
    installed.add(apk.path);
    if (hold != null) return hold!.future;
    return Future.value(
      results.isEmpty
          ? const InstallResult(InstallStatus.success)
          : results.removeAt(0),
    );
  }
}

/// Never touches disk or network; the test drives progress and completion.
class _FakeDownloader extends ApkDownloader {
  _FakeDownloader()
    : super(dio: Dio(), directory: () async => Directory('/nonexistent'));

  int cleanups = 0;
  final downloads = <ReleaseAsset>[];
  Completer<File>? pending;
  void Function(int, int)? progress;
  Object? error;

  @override
  Future<void> cleanup() async => cleanups++;

  @override
  Future<File> download(
    ReleaseAsset apk, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) {
    downloads.add(apk);
    if (error != null) return Future.error(error!);
    final c = pending = Completer<File>();
    progress = onProgress;
    cancel?.whenCancel.then((e) {
      if (!c.isCompleted) c.completeError(e);
    });
    return c.future;
  }
}

void main() {
  final releaseUrl = latestReleasePage;

  late int fetches;
  late List<Uri> opened;
  late _FakeInstaller installer;
  late _FakeDownloader downloader;

  setUp(() {
    fetches = 0;
    opened = [];
    installer = _FakeInstaller();
    downloader = _FakeDownloader();
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
          apkInstallerProvider.overrideWithValue(installer),
          apkDownloaderProvider.overrideWithValue(downloader),
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

    testWidgets('Update now: progress, then install of the download', (
      tester,
    ) async {
      await pump(tester, latest: withApk);
      expect(downloader.cleanups, 1, reason: 'old APKs removed at start');
      expect(find.byKey(const ValueKey('update-open')), findsOneWidget);
      await tester.tap(now);
      await tester.pump();
      expect(downloader.downloads, [apk]);
      expect(find.byKey(const ValueKey('update-progress')), findsOneWidget);
      downloader.progress!(40, 100);
      await tester.pump();
      expect(find.text('Downloading… 40 %'), findsOneWidget);

      downloader.pending!.complete(File('/cache/updates/x.apk'));
      await tester.pumpAndSettle();
      expect(installer.installed, ['/cache/updates/x.apk']);
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
      expect(find.byKey(const ValueKey('update-progress')), findsNothing);
      expect(find.text('Update now'), findsOneWidget);
      expect(installer.installed, isEmpty);
    });

    testWidgets('waiting for the system installer shows a hint', (
      tester,
    ) async {
      installer.hold = Completer();
      await pump(tester, latest: withApk);
      await tester.tap(now);
      await tester.pump();
      downloader.pending!.complete(File('/x.apk'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('update-installing')), findsOneWidget);
      installer.hold!.complete(const InstallResult(InstallStatus.aborted));
      await tester.pumpAndSettle();
      expect(find.text('Update now'), findsOneWidget, reason: 'aborted');
    });

    testWidgets('not allowed to install: opens settings and explains', (
      tester,
    ) async {
      installer.allowed = false;
      await pump(tester, latest: withApk);
      await tester.tap(now);
      await tester.pumpAndSettle();
      expect(installer.settingsOpened, 1);
      expect(downloader.downloads, isEmpty);
      expect(
        find.byKey(const ValueKey('update-needs-permission')),
        findsOneWidget,
      );
      // Allowed now: Try again goes through.
      installer.allowed = true;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(downloader.downloads, [apk]);
    });

    testWidgets('download error: message and GitHub fallback', (tester) async {
      downloader.error = const ApkUpdateException(
        'The download is damaged (checksum mismatch).',
      );
      await pump(tester, latest: withApk);
      await tester.tap(now);
      await tester.pumpAndSettle();
      expect(find.textContaining('checksum mismatch'), findsOneWidget);
      expect(installer.installed, isEmpty);
      await tester.tap(find.byKey(const ValueKey('update-open')));
      await tester.pumpAndSettle();
      expect(opened, [latestReleasePage]);
    });

    testWidgets('install failure is reported', (tester) async {
      installer.results.add(
        const InstallResult(InstallStatus.failure, 'INSTALL_FAILED_CONFLICT'),
      );
      await pump(tester, latest: withApk);
      await tester.tap(now);
      await tester.pump();
      downloader.pending!.complete(File('/x.apk'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Installation failed: INSTALL_FAILED_CONFLICT'),
        findsOneWidget,
      );
    });

    testWidgets('iOS and other platforms keep the plain dialog', (
      tester,
    ) async {
      await pump(tester, latest: withApk, inApp: false);
      expect(now, findsNothing);
      expect(downloader.cleanups, 0);
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
