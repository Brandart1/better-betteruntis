import 'dart:convert';

import 'package:better_betteruntis/app/app_update.dart';
import 'package:better_betteruntis/app/release_notes.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/release_version.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/infocenter/info_providers.dart';
import 'package:better_betteruntis/ui/shell/app_drawer.dart';
import 'package:better_betteruntis/ui/shell/whats_new.dart';
import 'package:better_betteruntis/ui/timetable/timetable_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _tags = [
  'v0.5.0',
  'v0.4.9-beta',
  'v0.4.8-alpha.3',
  'v0.4.8-alpha.2',
  'v0.4.8-alpha',
  'v0.4.7-beta',
  'v0.4.7-alpha',
  'v0.4.6-beta',
];

/// Fake asset bundle: an index plus one note per tag.
final Map<String, String> _assets = {
  '$releaseNotesAssetDir/index.json': jsonEncode({
    'releases': [
      for (final t in _tags) {'tag': t, 'file': '$t.md'},
    ],
  }),
  for (final t in _tags)
    '$releaseNotesAssetDir/$t.md':
        '## New in this release\n\n### New\n- **Feature** of $t, see '
        '[the docs](https://example.com/$t)\n\n## Install\n\nDownload it.\n',
};

void main() {
  late MemorySettingsStore store;
  late List<Uri> opened;

  setUp(() {
    store = MemorySettingsStore();
    opened = [];
  });

  List<Override> overrides({
    String current = '0.4.8-alpha.3',
    String channel = 'alpha',
    List<Account>? accounts,
  }) => [
    settingsStoreProvider.overrideWithValue(store),
    releaseNotesAssetLoaderProvider.overrideWithValue((path) async {
      final s = _assets[path];
      if (s == null) throw StateError('no asset $path');
      return s;
    }),
    releaseChannelProvider.overrideWithValue(channel),
    currentReleaseProvider.overrideWith(
      (ref) async => ReleaseVersion.tryParse(current),
    ),
    accountsProvider.overrideWith(
      (ref) => Stream.value(accounts ?? [demoAccount()]),
    ),
    urlOpenerProvider.overrideWithValue((uri) async {
      opened.add(uri);
      return true;
    }),
  ];

  Future<void> pump(
    WidgetTester tester, {
    String current = '0.4.8-alpha.3',
    String channel = 'alpha',
    List<Account>? accounts,
  }) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(
          current: current,
          channel: channel,
          accounts: accounts,
        ),
        child: MaterialApp(
          navigatorKey: key,
          builder: (context, child) =>
              WhatsNewChecker(navigatorKey: key, child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final dialog = find.byKey(const ValueKey('whats-new-dialog'));

  testWidgets('fresh install: stores the version silently', (tester) async {
    await pump(tester, current: '0.4.9-beta', channel: 'beta');
    expect(dialog, findsNothing);
    expect(store.values[lastVersionOpenedKey], '0.4.9-beta');
  });

  testWidgets('no account yet (login screen): nothing happens', (tester) async {
    store.values[lastVersionOpenedKey] = '0.4.7-beta';
    await pump(
      tester,
      current: '0.4.9-beta',
      channel: 'beta',
      accounts: const [],
    );
    expect(dialog, findsNothing);
    expect(store.values[lastVersionOpenedKey], '0.4.7-beta');
  });

  testWidgets('same version: no dialog', (tester) async {
    store.values[lastVersionOpenedKey] = '0.4.9-beta';
    await pump(tester, current: '0.4.9-beta', channel: 'beta');
    expect(dialog, findsNothing);
    expect(store.values[lastVersionOpenedKey], '0.4.9-beta');
  });

  testWidgets('downgrade: no dialog, stored version kept', (tester) async {
    store.values[lastVersionOpenedKey] = '0.5.0';
    await pump(tester, current: '0.4.9-beta', channel: 'beta');
    expect(dialog, findsNothing);
    expect(store.values[lastVersionOpenedKey], '0.5.0');
  });

  testWidgets(
    'missed releases: newest expanded, older collapsed, no alphas; stored after Close',
    (tester) async {
      store.values[lastVersionOpenedKey] = '0.4.6-beta';
      await pump(tester, current: '0.5.0', channel: 'stable');
      expect(dialog, findsOneWidget);
      expect(find.text("What's new"), findsOneWidget);
      // Newest first, every missed beta/stable release, nothing older.
      expect(find.text('Version 0.5.0'), findsOneWidget);
      expect(find.text('Version 0.4.9-beta'), findsOneWidget);
      expect(find.text('Version 0.4.7-beta'), findsOneWidget);
      expect(find.text('Version 0.4.6-beta'), findsNothing);
      expect(find.textContaining('alpha'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Version 0.5.0')).dy,
        lessThan(tester.getTopLeft(find.text('Version 0.4.9-beta')).dy),
      );
      // Only the newest is expanded; the intro heading and Install are gone.
      expect(find.textContaining('of v0.5.0'), findsOneWidget);
      expect(find.textContaining('of v0.4.9-beta'), findsNothing);
      expect(find.text('New in this release'), findsNothing);
      expect(find.textContaining('Download it'), findsNothing);
      // Not stored while the dialog is open.
      expect(store.values[lastVersionOpenedKey], '0.4.6-beta');

      await tester.tap(find.text('Version 0.4.9-beta'));
      await tester.pumpAndSettle();
      expect(find.textContaining('of v0.4.9-beta'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('whats-new-close')));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(store.values[lastVersionOpenedKey], '0.5.0');
    },
  );

  testWidgets('beta channel skips alpha notes', (tester) async {
    store.values[lastVersionOpenedKey] = '0.4.6-beta';
    await pump(tester, current: '0.4.9-beta', channel: 'beta');
    expect(find.text('Version 0.4.9-beta'), findsOneWidget);
    expect(find.text('Version 0.4.7-beta'), findsOneWidget);
    expect(find.text('Version 0.4.8-alpha.3'), findsNothing);
    expect(find.text('Version 0.4.7-alpha.1'), findsNothing);
  });

  for (final channel in ['alpha', 'dev']) {
    group('$channel build: never a dialog, nothing stored', () {
      testWidgets('fresh install', (tester) async {
        await pump(tester, channel: channel);
        expect(dialog, findsNothing);
        expect(store.values.containsKey(lastVersionOpenedKey), isFalse);
      });

      testWidgets('missed releases', (tester) async {
        store.values[lastVersionOpenedKey] = '0.4.6-beta';
        await pump(tester, channel: channel);
        expect(dialog, findsNothing);
        expect(store.values[lastVersionOpenedKey], '0.4.6-beta');
      });

      testWidgets('downgrade', (tester) async {
        store.values[lastVersionOpenedKey] = '0.5.0';
        await pump(tester, channel: channel);
        expect(dialog, findsNothing);
        expect(store.values[lastVersionOpenedKey], '0.5.0');
      });
    });
  }

  testWidgets('dismissing by tapping outside also stores the version', (
    tester,
  ) async {
    store.values[lastVersionOpenedKey] = '0.4.7-beta';
    await pump(tester, current: '0.4.9-beta', channel: 'beta');
    expect(dialog, findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(store.values[lastVersionOpenedKey], '0.4.9-beta');
  });

  testWidgets('links in the notes open via the URL opener', (tester) async {
    store.values[lastVersionOpenedKey] = '0.4.7-beta';
    await pump(tester, current: '0.4.9-beta', channel: 'beta');
    final text = find.textContaining('the docs', findRichText: true);
    expect(text, findsOneWidget);
    await tester.tapOnText(find.textRange.ofSubstring('the docs'));
    await tester.pump();
    expect(opened, [Uri.parse('https://example.com/v0.4.9-beta')]);
  });

  testWidgets('disabled: nothing is read or stored', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides(),
          whatsNewCheckEnabledProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          navigatorKey: key,
          builder: (context, child) =>
              WhatsNewChecker(navigatorKey: key, child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.values, isEmpty);
  });

  group('reread from the menu', () {
    testWidgets('drawer entry opens the screen with current and older notes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const TimetableScreen(drawer: AppDrawer()),
          ),
          GoRoute(
            path: '/whats-new',
            builder: (_, _) => const WhatsNewScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides(current: '0.4.8-alpha.2'),
            appVersionProvider.overrideWith(
              (ref) async => const AppVersion('0.4.8', '60'),
            ),
            timetableRepositoryProvider.overrideWithValue(
              FakeTimetableRepository(),
            ),
            accountRepositoryProvider.overrideWithValue(
              InMemoryAccountRepository(initial: [demoAccount()]),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('drawer-whats-new')));
      await tester.pumpAndSettle();

      expect(find.byType(WhatsNewScreen), findsOneWidget);
      // Not newer than the running version; alpha channel shows alphas.
      expect(find.text('Version 0.4.8-alpha.3'), findsNothing);
      expect(find.text('Version 0.4.8-alpha.2'), findsOneWidget);
      expect(find.text('Version 0.4.8-alpha.1'), findsOneWidget);
      expect(find.text('Version 0.4.7-beta'), findsOneWidget);
      expect(find.text('Version 0.4.7-alpha.1'), findsOneWidget);
      expect(find.text('Version 0.4.9-beta'), findsNothing);
      expect(find.textContaining('of v0.4.8-alpha.2'), findsOneWidget);
      // The automatic check never runs in alpha builds.
      expect(store.values.containsKey(lastVersionOpenedKey), isFalse);
    });

    testWidgets('beta channel: no alpha notes', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(current: '0.4.7-beta', channel: 'beta'),
          child: const MaterialApp(home: WhatsNewScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Version 0.4.7-beta'), findsOneWidget);
      expect(find.text('Version 0.4.7-alpha.1'), findsNothing);
      expect(find.textContaining('Version 0.4.8'), findsNothing);
    });

    testWidgets('loads the real bundled notes', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentReleaseProvider.overrideWith(
              (ref) async => ReleaseVersion.tryParse('0.4.8-alpha.7'),
            ),
            releaseChannelProvider.overrideWithValue('alpha'),
          ],
          child: const MaterialApp(home: WhatsNewScreen()),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Version 0.4.8-alpha.7'), findsOneWidget);
      expect(
        find.textContaining('Custom exams', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
