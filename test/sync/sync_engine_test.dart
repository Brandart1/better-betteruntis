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
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sync_server.dart';

class _Api implements UntisApi {
  /// Simulates WebUntis answering for another user.
  String? user;

  @override
  Future<String> restAuthToken({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) async => 'untis:${user ?? auth.username}';

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

Account _account(String id, String user) => Account(
  id: id,
  school: _school,
  username: user,
  anonymous: false,
  displayName: user,
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
  }) : store = store ?? MemorySettingsStore(),
       secrets = secrets ?? MemorySecretStore(),
       adapter = server.device(browser: web) {
    final repo = InMemoryAccountRepository(
      initial: [_account(accountId, user)],
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
            },
          ),
        ),
      ],
    );
    engine; // starts listening
  }

  final FakeSyncServer server;
  final String accountId;
  final String syncUrl;
  final api = _Api();
  final slept = <Duration>[];
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
  Future<SyncEnableResult> enable([String? passphrase]) =>
      engine.enable(accountId, SyncEnableOptions(passphrase: passphrase));

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

      // b signs in again, sees the reset and stops without uploading.
      final s = await b.sync();
      expect(s.phase, SyncPhase.signedOut);
      expect(s.error, contains('turned off or reset on another device'));
      expect(b.live, {'1': 'keep me'});
      expect(server.sessions, isEmpty);
      // The empty account the re-login created is removed again.
      expect(_ident(server), isNull);
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

  test('clock ahead: stamps are clamped and retried with the server time '
      '(H2)', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    await a.enable();
    final real = clock;
    clock = clock.add(const Duration(minutes: 10));
    a.write('1', 'from the future');
    // Further edits on a note from the future don't run away.
    for (var i = 0; i < 5; i++) {
      a.write('1', 'from the future $i');
    }
    clock = real;
    a.write('1', 'now');
    expect(
      a.all[a.key('1')]!.updatedAt,
      lessThanOrEqualTo(clock.millisecondsSinceEpoch + 60 * 1000),
    );
    clock = clock.add(const Duration(minutes: 10));
    a.write('2', 'ahead again');
    clock = real;
    final s = await a.sync();
    expect(s.phase, SyncPhase.on);
    expect(s.error, isNull);
    expect(a.notes.hasDirty('acc1'), isFalse);
    expect(
      _ident(server)!.notes['2026-11-16|0800|2|3']!['updatedAt'],
      lessThanOrEqualTo(clock.millisecondsSinceEpoch),
    );
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
          contains('one account'),
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
    // A new code clears the hint.
    await b.engine.regenerateRecoveryCode('acc1');
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
          contains('one account'),
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
