import 'dart:async';

import 'package:better_betteruntis/app/app_update.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/sync/sync_controller.dart';
import 'package:better_betteruntis/ui/shell/app_drawer.dart';
import 'package:better_betteruntis/ui/sync/sync_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _identity = SyncIdentity(
  host: 'demo.invalid',
  school: 'demo',
  userId: '4711',
);
const _passphrase = 'correct horse battery';
const _code = 'ABCD-EFGH-JKLM-NPQR-STUV-WX';

/// Fake engine: records calls, keeps state in memory.
class FakeSync extends SyncController {
  /// State the next instance starts with.
  static Map<String, SyncAccountState> initial = const {};

  /// Whether the server "already has" E2E for the identity (enable → locked).
  static bool serverHasE2e = false;

  final calls = <String>[];

  /// When set, syncNow waits for it.
  Completer<void>? syncGate;

  @override
  Map<String, SyncAccountState> build() => initial;

  void _set(SyncAccountState s) => state = {...state, s.accountId: s};

  SyncAccountState _on(String id, {required bool e2e}) => SyncAccountState(
    accountId: id,
    phase: SyncPhase.on,
    identity: _identity,
    e2e: e2e,
    lastSync: DateTime(2026, 11, 15, 10, 30),
  );

  @override
  Future<SyncEnableResult> enable(String id, SyncEnableOptions o) async {
    calls.add('enable:${o.passphrase}:${o.withRecoveryCode}');
    if (serverHasE2e) {
      final s = SyncAccountState(
        accountId: id,
        phase: SyncPhase.locked,
        identity: _identity,
        e2e: true,
      );
      _set(s);
      return SyncEnableResult(state: s);
    }
    final e2e = o.passphrase != null;
    final s = _on(id, e2e: e2e);
    _set(s);
    return SyncEnableResult(
      state: s,
      recoveryCode: e2e && o.withRecoveryCode ? _code : null,
    );
  }

  @override
  Future<SyncAccountState> unlock(String id, String secret) async {
    calls.add('unlock:$secret');
    if (secret != _passphrase && secret != _code) {
      throw const SyncException('Wrong passphrase.', wrongSecret: true);
    }
    final s = _on(id, e2e: true);
    _set(s);
    return s;
  }

  @override
  Future<SyncAccountState> syncNow(String id) async {
    calls.add('syncNow');
    final before = stateOf(id);
    _set(
      SyncAccountState(
        accountId: id,
        phase: before.phase,
        identity: before.identity,
        e2e: before.e2e,
        lastSync: before.lastSync,
        syncing: true,
      ),
    );
    await syncGate?.future;
    final s = _on(id, e2e: before.e2e);
    _set(s);
    return s;
  }

  @override
  Future<void> disable(String id) async {
    calls.add('disable');
    _set(SyncAccountState(accountId: id));
  }

  @override
  Future<void> signOutDevice(String id) async => calls.add('signOutDevice');

  @override
  Future<SyncEnableResult> enableE2e(
    String id,
    String passphrase, {
    bool withRecoveryCode = true,
  }) async {
    calls.add('enableE2e:$passphrase:$withRecoveryCode');
    final s = _on(id, e2e: true);
    _set(s);
    return SyncEnableResult(
      state: s,
      recoveryCode: withRecoveryCode ? _code : null,
    );
  }

  @override
  Future<void> disableE2e(String id) async {
    calls.add('disableE2e');
    _set(_on(id, e2e: false));
  }

  @override
  Future<void> changePassphrase(String id, String p) async =>
      calls.add('changePassphrase:$p');

  @override
  Future<String> regenerateRecoveryCode(String id) async {
    calls.add('regenerateRecoveryCode');
    return _code;
  }
}

void main() {
  final account = demoAccount();

  setUp(() {
    FakeSync.initial = const {};
    FakeSync.serverHasE2e = false;
  });

  Future<FakeSync> pump(
    WidgetTester tester, {
    Widget? home,
    Size size = const Size(900, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              home ?? const Scaffold(body: Center(child: Text('home'))),
        ),
        GoRoute(path: '/sync', builder: (_, _) => const SyncScreen()),
      ],
      initialLocation: home == null ? '/sync' : '/',
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(
            InMemoryAccountRepository(initial: [account]),
          ),
          appVersionProvider.overrideWith(
            (ref) async => const AppVersion('0.6.0', '1'),
          ),
          timetableRepositoryProvider.overrideWithValue(
            FakeTimetableRepository(),
          ),
          syncControllerProvider.overrideWith(FakeSync.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(Router<Object>));
    return ProviderScope.containerOf(ctx).read(syncControllerProvider.notifier)
        as FakeSync;
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> agreeAndChoose(WidgetTester tester, String choice) async {
    await tap(tester, key('sync-turn-on'));
    expect(key('sync-disclaimer'), findsOneWidget);
    expect(find.textContaining('Cloudflare'), findsOneWidget);
    expect(find.text('Privacy notice'), findsOneWidget);
    await tap(tester, key('sync-agree'));
    expect(key('sync-encryption-choice'), findsOneWidget);
    await tap(tester, key(choice));
  }

  testWidgets('off → opt in with E2E → recovery code → on', (tester) async {
    final sync = await pump(tester);
    expect(find.text('Sync is off'), findsOneWidget);
    await agreeAndChoose(tester, 'sync-choose-e2e');

    // Too short, then not matching, then OK.
    await tester.enterText(key('sync-passphrase'), 'short');
    await tap(tester, key('sync-passphrase-submit'));
    expect(find.text('At least 8 characters'), findsOneWidget);
    await tester.enterText(key('sync-passphrase'), _passphrase);
    await tester.enterText(key('sync-passphrase-repeat'), 'something else');
    await tap(tester, key('sync-passphrase-submit'));
    expect(find.text('Doesn\'t match'), findsOneWidget);
    expect(sync.calls, isEmpty);
    await tester.enterText(key('sync-passphrase-repeat'), _passphrase);
    await tap(tester, key('sync-passphrase-submit'));
    expect(sync.calls, ['enable:$_passphrase:true']);

    // Recovery code: Done only after "I saved it".
    expect(key('sync-recovery-dialog'), findsOneWidget);
    expect(find.text(_code), findsOneWidget);
    await tap(tester, key('sync-recovery-done'));
    expect(key('sync-recovery-dialog'), findsOneWidget);
    await tap(tester, key('sync-recovery-saved'));
    await tap(tester, key('sync-recovery-done'));
    expect(key('sync-recovery-dialog'), findsNothing);

    expect(find.text('Sync is on'), findsOneWidget);
    expect(find.text('Sync account'), findsOneWidget);
    expect(find.text(_identity.toString()), findsOneWidget);
    expect(find.text('End-to-end encryption is on'), findsOneWidget);
    expect(key('sync-change-passphrase'), findsOneWidget);
  });

  testWidgets('opt in without E2E', (tester) async {
    final sync = await pump(tester);
    await agreeAndChoose(tester, 'sync-choose-plain');
    expect(sync.calls, ['enable:null:true']);
    expect(key('sync-recovery-dialog'), findsNothing);
    expect(find.text('Sync is on'), findsOneWidget);
    expect(find.text('End-to-end encryption is off'), findsOneWidget);
    expect(key('sync-e2e-on'), findsOneWidget);
  });

  testWidgets('cancelling the disclaimer does nothing', (tester) async {
    final sync = await pump(tester);
    await tap(tester, key('sync-turn-on'));
    await tap(tester, find.text('Cancel'));
    expect(sync.calls, isEmpty);
    expect(find.text('Sync is off'), findsOneWidget);
  });

  testWidgets('server already encrypted: opt in leads to unlock', (
    tester,
  ) async {
    FakeSync.serverHasE2e = true;
    final sync = await pump(tester);
    await agreeAndChoose(tester, 'sync-choose-plain');
    expect(key('sync-unlock-dialog'), findsOneWidget);
    await tester.enterText(key('sync-unlock-field'), _passphrase);
    await tap(tester, key('sync-unlock-submit'));
    expect(sync.calls.last, 'unlock:$_passphrase');
    expect(find.text('Sync is on'), findsOneWidget);
  });

  testWidgets('locked → wrong passphrase → correct → on', (tester) async {
    FakeSync.initial = {
      'demo': const SyncAccountState(
        accountId: 'demo',
        phase: SyncPhase.locked,
        identity: _identity,
        e2e: true,
      ),
    };
    final sync = await pump(tester);
    expect(find.text('Sync is locked on this device'), findsOneWidget);
    await tap(tester, key('sync-unlock'));
    await tester.enterText(key('sync-unlock-field'), 'wrong one');
    await tap(tester, key('sync-unlock-submit'));
    expect(key('sync-unlock-dialog'), findsOneWidget);
    expect(find.text('Wrong passphrase.'), findsOneWidget);

    // Recovery code works too.
    await tap(tester, key('sync-unlock-toggle'));
    expect(find.text('Recovery code'), findsOneWidget);
    await tester.enterText(key('sync-unlock-field'), _code);
    await tap(tester, key('sync-unlock-submit'));
    expect(sync.calls, ['unlock:wrong one', 'unlock:$_code']);
    expect(key('sync-unlock-dialog'), findsNothing);
    expect(find.text('Sync is on'), findsOneWidget);
  });

  testWidgets('turn off asks first, then calls disable', (tester) async {
    FakeSync.initial = {
      'demo': const SyncAccountState(
        accountId: 'demo',
        phase: SyncPhase.on,
        identity: _identity,
      ),
    };
    final sync = await pump(tester);
    await tap(tester, key('sync-turn-off'));
    expect(find.text('Turn off sync?'), findsOneWidget);
    expect(find.textContaining('deleted'), findsWidgets);
    await tap(tester, find.text('Cancel'));
    expect(sync.calls, isEmpty);

    await tap(tester, key('sync-turn-off'));
    await tap(tester, key('sync-confirm'));
    expect(sync.calls, ['disable']);
    expect(find.text('Sync is off'), findsOneWidget);
  });

  testWidgets('E2E actions: turn on, new code, change, turn off', (
    tester,
  ) async {
    FakeSync.initial = {
      'demo': const SyncAccountState(
        accountId: 'demo',
        phase: SyncPhase.on,
        identity: _identity,
      ),
    };
    final sync = await pump(tester);
    await tap(tester, key('sync-e2e-on'));
    await tester.enterText(key('sync-passphrase'), _passphrase);
    await tester.enterText(key('sync-passphrase-repeat'), _passphrase);
    await tap(tester, key('sync-passphrase-submit'));
    await tap(tester, key('sync-recovery-saved'));
    await tap(tester, key('sync-recovery-done'));
    expect(find.text('End-to-end encryption is on'), findsOneWidget);

    await tap(tester, key('sync-new-recovery'));
    await tap(tester, key('sync-confirm'));
    expect(find.text(_code), findsOneWidget);
    await tap(tester, key('sync-recovery-saved'));
    await tap(tester, key('sync-recovery-done'));

    await tap(tester, key('sync-change-passphrase'));
    await tester.enterText(key('sync-passphrase'), 'new passphrase!');
    await tester.enterText(key('sync-passphrase-repeat'), 'new passphrase!');
    await tap(tester, key('sync-passphrase-submit'));
    expect(key('sync-passphrase-dialog'), findsNothing);

    await tap(tester, key('sync-e2e-off'));
    await tap(tester, key('sync-confirm'));
    expect(sync.calls, [
      'enableE2e:$_passphrase:true',
      'regenerateRecoveryCode',
      'changePassphrase:new passphrase!',
      'disableE2e',
    ]);
    expect(find.text('End-to-end encryption is off'), findsOneWidget);
  });

  testWidgets('signed out view offers turning on again', (tester) async {
    FakeSync.initial = {
      'demo': const SyncAccountState(
        accountId: 'demo',
        phase: SyncPhase.signedOut,
      ),
    };
    await pump(tester);
    expect(find.text('Sync stopped'), findsOneWidget);
    expect(find.textContaining('were kept'), findsOneWidget);
    await tap(tester, key('sync-turn-on-again'));
    expect(key('sync-disclaimer'), findsOneWidget);
  });

  testWidgets('sync now shows progress, error text is shown', (tester) async {
    FakeSync.initial = {
      'demo': const SyncAccountState(
        accountId: 'demo',
        phase: SyncPhase.on,
        identity: _identity,
        error: 'The server could not be reached.',
      ),
    };
    final sync = await pump(tester);
    expect(find.text('The server could not be reached.'), findsOneWidget);
    expect(find.text('Not synced yet'), findsOneWidget);
    sync.syncGate = Completer();
    await tester.tap(key('sync-now'));
    await tester.pump();
    expect(find.text('Syncing…'), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(key('sync-now')).onPressed, isNull);
    sync.syncGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Syncing…'), findsNothing);
    expect(find.textContaining('Last sync:'), findsOneWidget);
    expect(find.text('The server could not be reached.'), findsNothing);
    expect(sync.calls, ['syncNow']);
  });

  testWidgets('large text on a narrow screen: no overflow', (tester) async {
    FakeSync.initial = {
      'demo': const SyncAccountState(
        accountId: 'demo',
        phase: SyncPhase.on,
        identity: _identity,
        e2e: true,
        error: 'The server could not be reached.',
      ),
    };
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, size: const Size(360, 1600));
    expect(tester.takeException(), isNull);
    await tap(tester, key('sync-change-passphrase'));
    expect(tester.takeException(), isNull);
    expect(key('sync-passphrase-dialog'), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsWidgets);
  });

  testWidgets('drawer entry opens the sync screen', (tester) async {
    await pump(
      tester,
      home: Scaffold(
        appBar: AppBar(title: const Text('home')),
        drawer: const AppDrawer(),
      ),
    );
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tap(tester, key('drawer-sync'));
    expect(find.text('Sync is off'), findsOneWidget);
  });
}
