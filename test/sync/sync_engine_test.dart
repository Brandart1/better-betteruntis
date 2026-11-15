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
  @override
  Future<String> restAuthToken({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) async => 'untis:${auth.username}';

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
        untisApiProvider.overrideWithValue(_Api()),
        syncClientProvider.overrideWithValue(
          SyncClient(
            dio: Dio()..httpClientAdapter = adapter,
            baseUrl: Uri.parse('https://sync.test'),
          ),
        ),
        syncClockProvider.overrideWithValue(() => clock),
        lessonNotesClockProvider.overrideWithValue(() => clock),
        syncControllerProvider.overrideWith(
          () => SyncEngine(web: web, debounce: debounce),
        ),
      ],
    );
    engine; // starts listening
  }

  final FakeSyncServer server;
  final String accountId;
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

  test('disabling E2E resets the server and re-uploads in plaintext', () async {
    final a = Device(server);
    final b = Device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.write('1', 'one');
    await a.enable('a passphrase');
    await b.enable();
    await a.engine.disableE2e('acc1');
    expect(a.state.e2e, isFalse);
    expect(a.state.phase, SyncPhase.on);
    final n = _ident(server)!.notes.values.single;
    expect(n['text'], 'one');
    expect(_ident(server)!.header, isNull);
    // b (locked) learns that its session died with the reset.
    expect(b.state.phase, SyncPhase.locked);
    await expectLater(
      b.engine.unlock('acc1', 'a passphrase'),
      throwsA(isA<SyncException>()),
    );
    expect(b.state.phase, SyncPhase.signedOut);
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
      expect(a.state.phase, SyncPhase.off);
      expect(a.live, {'1': 'keep me'});
      expect(a.secrets.values, isEmpty);
      expect(a.store.values[SyncEngine.storeKey], isEmpty);

      final s = await b.sync();
      expect(s.phase, SyncPhase.signedOut);
      expect(s.error, isNotNull);
      expect(b.live, {'1': 'keep me'});
      // No automatic re-login.
      expect(server.sessions, isEmpty);
    },
  );

  test('401 → signed out without data loss; enable again works', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    a.write('1', 'one');
    await a.enable();
    server.sessions.clear();
    a.write('2', 'two');
    final s = await a.sync();
    expect(s.phase, SyncPhase.signedOut);
    expect(a.live, {'1': 'one', '2': 'two'});
    expect(a.secrets.values.keys.any((k) => k.startsWith('sync-token')), false);
    expect((await a.enable()).state.phase, SyncPhase.on);
    expect(_ident(server)!.notes.length, 2);
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

  test('clock skew is reported and keeps sync on', () async {
    final a = Device(server);
    addTearDown(a.dispose);
    await a.enable();
    final real = clock;
    clock = clock.add(const Duration(minutes: 10));
    a.write('1', 'from the future');
    clock = real;
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
      SyncClient.errorFor(409, {'error': 'e2e_check_mismatch'}).kind,
      SyncErrorKind.e2eCheckMismatch,
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
}
