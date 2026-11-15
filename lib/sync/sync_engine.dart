/// The sync engine: implements [SyncController] against the Worker's notes
/// API ([SyncClient]) and the local notes store ([LessonNotesNotifier]).
///
/// Per account:
/// * state (phase, identity, e2e, lastSeq, lastSync, error, pending full
///   upload, pending E2E setup) persisted in the [SettingsStore] under
///   [SyncEngine.storeKey];
/// * secrets in the [SecretStore]: the session token (native only; the web
///   app uses the HttpOnly cookie) and the cached E2E data key (on the web
///   dropped after [SyncEngine.webDekMaxAge], also from memory).
///
/// A sync is pull (`GET /notes?since=lastSeq`, paged, last-write-wins into
/// the local store) then push (local notes changed since they were last
/// acknowledged; after a new session / E2E change a "full push": a pull
/// from 0, then every note the server doesn't have in this version), in
/// batches of at most 500 notes / ~900 KB. Note keys on the server are the
/// local keys without the leading account id; with E2E the server only
/// sees `serverKey(keys, key)` and the real key travels inside the blob.
///
/// Safety rules:
/// * While E2E is being set up (`e2ePending`, persisted before the session
///   is used) nothing is ever pushed in plaintext.
/// * Every answer carries the session's identity and its `epoch` (changes
///   when the identity is deleted and created again). Another identity
///   (web: another tab switched the cookie) or another epoch (sync was
///   turned off or reset elsewhere) stops sync before anything is written
///   locally or pushed; this device never deletes an identity it didn't
///   set up (only the session it just created).
/// * An expired session is renewed with the account's WebUntis login;
///   transient failures keep sync on and retry at the next trigger.
/// * Notes the server keeps a version of that this device can't read are
///   not re-sent until they change (they would only use up the daily
///   write budget).
///
/// Operations of one account never run concurrently (a per-account lock;
/// sync requests while one runs are coalesced into one follow-up sync).
/// User operations cancel a sync that waits for the rate limit. On the web
/// every operation first re-reads the persisted state of its account
/// (another tab may have changed it), and saving only replaces this
/// account's entry.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/interfaces.dart' show UntisException;
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

/// `since` that returns no notes, only the identity's state (the server
/// accepts up to 15 digits).
const int _noNotesSince = 999999999999999;

const String _unavailableMessage = "Sync isn't available in this build.";

const String _resetMessage =
    'Sync was turned off or reset on another device. Your notes on this '
    'device were kept; turn sync on again to continue.';

const String _notSavedMessage =
    'The synced notes could not be saved on this device (storage full?). '
    'Sync tries again later.';

/// After a clock-skew rejection, stamps are clamped to the server's time
/// plus this (the server accepts up to 5 minutes ahead).
const Duration _clampLead = Duration(minutes: 4);

class _Meta {
  _Meta({
    this.lastSeq = 0,
    this.fullPush = false,
    this.e2ePending = false,
    this.pendingHeader,
    this.recoveryUnseen = false,
    Map<String, int>? unsendable,
  }) : unsendable = unsendable ?? {};

  /// Highest server seq applied (and persisted) locally.
  int lastSeq;

  /// Upload every local note at the next sync (new session, E2E change).
  bool fullPush;

  /// The user chose E2E and setting it up hasn't finished: never push
  /// plaintext while set.
  bool e2ePending;

  /// Header created on this device, upload not confirmed yet (JSON). Its
  /// data key is cached; the next sync finishes the upload.
  Map<String, Object?>? pendingHeader;

  /// The current recovery code may not be known to the user: set once a
  /// header with a recovery wrap is on the server, cleared only when the
  /// user confirms saving the code ([SyncEngine.acknowledgeRecoveryCode]).
  bool recoveryUnseen;

  /// Local key → updatedAt of unsynced notes the server keeps another
  /// version of that this device can't read: not sent again until they
  /// change.
  final Map<String, int> unsendable;
}

const Object _keep = Object();

class SyncEngine extends SyncController {
  SyncEngine({
    this.debounce = const Duration(seconds: 3),
    bool? web,
    this.webDekMaxAge = const Duration(days: 30),
    this.resumeInterval = const Duration(minutes: 1),
    this.maxRateLimitWait = const Duration(seconds: 65),
    this.maxPushWait = const Duration(minutes: 10),
    Future<void> Function(Duration)? sleep,
  }) : web = web ?? kIsWeb,
       _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  /// Delay between a local note change and the sync it triggers.
  final Duration debounce;

  /// Web mode: cookie auth (no stored token), one syncing account at a time
  /// (the browser has a single `bbu_sync` cookie), cached keys expire.
  final bool web;

  /// On the web the cached E2E key is dropped after this long.
  final Duration webDekMaxAge;

  /// [syncAll] skips accounts synced more recently than this.
  final Duration resumeInterval;

  /// A push rate-limited by the server (429) waits `retry-after`, at most
  /// this long per wait, ...
  final Duration maxRateLimitWait;

  /// ... and at most this long in total per sync.
  final Duration maxPushWait;

  final Future<void> Function(Duration) _sleep;

  static const storeKey = 'syncState';

  final Map<String, _Meta> _meta = {};
  final Map<String, E2eKeys> _keys = {};
  final Map<String, DateTime> _keysAt = {};
  final Map<String, Future<void>> _locks = {};
  final Map<String, Future<SyncAccountState>> _queued = {};

  /// User operations waiting for an account's lock (cancel 429 waits).
  final Map<String, int> _userOpsWaiting = {};

  /// Accounts whose session was created by a re-login in the running
  /// operation (only such a session is deleted when sync stops).
  final Set<String> _fresh = {};

  /// ... and whose re-login could not be checked against the stored epoch.
  final Set<String> _unverified = {};
  Future<void> _saving = Future.value();
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
  bool get available => _client.available;

  @override
  bool get singleAccountOnly => web;

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

  /// One persisted account entry (null: off or unreadable).
  static (SyncAccountState, _Meta)? _decodeOne(String id, Object? v) {
    if (v is! Map) return null;
    final phase = SyncPhase.values.asNameMap()[v['phase']] ?? SyncPhase.off;
    if (phase == SyncPhase.off) return null;
    final ident = v['identity'];
    final last = v['lastSync'];
    final seq = v['lastSeq'];
    final header = v['pendingHeader'];
    final unsendable = v['unsendable'];
    final meta = _Meta(
      lastSeq: seq is num ? seq.toInt() : 0,
      fullPush: v['fullPush'] == true,
      e2ePending: v['e2ePending'] == true,
      pendingHeader: header is Map
          ? {for (final h in header.entries) '${h.key}': h.value}
          : null,
      recoveryUnseen: v['recoveryUnseen'] == true,
      unsendable: {
        if (unsendable is Map)
          for (final u in unsendable.entries)
            if (u.value is num) '${u.key}': (u.value as num).toInt(),
      },
    );
    final e2eOn = v['e2e'] == true;
    final state = SyncAccountState(
      accountId: id,
      phase: phase,
      identity: parseSyncIdentity(ident),
      e2e: e2eOn,
      hasRecoveryCode: v['hasRecoveryCode'] == true,
      lastSync: last is num
          ? DateTime.fromMillisecondsSinceEpoch(last.toInt())
          : null,
      error: v['error'] is String ? v['error'] as String : null,
      e2eSetupPending: _setupPending(e2eOn, meta),
    );
    return (state, meta);
  }

  static bool _setupPending(bool e2eOn, _Meta? m) =>
      !e2eOn && m != null && m.e2ePending && m.pendingHeader != null;

  Map<String, SyncAccountState> _decode(Object? raw, {bool meta = true}) {
    final out = <String, SyncAccountState>{};
    if (raw is! Map) return out;
    for (final e in raw.entries) {
      final id = '${e.key}';
      final d = _decodeOne(id, e.value);
      if (d == null) continue;
      out[id] = d.$1;
      if (meta) _meta[id] = d.$2;
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

  /// The persisted entry of [accountId] (null: off).
  Map<String, Object?>? _encode(String accountId) {
    final s = state[accountId];
    if (s == null || s.phase == SyncPhase.off) return null;
    final m = _meta[accountId];
    return {
      'phase': s.phase.name,
      if (s.identity case final i?)
        'identity': {
          'host': i.host,
          'school': i.school,
          'userId': i.userId,
          'epoch': ?i.epoch,
        },
      'e2e': s.e2e,
      if (s.hasRecoveryCode) 'hasRecoveryCode': true,
      if (s.lastSync case final t?) 'lastSync': t.millisecondsSinceEpoch,
      'error': ?s.error,
      'lastSeq': m?.lastSeq ?? 0,
      if (m?.fullPush ?? false) 'fullPush': true,
      if (m?.e2ePending ?? false) 'e2ePending': true,
      'pendingHeader': ?m?.pendingHeader,
      if (m?.recoveryUnseen ?? false) 'recoveryUnseen': true,
      if (m != null && m.unsendable.isNotEmpty) 'unsendable': {...m.unsendable},
    };
  }

  /// Persists the entry of [accountId] only (read-modify-write: entries of
  /// other accounts, maybe changed by another tab, stay as stored). Saves
  /// run one after another.
  Future<void> _save(String accountId) {
    if (!ref.mounted) return Future.value();
    final store = _store;
    final next = _saving
        .then((_) async {
          final raw = await store.read(storeKey);
          final all = <String, Object?>{
            if (raw is Map)
              for (final e in raw.entries) '${e.key}': e.value,
          };
          // Encoded when the write runs: always the latest in-memory state.
          final entry = ref.mounted ? _encode(accountId) : all[accountId];
          if (entry == null) {
            all.remove(accountId);
          } else {
            all[accountId] = entry;
          }
          await store.write(storeKey, all);
        })
        .catchError((_) {});
    _saving = next;
    return next;
  }

  /// Web: replaces the in-memory state of [accountId] with the persisted
  /// one (another tab may have changed it; also drops the key from memory
  /// so it is read again from the secret store).
  Future<void> _reload(String accountId) async {
    if (!web || !ref.mounted) return;
    await _saving;
    final Object? raw;
    try {
      raw = await _store.read(storeKey);
    } catch (_) {
      return;
    }
    if (!ref.mounted) return;
    _keys.remove(accountId);
    _keysAt.remove(accountId);
    final d = _decodeOne(accountId, raw is Map ? raw[accountId] : null);
    _changed = true;
    if (d == null) {
      _meta.remove(accountId);
      state = {...state}..remove(accountId);
    } else {
      _meta[accountId] = d.$2;
      state = {...state, accountId: d.$1};
    }
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
      e2eSetupPending: _setupPending(e2e ?? s.e2e, _meta[accountId]),
    );
    if (ref.mounted) {
      _changed = true;
      state = {...state, accountId: next};
      unawaited(_save(accountId));
    }
    return next;
  }

  Future<void> _clearLocal(String accountId) async {
    _meta.remove(accountId);
    _keys.remove(accountId);
    _keysAt.remove(accountId);
    if (ref.mounted) {
      _changed = true;
      state = {...state}..remove(accountId);
      await _save(accountId);
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
    final token = s.token;
    if (token == null || token.isEmpty) {
      throw const SyncException('The sync server sent no session token.');
    }
    await _secrets.write(_tokenId(accountId), token);
    return token;
  }

  bool _expired(DateTime? at) =>
      web && (at == null || _now().difference(at) > webDekMaxAge);

  Future<E2eKeys?> _cachedKeys(String accountId) async {
    final mem = _keys[accountId];
    if (mem != null) {
      if (!_expired(_keysAt[accountId])) return mem;
      await _dropKeys(accountId);
      return null;
    }
    try {
      final raw = await _secrets.read(_dekId(accountId));
      if (raw == null) return null;
      final j = jsonDecode(raw);
      if (j is! Map || j['dek'] is! String) return null;
      final at = j['at'];
      final cachedAt = at is num
          ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
          : null;
      if (_expired(cachedAt)) {
        await _dropKeys(accountId);
        return null;
      }
      final keys = await E2eKeys.fromDek(e2e.b64uDecode(j['dek'] as String));
      _keysAt[accountId] = cachedAt ?? _now();
      return _keys[accountId] = keys;
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheKeys(String accountId, E2eKeys keys) async {
    final now = _now();
    _keys[accountId] = keys;
    _keysAt[accountId] = now;
    await _secrets.write(
      _dekId(accountId),
      jsonEncode({
        'dek': e2e.b64uEncode(keys.dekBytes),
        'at': now.millisecondsSinceEpoch,
      }),
    );
  }

  Future<void> _dropKeys(String accountId) async {
    _keys.remove(accountId);
    _keysAt.remove(accountId);
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

  /// Start of every operation (lock held): forget re-login markers of
  /// earlier operations; on the web re-read the persisted state.
  Future<void> _begin(String accountId) async {
    _fresh.remove(accountId);
    _unverified.remove(accountId);
    await _reload(accountId);
  }

  /// A user operation: marks itself as waiting (so a sync waiting for the
  /// rate limit gives up), then runs [fn] with the account's lock.
  Future<T> _userOp<T>(String accountId, Future<T> Function() fn) async {
    _userOpsWaiting[accountId] = (_userOpsWaiting[accountId] ?? 0) + 1;
    var counted = true;
    void done() {
      if (!counted) return;
      counted = false;
      final n = (_userOpsWaiting[accountId] ?? 1) - 1;
      if (n <= 0) {
        _userOpsWaiting.remove(accountId);
      } else {
        _userOpsWaiting[accountId] = n;
      }
    }

    try {
      await _ready();
      return await _exclusive(accountId, () async {
        done();
        await _begin(accountId);
        return fn();
      });
    } finally {
      done();
    }
  }

  bool _userOpWaiting(String accountId) =>
      (_userOpsWaiting[accountId] ?? 0) > 0;

  /// Queues one sync of [accountId] (coalesced with one already waiting).
  Future<SyncAccountState> _queueSync(String accountId) {
    final queued = _queued[accountId];
    if (queued != null) return queued;
    final f = _exclusive(accountId, () async {
      _queued.remove(accountId);
      await _begin(accountId);
      return _syncOnce(accountId, background: true);
    });
    _queued[accountId] = f;
    return f;
  }

  /// Continues in the background what a foreground operation left (the
  /// full upload after turning sync / E2E on, a rate-limited push).
  void _followUp(String accountId) {
    unawaited(_queueSync(accountId).then<void>((_) {}, onError: (Object _) {}));
  }

  /// Completes when no operation or sync of [accountId] is running or
  /// queued (tests).
  @visibleForTesting
  Future<void> whenIdle(String accountId) async {
    while (true) {
      final f = _queued[accountId] ?? _locks[accountId];
      if (f == null) return;
      try {
        await f;
      } catch (_) {}
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

  /// Syncs every account that syncs (app start / resume); locked accounts
  /// only check whether E2E is still on. Unless [force], accounts synced
  /// within [resumeInterval] are skipped. Also prunes old tombstones of
  /// accounts that don't sync (once per app run).
  Future<void> syncAll({bool force = false}) async {
    try {
      await _ready();
    } catch (_) {}
    if (!ref.mounted) return;
    if (!_pruned) {
      _pruned = true;
      _notes.pruneTombstones((id) => stateOf(id).enabled);
    }
    final now = _now();
    await Future.wait([
      for (final s in state.values)
        if ((s.phase == SyncPhase.on || s.phase == SyncPhase.locked) &&
            (force ||
                s.lastSync == null ||
                now.difference(s.lastSync!) >= resumeInterval))
          syncNow(s.accountId),
    ]);
  }

  // ------------------------------------------------------------------- sync

  @override
  Future<SyncAccountState> syncNow(String accountId) async {
    try {
      await _ready();
    } catch (_) {}
    final phase = stateOf(accountId).phase;
    if (phase != SyncPhase.on && phase != SyncPhase.locked) {
      return stateOf(accountId);
    }
    // Coalesce: at most one sync waiting behind the running one.
    try {
      return await _queueSync(accountId);
    } catch (e) {
      // _syncOnce never throws; this is the last line of defence.
      _queued.remove(accountId);
      return _update(accountId, syncing: false, error: 'Sync failed: $e');
    }
  }

  /// One sync; errors end up in the state (never thrown), `syncing` is
  /// always reset. Call with the account's lock held. [background]: a
  /// rate-limited push waits and continues; otherwise (user operations)
  /// it is continued by a background follow-up sync.
  Future<SyncAccountState> _syncOnce(
    String accountId, {
    bool background = false,
  }) async {
    final phase = stateOf(accountId).phase;
    if (phase != SyncPhase.on && phase != SyncPhase.locked) {
      return stateOf(accountId);
    }
    if (!_client.available) {
      return _update(accountId, error: _unavailableMessage);
    }
    try {
      _update(accountId, syncing: true);
      final skipped = await _authed(accountId, () async {
        if (stateOf(accountId).phase == SyncPhase.locked &&
            !await _probeLocked(accountId)) {
          return 0;
        }
        await _finishPendingSetup(accountId);
        return _pullPush(accountId, background: background);
      });
      if (stateOf(accountId).phase != SyncPhase.on) {
        return _update(accountId, syncing: false);
      }
      return _update(
        accountId,
        syncing: false,
        lastSync: _now(),
        error: _notice(accountId, skipped),
      );
    } on _Stopped {
      return _update(accountId, syncing: false);
    } on _Cancelled {
      // A user operation is waiting; the rest is uploaded later.
      return _update(accountId, syncing: false);
    } on SyncApiException catch (e) {
      if (e.kind == SyncErrorKind.rateLimited && !background) {
        // Continue in the background (waits for the rate limit).
        _followUp(accountId);
        return _update(accountId, syncing: false);
      }
      return _failed(accountId, e);
    } on SyncException catch (e) {
      return _update(accountId, syncing: false, error: e.message);
    } catch (e) {
      return _update(accountId, syncing: false, error: 'Sync failed: $e');
    } finally {
      if (ref.mounted && stateOf(accountId).syncing) {
        _update(accountId, syncing: false);
      }
    }
  }

  /// Status text after a sync that worked.
  String? _notice(String accountId, int skipped) {
    if (skipped > 0) {
      return '$skipped note${skipped == 1 ? '' : 's'} could not be synced '
          '(too long or not readable with this key).';
    }
    final s = stateOf(accountId);
    final m = _metaOf(accountId);
    if (!s.e2e && m.e2ePending) {
      return m.pendingHeader != null
          ? 'Encryption is being turned on; this finishes at the next sync. '
                'Until then nothing is uploaded unencrypted.'
          : 'Turning on encryption did not finish. Nothing was uploaded '
                'unencrypted since. Turn on encryption again to finish it.';
    }
    if (s.e2e && m.recoveryUnseen) {
      return 'Your recovery code may not have been saved. If you don\'t '
          'have it, create a new recovery code.';
    }
    return null;
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

  /// The server answered for another incarnation of the identity (sync was
  /// turned off or reset on another device): stop. Only the session this
  /// operation created is deleted; never the identity.
  Future<Never> _resetStop(String accountId) async {
    if (_fresh.remove(accountId)) {
      try {
        await _client.deleteSession(await _sessionToken(accountId));
      } catch (_) {}
    }
    _unverified.remove(accountId);
    throw _stop(accountId, _resetMessage);
  }

  /// Stops syncing [accountId] (phase signed out, [message] shown). Local
  /// notes stay. Returns the exception to throw.
  _Stopped _stop(String accountId, String message) {
    unawaited(_secrets.delete(_tokenId(accountId)).catchError((_) {}));
    _update(
      accountId,
      phase: SyncPhase.signedOut,
      syncing: false,
      error: message,
    );
    return const _Stopped();
  }

  /// Converts and records [e] (unauthorized → signed out), returns the
  /// exception to throw.
  SyncException _fail(String accountId, Object e) {
    if (e is SyncException) return e;
    if (e is _Stopped) {
      return SyncException(stateOf(accountId).error ?? 'Sync stopped.');
    }
    if (e is SyncApiException) {
      if (stateOf(accountId).enabled) _failed(accountId, e);
      return SyncException(e.message);
    }
    return SyncException('Sync failed: $e');
  }

  // --------------------------------------------------------------- session

  static bool _sameIdentity(SyncIdentity a, SyncIdentity b) =>
      a.host.toLowerCase() == b.host.toLowerCase() &&
      a.school.toLowerCase() == b.school.toLowerCase() &&
      a.userId == b.userId;

  /// Stops if the server answered for another identity than the stored one
  /// (nothing of that answer may be applied), or for another epoch of it
  /// (sync was turned off or reset on another device). A first epoch seen
  /// for state stored without one is remembered.
  Future<void> _checkIdentity(String accountId, SyncIdentity? got) async {
    final stored = stateOf(accountId).identity;
    if (got == null || stored == null) return;
    if (!_sameIdentity(stored, got)) {
      throw _stop(
        accountId,
        web
            ? 'This browser is now signed in to sync with another account '
                  '(another tab or window). Sync stopped for this account; '
                  'your notes here were kept.'
            : 'The sync server answered for another account ($got). Sync '
                  'stopped; your notes on this device were kept.',
      );
    }
    await _checkEpoch(accountId, got.epoch);
  }

  /// See [_checkIdentity] (for answers that only carry the epoch).
  Future<void> _checkEpoch(String accountId, String? got) async {
    if (got == null) return;
    final stored = stateOf(accountId).identity;
    if (stored == null) return;
    if (stored.epoch == null) {
      _update(accountId, identity: _withEpoch(stored, got));
      return;
    }
    if (stored.epoch != got) await _resetStop(accountId);
  }

  static SyncIdentity _withEpoch(SyncIdentity i, String? epoch) => SyncIdentity(
    host: i.host,
    school: i.school,
    userId: i.userId,
    epoch: epoch,
  );

  /// `GET /e2e` with the epoch check.
  Future<E2eHeader?> _getE2e(String accountId, String? token) async {
    final E2eState got;
    try {
      got = await _client.getE2eState(token);
    } on SyncApiException catch (e) {
      // An error answer may still tell the epoch.
      if (e.kind != SyncErrorKind.unauthorized) {
        await _checkEpoch(accountId, e.identityEpoch);
      }
      rethrow;
    }
    await _checkEpoch(accountId, got.epoch);
    return got.header;
  }

  /// Runs [fn]; if the session expired, signs in again once (same identity
  /// only) and runs it again.
  Future<T> _authed<T>(String accountId, Future<T> Function() fn) async {
    try {
      return await fn();
    } on SyncApiException catch (e) {
      if (e.kind != SyncErrorKind.unauthorized) rethrow;
      if (!await _relogin(accountId)) throw const _Stopped();
      return await fn();
    }
  }

  /// A new session with the account's WebUntis login, kept only for the
  /// stored identity and epoch. A definite rejection (WebUntis refused the
  /// login, host not allowed) or another identity / epoch signs the
  /// account out (returns false); a transient failure (network, 5xx, 429)
  /// throws and leaves sync on, to be retried at the next trigger.
  Future<bool> _relogin(String accountId) async {
    final stored = stateOf(accountId).identity;
    final SyncSession session;
    try {
      session = await _login(accountId);
    } on _LoginFailed catch (e) {
      if (!e.definite) {
        throw SyncException(
          'The sync session expired and signing in again failed: '
          '${e.message} Sync tries again later.',
        );
      }
      _stop(
        accountId,
        'Signed out of sync (the session expired or sync was turned off on '
        'another device), and signing in again failed: ${e.message}',
      );
      return false;
    } on SyncException catch (e) {
      _stop(
        accountId,
        'Signed out of sync (the session expired or sync was turned off on '
        'another device), and signing in again failed: ${e.message}',
      );
      return false;
    }
    Future<void> dropSession() async {
      try {
        await _client.deleteSession(web ? null : session.token);
      } catch (_) {}
    }

    if (stored != null && !_sameIdentity(stored, session.identity)) {
      await dropSession();
      _stop(
        accountId,
        'This account now signs in to sync as a different WebUntis user '
        '(${session.identity}). Sync stopped; your notes on this device were '
        'kept.',
      );
      return false;
    }
    final storedEpoch = stored?.epoch;
    final gotEpoch = session.identity.epoch;
    if (storedEpoch != null && gotEpoch != null && storedEpoch != gotEpoch) {
      // The identity was deleted and created again (by this login or on
      // another device): not the account this device synced with.
      await dropSession();
      _stop(accountId, _resetMessage);
      return false;
    }
    await _storeSession(accountId, session);
    _fresh.add(accountId);
    if (storedEpoch == null || gotEpoch == null) {
      // Can't tell a reset from a renewal: never switch to plaintext on
      // this session's word in this operation.
      _unverified.add(accountId);
    } else {
      // Same identity, same epoch: pull everything again and re-upload
      // what the server lacks (last write wins makes this safe, also after
      // a restore of the server's database).
      _metaOf(accountId)
        ..lastSeq = 0
        ..fullPush = true;
    }
    _update(
      accountId,
      identity: _withEpoch(session.identity, gotEpoch ?? storedEpoch),
    );
    await _save(accountId);
    return true;
  }

  /// Locked: checks whether E2E is still on. Returns true if the server
  /// switched to plaintext (the account is then on again).
  Future<bool> _probeLocked(String accountId) async {
    final token = await _sessionToken(accountId);
    final page = await _client.getNotes(token, _noNotesSince);
    await _checkIdentity(accountId, page.identity);
    if (page.e2e != false) return false;
    await _adoptMode(accountId, false);
    return true;
  }

  // --------------------------------------------------------------- pull/push

  /// Pull then (unless ![push]) push. Returns the number of notes skipped.
  /// May switch the phase (locked) when the server's E2E mode changed.
  /// [background]: a rate-limited push waits and continues.
  Future<int> _pullPush(
    String accountId, {
    bool push = true,
    bool background = false,
  }) async {
    var skewFixed = false;
    var waited = Duration.zero;
    for (var attempt = 0; ; attempt++) {
      try {
        return await _pullPushOnce(
          accountId,
          push: push,
          waitBudget: background ? maxPushWait - waited : Duration.zero,
          onWait: (d) => waited += d,
        );
      } on _ModeChanged catch (m) {
        if (attempt >= 3) {
          throw const SyncException('The sync mode keeps changing.');
        }
        if (!await _adoptMode(accountId, m.e2e)) return 0;
      } on SyncApiException catch (e) {
        if (attempt >= 3) rethrow;
        if (e.kind == SyncErrorKind.clockSkew &&
            e.serverTime != null &&
            !skewFixed) {
          // Our clock is ahead: stamp the offending unsynced notes just
          // below the server's limit and try once more.
          skewFixed = true;
          _notes.clampFuture(
            accountId,
            e.serverTime! + _clampLead.inMilliseconds,
          );
        } else if (e.kind == SyncErrorKind.e2eRequired) {
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
    if (serverE2e) {
      final token = await _sessionToken(accountId);
      final header = await _getE2e(accountId, token);
      if (header != null) {
        meta
          ..lastSeq = 0
          ..fullPush = true
          ..unsendable.clear();
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
        _e2eDone(accountId);
        _update(
          accountId,
          e2e: true,
          hasRecoveryCode: rec,
          phase: SyncPhase.on,
        );
        return true;
      }
      // The server explicitly says there is no E2E (e2e_not_enabled).
    }
    if (meta.e2ePending && !stateOf(accountId).e2e) {
      // We are setting up E2E ourselves; stay in "no plaintext push".
      return true;
    }
    if (_unverified.contains(accountId)) {
      // "No E2E" from a session of a re-login whose epoch couldn't be
      // checked: that may be a new, empty identity after a reset.
      await _resetStop(accountId);
    }
    // E2E was turned off on another device (the server said e2e: false):
    // only now plaintext uploads are allowed.
    meta
      ..lastSeq = 0
      ..fullPush = true
      ..recoveryUnseen = false
      ..unsendable.clear();
    // A finished or abandoned setup intent must not block plaintext sync.
    if (meta.pendingHeader == null) meta.e2ePending = false;
    await _dropKeys(accountId);
    _update(accountId, e2e: false, phase: SyncPhase.on);
    return true;
  }

  /// E2E is on with keys: the setup intent is fulfilled. A pending header
  /// with a recovery code that is cleared here may never have been shown.
  void _e2eDone(String accountId) {
    final m = _metaOf(accountId);
    if (m.pendingHeader?['wrappedDekRecovery'] != null) {
      m.recoveryUnseen = true;
    }
    m
      ..e2ePending = false
      ..pendingHeader = null;
  }

  /// Stops unless the latest local notes write reached the store (the seq
  /// must not move past notes that are only in memory).
  Future<void> _notesSaved() async {
    if (!await _notes.saved) throw const SyncException(_notSavedMessage);
  }

  Future<int> _pullPushOnce(
    String accountId, {
    required bool push,
    required Duration waitBudget,
    required void Function(Duration) onWait,
  }) async {
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
    // Notes that couldn't be synced: server keys (each counted once) and
    // notes too long for the server.
    final problems = <String>{};
    var tooLong = 0;
    int skipped() => problems.length + tooLong;

    // Pull. A full push needs to know everything the server has: from 0.
    if (push && meta.fullPush) meta.lastSeq = 0;
    final fullPull = meta.lastSeq == 0;
    // Server key -> updatedAt of the versions the server has (complete
    // after a full pull, else the changed ones).
    final known = <String, int>{};
    var since = meta.lastSeq;
    while (true) {
      final page = await _client.getNotes(token, since);
      await _checkIdentity(accountId, page.identity);
      if (page.e2e != null && page.e2e != s.e2e) throw _ModeChanged(page.e2e!);
      for (final r in page.notes) {
        known[r.key] = r.updatedAt;
      }
      final pulled = await _toLocal(accountId, page.notes, keys);
      problems.addAll(pulled.unreadable);
      _notes.applyRemote(pulled.notes);
      // Only remember the seq once the notes are stored.
      await _notesSaved();
      if (!page.more || page.notes.isEmpty) {
        since = page.latestSeq > since ? page.latestSeq : since;
        meta.lastSeq = since;
        break;
      }
      since = page.notes.last.seq;
      meta.lastSeq = since;
    }
    await _save(accountId);
    if (!push) return skipped();
    // Never upload plaintext while E2E is being set up or wanted.
    if (keys == null && meta.e2ePending) return skipped();

    // Push.
    final full = meta.fullPush;
    if (full) _notes.stampLegacy(accountId, _now().millisecondsSinceEpoch);
    final prefix = '$accountId|';
    final local = _notes.notesOf(accountId);
    // Forget "unsendable" marks of notes that changed or synced since.
    meta.unsendable.removeWhere(
      (k, at) =>
          local[k] == null || !local[k]!.dirty || local[k]!.updatedAt != at,
    );
    var marked = false;
    final out = <RemoteNote>[];
    final sent = <String, (String, LessonNote, RemoteNote)>{};
    for (final e in local.entries) {
      final n = e.value;
      if (!full && !n.dirty) continue;
      final remoteKey = e.key.substring(prefix.length);
      if (n.text.length > _maxTextLength ||
          (keys == null && remoteKey.length > _maxKeyLength)) {
        tooLong++;
        continue;
      }
      final sk = keys != null
          ? await e2e.serverKey(keys, remoteKey)
          : remoteKey;
      if (n.dirty && meta.unsendable[e.key] == n.updatedAt) {
        problems.add(sk);
        continue;
      }
      final have = known[sk];
      if (!n.dirty) {
        // Full push: only what the server doesn't have in this version.
        if (fullPull && have != null && have >= n.updatedAt) continue;
      } else if (have != null && have >= n.updatedAt) {
        // The server keeps a version at least as new that we couldn't
        // read (else the pull would have replaced or acknowledged this
        // one): sending it again would change nothing.
        meta.unsendable[e.key] = n.updatedAt;
        marked = true;
        problems.add(sk);
        continue;
      }
      final RemoteNote r;
      if (keys != null) {
        r = RemoteNote(
          key: sk,
          blob: await e2e.encryptNote(
            keys,
            noteKey: remoteKey,
            exam: n.deleted ? false : n.exam,
            text: n.deleted ? '' : n.text,
            updatedAt: n.updatedAt,
            deleted: n.deleted,
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
      sent[r.key] = (e.key, n, r);
    }
    if (marked) await _save(accountId);
    var budget = waitBudget;
    for (final batch in SyncClient.batches(out)) {
      NotesPage res;
      var busyRetried = false;
      while (true) {
        try {
          res = await _client.putNotes(token, batch);
          break;
        } on SyncApiException catch (e) {
          if (e.code == 'busy' && !busyRetried) {
            // 503 busy (concurrent writes): retry once after a moment.
            busyRetried = true;
            var wait = e.retryAfter ?? const Duration(seconds: 5);
            if (wait > const Duration(seconds: 5)) {
              wait = const Duration(seconds: 5);
            }
            await _sleep(wait);
            if (_userOpWaiting(accountId)) throw const _Cancelled();
            continue;
          }
          // A big upload runs into the write rate limit: wait and go on
          // (what was acknowledged so far is already stored). The daily
          // limit is not waited for.
          if (e.kind != SyncErrorKind.rateLimited || budget <= Duration.zero) {
            rethrow;
          }
          var wait = e.retryAfter ?? maxRateLimitWait;
          if (wait > maxRateLimitWait) wait = maxRateLimitWait;
          if (wait > budget) rethrow;
          if (_userOpWaiting(accountId)) throw const _Cancelled();
          budget -= wait;
          onWait(wait);
          await _sleep(wait);
          if (_userOpWaiting(accountId)) throw const _Cancelled();
          final now = stateOf(accountId);
          if (!ref.mounted ||
              now.phase != SyncPhase.on ||
              now.e2e != s.e2e ||
              !identical(_meta[accountId], meta)) {
            throw const _Stopped();
          }
        }
      }
      await _checkIdentity(accountId, res.identity);
      if (res.e2e != null && res.e2e != s.e2e) throw _ModeChanged(res.e2e!);
      final ack = <String, LessonNote>{};
      final other = <RemoteNote>[];
      for (final stored in res.notes) {
        final mine = sent[stored.key];
        if (mine != null && _sameVersion(mine.$3, stored)) {
          ack[mine.$1] = mine.$2;
        } else {
          // Newer on the server, or a tie the server kept: adopt it.
          other.add(stored);
        }
      }
      final adopted = await _toLocal(accountId, other, keys);
      for (final k in adopted.unreadable) {
        // The server kept a version this device can't read: don't send
        // ours again until it changes.
        final mine = sent[k];
        if (mine == null) continue;
        meta.unsendable[mine.$1] = mine.$2.updatedAt;
        problems.add(k);
      }
      _notes.applyRemote({...ack, ...adopted.notes});
      await _notesSaved();
    }
    meta.fullPush = false;
    await _save(accountId);
    return skipped();
  }

  /// Whether the server stored exactly what was [sent].
  static bool _sameVersion(RemoteNote sent, RemoteNote stored) {
    if (sent.updatedAt != stored.updatedAt) return false;
    if (sent.encrypted) return sent.blob == stored.blob;
    return sent.deleted == stored.deleted &&
        (sent.deleted ||
            (sent.exam == stored.exam && sent.text == stored.text));
  }

  /// Server notes as local notes by full local key, the count of notes
  /// that couldn't be read and their server keys.
  Future<({Map<String, LessonNote> notes, int bad, Set<String> unreadable})>
  _toLocal(String accountId, List<RemoteNote> notes, E2eKeys? keys) async {
    final out = <String, LessonNote>{};
    final unreadable = <String>{};
    for (final r in notes) {
      String key;
      bool exam;
      String text;
      if (r.encrypted) {
        if (keys == null) {
          unreadable.add(r.key);
          continue;
        }
        try {
          final n = await e2e.decryptNote(
            keys,
            r.key,
            r.blob!,
            updatedAt: r.updatedAt,
            deleted: r.deleted,
          );
          key = n.noteKey;
          exam = n.exam;
          text = n.text;
        } on e2e.E2eException {
          unreadable.add(r.key);
          continue;
        }
      } else {
        if (keys != null) {
          unreadable.add(r.key);
          continue;
        }
        key = r.key;
        exam = r.exam;
        text = r.text;
      }
      if (key.isEmpty) {
        unreadable.add(r.key);
        continue;
      }
      out['$accountId|$key'] = r.deleted
          ? LessonNote.tombstone(r.updatedAt)
          : LessonNote(exam: exam, text: text, updatedAt: r.updatedAt);
    }
    return (notes: out, bad: unreadable.length, unreadable: unreadable);
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
  /// Throws [_LoginFailed] (or [SyncException] if the account is gone).
  Future<SyncSession> _login(String accountId) async {
    final account = await _account(accountId);
    if (account.anonymous) {
      throw const _LoginFailed(
        'Sync needs a personal WebUntis login (not anonymous access).',
        definite: true,
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
    } on UntisException catch (e) {
      throw _LoginFailed(
        'Could not log in to WebUntis for sync: ${e.message}',
        // WebUntis answered and refused (wrong password, locked, ...).
        definite: !e.isNetwork && !e.isTimeout,
      );
    } catch (e) {
      throw _LoginFailed(
        'Could not log in to WebUntis for sync: $e',
        definite: false,
      );
    }
    try {
      return await _client.createSession(
        host: account.host,
        school: account.school.loginName,
        untisToken: untisToken,
      );
    } on SyncApiException catch (e) {
      throw _LoginFailed(
        e.message,
        definite:
            e.kind == SyncErrorKind.untisRejected ||
            e.kind == SyncErrorKind.hostNotAllowed,
      );
    }
  }

  /// The web version syncs one account at a time. Reads the persisted
  /// state too (another tab may have turned sync on meanwhile).
  Future<void> _webGuard(String accountId) async {
    final ids = {
      for (final s in state.values)
        if (s.enabled) s.accountId,
    };
    try {
      ids.addAll(_decode(await _store.read(storeKey), meta: false).keys);
    } catch (_) {}
    ids.remove(accountId);
    if (ids.isNotEmpty) {
      throw const SyncException(kWebSingleAccountMessage);
    }
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

  /// Whether two headers are the same version (fields the server keeps).
  static bool _sameHeader(E2eHeader a, E2eHeader b) {
    final x = a.toJson();
    final y = b.toJson();
    return jsonEncode(x['kdf']) == jsonEncode(y['kdf']) &&
        x['wrappedDek'] == y['wrappedDek'] &&
        x['wrappedDekRecovery'] == y['wrappedDekRecovery'] &&
        x['check'] == y['check'] &&
        x['authHash'] == y['authHash'];
  }

  /// Creates a new data key and header and uploads it (which also deletes
  /// the plaintext notes on the server). The key is cached and the header
  /// kept as pending first, so a lost answer can be resolved later.
  /// Returns (whether this device's key is now in use, recovery code).
  Future<(bool, String?)> _setUpE2e(
    String accountId,
    String passphrase,
    bool withRecovery,
  ) async {
    final setup = await _createE2e(passphrase, withRecovery);
    await _cacheKeys(accountId, setup.keys);
    _metaOf(accountId)
      ..e2ePending = true
      ..pendingHeader = setup.header.toJson();
    _update(accountId);
    await _save(accountId);
    final ok = await _uploadHeader(
      accountId,
      setup.header,
      setup.keys,
      passphrase: passphrase,
    );
    return (ok, ok ? setup.recoveryCode : null);
  }

  /// PUT [header]. Returns true once it is the server's header, false if
  /// another device's header won (then the account is on with that key if
  /// [passphrase] unlocks it, else locked). Throws if the outcome is
  /// unknown (the setup then stays pending) or the upload failed.
  Future<bool> _uploadHeader(
    String accountId,
    E2eHeader header,
    E2eKeys keys, {
    String? passphrase,
  }) async {
    final token = await _sessionToken(accountId);
    E2eHeader? current;
    try {
      final epoch = await _client.putE2e(token, header);
      current = header;
      await _checkEpoch(accountId, epoch);
    } on SyncApiException catch (e) {
      if (e.kind != SyncErrorKind.e2eExists && !e.outcomeUnknown) rethrow;
      try {
        current = await _getE2e(accountId, token);
      } on SyncApiException {
        if (e.outcomeUnknown) throw e; // still unknown: stays pending
        rethrow;
      }
      // No header: not applied (an unknown outcome is retried later).
      if (current == null) rethrow;
    }
    final meta = _metaOf(accountId);
    if (_sameHeader(current, header)) {
      // Ours (also when only the answer of an earlier upload was lost).
      _e2eDone(accountId);
      // The code works from now on: remind until the user confirms it.
      if (header.hasRecovery) meta.recoveryUnseen = true;
      meta
        ..fullPush = true
        ..unsendable.clear();
      _update(
        accountId,
        e2e: true,
        hasRecoveryCode: header.hasRecovery,
        phase: SyncPhase.on,
      );
      await _save(accountId);
      return true;
    }
    // Another device was faster.
    _e2eDone(accountId);
    meta
      ..lastSeq = 0
      ..fullPush = true
      ..unsendable.clear();
    await _dropKeys(accountId);
    if (passphrase != null) {
      try {
        final other = await _unlockKeys(current, passphrase);
        await _cacheKeys(accountId, other);
        _update(
          accountId,
          e2e: true,
          hasRecoveryCode: current.hasRecovery,
          phase: SyncPhase.on,
        );
        await _save(accountId);
        return false;
      } on SyncException {
        // Different passphrase: the user has to unlock.
      }
    }
    _update(
      accountId,
      e2e: true,
      hasRecoveryCode: current.hasRecovery,
      phase: SyncPhase.locked,
    );
    await _save(accountId);
    return false;
  }

  /// A setup whose upload wasn't confirmed: finish it now.
  Future<void> _finishPendingSetup(String accountId) async {
    final meta = _metaOf(accountId);
    final raw = meta.pendingHeader;
    if (raw == null) return;
    if (stateOf(accountId).e2e) {
      _e2eDone(accountId);
      _update(accountId);
      return;
    }
    E2eHeader header;
    try {
      header = E2eHeader.fromJson(raw);
    } on e2e.E2eException {
      meta.pendingHeader = null;
      _update(accountId);
      return;
    }
    final keys = await _cachedKeys(accountId);
    if (keys == null || !await keys.matchesHeader(header)) {
      // The key is gone: the setup can't be finished (e2ePending stays,
      // so nothing is uploaded in plaintext; the user turns it on again).
      meta.pendingHeader = null;
      _update(accountId);
      await _save(accountId);
      return;
    }
    // Sets recoveryUnseen if the header has a recovery code.
    await _uploadHeader(accountId, header, keys);
  }

  static const _pendingMessage =
      'Turning on encryption could not be confirmed (no answer from the '
      'sync server). It is finished automatically at the next sync; until '
      'then nothing is uploaded unencrypted. Create a new recovery code '
      'afterwards.';

  // ------------------------------------------------------------- contract

  @override
  Future<SyncEnableResult> enable(
    String accountId,
    SyncEnableOptions options,
  ) async {
    if (!_client.available) throw const SyncException(_unavailableMessage);
    return _userOp(accountId, () async {
      if (web) await _webGuard(accountId);
      final passphrase = options.passphrase;
      try {
        final session = await _login(accountId);
        // Persist the intent (E2E or not) before the session is used.
        _meta[accountId] = _Meta(
          fullPush: true,
          e2ePending: passphrase != null,
        );
        await _storeSession(accountId, session);
        _update(
          accountId,
          phase: SyncPhase.on,
          identity: session.identity,
          e2e: session.e2e,
          error: null,
        );
        await _save(accountId);
        var setUpE2e = passphrase != null && !session.e2e;
        if (session.e2e) {
          final header = await _getE2e(
            accountId,
            await _sessionToken(accountId),
          );
          if (header == null) {
            // E2E was turned off right after the login answer: with a
            // passphrase, set it up from scratch.
            _update(accountId, e2e: false);
            setUpE2e = passphrase != null;
          } else {
            var keys = await _matchingKeys(accountId, header);
            if (keys == null && passphrase != null) {
              try {
                keys = await _unlockKeys(header, passphrase);
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
            _e2eDone(accountId);
            _update(accountId);
          }
        }
        if (setUpE2e) {
          final String? code;
          try {
            // Fetch what other devices synced in plaintext first: the
            // header upload deletes the plaintext notes on the server.
            await _pullPush(accountId, push: false);
            final s = stateOf(accountId);
            if (s.e2e || s.phase != SyncPhase.on) {
              // Another device turned E2E on meanwhile.
              return SyncEnableResult(state: s);
            }
            final (ok, c) = await _setUpE2e(
              accountId,
              passphrase!,
              options.withRecoveryCode,
            );
            if (!ok) return SyncEnableResult(state: stateOf(accountId));
            code = c;
          } catch (e) {
            if (_keepPending(accountId, e)) {
              throw const SyncException(_pendingMessage);
            }
            // Roll back: never leave a plaintext account behind.
            await _rollBack(accountId);
            rethrow;
          }
          // The code is shown right away; the upload follows.
          _followUp(accountId);
          return SyncEnableResult(
            state: stateOf(accountId),
            recoveryCode: code,
          );
        }
        // Foreground: a rate-limited upload continues in the background.
        return SyncEnableResult(state: await _syncOnce(accountId));
      } catch (e) {
        throw _fail(accountId, e);
      }
    });
  }

  /// Whether a failed E2E setup stays pending (the header upload may have
  /// happened) instead of being rolled back.
  bool _keepPending(String accountId, Object e) =>
      _metaOf(accountId).pendingHeader != null &&
      !stateOf(accountId).e2e &&
      e is SyncApiException &&
      e.outcomeUnknown;

  Future<void> _rollBack(String accountId) async {
    try {
      await _client.deleteSession(await _sessionToken(accountId));
    } catch (_) {}
    await _clearLocal(accountId);
  }

  @override
  Future<SyncAccountState> unlock(
    String accountId,
    String passphraseOrCode,
  ) async {
    return _userOp(accountId, () async {
      final s = stateOf(accountId);
      if (s.phase == SyncPhase.off || s.phase == SyncPhase.signedOut) {
        throw const SyncException('Sync is not on for this account.');
      }
      try {
        await _authed(accountId, () async {
          final header = await _getE2e(
            accountId,
            await _sessionToken(accountId),
          );
          if (header == null) {
            await _adoptMode(accountId, false);
          } else {
            final keys = await _unlockKeys(header, passphraseOrCode);
            await _cacheKeys(accountId, keys);
            _e2eDone(accountId);
            _metaOf(accountId)
              ..lastSeq = 0
              ..fullPush = true
              ..unsendable.clear();
            _update(
              accountId,
              e2e: true,
              hasRecoveryCode: header.hasRecovery,
              phase: SyncPhase.on,
              error: null,
            );
          }
        });
        return await _syncOnce(accountId);
      } catch (e) {
        throw _fail(accountId, e);
      }
    });
  }

  @override
  Future<void> disable(String accountId) async {
    return _userOp(accountId, () async {
      final s = stateOf(accountId);
      if (s.enabled) {
        final stored = s.identity;
        String refusal(SyncIdentity now) =>
            'Sync was not turned off: this account now signs in as another '
            'WebUntis user ($now) than the one sync was set up with '
            '($stored). Nothing was deleted on the server.';
        try {
          String? token;
          SyncIdentity? got;
          var fresh = false;
          try {
            token = await _sessionToken(accountId);
            // Make sure the session (web: the cookie) is this identity's.
            final page = await _client.getNotes(token, _noNotesSince);
            got = page.identity;
          } on SyncApiException catch (e) {
            if (e.kind != SyncErrorKind.unauthorized) rethrow;
            // Session gone: log in again to delete the server data, but
            // only for the same identity and epoch.
            final session = await _login(accountId);
            token = web ? null : session.token;
            got = session.identity;
            fresh = true;
          }
          Future<void> dropFresh() async {
            if (!fresh) return;
            try {
              await _client.deleteSession(token);
            } catch (_) {}
          }

          if (got != null && stored != null && !_sameIdentity(stored, got)) {
            await dropFresh();
            throw SyncException(refusal(got));
          }
          if (got?.epoch != null &&
              stored?.epoch != null &&
              got!.epoch != stored!.epoch) {
            // Turned off or reset elsewhere (maybe on again since): not
            // the data this device synced, never delete it from here.
            await dropFresh();
            await _clearLocal(accountId);
            throw const SyncException(
              'Sync had already been turned off or reset on another device, '
              'so nothing was deleted on the server. Sync is now off on this '
              'device; your notes here were kept.',
            );
          }
          await _client.deleteAccount(token);
        } on SyncApiException catch (e) {
          throw SyncException(e.message);
        }
      }
      await _clearLocal(accountId);
    });
  }

  @override
  Future<void> signOutDevice(String accountId) async {
    return _userOp(accountId, () async {
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
    return _userOp(accountId, () async {
      final s = stateOf(accountId);
      if (s.phase != SyncPhase.on) {
        throw const SyncException('Sync is not on for this account.');
      }
      if (s.e2e) {
        throw const SyncException('End-to-end encryption is already on.');
      }
      final meta = _metaOf(accountId);
      if (meta.pendingHeader != null) {
        // An earlier setup isn't confirmed yet: finish that one first
        // (a second header could never be uploaded anyway).
        try {
          await _authed(accountId, () => _finishPendingSetup(accountId));
        } catch (e) {
          if (_keepPending(accountId, e)) {
            throw const SyncException(_pendingMessage);
          }
          throw _fail(accountId, e);
        }
        final now = stateOf(accountId);
        if (now.e2e || now.phase != SyncPhase.on) {
          if (now.phase == SyncPhase.on) _followUp(accountId);
          return SyncEnableResult(state: now);
        }
        if (meta.pendingHeader != null) {
          throw const SyncException(_pendingMessage);
        }
      }
      try {
        // From now on nothing is pushed in plaintext.
        meta.e2ePending = true;
        await _save(accountId);
        final ok = await _authed(accountId, () async {
          // Bring everything up to date first: the header upload deletes
          // the plaintext notes on the server, then all is re-uploaded
          // encrypted.
          await _pullPush(accountId, push: false);
          final now = stateOf(accountId);
          return !now.e2e && now.phase == SyncPhase.on;
        });
        if (!ok) {
          // Another device turned E2E on meanwhile.
          return SyncEnableResult(state: stateOf(accountId));
        }
        final (done, code) = await _setUpE2e(
          accountId,
          passphrase,
          withRecoveryCode,
        );
        if (!done) return SyncEnableResult(state: stateOf(accountId));
        // The code is shown right away; the upload follows.
        _followUp(accountId);
        return SyncEnableResult(state: stateOf(accountId), recoveryCode: code);
      } catch (e) {
        if (_keepPending(accountId, e)) {
          throw const SyncException(_pendingMessage);
        }
        if (!stateOf(accountId).e2e) {
          // Definitely not set up: back to plaintext sync as before.
          meta
            ..e2ePending = false
            ..pendingHeader = null;
          await _dropKeys(accountId);
          if (stateOf(accountId).enabled) _update(accountId);
          await _save(accountId);
        }
        throw _fail(accountId, e);
      }
    });
  }

  @override
  Future<void> disableE2e(String accountId) async {
    return _userOp(accountId, () async {
      final s = stateOf(accountId);
      if (s.phase == SyncPhase.locked) {
        throw const SyncException(
          'Unlock sync on this device first (enter the passphrase).',
        );
      }
      if (s.phase != SyncPhase.on || !s.e2e) {
        throw const SyncException('End-to-end encryption is not on.');
      }
      try {
        await _authed(accountId, () async {
          // Get the latest encrypted notes first, then turn E2E off on the
          // server (deletes the header and the encrypted notes; sessions
          // stay) and upload in plaintext.
          await _pullPush(accountId);
          final now = stateOf(accountId);
          if (now.phase != SyncPhase.on || !now.e2e) return;
          final keys = await _cachedKeys(accountId);
          if (keys == null) {
            _update(accountId, phase: SyncPhase.locked);
            throw const SyncException('Unlock sync on this device first.');
          }
          final token = await _sessionToken(accountId);
          try {
            await _checkEpoch(
              accountId,
              await _client.deleteE2e(token, keys.authKeyB64),
            );
          } on SyncApiException catch (e) {
            if (e.code == 'e2e_not_enabled') {
              // Already off.
            } else if (e.kind == SyncErrorKind.e2eAuthFailed) {
              await _dropKeys(accountId);
              _update(accountId, phase: SyncPhase.locked);
              rethrow;
            } else if (e.outcomeUnknown) {
              if (await _getE2e(accountId, token) != null) rethrow;
            } else {
              rethrow;
            }
          }
          final meta = _metaOf(accountId)
            ..e2ePending = false
            ..pendingHeader = null;
          await _adoptMode(accountId, false);
          meta.fullPush = true;
        });
        await _syncOnce(accountId);
      } catch (e) {
        throw _fail(accountId, e);
      }
    });
  }

  @override
  Future<void> acknowledgeRecoveryCode(String accountId) async {
    await _ready();
    final m = _meta[accountId];
    if (m == null || !stateOf(accountId).enabled) return;
    m.recoveryUnseen = false;
    final err = stateOf(accountId).error;
    _update(
      accountId,
      error: err != null && err.contains('recovery code') ? null : _keep,
    );
    await _save(accountId);
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
    final header = await _getE2e(accountId, token);
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

  /// PATCHes [next] over [old]. If the answer is lost, the header is
  /// fetched again to tell whether it was applied; throws [unknown] if
  /// that can't be told.
  Future<void> _replaceHeader(
    String accountId,
    String? token,
    E2eHeader old,
    E2eHeader next,
    E2eKeys keys, {
    required SyncException unknown,
  }) async {
    try {
      await _checkEpoch(
        accountId,
        await _client.patchE2e(token, next, keys.authKeyB64),
      );
    } on SyncApiException catch (e) {
      if (e.kind == SyncErrorKind.e2eAuthFailed) {
        await _dropKeys(accountId);
        _update(accountId, phase: SyncPhase.locked);
        rethrow;
      }
      if (!e.outcomeUnknown) rethrow;
      final E2eHeader? current;
      try {
        current = await _getE2e(accountId, token);
      } on SyncApiException {
        throw unknown;
      }
      if (current != null && _sameHeader(current, next)) return;
      if (current != null && _sameHeader(current, old)) rethrow;
      throw unknown;
    }
  }

  @override
  Future<void> changePassphrase(String accountId, String newPassphrase) async {
    return _userOp(accountId, () async {
      try {
        await _authed(accountId, () async {
          final (token, header, keys) = await _headerAndKeys(accountId);
          final E2eHeader next;
          try {
            next = await e2e.changePassphrase(header, keys, newPassphrase);
          } on ArgumentError {
            throw const SyncException(
              'The passphrase must have at least '
              '${e2e.e2eMinPassphraseLength} characters.',
            );
          }
          await _replaceHeader(
            accountId,
            token,
            header,
            next,
            keys,
            unknown: const SyncException(
              'The connection was lost while changing the passphrase, so it '
              'is not known whether it changed: the old or the new one '
              'works now. Change it again when you are online.',
            ),
          );
        });
      } catch (e) {
        throw _fail(accountId, e);
      }
    });
  }

  @override
  Future<String> regenerateRecoveryCode(String accountId) async {
    return _userOp(accountId, () async {
      try {
        return await _authed(accountId, () async {
          final (token, header, keys) = await _headerAndKeys(accountId);
          final (next, code) = await e2e.regenerateRecoveryCode(header, keys);
          try {
            await _replaceHeader(
              accountId,
              token,
              header,
              next,
              keys,
              unknown: const SyncException(
                'The connection was lost while creating the recovery code. '
                'Your old recovery code may have stopped working: create a '
                'new recovery code when you are online again.',
              ),
            );
          } on SyncException {
            _metaOf(accountId).recoveryUnseen = true;
            _update(
              accountId,
              error:
                  'Your recovery code may not work: create a new '
                  'recovery code.',
            );
            rethrow;
          }
          // Works now; remind until the user confirms saving it.
          _metaOf(accountId).recoveryUnseen = true;
          final s = stateOf(accountId);
          _update(
            accountId,
            hasRecoveryCode: true,
            error: s.error != null && s.error!.contains('recovery code')
                ? null
                : _keep,
          );
          return code;
        });
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

/// Sync was stopped for the account (state and message already set).
class _Stopped implements Exception {
  const _Stopped();
}

/// A sync waiting for the rate limit gave way to a user operation.
class _Cancelled implements Exception {
  const _Cancelled();
}

/// Signing in to the sync server failed. [definite]: WebUntis or the sync
/// server refused (signing in again won't help); otherwise transient
/// (network, server error, rate limit).
class _LoginFailed extends SyncException {
  const _LoginFailed(super.message, {required this.definite});
  final bool definite;
}
