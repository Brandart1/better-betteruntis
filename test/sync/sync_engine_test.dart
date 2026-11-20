import 'package:better_betteruntis/core/accessibility.dart';
import 'package:better_betteruntis/core/favourites.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/lesson_notes.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/data/data_providers.dart';
import 'package:better_betteruntis/data/secret_store.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/sync/sync_client.dart';
import 'package:better_betteruntis/sync/sync_controller.dart';
import 'package:better_betteruntis/sync/sync_engine.dart';
import 'package:better_betteruntis/sync/synced_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sync_server.dart';

class _Api implements UntisApi {
  /// Simulates WebUntis answering for another user.
  String? user;

  /// Thrown by the WebUntis login when set.
  Object? error;

  @override
  Future<String> restAuthToken({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) async {
    if (error case final e?) throw e;
    return 'untis:${user ?? auth.username}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _school = School(
  schoolId: 1,
  loginName: 'Demo-School',
  displayName: 'Demo',
  address: '',
  host: 'demo.webuntis.com',
);

Account _account(String id, String user, {bool anonymous = false}) => Account(
  id: id,
  school: _school,
  username: anonymous ? '#anonymous#' : user,
  anonymous: anonymous,
  displayName: anonymous ? 'Public timetable' : user,
);

/// One app installation.
class Device {
  Device(
    this.server, {
    this.accountId = 'acc1',
    String user = 'max',
    bool web = false,
    Duration debounce = const Duration(seconds: 30),
    MemorySettingsStore? store,
    MemorySecretStore? secrets,
    this.syncUrl = 'https://sync.test',
    bool anonymous = false,
    List<Account> more = const [],
  }) : store = store ?? MemorySettingsStore(),
       secrets = secrets ?? MemorySecretStore(),
       adapter = server.device(browser: web) {
    repo = InMemoryAccountRepository(
      initial: [
        _account(accountId, user, anonymous: anonymous),
        ...more,
      ],
    );
    repo.secrets[accountId] = 'secret';
    c = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(this.store),
        secretStoreProvider.overrideWithValue(this.secrets),
        accountRepositoryProvider.overrideWithValue(repo),
        untisApiProvider.overrideWithValue(api),
        syncClientProvider.overrideWithValue(
          SyncClient(
            dio: Dio()..httpClientAdapter = adapter,
            baseUrl: Uri.parse(syncUrl),
          ),
        ),
        syncClockProvider.overrideWithValue(() => clock),
        lessonNotesClockProvider.overrideWithValue(() => clock),
        syncControllerProvider.overrideWith(
          () => SyncEngine(
            web: web,
            debounce: debounce,
            sleep: (d) async {
              slept.add(d);
              server.resetWriteWindow();
              onSleep?.call();
            },
          ),
        ),
      ],
    );
    engine; // starts listening
  }

  final FakeSyncServer server;
  late final InMemoryAccountRepository repo;
  final String accountId;
  final String syncUrl;
  final api = _Api();
  final slept = <Duration>[];

  /// Called during each rate-limit wait.
  void Function()? onSleep;
  final MemorySettingsStore store;
  final MemorySecretStore secrets;
  final FakeDevice adapter;
  late final ProviderContainer c;

  SyncEngine get engine =>
      c.read(syncControllerProvider.notifier) as SyncEngine;
  SyncAccountState get state => engine.stateOf(accountId);
  LessonNotesNotifier get notes => c.read(lessonNotesProvider.notifier);

  String key(String lesson) => '$accountId|2026-11-16|0800|$lesson|3';

  void write(String lesson, String text, {bool exam = false}) =>
      notes.set([key(lesson)], LessonNote(text: text, exam: exam));

  /// Live notes by lesson.
  Map<String, String> get live => {
    for (final e in c.read(lessonNotesProvider).entries)
      if (!e.value.isEmpty)
        e.key.split('|')[3]: '${e.value.exam ? '[exam] ' : ''}${e.value.text}',
  };

  Future<SyncAccountState> sync() => engine.syncNow(accountId);

  /// Turns sync on and waits for the follow-up upload.
  Future<SyncEnableResult> enable([
    String? passphrase,
    WebKeyRetention retention = WebKeyRetention.standard,
  ]) async {
    final r = await engine.enable(
      accountId,
      SyncEnableOptions(passphrase: passphrase, webKeyRetention: retention),
    );
    await idle();
    return r;
  }

  /// Waits until no operation or (follow-up) sync runs.
  Future<void> idle() => engine.whenIdle(accountId);

  Map<String, LessonNote> get all => c.read(lessonNotesProvider);

  void dispose() => c.dispose();
}

late DateTime clock;

void tick([int ms = 1000]) => clock = clock.add(Duration(milliseconds: ms));

FakeIdentity? _ident(FakeSyncServer s, [String user = 'max']) =>
    s.identity('demo.webuntis.com', 'demo-school', user);

void main() {
  late FakeSyncServer server;
  setUp(() {
    clock = DateTime.utc(2026, 11, 16, 12);
    server = FakeSyncServer(now: () => clock);
  });

  test('two devices converge, including deletions', () async {
    final a = Device(server);
    final b = Device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.write('1', 'Topics 1-3', exam: true);
    a.write('2', 'Bring calculator');
    final r = await a.enable();
    expect(r.state.phase, SyncPhase.on);
    expect(r.state.identity.toString(), contains('max'));
    expect(r.recoveryCode, isNull);
    expect(_ident(server)!.notes.keys, {
      '2026-11-16|0800|1|3',
      '2026-11-16|0800|2|3',
    });
    expect(a.notes.hasDirty('acc1'), isFalse);

    expect((await b.enable()).state.phase, SyncPhase.on);
    expect(b.live, {'1': '[exam] Topics 1-3', '2': 'Bring calculator'});

    tick();
    b.notes.set([b.key('1')], const LessonNote());
    b.write('2', 'Calculator and ruler');
    b.write('3', 'New');
    await b.sync();
    await a.sync();
    expect(a.live, {'2': 'Calculator and ruler', '3': 'New'});
    expect(b.live, a.live);
    expect(_ident(server)!.notes['2026-11-16|0800|1|3']!['deleted'], isTrue);
    expect(a.state.lastSync, clock);
    expect(a.state.error, isNull);
  });

  test('last write wins in both orders', () async {
    final a = Device(server);
    final b = Device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.enable();
    await b.enable();
    // Offline edits: a first, b later; b syncs last.
    a.write('1', 'from a');
    tick();
    b.write('1', 'from b');
    await a.sync();
    await b.sync();
    await a.sync();
    expect(a.live['1'], 'from b');
    expect(b.live['1'], 'from b');

    // The newer edit is pushed first: the older one loses.
    tick();
    a.write('2', 'a older');
    tick();
    b.write('2', 'b newer');
    await b.sync();
    await a.sync();
    await b.sync();
    expect(a.live['2'], 'b newer');
    expect(b.live['2'], 'b newer');
  });

  test('paging pulls everything', () async {
    server.pageSize = 2;
    final a = Device(server);
    final b = Device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    for (var i = 0; i < 5; i++) {
      a.write('$i', 'n$i');
    }
    await a.enable();
    await b.enable();
    expect(b.live.length, 5);
  });

  test('same identity under different local account ids', () async {
    final a = Device(server, accountId: 'local-a');
    final b = Device(server, accountId: 'local-b');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.write('1', 'hello');
    await a.enable();
    await b.enable();
    expect(
      b.c.read(lessonNotesProvider)['local-b|2026-11-16|0800|1|3']!.text,
      'hello',
    );
    expect(
      b.c.read(lessonNotesProvider).keys.any((k) => k.startsWith('local-a')),
      isFalse,
    );
  });

  group('homework', () {
    Future<void> roundTrip(FakeSyncServer server, {String? passphrase}) async {
      final a = Device(server);
      final b = Device(server);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      a.notes.set([
        a.key('1'),
      ], const LessonNote(text: 'Topics', homework: 'S. 12 Nr. 3'));
      // Homework only: a note of its own.
      a.notes.set([a.key('2')], const LessonNote(homework: 'Essay'));
      await a.enable(passphrase);
      if (passphrase == null) {
        expect(
          _ident(server)!.notes['2026-11-16|0800|1|3']!['homework'],
          'S. 12 Nr. 3',
        );
      } else {
        expect(
          _ident(server)!.notes.values
              .every((n) => n['blob'] is String && !n.containsKey('homework')),
          isTrue,
        );
      }
      expect(a.notes.hasDirty('acc1'), isFalse);

      await b.enable();
      if (passphrase != null) await b.engine.unlock('acc1', passphrase);
      expect(
        b.all[b.key('1')],
        const LessonNote(text: 'Topics', homework: 'S. 12 Nr. 3'),
      );
      expect(b.all[b.key('2')], const LessonNote(homework: 'Essay'));

      // Changing only the homework syncs; removing it keeps the rest.
      tick();
      b.notes.set([
        b.key('1'),
      ], const LessonNote(text: 'Topics', homework: 'Nr. 4'));
      b.notes.set([b.key('2')], const LessonNote());
      await b.sync();
      await a.sync();
      expect(
        a.all[a.key('1')],
        const LessonNote(text: 'Topics', homework: 'Nr. 4'),
      );
      expect(a.all[a.key('2')]!.deleted, isTrue);
      tick();
      a.notes.set([a.key('1')], const LessonNote(text: 'Topics'));
      await a.sync();
      await b.sync();
      expect(b.all[b.key('1')], const LessonNote(text: 'Topics'));
      expect(a.notes.hasDirty('acc1'), isFalse);
      expect(b.notes.hasDirty('acc1'), isFalse);
    }

    test('plaintext round trip', () => roundTrip(server));

    test(
      'E2E round trip',
      () => roundTrip(server, passphrase: 'correct horse battery'),
    );

    test('a tie with other homework on the server adopts the server '
        'version', () async {
      final a = Device(server);
      final b = Device(server);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await a.enable();
      await b.enable();
      a.notes.set([a.key('1')], const LessonNote(homework: 'from a'));
      b.notes.set([b.key('1')], const LessonNote(homework: 'from b'));
      await a.sync();
      await b.sync();
      expect(b.all[b.key('1')]!.homework, 'from a');
      expect(b.notes.hasDirty('acc1'), isFalse);
    });
  });

  test('E2E: device B is locked until it unlocks, then converges', () async {
    final a = Device(server);
    final b = Device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.write('1', 'secret topic', exam: true);
    final ra = await a.enable('correct horse battery');
    expect(ra.state.phase, SyncPhase.on);
    expect(ra.state.e2e, isTrue);
    expect(ra.recoveryCode, isNotNull);
    expect(ra.state.hasRecoveryCode, isTrue);
    final stored = _ident(server)!.notes.values.single;
    expect(stored['blob'], isA<String>());
    expect(stored['key'], hasLength(43));
    expect(stored.containsKey('text'), isFalse);

    final rb = await b.enable();
    expect(rb.state.phase, SyncPhase.locked);
    expect(rb.state.hasRecoveryCode, isTrue);
    expect(b.live, isEmpty);
    // Locked: syncNow is a no-op.
    expect((await b.sync()).phase, SyncPhase.locked);

    await expectLater(
      b.engine.unlock('acc1', 'wrong passphrase'),
      throwsA(
        isA<SyncException>().having((e) => e.wrongSecret, 'wrongSecret', true),
      ),
    );
    expect(b.state.phase, SyncPhase.locked);

    // Recovery code, typed sloppily.
    final code = ra.recoveryCode!.toLowerCase().replaceAll('-', ' ');
    final s = await b.engine.unlock('acc1', code);
    expect(s.phase, SyncPhase.on);
    expect(b.live, {'1': '[exam] secret topic'});

    tick();
    b.write('2', 'from b');
    b.notes.set([b.key('1')], const LessonNote());
    await b.sync();
    await a.sync();
    expect(a.live, {'2': 'from b'});
    expect(
      _ident(server)!.notes.values.every((n) => n['blob'] is String),
      isTrue,
    );
  });

  test('turning E2E on elsewhere locks a plaintext device; passphrase '
      'change and recovery code', () async {
    final a = Device(server);
    final b = Device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.write('1', 'one');
    await a.enable();
    await b.enable();
    b.write('2', 'two');
    await b.sync();

    final r = await a.engine.enableE2e('acc1', 'first passphrase');
    await a.idle();
    expect(r.state.e2e, isTrue);
    expect(r.recoveryCode, isNotNull);
    expect(
      _ident(server)!.notes.values.every((n) => n['blob'] is String),
      isTrue,
    );
    expect(_ident(server)!.notes.length, 2);

    // b learns about it from the e2e flag.
    expect((await b.sync()).phase, SyncPhase.locked);
    b.write('3', 'while locked');

    await a.engine.changePassphrase('acc1', 'second passphrase');
    await expectLater(
      b.engine.unlock('acc1', 'first passphrase'),
      throwsA(isA<SyncException>()),
    );
    await b.engine.unlock('acc1', 'second passphrase');
    expect(b.state.phase, SyncPhase.on);
    await a.sync();
    expect(a.live, {'1': 'one', '2': 'two', '3': 'while locked'});

    final code = await a.engine.regenerateRecoveryCode('acc1');
    expect(code, isNot(r.recoveryCode));
    final c = Device(server);
    addTearDown(c.dispose);
    await c.enable();
    await expectLater(
      c.engine.unlock('acc1', r.recoveryCode!),
      throwsA(isA<SyncException>()),
    );
    await c.engine.unlock('acc1', code);
    expect(c.live.length, 3);
  });

  test('disabling E2E keeps sessions; other devices switch to plaintext '
      '(M3)', () async {
    final a = Device(server);
    final b = Device(server);
    final c = Device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    addTearDown(c.dispose);
    a.write('1', 'one');
    await a.enable('a passphrase');
    await b.enable();
    expect(b.state.phase, SyncPhase.locked);
    await c.enable();
    await c.engine.unlock('acc1', 'a passphrase');
    tick();
    c.write('2', 'two');
    await c.sync();
    await a.sync();
    final sessions = server.sessions.length;

    await a.engine.disableE2e('acc1');
    expect(a.state.e2e, isFalse);
    expect(a.state.phase, SyncPhase.on);
    expect(_ident(server)!.header, isNull);
    expect(server.sessions.length, sessions);
    expect(
      {for (final n in _ident(server)!.notes.values) n['text']},
      {'one', 'two'},
    );
    expect(a.secrets.values.keys.any((k) => k.startsWith('sync-dek')), false);

    // The locked device notices on its next sync and syncs in plaintext.
    expect((await b.sync()).phase, SyncPhase.on);
    expect(b.state.e2e, isFalse);
    expect(b.live, {'1': 'one', '2': 'two'});
    // The unlocked one drops its key and switches too.
    tick();
    c.write('3', 'three');
    final sc = await c.sync();
    expect(sc.phase, SyncPhase.on);
    expect(sc.e2e, isFalse);
    expect(c.secrets.values.keys.any((k) => k.startsWith('sync-dek')), false);
    expect(
      _ident(server)!.notes.values.every((n) => n['blob'] == null),
      isTrue,
    );
    await a.sync();
    expect(a.live, {'1': 'one', '2': 'two', '3': 'three'});
  });

  test('disableE2e needs the key on this device', () async {
    final a = Device(server);
    final b = Device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.enable('a passphrase');
    await b.enable();
    await expectLater(
      b.engine.disableE2e('acc1'),
      throwsA(isA<SyncException>()),
    );
    expect(_ident(server)!.header, isNotNull);
  });

  test(
    'disable wipes the server, keeps local notes, signs others out',
    () async {
      final a = Device(server);
      final b = Device(server);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      a.write('1', 'keep me');
      await a.enable();
      await b.enable();
      await a.engine.disable('acc1');
      expect(_ident(server), isNull);
      final puts = server.putRequests;
      expect(a.state.phase, SyncPhase.off);
      expect(a.live, {'1': 'keep me'});
      expect(a.secrets.values, isEmpty);
      expect(a.store.values[SyncEngine.storeKey], isEmpty);

      // b signs in again, gets another epoch of the identity and stops
      // without uploading (C1/H1).
      final s = await b.sync();
      expect(s.phase, SyncPhase.signedOut);
      expect(
        s.error,
        contains('Sync was turned off or reset on another device'),
      );
      expect(b.live, {'1': 'keep me'});
      // Only its own fresh session is deleted, never the identity (H3).
      expect(server.sessions, isEmpty);
      expect(_ident(server)!.notes, isEmpty);
      expect(server.log.where((l) => l == 'DELETE /api/sync/account'), [
        'DELETE /api/sync/account',
      ]);
      expect(server.putRequests, puts);
    },
  );

  test('401 → silent re-login with the same identity continues (M1)', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    a.write('1', 'one');
    await a.enable();
    server.sessions.clear();
    tick();
    a.write('2', 'two');
    final s = await a.sync();
    expect(s.phase, SyncPhase.on);
    expect(s.error, isNull);
    expect(_ident(server)!.notes.length, 2);
    expect(server.sessions.length, 1);
    expect(a.live, {'1': 'one', '2': 'two'});
  });

  test('401 and the re-login is another identity → signed out, nothing '
      'uploaded (M1)', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    a.write('1', 'one');
    await a.enable();
    server.sessions.clear();
    a.api.user = 'moritz';
    a.write('2', 'two');
    final s = await a.sync();
    expect(s.phase, SyncPhase.signedOut);
    expect(s.error, contains('different WebUntis user'));
    expect(_ident(server, 'moritz')?.notes ?? const {}, isEmpty);
    expect(server.sessions, isEmpty);
    expect(a.live, {'1': 'one', '2': 'two'});
    expect(a.secrets.values.keys.any((k) => k.startsWith('sync-token')), false);
    // Turning on again works (as whoever WebUntis says now).
    a.api.user = null;
    expect((await a.enable()).state.phase, SyncPhase.on);
    expect(_ident(server)!.notes.length, 2);
  });

  test('disable refuses when the re-login is another identity (L5)', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    a.write('1', 'one');
    await a.enable();
    server.sessions.clear();
    a.api.user = 'moritz';
    await expectLater(
      a.engine.disable('acc1'),
      throwsA(
        isA<SyncException>().having(
          (e) => e.message,
          'message',
          contains('Nothing was deleted'),
        ),
      ),
    );
    expect(_ident(server)!.notes.length, 1);
    expect(a.state.enabled, isTrue);
    a.api.user = null;
    await a.engine.disable('acc1');
    expect(_ident(server), isNull);
  });

  test('checkServer: new account, then enable reuses its session', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    final check = await a.engine.checkServer('acc1');
    expect([check.existing, check.e2e], [false, false]);
    expect(server.sessions, hasLength(1));
    await a.enable();
    expect(a.state.phase, SyncPhase.on);
    // The check's session was used: no second login.
    expect(server.sessions, hasLength(1));
  });

  test('checkServer finds an existing sync, with and without E2E', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    a.write('1', 'one');
    await a.enable();
    final b = Device(server);
    addTearDown(b.dispose);
    var check = await b.engine.checkServer('acc1');
    expect([check.existing, check.e2e], [true, false]);
    await b.engine.discardCheck('acc1');
    // Only b's session went away; the account and a's session stay.
    expect(server.sessions, hasLength(1));
    expect(_ident(server)!.notes.length, 1);

    await a.engine.enableE2e('acc1', 'correct horse battery');
    await a.idle();
    check = await b.engine.checkServer('acc1');
    expect([check.existing, check.e2e], [true, true]);
    final r = await b.enable();
    expect(r.state.phase, SyncPhase.locked);
  });

  test('discardCheck removes the entry the check created', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    await a.engine.checkServer('acc1');
    expect(_ident(server), isNotNull);
    await a.engine.discardCheck('acc1');
    expect(_ident(server), isNull);
    expect(server.sessions, isEmpty);
    expect(a.state.phase, SyncPhase.off);
    // So the next check doesn't find a "sync".
    expect((await a.engine.checkServer('acc1')).existing, isFalse);
  });

  test('state survives a restart; signOutDevice keeps server data', () async {
    final a = Device(server);
    a.write('1', 'one');
    await a.enable();
    a.dispose();
    final again = Device(server, store: a.store, secrets: a.secrets);
    addTearDown(again.dispose);
    await again.engine.syncAll(force: true);
    expect(again.state.phase, SyncPhase.on);
    expect(again.state.identity?.userId, 'max');
    await again.engine.signOutDevice('acc1');
    expect(again.state.phase, SyncPhase.off);
    expect(server.sessions, isEmpty);
    expect(_ident(server)!.notes.length, 1);
  });

  test('local changes trigger a debounced sync', () async {
    final a = Device(server, debounce: const Duration(milliseconds: 50));
    addTearDown(a.dispose);
    await a.enable();
    final before = server.putRequests;
    a.write('1', 'x');
    a.write('1', 'xy');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(server.putRequests, before);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(server.putRequests, before + 1);
    expect(_ident(server)!.notes.values.single['text'], 'xy');
    // Applying the server's answer doesn't trigger another sync.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(server.putRequests, before + 1);
  });

  test('clock ahead: unsynced stamps are clamped to the server time + 4 '
      'min and retried; edits never go below the replaced version '
      '(H2/M4)', () async {
    final a = Device(server);
    final b = Device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.enable();
    final real = clock;
    clock = clock.add(const Duration(minutes: 10));
    a.write('1', 'from the future');
    final future = a.all[a.key('1')]!.updatedAt;
    for (var i = 0; i < 5; i++) {
      a.write('1', 'from the future $i');
    }
    clock = real;
    a.write('1', 'now');
    // Still above the version it replaced.
    expect(a.all[a.key('1')]!.updatedAt, future + 6);
    clock = clock.add(const Duration(minutes: 10));
    a.write('2', 'ahead again');
    clock = real;
    final s = await a.sync();
    expect(s.phase, SyncPhase.on);
    expect(s.error, isNull);
    expect(a.notes.hasDirty('acc1'), isFalse);
    final limit = clock.add(const Duration(minutes: 4)).millisecondsSinceEpoch;
    expect(_ident(server)!.notes['2026-11-16|0800|1|3']!['updatedAt'], limit);
    expect(_ident(server)!.notes['2026-11-16|0800|2|3']!['updatedAt'], limit);
    expect(_ident(server)!.notes['2026-11-16|0800|1|3']!['text'], 'now');

    // A version from a device whose clock is 4.5 minutes ahead: an edit
    // here is stamped above it and wins.
    await b.enable();
    clock = real.add(const Duration(minutes: 4, seconds: 30));
    b.write('3', 'from b');
    await b.sync();
    clock = real;
    await a.sync();
    a.write('3', 'from a');
    expect(
      a.all[a.key('3')]!.updatedAt,
      greaterThan(
        _ident(server)!.notes['2026-11-16|0800|3|3']!['updatedAt']! as int,
      ),
    );
    expect((await a.sync()).error, isNull);
    await b.sync();
    expect(b.live['3'], 'from a');
  });

  test('clock skew that persists is reported and keeps sync on', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    await a.enable();
    server.alwaysClockSkew = true;
    a.write('1', 'x');
    final s = await a.sync();
    expect(s.phase, SyncPhase.on);
    expect(s.error, contains('clock'));
    expect(a.notes.hasDirty('acc1'), isTrue);
  });

  test('web: cookie auth, one account at a time, key expires after 30 '
      'days', () async {
    final store = MemorySettingsStore();
    final secrets = MemorySecretStore();
    final a = Device(server, web: true, store: store, secrets: secrets);
    a.write('1', 'one');
    await a.enable('web passphrase');
    expect(a.state.phase, SyncPhase.on);
    expect(a.adapter.cookie, isNotNull);
    await expectLater(
      a.engine.enable('acc2', const SyncEnableOptions()),
      throwsA(
        isA<SyncException>().having(
          (e) => e.message,
          'message',
          contains('only supports one synced account'),
        ),
      ),
    );
    expect(secrets.values.keys.any((k) => k.startsWith('sync-token')), false);
    expect(server.log.where((l) => l.contains('/notes')), isNotEmpty);

    // Restart within 30 days: still unlocked.
    final cookie = a.adapter.cookie;
    a.dispose();
    clock = clock.add(const Duration(days: 29));
    final b = Device(server, web: true, store: store, secrets: secrets);
    b.adapter.cookie = cookie;
    expect((await b.sync()).phase, SyncPhase.on);
    b.dispose();

    // After 30 days: the key is dropped, the passphrase is needed again.
    clock = clock.add(const Duration(days: 2));
    final c = Device(server, web: true, store: store, secrets: secrets);
    addTearDown(c.dispose);
    c.adapter.cookie = cookie;
    expect((await c.sync()).phase, SyncPhase.locked);
    expect(secrets.values.keys.any((k) => k.startsWith('sync-dek')), false);
    await c.engine.unlock('acc1', 'web passphrase');
    expect(c.state.phase, SyncPhase.on);
  });

  group('web key retention', () {
    late MemorySettingsStore store;
    late MemorySecretStore secrets;
    String? cookie;
    setUp(() {
      store = MemorySettingsStore();
      secrets = MemorySecretStore();
      cookie = null;
    });

    /// A browser tab (a new engine instance = a reload); shares storage
    /// and the cookie with the earlier tabs.
    Device tab() {
      final d = Device(server, web: true, store: store, secrets: secrets);
      addTearDown(d.dispose);
      if (cookie != null) d.adapter.cookie = cookie;
      return d;
    }

    Future<Device> enabled(WebKeyRetention r) async {
      final d = tab();
      d.write('1', 'one');
      await d.enable('web passphrase', r);
      expect(d.state.phase, SyncPhase.on);
      expect(d.state.webKeyRetention, r);
      cookie = d.adapter.cookie;
      return d;
    }

    bool stored() => secrets.values.keys.any((k) => k.startsWith('sync-dek'));

    for (final (r, ok, gone) in [
      (WebKeyRetention.day, const Duration(hours: 23), const Duration(days: 2)),
      (WebKeyRetention.week, const Duration(days: 6), const Duration(days: 8)),
      (
        WebKeyRetention.month,
        const Duration(days: 29),
        const Duration(days: 31),
      ),
    ]) {
      test('${r.name}: kept within ${r.maxAge}, then asked again', () async {
        final start = clock;
        final a = await enabled(r);
        expect(stored(), isTrue);
        clock = start.add(ok);
        expect((await a.sync()).phase, SyncPhase.on);
        expect((await tab().sync()).phase, SyncPhase.on);
        clock = start.add(gone);
        // Also the key in memory (L7) and after a reload.
        expect((await a.sync()).phase, SyncPhase.locked);
        expect((await tab().sync()).phase, SyncPhase.locked);
        expect(stored(), isFalse);
      });
    }

    test('until sign out: no expiry; signing out removes it', () async {
      final a = await enabled(WebKeyRetention.untilSignOut);
      clock = clock.add(const Duration(days: 400));
      expect((await a.sync()).phase, SyncPhase.on);
      final b = tab();
      expect((await b.sync()).phase, SyncPhase.on);
      expect(b.state.webKeyRetention, WebKeyRetention.untilSignOut);
      await b.engine.signOutDevice('acc1');
      expect(stored(), isFalse);
    });

    test('only this tab: never stored, never expires in the tab, a reload '
        'asks again', () async {
      final a = await enabled(WebKeyRetention.tab);
      expect(stored(), isFalse);
      a.write('2', 'two');
      clock = clock.add(const Duration(days: 400));
      expect((await a.sync()).phase, SyncPhase.on);
      expect(_ident(server)!.notes.length, 2);
      expect(stored(), isFalse);

      final b = tab();
      expect((await b.sync()).phase, SyncPhase.locked);
      expect(b.state.webKeyRetention, WebKeyRetention.tab);
      // Unlocking keeps the persisted choice: still not stored.
      await b.engine.unlock('acc1', 'web passphrase');
      expect(b.state.phase, SyncPhase.on);
      expect(stored(), isFalse);
      // Unlocking with another choice stores it.
      final c = tab();
      expect((await c.sync()).phase, SyncPhase.locked);
      await c.engine.unlock(
        'acc1',
        'web passphrase',
        webKeyRetention: WebKeyRetention.week,
      );
      expect(c.state.webKeyRetention, WebKeyRetention.week);
      expect(stored(), isTrue);
      expect((await tab().sync()).phase, SyncPhase.on);
    });

    test('a shorter time drops an older stored key, the tab keeps '
        'working', () async {
      final a = await enabled(WebKeyRetention.month);
      clock = clock.add(const Duration(days: 3));
      await a.engine.setWebKeyRetention('acc1', WebKeyRetention.week);
      expect(stored(), isTrue, reason: '3 days < 7 days');
      await a.engine.setWebKeyRetention('acc1', WebKeyRetention.day);
      expect(stored(), isFalse);
      expect(a.state.webKeyRetention, WebKeyRetention.day);
      a.write('2', 'two');
      expect((await a.sync()).phase, SyncPhase.on);
      expect(_ident(server)!.notes.length, 2);
      // A reload asks again.
      final b = tab();
      expect(b.state.webKeyRetention, WebKeyRetention.day);
      expect((await b.sync()).phase, SyncPhase.locked);
    });

    test('switching to this tab only removes the stored key now; back to '
        'longer stores it again', () async {
      final a = await enabled(WebKeyRetention.month);
      expect(stored(), isTrue);
      await a.engine.setWebKeyRetention('acc1', WebKeyRetention.tab);
      expect(stored(), isFalse);
      expect((await a.sync()).phase, SyncPhase.on);
      await a.engine.setWebKeyRetention('acc1', WebKeyRetention.month);
      expect(stored(), isTrue);
      expect((await tab().sync()).phase, SyncPhase.on);
    });

    test('a longer time keeps the stored timestamp', () async {
      final start = clock;
      final a = await enabled(WebKeyRetention.day);
      clock = start.add(const Duration(hours: 12));
      await a.engine.setWebKeyRetention('acc1', WebKeyRetention.week);
      clock = start.add(const Duration(days: 6));
      expect((await tab().sync()).phase, SyncPhase.on);
      clock = start.add(const Duration(days: 8));
      expect((await tab().sync()).phase, SyncPhase.locked);
    });

    test('native apps keep the key in secure storage regardless', () async {
      final a = Device(server, store: store, secrets: secrets);
      addTearDown(a.dispose);
      await a.enable('a passphrase', WebKeyRetention.tab);
      expect(a.engine.webKeyChoice, isFalse);
      expect(stored(), isTrue);
      clock = clock.add(const Duration(days: 400));
      expect((await a.sync()).phase, SyncPhase.on);
    });
  });

  test('client batches by count and size', () {
    RemoteNote n(int i, int len) =>
        RemoteNote(key: 'k$i', text: 'x' * len, updatedAt: 1, deleted: false);
    expect(
      SyncClient.batches([for (var i = 0; i < 1200; i++) n(i, 1)])
          .map((b) => b.length)
          .toList(),
      [500, 500, 200],
    );
    final big = SyncClient.batches([for (var i = 0; i < 300; i++) n(i, 4000)]);
    expect(big.length, greaterThan(1));
    for (final b in big) {
      expect(b.length * 4000, lessThan(SyncClient.maxBodyBytes));
    }
  });

  test('client maps errors to user-facing kinds', () {
    expect(
      SyncClient.errorFor(401, {'error': 'unauthorized'}).kind,
      SyncErrorKind.unauthorized,
    );
    expect(
      SyncClient.errorFor(401, {'error': 'invalid_token'}, login: true).kind,
      SyncErrorKind.untisRejected,
    );
    final anon = SyncClient.errorFor(403, {
      'error': 'anonymous_not_allowed',
    }, login: true);
    expect(anon.kind, SyncErrorKind.untisRejected);
    expect(anon.message, kAnonymousSyncMessage);
    expect(SyncClient.errorFor(429, null).kind, SyncErrorKind.rateLimited);
    expect(
      SyncClient.errorFor(400, {'error': 'clock_skew'}).kind,
      SyncErrorKind.clockSkew,
    );
    expect(
      SyncClient.errorFor(413, {'error': 'too_many_notes'}).kind,
      SyncErrorKind.quota,
    );
    expect(
      SyncClient.errorFor(409, {'error': 'e2e_required'}).kind,
      SyncErrorKind.e2eRequired,
    );
    expect(
      SyncClient.errorFor(409, {'error': 'e2e_exists'}).kind,
      SyncErrorKind.e2eExists,
    );
    expect(
      SyncClient.errorFor(403, {'error': 'e2e_auth_failed'}).kind,
      SyncErrorKind.e2eAuthFailed,
    );
    expect(
      SyncClient.errorFor(400, {
        'error': 'clock_skew',
        'serverTime': 1234,
      }).serverTime,
      1234,
    );
    expect(
      SyncClient.errorFor(413, {'error': 'storage_quota'}).message,
      contains('5 MB'),
    );
    expect(SyncClient.errorFor(503, null).kind, SyncErrorKind.server);
  });

  test('network errors leave the state on with an error', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    await a.enable();
    server.forceStatus = 500;
    final s = await a.sync();
    expect(s.phase, SyncPhase.on);
    expect(s.error, isNotNull);
    server.forceStatus = null;
    expect((await a.sync()).error, isNull);
  });

  // ------------------------------------------------------------ findings

  test(
    'C1: failed E2E setup on enable rolls back, nothing in plaintext',
    () async {
      final a = Device(server);
      addTearDown(a.dispose);
      a.write('1', 'secret');
      server.writesPerWindow = 0; // PUT /e2e is refused (429)
      await expectLater(
        a.enable('a passphrase'),
        throwsA(isA<SyncException>()),
      );
      expect(a.state.phase, SyncPhase.off);
      expect(server.sessions, isEmpty);
      expect(a.secrets.values, isEmpty);
      expect(_ident(server)!.notes, isEmpty);
      server.writesPerWindow = null;
      await a.engine.syncAll(force: true);
      expect(_ident(server)!.notes, isEmpty);
      expect(server.putRequests, 0);
    },
  );

  test('C1: lost answers keep the setup pending; the next sync finishes it '
      'encrypted (L1: recovery code flagged)', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    a.write('1', 'secret');
    server.loseAnswer.addAll({'PUT /api/sync/e2e', 'GET /api/sync/e2e'});
    await expectLater(
      a.enable('a passphrase'),
      throwsA(
        isA<SyncException>().having(
          (e) => e.message,
          'message',
          contains('nothing is uploaded unencrypted'),
        ),
      ),
    );
    expect(a.state.phase, SyncPhase.on);
    expect(a.state.e2e, isFalse);
    expect(server.putRequests, 0);
    // Restart: the pending setup survives and finishes.
    a.dispose();
    final b = Device(server, store: a.store, secrets: a.secrets);
    addTearDown(b.dispose);
    final s = await b.sync();
    expect(s.phase, SyncPhase.on);
    expect(s.e2e, isTrue);
    expect(s.error, contains('recovery code'));
    expect(_ident(server)!.notes.values.single['blob'], isA<String>());
    // A new code clears the hint once the user confirms saving it.
    await b.engine.regenerateRecoveryCode('acc1');
    expect((await b.sync()).error, contains('recovery code'));
    await b.engine.acknowledgeRecoveryCode('acc1');
    expect((await b.sync()).error, isNull);
  });

  test('C1: an account meant to be encrypted never pushes plaintext', () async {
    final a = Device(server);
    await a.enable();
    final st = Map<String, Object?>.from(
      a.store.values[SyncEngine.storeKey]! as Map,
    );
    st['acc1'] = {...(st['acc1']! as Map), 'e2ePending': true};
    a.store.values[SyncEngine.storeKey] = st;
    a.dispose();
    final b = Device(server, store: a.store, secrets: a.secrets);
    addTearDown(b.dispose);
    b.write('1', 'must stay local');
    final puts = server.putRequests;
    final s = await b.sync();
    expect(server.putRequests, puts);
    expect(_ident(server)!.notes, isEmpty);
    expect(s.error, contains('encryption'));
    // Finishing it: turn on encryption again.
    await b.engine.enableE2e('acc1', 'a passphrase');
    await b.idle();
    expect(_ident(server)!.notes.values.single['blob'], isA<String>());
  });

  test(
    'C1: enableE2e that fails definitely stays plaintext as before',
    () async {
      final a = Device(server);
      addTearDown(a.dispose);
      a.write('1', 'one');
      await a.enable();
      server.writesPerWindow = 0;
      await expectLater(
        a.engine.enableE2e('acc1', 'a passphrase'),
        throwsA(isA<SyncException>()),
      );
      server.writesPerWindow = null;
      expect(a.state.e2e, isFalse);
      expect(_ident(server)!.header, isNull);
      tick();
      a.write('2', 'two');
      expect((await a.sync()).error, isNull);
      expect(_ident(server)!.notes.length, 2);
    },
  );

  test(
    'H1: remote tombstones are kept and beat older copies after a reset',
    () async {
      final a = Device(server);
      final b = Device(server);
      final c = Device(server);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      addTearDown(c.dispose);
      a.write('1', 'old note');
      await a.enable();
      await b.enable();
      tick();
      a.notes.set([a.key('1')], const LessonNote());
      await a.sync();
      await c.enable();
      expect(c.all[c.key('1')]!.deleted, isTrue);
      // Reset on a; c turns on again first, then b (still has the old copy).
      await a.engine.disable('acc1');
      await c.sync(); // signed out (reset)
      await c.enable();
      await b.sync();
      await b.enable();
      expect(b.live, isEmpty);
      expect(_ident(server)!.notes.values.single['deleted'], isTrue);
    },
  );

  test('H3: a tie keeps the server version on every device', () async {
    final a = Device(server);
    final b = Device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.enable();
    await b.enable();
    tick();
    a.write('1', 'from a');
    b.write('1', 'from b'); // same millisecond
    await a.sync();
    await b.sync();
    expect(b.live['1'], 'from a');
    expect(b.notes.hasDirty('acc1'), isFalse);
    await a.sync();
    expect(a.live['1'], 'from a');
  });

  test(
    'H3: legacy notes (updatedAt 0) are stamped on their first upload',
    () async {
      MemorySettingsStore legacy(String text) => MemorySettingsStore({
        LessonNotesNotifier.storeKey: {
          'acc1|2026-11-16|0800|1|3': {'text': text},
        },
      });
      final a = Device(server, store: legacy('from a'));
      final b = Device(server, store: legacy('from b'));
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await a.enable();
      expect(
        _ident(server)!.notes.values.single['updatedAt'],
        clock.millisecondsSinceEpoch,
      );
      tick();
      await b.enable();
      expect(b.live['1'], 'from a');
      expect(_ident(server)!.notes.values.single['text'], 'from a');
    },
  );

  test('M2: syncNow never throws and resets syncing', () async {
    final secrets = _ThrowingSecrets();
    final a = Device(server, secrets: secrets);
    addTearDown(a.dispose);
    await a.enable();
    secrets.fail = true;
    final s = await a.sync();
    expect(s.syncing, isFalse);
    expect(a.state.syncing, isFalse);
    expect(s.error, isNotNull);
  });

  test('M4: encrypted tombstones', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    a.write('1', 'x');
    await a.enable('a passphrase');
    tick();
    a.notes.set([a.key('1')], const LessonNote());
    await a.sync();
    final n = _ident(server)!.notes.values.single;
    expect(n['deleted'], isTrue);
    expect(n['blob'], isA<String>());
    // Moving the deleted flag breaks the blob: unreadable, not applied.
    n['deleted'] = false;
    n['seq'] = ++_ident(server)!.lastSeq;
    final b = Device(server);
    addTearDown(b.dispose);
    await b.enable('a passphrase');
    expect(b.live, isEmpty);
    expect(b.state.error, contains('could not be synced'));
  });

  test(
    'M5: web, another tab switched the cookie → stop, nothing applied',
    () async {
      final a = Device(server, web: true);
      final m = Device(server, web: true, user: 'moritz');
      addTearDown(a.dispose);
      addTearDown(m.dispose);
      a.write('1', 'max note');
      await a.enable();
      m.write('1', 'moritz note');
      await m.enable();
      a.adapter.cookie = m.adapter.cookie;
      tick();
      a.write('2', 'max only');
      final puts = server.putRequests;
      final s = await a.sync();
      expect(s.phase, SyncPhase.signedOut);
      expect(s.error, contains('another account'));
      expect(a.live, {'1': 'max note', '2': 'max only'});
      expect(server.putRequests, puts);
      expect(
        _ident(server, 'moritz')!.notes.values.single['text'],
        'moritz note',
      );
      final requests = server.log.length;
      await a.sync();
      expect(server.log.length, requests);
    },
  );

  test('M5: web guard reads the state another tab stored', () async {
    final store = MemorySettingsStore();
    final secrets = MemorySecretStore();
    final tab2 = Device(
      server,
      web: true,
      accountId: 'acc2',
      store: store,
      secrets: secrets,
    );
    final tab1 = Device(server, web: true, store: store, secrets: secrets);
    addTearDown(tab1.dispose);
    addTearDown(tab2.dispose);
    await tab1.enable();
    await expectLater(
      tab2.enable(),
      throwsA(
        isA<SyncException>().having(
          (e) => e.message,
          'message',
          contains('only supports one synced account'),
        ),
      ),
    );
  });

  test(
    'L1: lost answers of PUT/PATCH /e2e are resolved by re-reading',
    () async {
      final a = Device(server);
      addTearDown(a.dispose);
      a.write('1', 'one');
      server.loseAnswer.add('PUT /api/sync/e2e');
      final r = await a.enable('a passphrase');
      expect(r.state.e2e, isTrue);
      expect(r.recoveryCode, isNotNull);

      server.loseAnswer.add('PATCH /api/sync/e2e');
      final code = await a.engine.regenerateRecoveryCode('acc1');
      final b = Device(server);
      addTearDown(b.dispose);
      await b.enable();
      await b.engine.unlock('acc1', code);
      expect(b.live, {'1': 'one'});

      server.loseAnswer.add('PATCH /api/sync/e2e');
      server.onHandled = (r) {
        // The re-read after the lost PATCH answer fails too.
        if (r == 'PATCH /api/sync/e2e') {
          server.loseAnswer.add('GET /api/sync/e2e');
        }
      };
      await expectLater(
        a.engine.regenerateRecoveryCode('acc1'),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('may have stopped working'),
          ),
        ),
      );
      expect(a.state.error, contains('recovery code'));
    },
  );

  test('L3: only e2e_not_enabled means "no E2E"', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    await a.enable();
    final client = a.c.read(syncClientProvider);
    final token = a.secrets.values['sync-token|acc1'];
    expect(await client.getE2e(token), isNull);
    server.forceStatus = 404;
    await expectLater(client.getE2e(token), throwsA(isA<SyncApiException>()));
  });

  test('L6: lastSeq is stored only after the pulled notes', () async {
    final store = _RecordingStore();
    final a = Device(server);
    final b = Device(server, store: store);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.write('1', 'one');
    await a.enable();
    await b.enable();
    final notesAt = store.order.indexWhere(
      (e) => e.startsWith('lessonNotes:') && e != 'lessonNotes:0',
    );
    final seqAt = store.order.indexWhere(
      (e) => e.startsWith('syncState:') && e != 'syncState:0',
    );
    expect(notesAt, greaterThanOrEqualTo(0));
    expect(seqAt, greaterThan(notesAt));
  });

  test('L7: web key expiry also applies to the key in memory', () async {
    final a = Device(server, web: true);
    addTearDown(a.dispose);
    await a.enable('web passphrase');
    clock = clock.add(const Duration(days: 31));
    expect((await a.sync()).phase, SyncPhase.locked);
  });

  test('no sync URL in this build: unavailable', () async {
    final a = Device(server, syncUrl: '');
    addTearDown(a.dispose);
    expect(a.engine.available, isFalse);
    await expectLater(
      a.enable(),
      throwsA(
        isA<SyncException>().having(
          (e) => e.message,
          'message',
          contains("isn't available"),
        ),
      ),
    );
    expect(server.log, isEmpty);
  });

  test('a big upload waits for the write rate limit and continues', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    for (var i = 0; i < 600; i++) {
      a.write('$i', 'n$i');
    }
    server.writesPerWindow = 1;
    final r = await a.enable();
    expect(r.state.error, isNull);
    expect(a.slept, [const Duration(seconds: 60)]);
    expect(_ident(server)!.notes.length, 600);
    expect(a.notes.hasDirty('acc1'), isFalse);
  });

  // ------------------------------------------------------- second review

  test(
    'C1/H1: web, another tab turned sync on again after a reset (new '
    'epoch, same identity) → stop, nothing pushed, nothing deleted',
    () async {
      final a = Device(server, web: true);
      final other = Device(server);
      final tab2 = Device(server, web: true);
      addTearDown(a.dispose);
      addTearDown(other.dispose);
      addTearDown(tab2.dispose);
      a.write('1', 'max note');
      await a.enable();
      final epoch = a.state.identity!.epoch;
      expect(epoch, hasLength(22));
      expect(a.store.values[SyncEngine.storeKey], isA<Map>());
      // Reset on another device, then another tab turns sync on again.
      await other.enable();
      await other.engine.disable('acc1');
      await tab2.enable();
      expect(_ident(server)!.epoch, isNot(epoch));
      a.adapter.cookie = tab2.adapter.cookie;
      tick();
      a.write('2', 'only here');
      final puts = server.putRequests;
      final sessions = server.sessions.length;
      final s = await a.sync();
      expect(s.phase, SyncPhase.signedOut);
      expect(
        s.error,
        contains('Sync was turned off or reset on another device'),
      );
      expect(server.putRequests, puts);
      // The other tab's session (the shared cookie) is not deleted.
      expect(server.sessions.length, sessions);
      expect(a.live, {'1': 'max note', '2': 'only here'});
    },
  );

  test('H1: a re-login into the same epoch pulls from 0 and re-uploads what '
      'the server lacks (e.g. after a database restore)', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    a.write('1', 'one');
    a.write('2', 'two');
    await a.enable();
    // Restore to a point where note 2 didn't exist; seqs went back.
    final ident = _ident(server)!;
    ident.notes.remove('2026-11-16|0800|2|3');
    ident.lastSeq = 1;
    server.sessions.clear();
    final writes = server.noteWrites;
    final s = await a.sync();
    expect(s.phase, SyncPhase.on);
    expect(s.error, isNull);
    expect(ident.notes.keys, contains('2026-11-16|0800|2|3'));
    // Only the missing note was written again.
    expect(server.noteWrites, writes + 1);
  });

  test(
    'full push skips notes the server already has in that version',
    () async {
      final a = Device(server);
      final b = Device(server);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      for (var i = 0; i < 5; i++) {
        a.write('$i', 'n$i');
      }
      await a.enable();
      expect(server.noteWrites, 5);
      final puts = server.putRequests;
      await b.enable();
      expect(b.live.length, 5);
      expect(server.putRequests, puts);
      expect(server.noteWrites, 5);
      // Unlocking / mode changes also do a full push: nothing to write.
      server.sessions.clear();
      await a.sync();
      expect(server.noteWrites, 5);
    },
  );

  test('daily write limit: no waiting, a clear message, continues at the '
      'next trigger', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    a.write('1', 'one');
    a.write('2', 'two');
    server.dailyWrites = 1;
    final r = await a.enable();
    expect(r.state.phase, SyncPhase.on);
    expect(a.state.error, 'Daily sync limit reached, continues tomorrow.');
    expect(a.slept, isEmpty);
    expect(a.notes.hasDirty('acc1'), isTrue);
    server.dailyWrites = 5000;
    final s = await a.sync();
    expect(s.error, isNull);
    expect(_ident(server)!.notes.length, 2);
    expect(
      SyncClient.errorFor(429, {'error': 'daily_limit'}).kind,
      SyncErrorKind.dailyLimit,
    );
  });

  test('M5: a transient re-login failure keeps sync on and retries; a '
      'definite one signs out', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    a.write('1', 'one');
    await a.enable();
    server.sessions.clear();
    server.sessionStatus = 503;
    tick();
    a.write('2', 'two');
    var s = await a.sync();
    expect(s.phase, SyncPhase.on);
    expect(s.error, contains('signing in again failed'));
    server.sessionStatus = 429;
    s = await a.sync();
    expect(s.phase, SyncPhase.on);
    server.sessionStatus = null;
    a.api.error = const UntisException(0, 'offline');
    s = await a.sync();
    expect(s.phase, SyncPhase.on);
    a.api.error = null;
    s = await a.sync();
    expect(s.phase, SyncPhase.on);
    expect(s.error, isNull);
    expect(_ident(server)!.notes.length, 2);

    server.sessions.clear();
    a.api.error = const UntisException(
      UntisException.invalidPassword,
      'bad credentials',
    );
    s = await a.sync();
    expect(s.phase, SyncPhase.signedOut);
    expect(a.live, {'1': 'one', '2': 'two'});
  });

  test(
    'M5: WebUntis rejected the token at the sync server → signed out',
    () async {
      final a = Device(server);
      addTearDown(a.dispose);
      await a.enable();
      server.sessions.clear();
      server.sessionStatus = 401;
      expect((await a.sync()).phase, SyncPhase.signedOut);
    },
  );

  test('M6: enable returns the recovery code before the upload; the hint '
      'stays until the code is acknowledged', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    a.write('1', 'one');
    final r = await a.engine.enable(
      'acc1',
      const SyncEnableOptions(passphrase: 'a passphrase'),
    );
    expect(r.recoveryCode, isNotNull);
    expect(r.state.e2e, isTrue);
    // The upload runs as a follow-up.
    expect(_ident(server)!.notes, isEmpty);
    await a.idle();
    expect(_ident(server)!.notes.values.single['blob'], isA<String>());
    // Killed before "I saved it": reminded.
    expect(a.state.error, contains('recovery code'));
    await a.engine.acknowledgeRecoveryCode('acc1');
    expect(a.state.error, isNull);
    expect((await a.sync()).error, isNull);
    // Persisted.
    final st = (a.store.values[SyncEngine.storeKey]! as Map)['acc1'] as Map;
    expect(st.containsKey('recoveryUnseen'), isFalse);
  });

  test('M9: while a setup is pending, enableE2e finishes it first', () async {
    final a = Device(server);
    final b = Device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.write('1', 'secret');
    server.loseAnswer.addAll({'PUT /api/sync/e2e', 'GET /api/sync/e2e'});
    await expectLater(a.enable('a passphrase'), throwsA(isA<SyncException>()));
    expect(a.state.e2eSetupPending, isTrue);
    final r = await a.engine.enableE2e('acc1', 'other passphrase');
    await a.idle();
    expect(r.state.e2e, isTrue);
    expect(r.recoveryCode, isNull);
    expect(a.state.e2eSetupPending, isFalse);
    // The first passphrase is the one in use; the code is flagged.
    expect(a.state.error, contains('recovery code'));
    await b.enable();
    await b.engine.unlock('acc1', 'a passphrase');
    expect(b.live, {'1': 'secret'});
  });

  test(
    'M7: a user operation cancels a sync waiting for the rate limit',
    () async {
      final a = Device(server);
      addTearDown(a.dispose);
      for (var i = 0; i < 600; i++) {
        a.write('$i', 'n$i');
      }
      server.writesPerWindow = 1;
      Future<void>? off;
      a.onSleep = () => off ??= a.engine.disable('acc1');
      await a.engine.enable('acc1', const SyncEnableOptions());
      await a.idle();
      await off;
      expect(a.slept, hasLength(1));
      expect(server.putRequests, 1);
      expect(a.state.phase, SyncPhase.off);
      expect(_ident(server), isNull);
    },
  );

  test('M8: a failed notes write does not advance lastSeq', () async {
    final store = _FailingNotesStore();
    final a = Device(server, store: store);
    final b = Device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.enable();
    await b.enable();
    b.write('1', 'from b');
    await b.sync();
    int seq() =>
        ((store.values[SyncEngine.storeKey]! as Map)['acc1'] as Map)['lastSeq']
            as int;
    final before = seq();
    store.failNotes = true;
    final s = await a.sync();
    expect(s.error, contains('could not be saved'));
    expect(seq(), before);
    store.failNotes = false;
    expect((await a.sync()).error, isNull);
    expect(seq(), greaterThan(before));
    expect(
      (store.values[LessonNotesNotifier.storeKey]! as Map).keys,
      contains(a.key('1')),
    );
  });

  test(
    '10: saving merges per account (another engine on the same store)',
    () async {
      final store = MemorySettingsStore();
      final secrets = MemorySecretStore();
      final one = Device(server, store: store, secrets: secrets);
      final two = Device(
        server,
        accountId: 'acc2',
        user: 'moritz',
        store: store,
        secrets: secrets,
      );
      addTearDown(one.dispose);
      addTearDown(two.dispose);
      await one.enable();
      await two.enable(); // its in-memory state doesn't know acc1
      final st = store.values[SyncEngine.storeKey]! as Map;
      expect(st.keys, unorderedEquals(['acc1', 'acc2']));
    },
  );

  test('10: web, another tab turned sync off → this tab re-reads it', () async {
    final store = MemorySettingsStore();
    final secrets = MemorySecretStore();
    final tab1 = Device(server, web: true, store: store, secrets: secrets);
    await tab1.enable();
    final tab2 = Device(server, web: true, store: store, secrets: secrets);
    tab2.adapter.cookie = tab1.adapter.cookie;
    addTearDown(tab1.dispose);
    addTearDown(tab2.dispose);
    expect(tab2.state.phase, SyncPhase.on);
    await tab1.engine.disable('acc1');
    final requests = server.log.length;
    final s = await tab2.sync();
    expect(s.phase, SyncPhase.off);
    expect(server.log.length, requests);
    expect(store.values[SyncEngine.storeKey], isEmpty);
  });

  test('11: E2E turned off elsewhere clears a stale setup intent', () async {
    final a = Device(server);
    final b = Device(server);
    addTearDown(b.dispose);
    await a.enable('a passphrase');
    await b.enable();
    await b.engine.unlock('acc1', 'a passphrase');
    final st = Map<String, Object?>.from(
      a.store.values[SyncEngine.storeKey]! as Map,
    );
    st['acc1'] = {...(st['acc1']! as Map), 'e2ePending': true};
    a.store.values[SyncEngine.storeKey] = st;
    a.dispose();
    final a2 = Device(server, store: a.store, secrets: a.secrets);
    addTearDown(a2.dispose);
    await b.engine.disableE2e('acc1');
    tick();
    a2.write('1', 'plain now');
    final s = await a2.sync();
    expect(s.e2e, isFalse);
    expect(s.error, isNull);
    expect(_ident(server)!.notes['2026-11-16|0800|1|3']!['text'], 'plain now');
  });

  test('12: E2E turned off between the login and GET /e2e: enable with a '
      'passphrase sets it up', () async {
    final a = Device(server);
    final b = Device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await b.enable('b passphrase');
    a.write('1', 'secret');
    server.onHandled = (r) {
      if (r == 'POST /api/sync/session') {
        _ident(server)!
          ..header = null
          ..notes.clear();
        server.onHandled = null;
      }
    };
    final r = await a.enable('a passphrase');
    expect(r.state.e2e, isTrue);
    expect(r.recoveryCode, isNotNull);
    expect(_ident(server)!.notes.values.single['blob'], isA<String>());
  });

  test('14: a note the server keeps an unreadable newer version of is not '
      're-sent until it changes; other notes still go', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    a.write('1', 'one');
    await a.enable('a passphrase');
    tick();
    a.write('1', 'edited');
    final at = a.all[a.key('1')]!.updatedAt;
    // The server's version is newer and can't be read (its stamp doesn't
    // match the blob).
    final n = _ident(server)!.notes.values.single;
    n['updatedAt'] = at + 60000;
    n['seq'] = ++_ident(server)!.lastSeq;
    final puts = server.putRequests;
    var s = await a.sync();
    expect(s.error, contains('could not be synced'));
    s = await a.sync();
    expect(server.putRequests, puts);
    expect(a.notes.hasDirty('acc1'), isTrue);
    // Normal changes still go.
    tick();
    a.write('2', 'two');
    s = await a.sync();
    expect(server.putRequests, puts + 1);
    expect(_ident(server)!.notes.length, 2);
    // Changing the note sends it again (the server keeps its newer one).
    tick();
    a.write('1', 'again');
    await a.sync();
    expect(server.putRequests, puts + 2);
    await a.sync();
    expect(server.putRequests, puts + 2);
  });

  test('H3: disable never deletes an identity of another epoch', () async {
    final a = Device(server);
    final c = Device(server);
    final d = Device(server);
    addTearDown(a.dispose);
    addTearDown(c.dispose);
    addTearDown(d.dispose);
    a.write('1', 'one');
    await a.enable();
    await c.enable();
    await c.engine.disable('acc1');
    d.write('2', 'new start');
    await d.enable();
    await expectLater(
      a.engine.disable('acc1'),
      throwsA(
        isA<SyncException>().having(
          (e) => e.message,
          'message',
          contains('nothing was deleted'),
        ),
      ),
    );
    expect(a.state.phase, SyncPhase.off);
    expect(_ident(server)!.notes.keys, ['2026-11-16|0800|2|3']);
    expect(d.state.phase, SyncPhase.on);
  });

  test('503 busy on PUT /notes is retried once', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    await a.enable();
    server.busyPuts = 1;
    a.write('1', 'one');
    expect((await a.sync()).error, isNull);
    expect(a.slept, [const Duration(seconds: 5)]);
    expect(_ident(server)!.notes.length, 1);
    server.busyPuts = 2;
    tick();
    a.write('1', 'two');
    expect((await a.sync()).error, isNotNull);
    expect(a.notes.hasDirty('acc1'), isTrue);
  });

  test('client: epoch from identity objects and the /e2e header', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    await a.enable();
    final client = a.c.read(syncClientProvider);
    final token = a.secrets.values['sync-token|acc1'];
    final epoch = _ident(server)!.epoch;
    expect((await client.getNotes(token, 0)).identity!.epoch, epoch);
    expect((await client.getE2eState(token)).epoch, epoch);
    expect((await client.getE2eState(token)).header, isNull);
    expect(a.state.identity!.epoch, epoch);
  });

  group('synced settings', () {
    TimetableSettings tt(Device d) => d.c.read(timetableSettingsProvider);
    AccessibilitySettings a11y(Device d) => d.c.read(accessibilityProvider);
    void setTt(Device d, TimetableSettings Function(TimetableSettings) f) =>
        d.c.read(timetableSettingsProvider.notifier).update(f);
    void setA11y(
      Device d,
      AccessibilitySettings Function(AccessibilitySettings) f,
    ) => d.c.read(accessibilityProvider.notifier).update(f);
    Map<String, Map<String, Object?>> records() => _ident(server)!.notes;

    test('two devices converge on colours and text (plaintext)', () async {
      final a = Device(server);
      final b = Device(server);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await a.enable();
      tick();
      setTt(
        a,
        (s) => s
            .copyWith(
              examColor: 0xFFFF0000,
              subjectFontSize: 18,
              boldSubject: false,
            )
            .withSubjectColor('ma', 0xFF00FF00),
      );
      await a.sync();
      final r = records();
      expect(r.keys.toSet(), {
        'settings|timetable.examColor',
        'settings|timetable.subjectFontSize',
        'settings|timetable.boldSubject',
        'settings|timetable.subjectColor.MA',
      });
      expect(r['settings|timetable.examColor']!['exam'], false);
      expect(r['settings|timetable.examColor']!['text'], '${0xFFFF0000}');
      expect(r['settings|timetable.subjectFontSize']!['text'], '18');

      await b.enable();
      expect(tt(b), tt(a));
      expect(tt(b).subjectColorFor('Ma'), 0xFF00FF00);
      // Never lesson notes.
      expect(b.all, isEmpty);
      expect(b.state.error, isNull);
      // Nothing sent back (b only adopted).
      final writes = server.noteWrites;
      await b.sync();
      await a.sync();
      expect(server.noteWrites, writes);
    });

    test('E2E: settings are encrypted like notes and converge', () async {
      final a = Device(server);
      final b = Device(server);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      a.write('1', 'note');
      await a.enable('a passphrase');
      tick();
      setTt(a, (s) => s.withSubjectColor('D', 0xFF123456));
      setA11y(a, (s) => s.copyWith(textScale: 1.3));
      await a.sync();
      expect(records().length, 3);
      for (final k in records().keys) {
        expect(k, isNot(contains('|')));
        expect(records()[k]!['text'], isNull);
      }
      await b.enable('a passphrase');
      expect(tt(b).subjectColorFor('D'), 0xFF123456);
      expect(a11y(b).textScale, 1.3);
      expect(b.live, {'1': 'note'});
      expect(b.all.keys.single, b.key('1'));
      expect(b.state.error, isNull);
    });

    test('accessibility changed on A shows up on B', () async {
      final a = Device(server);
      final b = Device(server);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await a.enable();
      await b.enable();
      tick();
      setA11y(
        a,
        (s) => s.copyWith(
          contrast: ContrastMode.dark,
          dayViewByDefault: true,
          speechLanguage: SpeechLanguage.de,
          speechRate: 1.5,
        ),
      );
      await a.sync();
      await b.sync();
      expect(a11y(b), a11y(a));
      expect(a11y(b).contrast, ContrastMode.dark);
    });

    test('last write wins per setting; different subjects merge', () async {
      final a = Device(server);
      final b = Device(server);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await a.enable();
      await b.enable();
      tick();
      setTt(
        a,
        (s) => s.copyWith(examColor: 0xFF111111).withSubjectColor('MA', 1),
      );
      tick();
      setTt(
        b,
        (s) => s.copyWith(examColor: 0xFF222222).withSubjectColor('DE', 2),
      );
      // The older change syncs last: still loses.
      await b.sync();
      await a.sync();
      await b.sync();
      expect(tt(a).examColor, 0xFF222222);
      expect(tt(b).examColor, 0xFF222222);
      expect(tt(a).subjectColors, {'MA': 1, 'DE': 2});
      expect(tt(b), tt(a));
    });

    test('reset to default propagates as a tombstone', () async {
      final a = Device(server);
      final b = Device(server);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      setTt(
        a,
        (s) => s.copyWith(regularColor: 0xFF00AA00).withSubjectColor('MA', 5),
      );
      await a.enable();
      await b.enable();
      expect(tt(b).regularColor, 0xFF00AA00);
      tick();
      a.c.read(timetableSettingsProvider.notifier).reset();
      await a.sync();
      expect(records()['settings|timetable.regularColor']!['deleted'], true);
      expect(records()['settings|timetable.subjectColor.MA']!['deleted'], true);
      await b.sync();
      expect(tt(b), const TimetableSettings());
      // A device that joins later doesn't get the reset values either.
      final c = Device(server);
      addTearDown(c.dispose);
      await c.enable();
      expect(tt(c), const TimetableSettings());
    });

    test('settings from before sync: the synced version wins, the rest is '
        'uploaded', () async {
      final a = Device(
        server,
        store: MemorySettingsStore({
          'timetable': const TimetableSettings(examColor: 0xFF0000AA).toJson(),
        }),
      );
      addTearDown(a.dispose);
      await a.enable();
      expect(
        records()['settings|timetable.examColor']!['text'],
        '${0xFF0000AA}',
      );
      tick();
      final b = Device(
        server,
        store: MemorySettingsStore({
          'timetable': const TimetableSettings(
            examColor: 0xFFBBBBBB,
            centerText: false,
          ).toJson(),
        }),
      );
      addTearDown(b.dispose);
      await b.enable();
      expect(tt(b).examColor, 0xFF0000AA);
      expect(tt(b).centerText, isFalse);
      await a.sync();
      expect(tt(a).centerText, isFalse);
    });

    test('invalid and unknown remote settings are skipped, oversized ones '
        'counted', () async {
      final a = Device(server);
      addTearDown(a.dispose);
      await a.enable();
      void put(String key, String text) => records()[key] = {
        'key': key,
        'exam': false,
        'text': text,
        'updatedAt': clock.millisecondsSinceEpoch,
        'deleted': false,
        'seq': ++_ident(server)!.lastSeq,
      };
      put('settings|timetable.examColor', '"red"'); // wrong type
      put('settings|timetable.subjectFontSize', '99'); // out of range
      put('settings|timetable.subjectColor.ma', '1'); // not normalised
      put('settings|from.a.newer.version', '1'); // unknown: ignored
      await a.sync();
      expect(tt(a), const TimetableSettings());
      expect(a.all, isEmpty);
      expect(
        a.state.error,
        contains('3 notes or settings could not be synced'),
      );

      tick();
      setTt(a, (s) => s.withSubjectColor('X' * 300, 7));
      await a.sync();
      expect(records().keys.where((k) => k.contains('XXX')), isEmpty);
      expect(a.state.error, contains('could not be synced'));
    });

    test('device-specific data is never uploaded', () async {
      final a = Device(server);
      addTearDown(a.dispose);
      await a.store.write('calendarSync', [
        {'id': 'x', 'secret': 'calendar'},
      ]);
      await a.store.write('lastVersionOpened', '0.5.0');
      await a.store.write('activeAccountId', 'acc1');
      setTt(a, (s) => s.copyWith(showCancelled: false));
      await a.enable();
      expect(records().keys.toSet(), {'settings|timetable.showCancelled'});
      for (final n in records().values) {
        expect('${n['text']}', isNot(contains('calendar')));
      }
    });

    group('favourites', () {
      Set<String> favs(Device d) =>
          d.c.read(favouritesProvider)[d.accountId] ?? const {};
      void star(Device d, ElementType t, int id, {String? account}) => d.c
          .read(favouritesProvider.notifier)
          .toggle(account ?? d.accountId, t, id);

      test('starred and unstarred on one device, the same on the other '
          '(also under another local account id)', () async {
        final a = Device(server);
        final b = Device(server, accountId: 'other-local-id');
        addTearDown(a.dispose);
        addTearDown(b.dispose);
        await a.enable();
        tick();
        star(a, ElementType.klasse, 40);
        star(a, ElementType.teacher, 2);
        await a.sync();
        expect(records()['settings|favourite.CLASS#40']!['text'], 'true');
        expect(records()['settings|favourite.TEACHER#2']!['text'], 'true');

        await b.enable();
        expect(favs(b), {'CLASS#40', 'TEACHER#2'});

        tick();
        star(b, ElementType.teacher, 2); // unstar
        await b.sync();
        expect(records()['settings|favourite.TEACHER#2']!['deleted'], true);
        await a.sync();
        expect(favs(a), {'CLASS#40'});
        // Settings of the timetable are untouched.
        expect(tt(a), const TimetableSettings());
      });

      test(
        "another account's favourites stay off this account's server",
        () async {
          final a = Device(server, more: [_account('acc2', 'lisa')]);
          addTearDown(a.dispose);
          await a.enable();
          tick();
          star(a, ElementType.klasse, 7, account: 'acc2');
          star(a, ElementType.klasse, 40);
          await a.sync();
          expect(
            records().keys.where((k) => k.startsWith('settings|favourite.')),
            ['settings|favourite.CLASS#40'],
          );
        },
      );

      test(
        'names and values that are no favourites are refused or ignored',
        () {
          expect(isFavouriteSetting('favourite.CLASS#40'), isTrue);
          expect(isFavouriteSetting('favourite.ROOM#4'), isTrue);
          expect(isFavouriteSetting('favourite.SUBJECT#4'), isFalse);
          expect(
            readRemoteSetting('favourite.CLASS#40', 'true'),
            isA<SettingValue>().having((v) => v.value, 'value', true),
          );
          expect(
            readRemoteSetting('favourite.CLASS#40', 'false'),
            isA<InvalidSetting>(),
          );
          expect(
            readRemoteSetting('favourite.CLASS#40', '', deleted: true),
            isA<SettingValue>().having((v) => v.value, 'value', null),
          );
          // e.g. new types from a newer version: ignored, not an error.
          expect(
            readRemoteSetting('favourite.SUBJECT#4', 'true'),
            isA<UnknownSetting>(),
          );
          expect(
            splitAccountSetting(accountSettingKey('acc1', 'favourite.CLASS#4')),
            ('acc1', 'favourite.CLASS#4'),
          );
          expect(splitAccountSetting('timetable.examColor'), isNull);
        },
      );
    });

    test('namespaces: notes stay notes, settings records stored as notes by '
        'older versions are dropped and not re-sent as notes', () async {
      final a = Device(
        server,
        store: MemorySettingsStore({
          LessonNotesNotifier.storeKey: {
            'acc1|settings|timetable.examColor': {
              'text': '123',
              'updatedAt': 5,
            },
          },
        }),
      );
      addTearDown(a.dispose);
      a.write('1', 'a lesson note');
      await a.enable();
      expect(records().keys.toSet(), {'2026-11-16|0800|1|3'});
      expect(a.all.keys, [a.key('1')]);
      expect(tt(a), const TimetableSettings());
      expect(isSettingsKey('2026-11-16|0800|1|3'), isFalse);
      expect(isSettingsKey(settingsRemoteKey('timetable.examColor')), isTrue);
    });
  });

  group('anonymous (public timetable) accounts never sync', () {
    Map<String, Object?> storedState(Device d) => {
      ...?(d.store.values[SyncEngine.storeKey] as Map?)?.map(
        (k, v) => MapEntry('$k', v),
      ),
    };

    test('turning sync on is refused without asking the server', () async {
      final a = Device(server, anonymous: true);
      addTearDown(a.dispose);
      a.write('1', 'note');
      await expectLater(
        a.engine.enable('acc1', const SyncEnableOptions()),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            kAnonymousSyncMessage,
          ),
        ),
      );
      await a.idle();
      expect(a.state.phase, SyncPhase.off);
      expect(server.log, isEmpty);
      expect(storedState(a), isEmpty);
      expect(a.secrets.values.keys.where((k) => k.startsWith('sync-')), []);
      expect(a.live, {'1': 'note'});
    });

    test(
      'state left from before is dropped at start, nothing is sent',
      () async {
        // Sync on for acc1 (as a personal account) ...
        final store = MemorySettingsStore();
        final secrets = MemorySecretStore();
        final a = Device(server, store: store, secrets: secrets);
        a.write('1', 'note');
        await a.enable('passphrase 123');
        expect(a.state.phase, SyncPhase.on);
        a.dispose();
        expect(storedState(a), contains('acc1'));
        expect(
          secrets.values.keys.where((k) => k.startsWith('sync-')),
          isNotEmpty,
        );

        // ... and now it is anonymous.
        final requests = server.log.length;
        final b = Device(
          server,
          store: store,
          secrets: secrets,
          anonymous: true,
        );
        addTearDown(b.dispose);
        await b.engine.syncAll(force: true);
        await b.idle();
        b.write('2', 'later');
        expect((await b.sync()).phase, SyncPhase.off);
        await b.idle();
        expect(b.state.phase, SyncPhase.off);
        expect(b.engine.state, isEmpty);
        expect(storedState(b), isEmpty);
        expect(secrets.values.keys.where((k) => k.startsWith('sync-')), []);
        expect(server.log.length, requests);
        expect(b.live, {'1': 'note', '2': 'later'});
      },
    );

    test('an account that becomes anonymous stops syncing', () async {
      final a = Device(server);
      addTearDown(a.dispose);
      await a.enable();
      expect(a.state.phase, SyncPhase.on);
      final requests = server.log.length;
      await a.repo.update(_account('acc1', 'max', anonymous: true));
      // The next sync (here: a note change) drops it instead.
      a.write('1', 'note');
      expect((await a.sync()).phase, SyncPhase.off);
      await a.idle();
      expect(a.state.phase, SyncPhase.off);
      expect(storedState(a), isEmpty);
      expect(a.secrets.values.keys.where((k) => k.startsWith('sync-')), []);
      await a.engine.syncAll(force: true);
      expect(server.log.length, requests);
    });

    test('web: its old state does not block the personal account', () async {
      final store = MemorySettingsStore({
        SyncEngine.storeKey: {
          'anon': {
            'phase': 'on',
            'identity': {
              'host': 'demo.webuntis.com',
              'school': 'demo-school',
              'userId': 'someone',
            },
            'e2e': false,
            'lastSeq': 0,
          },
        },
      });
      final a = Device(
        server,
        web: true,
        store: store,
        more: [_account('anon', '', anonymous: true)],
      );
      addTearDown(a.dispose);
      a.write('1', 'note');
      final r = await a.enable();
      expect(r.state.phase, SyncPhase.on);
      await a.engine.whenIdle('anon');
      expect(a.engine.stateOf('anon').phase, SyncPhase.off);
      expect(storedState(a).keys, ['acc1']);
      await expectLater(
        a.engine.enable('anon', const SyncEnableOptions()),
        throwsA(isA<SyncException>()),
      );
      expect(a.engine.stateOf('acc1').phase, SyncPhase.on);
    });
  });
}

class _ThrowingSecrets extends MemorySecretStore {
  bool fail = false;
  @override
  Future<String?> read(String accountId) async {
    if (fail) throw StateError('keystore broken');
    return super.read(accountId);
  }
}

/// Records the order of writes: `key:count` (notes) / `key:lastSeq`.
class _RecordingStore extends MemorySettingsStore {
  final order = <String>[];
  @override
  Future<void> write(String key, Object? value) async {
    if (key == LessonNotesNotifier.storeKey) {
      order.add('$key:${(value as Map).length}');
    } else if (key == SyncEngine.storeKey) {
      final acc = (value as Map)['acc1'];
      order.add('$key:${acc is Map ? acc['lastSeq'] : 0}');
    }
    await Future<void>.delayed(Duration.zero);
    await super.write(key, value);
  }
}

/// Fails writes of the lesson notes while [failNotes].
class _FailingNotesStore extends MemorySettingsStore {
  bool failNotes = false;
  @override
  Future<void> write(String key, Object? value) async {
    if (failNotes && key == LessonNotesNotifier.storeKey) {
      throw StateError('disk full');
    }
    await super.write(key, value);
  }
}
