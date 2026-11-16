import 'dart:async';

import 'package:better_betteruntis/app/app_update.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/models.dart';
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

  /// Whether this build has a sync server.
  static bool isAvailable = true;

  /// Web version: only one account can sync.
  static bool singleAccount = false;

  @override
  bool get singleAccountOnly => singleAccount;

  /// Web version: the key retention choice is shown.
  static bool webKeys = false;

  @override
  bool get webKeyChoice => webKeys;

  /// Runs inside enableE2e before it returns.
  static Future<void> Function()? duringEnableE2e;

  @override
  bool get available => isAvailable;

  @override
  Map<String, SyncAccountState> build() => initial;

  void _set(SyncAccountState s) => state = {...state, s.accountId: s};

  SyncAccountState _on(String id, {required bool e2e, bool recovery = false}) =>
      SyncAccountState(
        accountId: id,
        phase: SyncPhase.on,
        identity: _identity,
        e2e: e2e,
        hasRecoveryCode: e2e && recovery,
        lastSync: DateTime(2026, 11, 15, 10, 30),
      );

  /// What checkServer finds (default: nothing, the normal opt-in).
  static SyncServerCheck serverCheck = SyncServerCheck.unknown;

  @override
  Future<SyncServerCheck> checkServer(String id) async => serverCheck;

  @override
  Future<void> discardCheck(String id) async => calls.add('discardCheck');

  @override
  Future<SyncEnableResult> enable(String id, SyncEnableOptions o) async {
    calls.add(
      'enable:${o.passphrase}:${o.withRecoveryCode}'
      '${webKeys ? ':${o.webKeyRetention.name}' : ''}',
    );
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
  Future<SyncAccountState> unlock(
    String id,
    String secret, {
    WebKeyRetention? webKeyRetention,
  }) async {
    calls.add(
      'unlock:$secret${webKeyRetention == null ? '' : ':${webKeyRetention.name}'}',
    );
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
  Future<void> signOutDevice(String id) async {
    calls.add('signOutDevice');
    _set(SyncAccountState(accountId: id));
  }

  @override
  Future<SyncEnableResult> enableE2e(
    String id,
    String passphrase, {
    bool withRecoveryCode = true,
    WebKeyRetention? webKeyRetention,
  }) async {
    calls.add(
      'enableE2e:$passphrase:$withRecoveryCode'
      '${webKeyRetention == null ? '' : ':${webKeyRetention.name}'}',
    );
    await duringEnableE2e?.call();
    final s = _on(id, e2e: true, recovery: withRecoveryCode);
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

  @override
  Future<void> acknowledgeRecoveryCode(String id) async =>
      calls.add('acknowledgeRecoveryCode');

  @override
  Future<void> setWebKeyRetention(String id, WebKeyRetention r) async {
    calls.add('setWebKeyRetention:${r.name}');
    final s = stateOf(id);
    _set(
      SyncAccountState(
        accountId: id,
        phase: s.phase,
        identity: s.identity,
        e2e: s.e2e,
        hasRecoveryCode: s.hasRecoveryCode,
        lastSync: s.lastSync,
        webKeyRetention: r,
      ),
    );
  }
}

void main() {
  final account = demoAccount();

  setUp(() {
    FakeSync.initial = const {};
    FakeSync.serverHasE2e = false;
    FakeSync.serverCheck = SyncServerCheck.unknown;
    FakeSync.isAvailable = true;
    FakeSync.singleAccount = false;
    FakeSync.webKeys = false;
    FakeSync.duringEnableE2e = null;
  });

  late InMemoryAccountRepository repo;

  Future<FakeSync> pump(
    WidgetTester tester, {
    Widget? home,
    Size size = const Size(900, 2400),
    List<Account>? accounts,
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
            repo = InMemoryAccountRepository(initial: accounts ?? [account]),
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
    // Only "I saved it" tells the engine the code is known (M6).
    expect(sync.calls, ['enable:$_passphrase:true', 'acknowledgeRecoveryCode']);

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

  testWidgets('account already syncs without passphrase: only confirm', (
    tester,
  ) async {
    FakeSync.serverCheck = const SyncServerCheck(existing: true, e2e: false);
    final sync = await pump(tester);
    await tap(tester, key('sync-turn-on'));
    await tap(tester, key('sync-agree'));
    expect(key('sync-encryption-choice'), findsNothing);
    expect(find.text('This account already syncs'), findsOneWidget);
    await tap(tester, key('sync-confirm'));
    expect(sync.calls, ['enable:null:true']);
    expect(find.text('Sync is on'), findsOneWidget);
    expect(find.text('End-to-end encryption is off'), findsOneWidget);
  });

  testWidgets('account already syncs: cancelling drops the check', (
    tester,
  ) async {
    FakeSync.serverCheck = const SyncServerCheck(existing: true, e2e: false);
    final sync = await pump(tester);
    await tap(tester, key('sync-turn-on'));
    await tap(tester, key('sync-agree'));
    await tap(tester, find.text('Cancel'));
    expect(sync.calls, ['discardCheck']);
    expect(find.text('Sync is off'), findsOneWidget);
  });

  testWidgets('account already syncs with passphrase: asks for it', (
    tester,
  ) async {
    FakeSync.serverCheck = const SyncServerCheck(existing: true, e2e: true);
    FakeSync.serverHasE2e = true;
    final sync = await pump(tester);
    await tap(tester, key('sync-turn-on'));
    await tap(tester, key('sync-agree'));
    expect(key('sync-encryption-choice'), findsNothing);
    expect(key('sync-unlock-dialog'), findsOneWidget);
    expect(find.textContaining('already end-to-end'), findsOneWidget);
    await tester.enterText(key('sync-unlock-field'), 'wrong one!');
    await tap(tester, key('sync-unlock-submit'));
    expect(find.text('Wrong passphrase.'), findsOneWidget);
    await tester.enterText(key('sync-unlock-field'), _passphrase);
    await tap(tester, key('sync-unlock-submit'));
    expect(sync.calls, [
      'enable:null:true',
      'unlock:wrong one!',
      'unlock:$_passphrase',
    ]);
    expect(find.text('Sync is on'), findsOneWidget);
    expect(find.text('End-to-end encryption is on'), findsOneWidget);
  });

  testWidgets('account already syncs with passphrase: cancel turns it off', (
    tester,
  ) async {
    FakeSync.serverCheck = const SyncServerCheck(existing: true, e2e: true);
    FakeSync.serverHasE2e = true;
    final sync = await pump(tester);
    await tap(tester, key('sync-turn-on'));
    await tap(tester, key('sync-agree'));
    await tap(tester, find.text('Cancel'));
    expect(sync.calls, ['enable:null:true', 'signOutDevice']);
    expect(find.text('Sync is off'), findsOneWidget);
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

    // A code exists: replacing it asks first.
    expect(find.text('New recovery code'), findsOneWidget);
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
      'acknowledgeRecoveryCode',
      'regenerateRecoveryCode',
      'acknowledgeRecoveryCode',
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

  testWidgets('signed out view: forget sync on this device', (tester) async {
    FakeSync.initial = {
      'demo': const SyncAccountState(
        accountId: 'demo',
        phase: SyncPhase.signedOut,
      ),
    };
    final sync = await pump(tester);
    await tap(tester, key('sync-forget'));
    expect(find.text('Forget sync on this device?'), findsOneWidget);
    await tap(tester, key('sync-confirm'));
    expect(sync.calls, ['signOutDevice']);
    expect(find.text('Sync is off'), findsOneWidget);
  });

  testWidgets('no sync server in this build: no opt-in', (tester) async {
    FakeSync.isAvailable = false;
    await pump(tester);
    expect(find.text("Sync isn't available in this build"), findsOneWidget);
    expect(key('sync-turn-on'), findsNothing);
  });

  testWidgets('the recovery code is shown even if the section is gone', (
    tester,
  ) async {
    FakeSync.initial = {
      'demo': const SyncAccountState(
        accountId: 'demo',
        phase: SyncPhase.on,
        identity: _identity,
      ),
    };
    FakeSync.duringEnableE2e = () => repo.delete(account.id);
    await pump(tester);
    await tap(tester, key('sync-e2e-on'));
    await tester.enterText(key('sync-passphrase'), _passphrase);
    await tester.enterText(key('sync-passphrase-repeat'), _passphrase);
    await tap(tester, key('sync-passphrase-submit'));
    expect(find.byType(SyncAccountSection), findsNothing);
    expect(key('sync-recovery-dialog'), findsOneWidget);
    expect(find.text(_code), findsOneWidget);
  });

  testWidgets('a pending E2E setup: "Turn on encryption" is disabled (M9)', (
    tester,
  ) async {
    FakeSync.initial = {
      'demo': const SyncAccountState(
        accountId: 'demo',
        phase: SyncPhase.on,
        identity: _identity,
        e2eSetupPending: true,
      ),
    };
    final sync = await pump(tester);
    expect(find.text('Turning on encryption…'), findsOneWidget);
    await tap(tester, key('sync-e2e-on'));
    expect(key('sync-passphrase-dialog'), findsNothing);
    expect(sync.calls, isEmpty);
  });

  testWidgets('the recovery code is confirmed even if the section is gone', (
    tester,
  ) async {
    FakeSync.initial = {
      'demo': const SyncAccountState(
        accountId: 'demo',
        phase: SyncPhase.on,
        identity: _identity,
      ),
    };
    FakeSync.duringEnableE2e = () => repo.delete(account.id);
    final sync = await pump(tester);
    await tap(tester, key('sync-e2e-on'));
    await tester.enterText(key('sync-passphrase'), _passphrase);
    await tester.enterText(key('sync-passphrase-repeat'), _passphrase);
    await tap(tester, key('sync-passphrase-submit'));
    await tap(tester, key('sync-recovery-saved'));
    await tap(tester, key('sync-recovery-done'));
    expect(sync.calls.last, 'acknowledgeRecoveryCode');
  });

  testWidgets('turning off encryption says other devices switch', (
    tester,
  ) async {
    FakeSync.initial = {
      'demo': const SyncAccountState(
        accountId: 'demo',
        phase: SyncPhase.on,
        identity: _identity,
        e2e: true,
      ),
    };
    await pump(tester);
    await tap(tester, key('sync-e2e-off'));
    expect(find.textContaining('stay signed in'), findsOneWidget);
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

  testWidgets('web: a second account explains the single-account limit', (
    tester,
  ) async {
    final other = Account(
      id: 'second',
      school: account.school,
      username: 'second.user',
      anonymous: false,
      displayName: 'Second User',
    );
    FakeSync.singleAccount = true;
    FakeSync.initial = {
      account.id: SyncAccountState(
        accountId: account.id,
        phase: SyncPhase.on,
        identity: const SyncIdentity(
          host: 'demo.webuntis.com',
          school: 'demo',
          userId: '1',
        ),
      ),
    };
    await pump(tester, accounts: [account, other]);
    expect(
      find.byKey(const ValueKey('sync-web-single-account')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sync-get-apps')), findsOneWidget);
    // Only the synced account's section offers sync actions.
    expect(find.byKey(const ValueKey('sync-turn-on')), findsNothing);
  });

  group('anonymous (public timetable) accounts', () {
    final anon = Account(
      id: 'anon',
      school: account.school,
      username: '#anonymous#',
      anonymous: true,
      displayName: 'Public timetable',
    );

    testWidgets('no opt-in, a short explanation instead', (tester) async {
      final sync = await pump(tester, accounts: [anon]);
      expect(key('sync-anonymous'), findsOneWidget);
      expect(
        find.textContaining("Public timetable logins can't sync"),
        findsOneWidget,
      );
      expect(key('sync-turn-on'), findsNothing);
      expect(sync.calls, isEmpty);
    });

    testWidgets('old sync state of it shows no actions', (tester) async {
      FakeSync.initial = {
        anon.id: SyncAccountState(
          accountId: anon.id,
          phase: SyncPhase.on,
          identity: _identity,
        ),
      };
      await pump(tester, accounts: [anon]);
      expect(key('sync-anonymous'), findsOneWidget);
      expect(key('sync-now'), findsNothing);
      expect(key('sync-turn-off'), findsNothing);
    });

    testWidgets('next to a personal account, only that one can sync', (
      tester,
    ) async {
      await pump(tester, accounts: [account, anon]);
      expect(key('sync-anonymous'), findsOneWidget);
      expect(key('sync-turn-on'), findsOneWidget);
    });

    testWidgets('web: its old state does not block the personal account', (
      tester,
    ) async {
      FakeSync.singleAccount = true;
      FakeSync.initial = {
        anon.id: SyncAccountState(
          accountId: anon.id,
          phase: SyncPhase.on,
          identity: _identity,
        ),
      };
      await pump(tester, accounts: [account, anon]);
      expect(key('sync-web-single-account'), findsNothing);
      expect(key('sync-turn-on'), findsOneWidget);
      expect(key('sync-anonymous'), findsOneWidget);
    });
  });

  group('web key retention', () {
    const e2eOn = SyncAccountState(
      accountId: 'demo',
      phase: SyncPhase.on,
      identity: _identity,
      e2e: true,
    );

    Future<void> choose(WidgetTester tester, WebKeyRetention r) async {
      await tap(tester, key('sync-key-retention'));
      await tester.tap(find.text(r.label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('phone apps: no choice anywhere', (tester) async {
      FakeSync.initial = {'demo': e2eOn};
      await pump(tester);
      expect(find.text('End-to-end encryption is on'), findsOneWidget);
      expect(key('sync-key-retention'), findsNothing);
    });

    testWidgets('web: the encryption section shows and changes it', (
      tester,
    ) async {
      FakeSync.webKeys = true;
      FakeSync.initial = {'demo': e2eOn};
      final sync = await pump(tester);
      expect(key('sync-key-retention'), findsOneWidget);
      expect(find.text('Remember key in this browser'), findsOneWidget);
      expect(find.text('30 days'), findsOneWidget);
      expect(find.textContaining('Shorter is safer'), findsOneWidget);
      await choose(tester, WebKeyRetention.tab);
      expect(sync.calls, ['setWebKeyRetention:tab']);
      expect(sync.stateOf('demo').webKeyRetention, WebKeyRetention.tab);
      expect(find.text(WebKeyRetention.tab.label), findsOneWidget);
    });

    testWidgets('web: not shown without encryption', (tester) async {
      FakeSync.webKeys = true;
      FakeSync.initial = {
        'demo': const SyncAccountState(
          accountId: 'demo',
          phase: SyncPhase.on,
          identity: _identity,
        ),
      };
      await pump(tester);
      expect(key('sync-key-retention'), findsNothing);
    });

    testWidgets('web: chosen in the opt-in passphrase dialog', (tester) async {
      FakeSync.webKeys = true;
      final sync = await pump(tester);
      await agreeAndChoose(tester, 'sync-choose-e2e');
      expect(key('sync-key-retention'), findsOneWidget);
      await choose(tester, WebKeyRetention.day);
      await tester.enterText(key('sync-passphrase'), _passphrase);
      await tester.enterText(key('sync-passphrase-repeat'), _passphrase);
      await tap(tester, key('sync-passphrase-submit'));
      expect(sync.calls, ['enable:$_passphrase:true:day']);
    });

    testWidgets('phone apps: the opt-in has no choice', (tester) async {
      await pump(tester);
      await agreeAndChoose(tester, 'sync-choose-e2e');
      expect(key('sync-passphrase-dialog'), findsOneWidget);
      expect(key('sync-key-retention'), findsNothing);
    });

    testWidgets('web: chosen when unlocking (default 30 days)', (tester) async {
      FakeSync.webKeys = true;
      FakeSync.initial = {
        'demo': const SyncAccountState(
          accountId: 'demo',
          phase: SyncPhase.locked,
          identity: _identity,
          e2e: true,
        ),
      };
      final sync = await pump(tester);
      await tap(tester, key('sync-unlock'));
      expect(key('sync-key-retention'), findsOneWidget);
      expect(find.text('30 days'), findsOneWidget);
      await choose(tester, WebKeyRetention.untilSignOut);
      await tester.enterText(key('sync-unlock-field'), _passphrase);
      await tap(tester, key('sync-unlock-submit'));
      expect(sync.calls, ['unlock:$_passphrase:untilSignOut']);
    });

    testWidgets('web: chosen when turning on encryption later', (tester) async {
      FakeSync.webKeys = true;
      FakeSync.initial = {
        'demo': const SyncAccountState(
          accountId: 'demo',
          phase: SyncPhase.on,
          identity: _identity,
        ),
      };
      final sync = await pump(tester);
      await tap(tester, key('sync-e2e-on'));
      await choose(tester, WebKeyRetention.week);
      await tester.enterText(key('sync-passphrase'), _passphrase);
      await tester.enterText(key('sync-passphrase-repeat'), _passphrase);
      await tap(tester, key('sync-passphrase-submit'));
      expect(sync.calls.first, 'enableE2e:$_passphrase:true:week');
    });

    testWidgets('web: narrow screen, large text: no overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      FakeSync.webKeys = true;
      FakeSync.initial = {'demo': e2eOn};
      await pump(tester, size: const Size(360, 2400));
      expect(tester.takeException(), isNull);
      await choose(tester, WebKeyRetention.untilSignOut);
      expect(tester.takeException(), isNull);
    });
  });
}
