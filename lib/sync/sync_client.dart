/// HTTP client for the notes sync API of the Cloudflare Worker
/// (worker/src/sync/, docs/SYNC-PLAN.md).
///
/// Native apps authenticate with `Authorization: Bearer <token>`; the web
/// app (served by the same Worker) uses the HttpOnly `__Host-bbu_sync` cookie that
/// `POST /api/sync/session` sets. Every request carries `X-BBU-Sync: 1`
/// (CSRF rule for cookie requests; harmless with a bearer token).
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'e2e_crypto.dart';
import 'sync_controller.dart';

/// Sync server for the phone apps (compile-time, `--dart-define
/// BBU_SYNC_URL=...`, set from the repository variable `BBU_SYNC_URL` in
/// release builds). Empty (the default): sync is unavailable in the phone
/// apps of this build. The web app always uses its own origin.
const String kSyncServerUrl = String.fromEnvironment('BBU_SYNC_URL');

/// The sync server's base URL for this platform (empty if unavailable).
Uri defaultSyncBaseUrl() =>
    kIsWeb ? Uri.parse(Uri.base.origin) : Uri.parse(kSyncServerUrl.trim());

/// Kinds of sync API failures.
enum SyncErrorKind {
  /// 401 on an authenticated endpoint: the session is gone.
  unauthorized,

  /// WebUntis didn't accept the token or the school didn't match (login).
  untisRejected,

  /// The WebUntis host isn't allowed by the server.
  hostNotAllowed,
  rateLimited,

  /// 429 daily_limit: the identity's note writes for today (UTC) are used
  /// up; sync continues tomorrow (not worth waiting for).
  dailyLimit,
  clockSkew,

  /// 413: too many notes, request too large.
  quota,

  /// 409 e2e_required: the server has E2E, plaintext was sent.
  e2eRequired,

  /// 409 / 404 e2e_not_enabled.
  e2eNotEnabled,

  /// 409 e2e_exists (PUT /e2e).
  e2eExists,

  /// 403 e2e_auth_failed (PATCH/DELETE /e2e): the auth key doesn't match
  /// the server's header (this device's data key is outdated).
  e2eAuthFailed,
  network,
  server,
  badRequest,
}

/// A failed sync API request with a user-facing [message].
class SyncApiException implements Exception {
  const SyncApiException(
    this.kind,
    this.message, {
    this.code,
    this.status,
    this.serverTime,
    this.retryAfter,
    this.identityEpoch,
  });
  final SyncErrorKind kind;
  final String message;

  /// The identity epoch the server reported with this error (header
  /// `x-bbu-identity-epoch` or `identity.epoch` in the body), if any.
  final String? identityEpoch;

  /// The server's clock (ms since the epoch) of a `clock_skew` answer.
  final int? serverTime;

  /// `retry-after` of a 429 answer.
  final Duration? retryAfter;

  /// The request may have been carried out although no answer arrived
  /// (connection lost, timeout, 5xx).
  bool get outcomeUnknown =>
      kind == SyncErrorKind.network ||
      (kind == SyncErrorKind.server && (status == null || status! >= 500));

  /// Server error code (`{"error": code}`), if any.
  final String? code;
  final int? status;

  SyncException toSyncException() => SyncException(message);

  @override
  String toString() => 'SyncApiException($kind, $code, $status): $message';
}

/// A note as stored on the server. Plaintext notes have [exam]/[text];
/// end-to-end encrypted notes have [blob] (and [key] is the hidden server
/// key).
class RemoteNote {
  const RemoteNote({
    required this.key,
    required this.updatedAt,
    required this.deleted,
    this.exam = false,
    this.text = '',
    this.blob,
    this.seq = 0,
  });

  final String key;
  final bool exam;
  final String text;
  final String? blob;
  final int updatedAt;
  final bool deleted;
  final int seq;

  bool get encrypted => blob != null;

  Map<String, Object?> toJson() => blob != null
      ? {'key': key, 'blob': blob, 'updatedAt': updatedAt, 'deleted': deleted}
      : {
          'key': key,
          'exam': exam,
          'text': text,
          'updatedAt': updatedAt,
          'deleted': deleted,
        };

  static RemoteNote? tryParse(Object? j) {
    if (j is! Map) return null;
    final key = j['key'];
    final at = j['updatedAt'];
    if (key is! String || at is! num) return null;
    final blob = j['blob'];
    final seq = j['seq'];
    return RemoteNote(
      key: key,
      updatedAt: at.toInt(),
      deleted: j['deleted'] == true,
      exam: j['exam'] == true,
      text: j['text'] is String ? j['text'] as String : '',
      blob: blob is String ? blob : null,
      seq: seq is num ? seq.toInt() : 0,
    );
  }
}

/// The `identity` object of an answer (`{host, school, userId, epoch}`).
SyncIdentity? parseSyncIdentity(Object? id, {String? host, String? school}) {
  if (id is! Map) return null;
  final epoch = id['epoch'];
  return SyncIdentity(
    host: '${id['host'] ?? host ?? ''}',
    school: '${id['school'] ?? school ?? ''}',
    userId: '${id['userId'] ?? ''}',
    epoch: epoch is String && epoch.isNotEmpty ? epoch : null,
  );
}

/// Answer of `GET /api/sync/e2e`: the header (null: E2E not enabled) and
/// the identity epoch the server answered for (null if not sent).
class E2eState {
  const E2eState(this.header, this.epoch);
  final E2eHeader? header;
  final String? epoch;
}

/// Answer of `POST /api/sync/session`.
class SyncSession {
  const SyncSession({
    required this.token,
    required this.expiresAt,
    required this.identity,
    required this.e2e,
    this.existing,
  });

  /// Bearer token; null for browsers (the server only sets the cookie).
  final String? token;
  final DateTime? expiresAt;
  final SyncIdentity identity;
  final bool e2e;

  /// The identity existed before this login (the account already syncs on
  /// another device or did before). Null from servers that don't say.
  final bool? existing;
}

/// A page of `GET /api/sync/notes` or the answer of `PUT /api/sync/notes`.
class NotesPage {
  const NotesPage({
    required this.notes,
    required this.latestSeq,
    required this.more,
    required this.e2e,
    this.identity,
  });
  final List<RemoteNote> notes;
  final int latestSeq;
  final bool more;

  /// Whether the identity has E2E on (null if the server didn't say).
  final bool? e2e;

  /// The identity of the session the server answered for.
  final SyncIdentity? identity;
}

class SyncClient {
  SyncClient({Dio? dio, Uri? baseUrl})
    : baseUrl = baseUrl ?? defaultSyncBaseUrl(),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
            ),
          );

  final Uri baseUrl;
  final Dio _dio;

  /// Whether this build has a sync server.
  bool get available => baseUrl.hasScheme && baseUrl.host.isNotEmpty;

  /// Max notes per PUT (server limit).
  static const maxNotesPerRequest = 500;

  /// Target body size per PUT (server limit 1 MiB).
  static const maxBodyBytes = 900 * 1024;

  String _url(String path, [Map<String, String>? query]) {
    final base = baseUrl.toString().replaceAll(RegExp(r'/+$'), '');
    final q = query == null || query.isEmpty
        ? ''
        : '?${Uri(queryParameters: query).query}';
    return '$base$path$q';
  }

  /// Response header with the identity epoch (`GET /e2e` may carry it
  /// there instead of in the body).
  static const epochHeader = 'x-bbu-identity-epoch';

  Future<(int, Object?, String?)> _send(
    String method,
    String path, {
    String? token,
    Object? body,
    Map<String, String>? query,
  }) async {
    final Response<String> resp;
    try {
      resp = await _dio.request<String>(
        _url(path, query),
        data: body == null ? null : jsonEncode(body),
        options: Options(
          method: method,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          headers: {
            'X-BBU-Sync': '1',
            'Accept': 'application/json',
            if (body != null) 'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
    } on DioException catch (e) {
      throw SyncApiException(
        SyncErrorKind.network,
        'The sync server could not be reached. Check your connection.',
        code: e.type.name,
      );
    }
    final status = resp.statusCode ?? 0;
    Object? json;
    final text = resp.data;
    if (text != null && text.isNotEmpty) {
      try {
        json = jsonDecode(text);
      } on FormatException {
        json = null;
      }
    }
    final epoch = resp.headers.value(epochHeader);
    if (status >= 200 && status < 300) return (status, json, epoch);
    final retry = int.tryParse(resp.headers.value('retry-after') ?? '');
    throw errorFor(
      status,
      json,
      login: path == '/api/sync/session',
      retryAfter: retry == null ? null : Duration(seconds: retry),
      identityEpoch: epoch,
    );
  }

  /// Maps an error answer to a [SyncApiException] with a user-facing text.
  static SyncApiException errorFor(
    int status,
    Object? json, {
    bool login = false,
    Duration? retryAfter,
    String? identityEpoch,
  }) {
    final code = json is Map && json['error'] is String
        ? json['error'] as String
        : null;
    final st = json is Map ? json['serverTime'] : null;
    final epoch =
        (identityEpoch != null && identityEpoch.isNotEmpty
            ? identityEpoch
            : null) ??
        (json is Map ? parseSyncIdentity(json['identity'])?.epoch : null);
    SyncApiException e(SyncErrorKind k, String m) => SyncApiException(
      k,
      m,
      code: code,
      status: status,
      serverTime: st is num ? st.toInt() : null,
      retryAfter: retryAfter,
      identityEpoch: epoch,
    );
    switch ((status, code)) {
      case (401, _) when login:
        return e(
          SyncErrorKind.untisRejected,
          code == 'school_mismatch'
              ? 'The sync server could not confirm this school with WebUntis.'
              : 'The sync server could not confirm your WebUntis login. '
                    'Try again later.',
        );
      case (401, _):
        return e(
          SyncErrorKind.unauthorized,
          'Signed out of sync (the session expired or sync was turned off '
          'on another device).',
        );
      case (403, 'anonymous_not_allowed') when login:
        // WebUntis answered for anonymous (public timetable) access.
        return e(SyncErrorKind.untisRejected, kAnonymousSyncMessage);
      case (403, 'host_not_allowed'):
        return e(
          SyncErrorKind.hostNotAllowed,
          'Sync is not available for this WebUntis server.',
        );
      case (429, 'daily_limit'):
        return e(
          SyncErrorKind.dailyLimit,
          'Daily sync limit reached, continues tomorrow.',
        );
      case (429, _):
        return e(
          SyncErrorKind.rateLimited,
          'Too many sync requests. Try again in a minute.',
        );
      case (400, 'clock_skew'):
        return e(
          SyncErrorKind.clockSkew,
          "Your device's clock is ahead. Set the correct time and sync "
          'again.',
        );
      case (413, 'too_many_notes'):
        return e(
          SyncErrorKind.quota,
          'Too many notes to sync (at most 5 000 per account).',
        );
      case (413, 'storage_quota'):
        return e(
          SyncErrorKind.quota,
          'Your synced notes take up too much space on the server (at most '
          '5 MB per account). Delete some long lesson details.',
        );
      case (413, _):
        return e(SyncErrorKind.quota, 'The sync request was too large.');
      case (409, 'e2e_required'):
        return e(
          SyncErrorKind.e2eRequired,
          'End-to-end encryption was turned on on another device.',
        );
      case (409, 'e2e_not_enabled') || (404, 'e2e_not_enabled'):
        return e(
          SyncErrorKind.e2eNotEnabled,
          'End-to-end encryption is not set up for this account.',
        );
      case (409, 'e2e_exists'):
        return e(
          SyncErrorKind.e2eExists,
          'End-to-end encryption was already set up on another device.',
        );
      case (403, 'e2e_auth_failed'):
        return e(
          SyncErrorKind.e2eAuthFailed,
          'The encryption key changed on another device. Unlock again.',
        );
      case (502, _):
        return e(
          SyncErrorKind.server,
          'The sync server could not reach WebUntis. Try again later.',
        );
      case (400, _) || (415, _):
        return e(
          SyncErrorKind.badRequest,
          'The sync server rejected the request.',
        );
      default:
        return e(
          SyncErrorKind.server,
          'The sync server had a problem (HTTP $status). Try again later.',
        );
    }
  }

  static SyncApiException _unexpected() => const SyncApiException(
    SyncErrorKind.server,
    'The sync server sent an unexpected answer.',
  );

  /// `POST /api/sync/session`.
  Future<SyncSession> createSession({
    required String host,
    required String school,
    required String untisToken,
  }) async {
    final (_, j, _) = await _send(
      'POST',
      '/api/sync/session',
      body: {'host': host, 'school': school, 'untisToken': untisToken},
    );
    if (j is! Map) throw _unexpected();
    final token = j['token'];
    final id = j['identity'];
    if ((token != null && token is! String) || id is! Map) {
      throw _unexpected();
    }
    final exp = j['expiresAt'];
    return SyncSession(
      token: token as String?,
      expiresAt: exp is String
          ? DateTime.tryParse(exp)
          : exp is num
          ? DateTime.fromMillisecondsSinceEpoch(exp.toInt(), isUtc: true)
          : null,
      identity: parseSyncIdentity(id, host: host, school: school)!,
      e2e: j['e2e'] == true,
      existing: j['existing'] is bool ? j['existing'] as bool : null,
    );
  }

  /// `DELETE /api/sync/session` (log out this device).
  Future<void> deleteSession(String? token) async {
    await _send('DELETE', '/api/sync/session', token: token);
  }

  static NotesPage _page(Object? j) {
    if (j is! Map || j['notes'] is! List) throw _unexpected();
    final latest = j['latestSeq'];
    final e2e = j['e2e'];
    final id = j['identity'];
    return NotesPage(
      notes: [for (final n in j['notes'] as List) ?RemoteNote.tryParse(n)],
      latestSeq: latest is num ? latest.toInt() : 0,
      more: j['more'] == true,
      e2e: e2e is bool ? e2e : null,
      identity: parseSyncIdentity(id),
    );
  }

  /// `GET /api/sync/notes?since=` (one page).
  Future<NotesPage> getNotes(String? token, int since) async {
    final (_, j, _) = await _send(
      'GET',
      '/api/sync/notes',
      token: token,
      query: {'since': '$since'},
    );
    return _page(j);
  }

  /// `PUT /api/sync/notes` (one batch; see [batches]). Returns the stored
  /// version of every note.
  Future<NotesPage> putNotes(String? token, List<RemoteNote> notes) async {
    final (_, j, _) = await _send(
      'PUT',
      '/api/sync/notes',
      token: token,
      body: {
        'notes': [for (final n in notes) n.toJson()],
      },
    );
    return _page(j);
  }

  /// Splits [notes] into requests of at most [maxNotesPerRequest] notes and
  /// about [maxBodyBytes].
  static List<List<RemoteNote>> batches(List<RemoteNote> notes) {
    final out = <List<RemoteNote>>[];
    var cur = <RemoteNote>[];
    var bytes = 0;
    for (final n in notes) {
      final size = utf8.encode(jsonEncode(n.toJson())).length + 1;
      if (cur.isNotEmpty &&
          (cur.length >= maxNotesPerRequest || bytes + size > maxBodyBytes)) {
        out.add(cur);
        cur = [];
        bytes = 0;
      }
      cur.add(n);
      bytes += size;
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  /// `GET /api/sync/e2e`; null if E2E isn't set up (404 `e2e_not_enabled`;
  /// any other error is thrown).
  Future<E2eHeader?> getE2e(String? token) async =>
      (await getE2eState(token)).header;

  /// `GET /api/sync/e2e` with the identity epoch. Accepts the header as
  /// the body, or `{header, identity}`; the epoch comes from
  /// `identity.epoch` or the `x-bbu-identity-epoch` response header.
  Future<E2eState> getE2eState(String? token) async {
    try {
      final (_, j, epochHdr) = await _send(
        'GET',
        '/api/sync/e2e',
        token: token,
      );
      final wrapped = j is Map && j['header'] is Map;
      final epoch =
          (wrapped ? parseSyncIdentity(j['identity'])?.epoch : null) ??
          (epochHdr != null && epochHdr.isNotEmpty ? epochHdr : null);
      return E2eState(E2eHeader.fromJson(wrapped ? j['header'] : j), epoch);
    } on SyncApiException catch (e) {
      if (e.code == 'e2e_not_enabled') return E2eState(null, e.identityEpoch);
      rethrow;
    } on E2eException {
      throw const SyncApiException(
        SyncErrorKind.server,
        'The encryption settings on the sync server are not supported by '
        'this app version.',
      );
    } on FormatException {
      throw _unexpected();
    }
  }

  /// `PUT /api/sync/e2e` (create once; also deletes the plaintext notes on
  /// the server). Throws [SyncErrorKind.e2eExists] if a header exists.
  /// Returns the identity epoch of the answer (null if not sent).
  Future<String?> putE2e(String? token, E2eHeader header) async {
    final (_, _, epoch) = await _send(
      'PUT',
      '/api/sync/e2e',
      token: token,
      body: header.toJson(),
    );
    return epoch;
  }

  /// `PATCH /api/sync/e2e`: replaces the header with one for the same data
  /// key; [authKey] (`E2eKeys.authKeyB64`) proves this device has it.
  /// Throws [SyncErrorKind.e2eAuthFailed] otherwise.
  /// Returns the identity epoch of the answer (null if not sent).
  Future<String?> patchE2e(
    String? token,
    E2eHeader header,
    String authKey,
  ) async {
    final (_, _, epoch) = await _send(
      'PATCH',
      '/api/sync/e2e',
      token: token,
      body: {'header': header.toJson(), 'authKey': authKey},
    );
    return epoch;
  }

  /// `DELETE /api/sync/e2e`: turns E2E off (deletes the header and all
  /// notes on the server; sessions stay, other devices switch to plaintext
  /// when they see `e2e: false`).
  /// Returns the identity epoch of the answer (null if not sent).
  Future<String?> deleteE2e(String? token, String authKey) async {
    final (_, _, epoch) = await _send(
      'DELETE',
      '/api/sync/e2e',
      token: token,
      body: {'authKey': authKey},
    );
    return epoch;
  }

  /// `DELETE /api/sync/account`: deletes the identity and all its data.
  Future<void> deleteAccount(String? token) async {
    await _send('DELETE', '/api/sync/account', token: token);
  }
}
