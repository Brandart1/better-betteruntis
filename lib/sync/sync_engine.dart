/// The sync engine: implements [SyncController] against the Worker's notes
/// API ([SyncClient]) and the local notes store ([LessonNotesNotifier]).
///
/// Per account:
/// * state (phase, identity, e2e, lastSeq, lastSync, error, pending full
///   upload) persisted in the [SettingsStore] under [SyncEngine.storeKey];
/// * secrets in the [SecretStore]: the session token (native only; the web
///   app uses the HttpOnly cookie) and the cached E2E data key (on the web
///   dropped after [SyncEngine.webDekMaxAge]).
///
/// A sync is pull (`GET /notes?since=lastSeq`, paged, last-write-wins into
/// the local store) then push (local notes changed since they were last
/// acknowledged, or all after a new session / E2E change), in batches of
/// at most 500 notes / ~900 KB. Note keys on the server are the local keys
/// without the leading account id; with E2E the server only sees
/// `serverKey(keys, key)` and the real key travels inside the blob.
///
/// Operations of one account never run concurrently (a per-account lock;
/// sync requests while one runs are coalesced into one follow-up sync).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/lesson_notes.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../core/settings.dart';
import '../data/data_providers.dart';
import '../data/secret_store.dart';
import 'e2e_crypto.dart' as e2e;
import 'e2e_crypto.dart' show E2eHeader, E2eKeys;
import 'sync_client.dart';
import 'sync_controller.dart';

/// The HTTP client of the sync API (tests override it with a fake server).
final syncClientProvider = Provider<SyncClient>((ref) => SyncClient());

/// Clock of the sync engine (tests override it).
final syncClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Server limits for plaintext notes (worker/src/sync/notes.ts).
const int _maxKeyLength = 256;
const int _maxTextLength = 4000;

class _Meta {
  _Meta({this.lastSeq = 0, this.fullPush = false});

  /// Highest server seq applied locally.
  int lastSeq;

  /// Upload every local note at the next sync (new session, E2E change).
  bool fullPush;
}

const Object _keep = Object();

class SyncEngine extends SyncController {
  SyncEngine({
    this.debounce = const Duration(seconds: 3),
    bool? web,
    this.webDekMaxAge = const Duration(days: 30),
    this.resumeInterval = const Duration(minutes: 1),
  }) : web = web ?? kIsWeb;

  /// Delay between a local note change and the sync it triggers.
  final Duration debounce;

  /// Web mode: cookie auth (no stored token), one syncing account at a time
  /// (the browser has a single `bbu_sync` cookie), cached keys expire.
  final bool web;

  /// On the web the cached E2E key is dropped after this long.
  final Duration webDekMaxAge;

  /// [syncAll] skips accounts synced more recently than this.
  final Duration resumeInterval;

  static const storeKey = 'syncState';

  final Map<String, _Meta> _meta = {};
  final Map<String, E2eKeys> _keys = {};
  final Map<String, Future<void>> _locks = {};
  final Map<String, Future<SyncAccountState>> _queued = {};
  Future<void> _loading = Future.value();
  bool _changed = false;
  bool _pruned = false;
  Timer? _debounceTimer;

  SyncClient get _client => ref.read(syncClientProvider);
  SettingsStore get _store => ref.read(settingsStoreProvider);
  SecretStore get _secrets => ref.read(secretStoreProvider);
  LessonNotesNotifier get _notes => ref.read(lessonNotesProvider.notifier);
  DateTime _now() => ref.read(syncClockProvider)();

  static String _tokenId(String accountId) => 'sync-token|$accountId';
  static String _dekId(String accountId) => 'sync-dek|$accountId';

  @override
  Map<String, SyncAccountState> build() {
    ref.listen(lessonNotesProvider, (_, _) => _onNotesChanged());
    ref.onDispose(() => _debounceTimer?.cancel());
    final store = ref.read(settingsStoreProvider);
    final cached = store.peek(storeKey);
    if (cached != null) return _decode(cached);
    _loading = _load(store);
    return const {};
  }

  // ------------------------------------------------------------ persistence

  Map<String, SyncAccountState> _decode(Object? raw) {
    final out = <String, SyncAccountState>{};
    if (raw is! Map) return out;
    for (final e in raw.entries) {
      final id = '${e.key}';
      final v = e.value;
      if (v is! Map) continue;
      final phase = SyncPhase.values.asNameMap()[v['phase']] ?? SyncPhase.off;
      if (phase == SyncPhase.off) continue;
      final ident = v['identity'];
      final last = v['lastSync'];
      final seq = v['lastSeq'];
      out[id] = SyncAccountState(
        accountId: id,
        phase: phase,
        identity: ident is Map
            ? SyncIdentity(
                host: '${ident['host'] ?? ''}',
                school: '${ident['school'] ?? ''}',
                userId: '${ident['userId'] ?? ''}',
              )
            : null,
        e2e: v['e2e'] == true,
        hasRecoveryCode: v['hasRecoveryCode'] == true,
        lastSync: last is num
            ? DateTime.fromMillisecondsSinceEpoch(last.toInt())
            : null,
        error: v['error'] is String ? v['error'] as String : null,
      );
      _meta[id] = _Meta(
        lastSeq: seq is num ? seq.toInt() : 0,
        fullPush: v['fullPush'] == true,
      );
    }
    return out;
  }

  Future<void> _load(SettingsStore store) async {
    try {
      final raw = await store.read(storeKey);
      if (!ref.mounted || _changed || raw == null) return;
      state = _decode(raw);
    } catch (_) {}
  }

  Future<void> _save() {
    final meta = _meta;
    return _store
        .write(storeKey, {
          for (final s in state.values)
            if (s.phase != SyncPhase.off)
              s.accountId: {
                'phase': s.phase.name,
                if (s.identity case final i?)
                  'identity': {
                    'host': i.host,
                    'school': i.school,
                    'userId': i.userId,
                  },
                'e2e': s.e2e,
                if (s.hasRecoveryCode) 'hasRecoveryCode': true,
                if (s.lastSync case final t?)
                  'lastSync': t.millisecondsSinceEpoch,
                'error': ?s.error,
                'lastSeq': meta[s.accountId]?.lastSeq ?? 0,
                if (meta[s.accountId]?.fullPush ?? false) 'fullPush': true,
              },
        })
        .catchError((_) {});
  }

  _Meta _metaOf(String accountId) => _meta.putIfAbsent(accountId, _Meta.new);

  SyncAccountState _update(
    String accountId, {
    SyncPhase? phase,
    Object? identity = _keep,
    bool? e2e,
    bool? hasRecoveryCode,
    Object? lastSync = _keep,
    bool? syncing,
    Object? error = _keep,
  }) {
    final s = stateOf(accountId);
    final next = SyncAccountState(
      accountId: accountId,
      phase: phase ?? s.phase,
      identity: identical(identity, _keep)
          ? s.identity
          : identity as SyncIdentity?,
      e2e: e2e ?? s.e2e,
      hasRecoveryCode: (e2e ?? s.e2e)
          ? hasRecoveryCode ?? s.hasRecoveryCode
          : false,
      lastSync: identical(lastSync, _keep) ? s.lastSync : lastSync as DateTime?,
      syncing: syncing ?? s.syncing,
      error: identical(error, _keep) ? s.error : error as String?,
    );
    if (ref.mounted) {
      _changed = true;
      state = {...state, accountId: next};
      unawaited(_save());
    }
    return next;
  }

  Future<void> _clearLocal(String accountId) async {
    _meta.remove(accountId);
    _keys.remove(accountId);
    if (ref.mounted) {
      _changed = true;
      state = {...state}..remove(accountId);
      await _save();
    }
    await _secrets.delete(_tokenId(accountId)).catchError((_) {});
    await _secrets.delete(_dekId(accountId)).catchError((_) {});
  }

  // ---------------------------------------------------------------- secrets

  /// The session token for requests: null on the web (cookie). Throws
  /// [SyncErrorKind.unauthorized] if a native app has none.
  Future<String?> _sessionToken(String accountId) async {
    if (web) return null;
    final t = await _secrets.read(_tokenId(accountId));
    if (t == null || t.isEmpty) {
      throw const SyncApiException(
        SyncErrorKind.unauthorized,
        'Signed out of sync on this device.',
      );
    }
    return t;
  }

  Future<String?> _storeSession(String accountId, SyncSession s) async {
    if (web) return null;
    await _secrets.write(_tokenId(accountId), s.token);
    return s.token;
  }

  Future<E2eKeys?> _cachedKeys(String accountId) async {
    final mem = _keys[accountId];
    if (mem != null) return mem;
    try {
      final raw = await _secrets.read(_dekId(accountId));
      if (raw == null) return null;
      final j = jsonDecode(raw);
      if (j is! Map || j['dek'] is! String) return null;
      final at = j['at'];
      if (web &&
          (at is! num ||
              _now().difference(
                    DateTime.fromMillisecondsSinceEpoch(at.toInt()),
                  ) >
                  webDekMaxAge)) {
        await _secrets.delete(_dekId(accountId));
        return null;
      }
      final keys = await E2eKeys.fromDek(e2e.b64uDecode(j['dek'] as String));
      return _keys[accountId] = keys;
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheKeys(String accountId, E2eKeys keys) async {
    _keys[accountId] = keys;
    await _secrets.write(
      _dekId(accountId),
      jsonEncode({
        'dek': e2e.b64uEncode(keys.dekBytes),
        'at': _now().millisecondsSinceEpoch,
      }),
    );
  }

  Future<void> _dropKeys(String accountId) async {
    _keys.remove(accountId);
    await _secrets.delete(_dekId(accountId)).catchError((_) {});
  }

  /// Cached keys of [accountId] if they belong to [header].
  Future<E2eKeys?> _matchingKeys(String accountId, E2eHeader header) async {
    final keys = await _cachedKeys(accountId);
    if (keys == null) return null;
    if (await keys.matchesHeader(header)) return keys;
    await _dropKeys(accountId);
    return null;
  }

  // ------------------------------------------------------------ concurrency

  Future<void> _ready() async {
    await _loading;
    await _notes.ready;
  }

  /// Runs [fn] after every earlier operation of [accountId] finished.
  Future<T> _exclusive<T>(String accountId, Future<T> Function() fn) async {
    final prev = _locks[accountId] ?? Future<void>.value();
    final done = Completer<void>();
    final mine = done.future;
    _locks[accountId] = mine;
    try {
      await prev.catchError((_) {});
      return await fn();
    } finally {
      done.complete();
      if (identical(_locks[accountId], mine)) _locks.remove(accountId);
    }
  }

  // --------------------------------------------------------------- triggers

  void _onNotesChanged() {
    final due = [
      for (final s in state.values)
        if (s.phase == SyncPhase.on && _notes.hasDirty(s.accountId))
          s.accountId,
    ];
    if (due.isEmpty) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      if (!ref.mounted) return;
      for (final id in due) {
        unawaited(syncNow(id).then((_) {}, onError: (_) {}));
      }
    });
  }

  /// Syncs every account that syncs (app start / resume). Unless [force],
  /// accounts synced within [resumeInterval] are skipped. Also prunes old
  /// tombstones of accounts that don't sync (once per app run).
  Future<void> syncAll({bool force = false}) async {
    await _ready();
    if (!ref.mounted) return;
    if (!_pruned) {
      _pruned = true;
      _notes.pruneTombstones((id) => stateOf(id).enabled);
    }
    final now = _now();
    await Future.wait([
      for (final s in state.values)
        if (s.phase == SyncPhase.on &&
            (force ||
                s.lastSync == null ||
                now.difference(s.lastSync!) >= resumeInterval))
          syncNow(s.accountId),
    ]);
  }

  // ------------------------------------------------------------------- sync

  @override
  Future<SyncAccountState> syncNow(String accountId) async {
    await _ready();
    if (stateOf(accountId).phase != SyncPhase.on) return stateOf(accountId);
    // Coalesce: at most one sync waiting behind the running one.
    final queued = _queued[accountId];
    if (queued != null) return queued;
    final f = _exclusive(accountId, () {
      _queued.remove(accountId);
      return _syncOnce(accountId);
    });
    _queued[accountId] = f;
    return f;
  }

  /// One sync; errors end up in the state (never thrown). Call with the
  /// account's lock held.
  Future<SyncAccountState> _syncOnce(String accountId) async {
    if (stateOf(accountId).phase != SyncPhase.on) return stateOf(accountId);
    _update(accountId, syncing: true);
    try {
      final skipped = await _pullPush(accountId);
      if (stateOf(accountId).phase != SyncPhase.on) {
        return _update(accountId, syncing: false);
      }
      return _update(
        accountId,
        syncing: false,
        lastSync: _now(),
        error: skipped == 0
            ? null
            : '$skipped note${skipped == 1 ? '' : 's'} could not be synced '
                  '(too long or not readable with this key).',
      );
    } on SyncApiException catch (e) {
      return _failed(accountId, e);
    } on SyncException catch (e) {
      return _update(accountId, syncing: false, error: e.message);
    }
  }

  SyncAccountState _failed(String accountId, SyncApiException e) {
    if (e.kind == SyncErrorKind.unauthorized) {
      unawaited(_secrets.delete(_tokenId(accountId)).catchError((_) {}));
      return _update(
        accountId,
        phase: SyncPhase.signedOut,
        syncing: false,
        error: e.message,
      );
    }
    return _update(accountId, syncing: false, error: e.message);
  }

  /// Converts and records [e] (unauthorized → signed out), returns the
  /// exception to throw.
  SyncException _fail(String accountId, Object e) {
    if (e is SyncException) return e;
    if (e is SyncApiException) {
      if (stateOf(accountId).enabled) _failed(accountId, e);
      return SyncException(e.message);
    }
    return SyncException('Sync failed: $e');
  }

  /// Pull then (unless ![push]) push. Returns the number of notes skipped.
  /// May switch the phase (locked) when the server's E2E mode changed.
  Future<int> _pullPush(String accountId, {bool push = true}) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _pullPushOnce(accountId, push: push);
      } on _ModeChanged catch (m) {
        if (attempt >= 2) {
          throw const SyncException('The sync mode keeps changing.');
        }
        if (!await _adoptMode(accountId, m.e2e)) return 0;
      } on SyncApiException catch (e) {
        if (attempt >= 2) rethrow;
        if (e.kind == SyncErrorKind.e2eRequired) {
          if (!await _adoptMode(accountId, true)) return 0;
        } else if (e.kind == SyncErrorKind.e2eNotEnabled) {
          if (!await _adoptMode(accountId, false)) return 0;
        } else {
          rethrow;
        }
      }
    }
  }

  /// The server's E2E mode differs from ours: adopt it. Returns false if
  /// the account is now locked (no key for the new header).
  Future<bool> _adoptMode(String accountId, bool serverE2e) async {
    final meta = _metaOf(accountId);
    meta
      ..lastSeq = 0
      ..fullPush = true;
    if (!serverE2e) {
      await _dropKeys(accountId);
      _update(accountId, e2e: false);
      return true;
    }
    final token = await _sessionToken(accountId);
    final header = await _client.getE2e(token);
    if (header == null) {
      _update(accountId, e2e: false);
      return true;
    }
    final rec = header.hasRecovery;
    final keys = await _matchingKeys(accountId, header);
    if (keys == null) {
      _update(
        accountId,
        e2e: true,
        hasRecoveryCode: rec,
        phase: SyncPhase.locked,
      );
      return false;
    }
    _update(accountId, e2e: true, hasRecoveryCode: rec);
    return true;
  }

  Future<int> _pullPushOnce(String accountId, {required bool push}) async {
    final s = stateOf(accountId);
    final token = await _sessionToken(accountId);
    final meta = _metaOf(accountId);
    E2eKeys? keys;
    if (s.e2e) {
      keys = await _cachedKeys(accountId);
      if (keys == null) {
        _update(accountId, phase: SyncPhase.locked);
        return 0;
      }
    }
    var skipped = 0;

    // Pull.
    var since = meta.lastSeq;
    while (true) {
      final page = await _client.getNotes(token, since);
      if (page.e2e != null && page.e2e != s.e2e) throw _ModeChanged(page.e2e!);
      final (remote, bad) = await _toLocal(accountId, page.notes, keys);
      skipped += bad;
      _notes.applyRemote(remote);
      if (!page.more || page.notes.isEmpty) {
        since = page.latestSeq;
        break;
      }
      since = page.notes.last.seq;
    }
    meta.lastSeq = since;
    unawaited(_save());
    if (!push) return skipped;

    // Push.
    final full = meta.fullPush;
    final prefix = '$accountId|';
    final out = <RemoteNote>[];
    final sent = <String, (String, LessonNote)>{};
    for (final e in _notes.notesOf(accountId).entries) {
      final n = e.value;
      if (!full && !n.dirty) continue;
      final remoteKey = e.key.substring(prefix.length);
      if (n.text.length > _maxTextLength ||
          (keys == null && remoteKey.length > _maxKeyLength)) {
        skipped++;
        continue;
      }
      final RemoteNote r;
      if (keys != null) {
        r = RemoteNote(
          key: await e2e.serverKey(keys, remoteKey),
          blob: await e2e.encryptNote(
            keys,
            noteKey: remoteKey,
            exam: n.deleted ? false : n.exam,
            text: n.deleted ? '' : n.text,
          ),
          updatedAt: n.updatedAt,
          deleted: n.deleted,
        );
      } else {
        r = RemoteNote(
          key: remoteKey,
          exam: n.deleted ? false : n.exam,
          text: n.deleted ? '' : n.text,
          updatedAt: n.updatedAt,
          deleted: n.deleted,
        );
      }
      out.add(r);
      sent[r.key] = (e.key, n);
    }
    for (final batch in SyncClient.batches(out)) {
      final res = await _client.putNotes(token, batch);
      if (res.e2e != null && res.e2e != s.e2e) throw _ModeChanged(res.e2e!);
      final ack = <String, LessonNote>{};
      final other = <RemoteNote>[];
      for (final stored in res.notes) {
        final mine = sent[stored.key];
        if (mine != null && mine.$2.updatedAt == stored.updatedAt) {
          ack[mine.$1] = mine.$2;
        } else {
          other.add(stored);
        }
      }
      final (remote, _) = await _toLocal(accountId, other, keys);
      _notes.applyRemote({...ack, ...remote});
    }
    meta.fullPush = false;
    unawaited(_save());
    return skipped;
  }

  /// Server notes as local notes by full local key; returns the count of
  /// notes that couldn't be read.
  Future<(Map<String, LessonNote>, int)> _toLocal(
    String accountId,
    List<RemoteNote> notes,
    E2eKeys? keys,
  ) async {
    final out = <String, LessonNote>{};
    var bad = 0;
    for (final r in notes) {
      String key;
      bool exam;
      String text;
      if (r.encrypted) {
        if (keys == null) {
          bad++;
          continue;
        }
        try {
          final n = await e2e.decryptNote(keys, r.key, r.blob!);
          key = n.noteKey;
          exam = n.exam;
          text = n.text;
        } on e2e.E2eException {
          bad++;
          continue;
        }
      } else {
        if (keys != null) {
          bad++;
          continue;
        }
        key = r.key;
        exam = r.exam;
        text = r.text;
      }
      if (key.isEmpty) {
        bad++;
        continue;
      }
      out['$accountId|$key'] = r.deleted
          ? LessonNote.tombstone(r.updatedAt)
          : LessonNote(exam: exam, text: text, updatedAt: r.updatedAt);
    }
    return (out, bad);
  }

  // ------------------------------------------------------------------ login

  Future<Account> _account(String accountId) async {
    final accounts = await ref
        .read(accountRepositoryProvider)
        .watchAccounts()
        .first;
    for (final a in accounts) {
      if (a.id == accountId) return a;
    }
    throw const SyncException('This account no longer exists.');
  }

  /// New sync session for [accountId] (WebUntis token → POST /session).
  Future<SyncSession> _login(String accountId) async {
    final account = await _account(accountId);
    if (account.anonymous) {
      throw const SyncException(
        'Sync needs a personal WebUntis login (not anonymous access).',
      );
    }
    final String untisToken;
    try {
      final creds = await ref
          .read(accountRepositoryProvider)
          .credentials(accountId);
      untisToken = await ref
          .read(untisApiProvider)
          .restAuthToken(
            host: account.host,
            school: account.school.loginName,
            auth: creds,
          );
    } on SyncException {
      rethrow;
    } catch (e) {
      throw SyncException('Could not log in to WebUntis for sync: $e');
    }
    try {
      return await _client.createSession(
        host: account.host,
        school: account.school.loginName,
        untisToken: untisToken,
      );
    } on SyncApiException catch (e) {
      throw SyncException(e.message);
    }
  }

  /// Starts with a fresh session: state on, lastSeq 0, full upload due.
  Future<(SyncSession, String?)> _newSession(String accountId) async {
    final session = await _login(accountId);
    final token = await _storeSession(accountId, session);
    _meta[accountId] = _Meta(fullPush: true);
    _update(
      accountId,
      phase: SyncPhase.on,
      identity: session.identity,
      e2e: session.e2e,
      error: null,
    );
    return (session, token);
  }

  // ---------------------------------------------------------------- E2E

  /// Unwraps the key with a recovery code (if [secret] looks like one) or
  /// the passphrase.
  Future<E2eKeys> _unlockKeys(E2eHeader header, String secret) async {
    try {
      if (header.hasRecovery && _looksLikeRecoveryCode(secret)) {
        try {
          return await e2e.unlockWithRecoveryCode(header, secret);
        } on e2e.E2eWrongSecret {
          // Maybe a passphrase that happens to look like a code.
        }
      }
      return await e2e.unlockWithPassphrase(header, secret);
    } on e2e.E2eWrongSecret {
      throw const SyncException(
        'Wrong passphrase or recovery code.',
        wrongSecret: true,
      );
    } on e2e.E2eUnsupported {
      throw const SyncException(
        'The encryption settings on the sync server are not supported by '
        'this app version. Update the app.',
      );
    } on e2e.E2eCorrupt {
      throw const SyncException(
        'The encryption settings on the sync server are damaged. Reset '
        'sync to start over.',
      );
    }
  }

  static bool _looksLikeRecoveryCode(String s) {
    try {
      e2e.parseRecoveryCode(s);
      return true;
    } on FormatException {
      return false;
    }
  }

  Future<e2e.E2eSetup> _createE2e(String passphrase, bool withRecovery) async {
    try {
      return await e2e.createE2e(passphrase, withRecovery: withRecovery);
    } on ArgumentError {
      throw const SyncException(
        'The passphrase must have at least ${e2e.e2eMinPassphraseLength} '
        'characters.',
      );
    }
  }

  /// Uploads a new E2E header (which also deletes the plaintext notes on the
  /// server). Returns the recovery code, or null if another device was
  /// faster (then the account is locked unless [passphrase] unlocks it).
  Future<(bool, String?)> _setUpE2e(
    String accountId,
    String? token,
    String passphrase,
    bool withRecovery,
  ) async {
    final setup = await _createE2e(passphrase, withRecovery);
    try {
      await _client.putE2e(token, setup.header);
    } on SyncApiException catch (e) {
      if (e.kind != SyncErrorKind.e2eExists) rethrow;
      final header = await _client.getE2e(token);
      if (header != null) {
        try {
          final keys = await _unlockKeys(header, passphrase);
          await _cacheKeys(accountId, keys);
          _metaOf(accountId)
            ..lastSeq = 0
            ..fullPush = true;
          _update(
            accountId,
            e2e: true,
            hasRecoveryCode: header.hasRecovery,
            phase: SyncPhase.on,
          );
          return (true, null);
        } on SyncException {
          // Different passphrase: the user has to unlock.
        }
      }
      _update(
        accountId,
        e2e: true,
        hasRecoveryCode: header?.hasRecovery,
        phase: SyncPhase.locked,
      );
      return (false, null);
    }
    await _cacheKeys(accountId, setup.keys);
    _metaOf(accountId).fullPush = true;
    _update(
      accountId,
      e2e: true,
      hasRecoveryCode: setup.header.hasRecovery,
      phase: SyncPhase.on,
    );
    return (true, setup.recoveryCode);
  }

  // ------------------------------------------------------------- contract

  @override
  Future<SyncEnableResult> enable(
    String accountId,
    SyncEnableOptions options,
  ) async {
    await _ready();
    return _exclusive(accountId, () async {
      if (web) {
        for (final s in state.values) {
          if (s.accountId != accountId && s.enabled) {
            throw const SyncException(
              'In the web version sync can be on for one account at a time. '
              'Turn it off for the other account first.',
            );
          }
        }
      }
      try {
        final (session, token) = await _newSession(accountId);
        String? code;
        if (session.e2e) {
          final header = await _client.getE2e(token);
          if (header == null) {
            _update(accountId, e2e: false);
          } else {
            var keys = await _matchingKeys(accountId, header);
            if (keys == null && options.passphrase != null) {
              try {
                keys = await _unlockKeys(header, options.passphrase!);
              } on SyncException {
                keys = null;
              }
            }
            _update(accountId, hasRecoveryCode: header.hasRecovery);
            if (keys == null) {
              return SyncEnableResult(
                state: _update(accountId, phase: SyncPhase.locked),
              );
            }
            await _cacheKeys(accountId, keys);
          }
        } else if (options.passphrase != null) {
          // Fetch what other devices synced in plaintext first: the header
          // upload deletes the plaintext notes on the server.
          await _pullPush(accountId, push: false);
          final (ok, c) = await _setUpE2e(
            accountId,
            token,
            options.passphrase!,
            options.withRecoveryCode,
          );
          if (!ok) return SyncEnableResult(state: stateOf(accountId));
          code = c;
        }
        return SyncEnableResult(
          state: await _syncOnce(accountId),
          recoveryCode: code,
        );
      } catch (e) {
        throw _fail(accountId, e);
      }
    });
  }

  @override
  Future<SyncAccountState> unlock(
    String accountId,
    String passphraseOrCode,
  ) async {
    await _ready();
    return _exclusive(accountId, () async {
      final s = stateOf(accountId);
      if (s.phase == SyncPhase.off || s.phase == SyncPhase.signedOut) {
        throw const SyncException('Sync is not on for this account.');
      }
      try {
        final token = await _sessionToken(accountId);
        final header = await _client.getE2e(token);
        _metaOf(accountId)
          ..lastSeq = 0
          ..fullPush = true;
        if (header == null) {
          await _dropKeys(accountId);
          _update(accountId, e2e: false, phase: SyncPhase.on);
        } else {
          final keys = await _unlockKeys(header, passphraseOrCode);
          await _cacheKeys(accountId, keys);
          _update(
            accountId,
            e2e: true,
            hasRecoveryCode: header.hasRecovery,
            phase: SyncPhase.on,
            error: null,
          );
        }
        return await _syncOnce(accountId);
      } catch (e) {
        throw _fail(accountId, e);
      }
    });
  }

  @override
  Future<void> disable(String accountId) async {
    await _ready();
    return _exclusive(accountId, () async {
      if (stateOf(accountId).enabled) {
        try {
          String? token;
          try {
            token = await _sessionToken(accountId);
            await _client.deleteAccount(token);
          } on SyncApiException catch (e) {
            if (e.kind != SyncErrorKind.unauthorized) rethrow;
            // Session gone: log in again to delete the server data.
            final session = await _login(accountId);
            await _client.deleteAccount(web ? null : session.token);
          }
        } on SyncApiException catch (e) {
          throw SyncException(e.message);
        }
      }
      await _clearLocal(accountId);
    });
  }

  @override
  Future<void> signOutDevice(String accountId) async {
    await _ready();
    return _exclusive(accountId, () async {
      final s = stateOf(accountId);
      if (s.phase == SyncPhase.on || s.phase == SyncPhase.locked) {
        try {
          await _client.deleteSession(await _sessionToken(accountId));
        } catch (_) {
          // Offline or already gone: the session expires on its own.
        }
      }
      await _clearLocal(accountId);
    });
  }

  @override
  Future<SyncEnableResult> enableE2e(
    String accountId,
    String passphrase, {
    bool withRecoveryCode = true,
  }) async {
    await _ready();
    return _exclusive(accountId, () async {
      final s = stateOf(accountId);
      if (s.phase != SyncPhase.on) {
        throw const SyncException('Sync is not on for this account.');
      }
      if (s.e2e) {
        throw const SyncException('End-to-end encryption is already on.');
      }
      try {
        // Bring everything up to date first: the header upload deletes the
        // plaintext notes on the server, then all is re-uploaded encrypted.
        await _pullPush(accountId);
        if (stateOf(accountId).e2e ||
            stateOf(accountId).phase != SyncPhase.on) {
          // Another device turned E2E on meanwhile.
          return SyncEnableResult(state: stateOf(accountId));
        }
        final token = await _sessionToken(accountId);
        final (ok, code) = await _setUpE2e(
          accountId,
          token,
          passphrase,
          withRecoveryCode,
        );
        if (!ok) return SyncEnableResult(state: stateOf(accountId));
        return SyncEnableResult(
          state: await _syncOnce(accountId),
          recoveryCode: code,
        );
      } catch (e) {
        throw _fail(accountId, e);
      }
    });
  }

  @override
  Future<void> disableE2e(String accountId) async {
    await _ready();
    return _exclusive(accountId, () async {
      final s = stateOf(accountId);
      if (!s.enabled || s.phase == SyncPhase.signedOut) {
        throw const SyncException('Sync is not on for this account.');
      }
      try {
        // Get the latest encrypted notes first (if this device can read
        // them), then reset the server and upload in plaintext.
        if (s.phase == SyncPhase.on && s.e2e) await _pullPush(accountId);
        try {
          await _client.deleteAccount(await _sessionToken(accountId));
        } on SyncApiException catch (e) {
          if (e.kind != SyncErrorKind.unauthorized) rethrow;
        }
        await _dropKeys(accountId);
        await _newSession(accountId);
        await _syncOnce(accountId);
      } catch (e) {
        throw _fail(accountId, e);
      }
    });
  }

  /// Unlocked keys and the current header, for header changes.
  Future<(String?, E2eHeader, E2eKeys)> _headerAndKeys(String accountId) async {
    final s = stateOf(accountId);
    if (s.phase != SyncPhase.on || !s.e2e) {
      throw const SyncException(
        'End-to-end encryption is not on (or not unlocked) on this device.',
      );
    }
    final token = await _sessionToken(accountId);
    final header = await _client.getE2e(token);
    if (header == null) {
      await _adoptMode(accountId, false);
      throw const SyncException(
        'End-to-end encryption was turned off on another device.',
      );
    }
    _update(accountId, hasRecoveryCode: header.hasRecovery);
    final keys = await _matchingKeys(accountId, header);
    if (keys == null) {
      _update(accountId, phase: SyncPhase.locked);
      throw const SyncException(
        'The encryption key changed on another device. Unlock again.',
      );
    }
    return (token, header, keys);
  }

  Future<void> _replaceHeader(
    String accountId,
    String? token,
    E2eHeader header,
  ) async {
    try {
      await _client.patchE2e(token, header);
    } on SyncApiException catch (e) {
      if (e.kind == SyncErrorKind.e2eCheckMismatch) {
        await _dropKeys(accountId);
        _update(accountId, phase: SyncPhase.locked);
      }
      rethrow;
    }
  }

  @override
  Future<void> changePassphrase(String accountId, String newPassphrase) async {
    await _ready();
    return _exclusive(accountId, () async {
      try {
        final (token, header, keys) = await _headerAndKeys(accountId);
        final E2eHeader next;
        try {
          next = await e2e.changePassphrase(header, keys, newPassphrase);
        } on ArgumentError {
          throw const SyncException(
            'The passphrase must have at least ${e2e.e2eMinPassphraseLength} '
            'characters.',
          );
        }
        await _replaceHeader(accountId, token, next);
      } catch (e) {
        throw _fail(accountId, e);
      }
    });
  }

  @override
  Future<String> regenerateRecoveryCode(String accountId) async {
    await _ready();
    return _exclusive(accountId, () async {
      try {
        final (token, header, keys) = await _headerAndKeys(accountId);
        final (next, code) = await e2e.regenerateRecoveryCode(header, keys);
        await _replaceHeader(accountId, token, next);
        _update(accountId, hasRecoveryCode: true);
        return code;
      } catch (e) {
        throw _fail(accountId, e);
      }
    });
  }
}

/// The server reported another E2E mode than this device assumed.
class _ModeChanged implements Exception {
  const _ModeChanged(this.e2e);
  final bool e2e;
}
