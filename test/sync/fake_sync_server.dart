/// In-memory stand-in for the Worker's sync API (worker/src/sync/), used
/// as a dio [HttpClientAdapter]: sessions (browsers get no token in the
/// body), last-write-wins notes with seqs (a tie keeps the stored version),
/// tombstones, identity in every notes answer, E2E header (create once and
/// delete the plaintext notes; PATCH and DELETE need the auth key; DELETE
/// keeps sessions and seqs), account deletion, clock skew with
/// `serverTime`, storage quota, 5 000 live notes, daily write budget,
/// write rate limit, 401, lost answers. Every identity has a random
/// `epoch` (new when it is deleted and created again), sent in `identity`
/// objects and, for /e2e answers, in the `x-bbu-identity-epoch` header
/// (the browser cookie is `__Host-bbu_sync`; the fake keeps it per device).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';

final _rnd = Random(42);

/// 22-char base64url (16 random bytes), like the Worker's epochs.
String _newEpoch() => base64Url
    .encode([for (var i = 0; i < 16; i++) _rnd.nextInt(256)])
    .replaceAll('=', '');

class FakeIdentity {
  FakeIdentity(this.host, this.school, this.userId) : epoch = _newEpoch();
  final String host;
  final String school;
  final String userId;

  /// Changes only when the identity is deleted and created again.
  final String epoch;
  int lastSeq = 0;
  final Map<String, Map<String, Object?>> notes = {};
  Map<String, Object?>? header;

  /// Note writes on [writesDay] (UTC day number).
  int writesToday = 0;
  int writesDay = -1;

  Map<String, Object?> get json => {
    'host': host,
    'school': school,
    'userId': userId,
    'epoch': epoch,
  };
}

class FakeSyncServer {
  FakeSyncServer({required this.now, this.pageSize = 1000});

  DateTime Function() now;
  int pageSize;
  final Map<String, FakeIdentity> identities = {};

  /// token -> identity key.
  final Map<String, String> sessions = {};
  int _tokens = 0;
  int putRequests = 0;
  final List<String> log = [];

  /// Every request answers with this status (e.g. simulate outages).
  int? forceStatus;

  /// `PUT /notes` always fails with clock_skew (with serverTime).
  bool alwaysClockSkew = false;

  /// `POST /session` answers with this status (e.g. 503, 429).
  int? sessionStatus;

  /// The next [busyPuts] `PUT /notes` answer 503 `busy` (retry-after 5),
  /// without writing.
  int busyPuts = 0;

  /// Stored bytes per identity (key + text/homework/blob), like the Worker's 5 MiB.
  int maxBytes = 5 * 1024 * 1024;

  /// Live notes (tombstones don't count) per identity.
  int maxLiveNotes = 5000;

  /// Note writes per identity and UTC day → 429 `daily_limit`.
  int dailyWrites = 5000;

  /// Notes written by PUT /notes (stored because they were newer).
  int noteWrites = 0;

  /// Extra response headers of the last answer (taken by the device).
  Map<String, String> _headers = {};
  Map<String, String> takeHeaders() {
    final h = _headers;
    _headers = {};
    return h;
  }

  /// Writes (PUT notes, PUT/PATCH/DELETE e2e) allowed until
  /// [resetWriteWindow]; null = unlimited. Then 429 + retry-after 60.
  int? writesPerWindow;
  int writesInWindow = 0;
  void resetWriteWindow() => writesInWindow = 0;

  /// "METHOD path" entries: the request is carried out, then the answer is
  /// lost (connection error) once.
  final Set<String> loseAnswer = {};

  /// Called with "METHOD path" after each request was handled.
  void Function(String request)? onHandled;

  FakeIdentity? identity(String host, String school, String userId) =>
      identities['$host|$school|$userId'];

  /// A device: an adapter; with [browser] it keeps the session cookie,
  /// sends it when no bearer token is given and (like a browser) an Origin
  /// on POST /session, so it gets no token in the body.
  FakeDevice device({bool browser = false}) => FakeDevice(this, browser);

  (int, Object?, String?) handle(
    String method,
    Uri uri,
    Map<String, dynamic> headers,
    Object? body,
    String? cookie, {
    bool origin = false,
  }) {
    final path = uri.path;
    log.add('$method $path');
    _headers = {};
    if (forceStatus != null) {
      return (forceStatus!, {'error': 'forced', 'message': 'forced'}, null);
    }
    (int, Object?, String?) err(
      int s,
      String code, [
      Map<String, Object?>? extra,
    ]) => (s, {'error': code, 'message': code, ...?extra}, null);

    if (path == '/api/sync/session' && method == 'POST') {
      if (sessionStatus case final st?) return err(st, 'unavailable');
      final b = body as Map;
      final t = '${b['untisToken']}';
      if (!t.startsWith('untis:')) return err(401, 'invalid_token');
      final host = '${b['host']}'.toLowerCase();
      final school = '${b['school']}'.toLowerCase();
      final user = t.substring('untis:'.length);
      final key = '$host|$school|$user';
      final existing = identities.containsKey(key);
      final ident = identities.putIfAbsent(
        key,
        () => FakeIdentity(host, school, user),
      );
      final token = 'tok${_tokens++}';
      sessions[token] = key;
      return (
        200,
        {
          if (!origin) 'token': token,
          'expiresAt': now().add(const Duration(days: 90)).toIso8601String(),
          'identity': ident.json,
          'e2e': ident.header != null,
          'existing': existing,
        },
        token,
      );
    }
    if (path == '/api/sync/session' && method == 'DELETE') {
      final t = _presented(headers, cookie);
      if (t != null) sessions.remove(t);
      return (204, null, '');
    }

    final t = _presented(headers, cookie);
    if (t != null && _isCookie(headers) && headers['x-bbu-sync'] != '1') {
      return err(403, 'csrf_rejected');
    }
    final key = t == null ? null : sessions[t];
    final ident = key == null ? null : identities[key];
    if (ident == null) return err(401, 'unauthorized');
    // Like the Worker: the epoch header on GET 200/404, PUT 201, PATCH 200
    // and DELETE 204 of /e2e.
    void epochHeader() =>
        _headers = {..._headers, 'x-bbu-identity-epoch': ident.epoch};

    final write =
        (method == 'PUT' && path == '/api/sync/notes') ||
        (path == '/api/sync/e2e' && method != 'GET');
    if (write && writesPerWindow != null) {
      if (writesInWindow >= writesPerWindow!) {
        _headers = {..._headers, 'retry-after': '60'};
        return err(429, 'rate_limited');
      }
      writesInWindow++;
    }

    switch ((method, path)) {
      case ('GET', '/api/sync/notes'):
        final since = int.parse(uri.queryParameters['since'] ?? '0');
        final changed =
            ident.notes.values.where((n) => (n['seq'] as int) > since).toList()
              ..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
        final more = changed.length > pageSize;
        return (
          200,
          {
            'notes': changed.take(pageSize).toList(),
            'latestSeq': ident.lastSeq,
            'more': more,
            'e2e': ident.header != null,
            'identity': ident.json,
          },
          null,
        );
      case ('PUT', '/api/sync/notes'):
        if (busyPuts > 0) {
          busyPuts--;
          _headers = {'retry-after': '5'};
          return err(503, 'busy');
        }
        putRequests++;
        final list = (body as Map)['notes'] as List;
        if (list.length > 500) return err(413, 'batch_too_large');
        final e2e = ident.header != null;
        final serverTime = now().millisecondsSinceEpoch;
        final limit = serverTime + 5 * 60 * 1000;
        for (final n in list.cast<Map>()) {
          if ((n['updatedAt'] as int) > limit || alwaysClockSkew) {
            return err(400, 'clock_skew', {'serverTime': serverTime});
          }
          if ((n['blob'] != null) != e2e) {
            return err(409, e2e ? 'e2e_required' : 'e2e_not_enabled');
          }
        }
        final next = {...ident.notes};
        final changedKeys = <String>[];
        final keys = <String>[];
        for (final n in list.cast<Map>()) {
          final k = n['key'] as String;
          keys.add(k);
          final old = next[k];
          final at = n['updatedAt'] as int;
          // Tie: the stored version stays.
          if (old == null || at > (old['updatedAt'] as int)) {
            final deleted = n['deleted'] == true;
            next[k] = {
              'key': k,
              if (e2e)
                'blob': n['blob']
              else ...{
                // Plaintext tombstones are stored without content.
                'exam': deleted ? false : n['exam'],
                'text': deleted ? '' : n['text'],
                // Optional (missing = ''), like the Worker.
                'homework': deleted ? '' : (n['homework'] ?? ''),
              },
              'updatedAt': at,
              'deleted': deleted,
            };
            changedKeys
              ..remove(k)
              ..add(k);
          }
        }
        final day = now().toUtc().millisecondsSinceEpoch ~/ 86400000;
        if (ident.writesDay != day) {
          ident
            ..writesDay = day
            ..writesToday = 0;
        }
        if (changedKeys.isNotEmpty &&
            ident.writesToday + changedKeys.length > dailyWrites) {
          final midnight = (day + 1) * 86400000;
          _headers = {
            'retry-after':
                '${((midnight - now().millisecondsSinceEpoch) / 1000).ceil()}',
          };
          return err(429, 'daily_limit');
        }
        int live(Map<String, Map<String, Object?>> m) =>
            m.values.where((n) => n['deleted'] != true).length;
        final liveAfter = live(next);
        if (liveAfter > maxLiveNotes && liveAfter > live(ident.notes)) {
          return err(413, 'too_many_notes');
        }
        var bytes = 0;
        for (final n in next.values) {
          bytes += utf8.encode(n['key'] as String).length;
          bytes += utf8.encode('${n['blob'] ?? n['text'] ?? ''}').length;
          bytes += utf8.encode('${n['homework'] ?? ''}').length;
        }
        if (bytes > maxBytes) return err(413, 'storage_quota');
        ident.writesToday += changedKeys.length;
        noteWrites += changedKeys.length;
        for (final k in changedKeys) {
          next[k] = {...next[k]!, 'seq': ++ident.lastSeq};
        }
        ident.notes
          ..clear()
          ..addAll(next);
        return (
          200,
          {
            'notes': [for (final k in keys.toSet()) ident.notes[k]],
            'latestSeq': ident.lastSeq,
            'e2e': e2e,
            'identity': ident.json,
          },
          null,
        );
      case ('GET', '/api/sync/e2e'):
        epochHeader();
        if (ident.header == null) return err(404, 'e2e_not_enabled');
        return (200, ident.header, null);
      case ('PUT', '/api/sync/e2e'):
        final h = Map<String, Object?>.from(body as Map);
        final hash = h['authHash'];
        if (hash is! String || hash.length != 43) {
          return err(400, 'bad_request');
        }
        if (ident.header != null) return err(409, 'e2e_exists');
        ident.header = h;
        ident.notes.removeWhere((_, n) => n['blob'] == null);
        epochHeader();
        return (201, ident.header, null);
      case ('PATCH', '/api/sync/e2e'):
        final b = body as Map;
        if (b['header'] is! Map || b['authKey'] is! String) {
          return err(400, 'bad_request');
        }
        if (ident.header == null) return err(404, 'e2e_not_enabled');
        final h = Map<String, Object?>.from(b['header'] as Map);
        final stored = ident.header!['authHash'];
        if (_hash(b['authKey'] as String) != stored ||
            h['authHash'] != stored) {
          return err(403, 'e2e_auth_failed');
        }
        ident.header = h;
        epochHeader();
        return (200, h, null);
      case ('DELETE', '/api/sync/e2e'):
        final b = body as Map?;
        if (b == null || b['authKey'] is! String) {
          return err(400, 'bad_request');
        }
        if (ident.header == null) return err(404, 'e2e_not_enabled');
        if (_hash(b['authKey'] as String) != ident.header!['authHash']) {
          return err(403, 'e2e_auth_failed');
        }
        // Sessions and lastSeq stay.
        ident.header = null;
        ident.notes.clear();
        epochHeader();
        return (204, null, null);
      case ('DELETE', '/api/sync/account'):
        identities.remove(key);
        sessions.removeWhere((_, v) => v == key);
        return (204, null, '');
    }
    return err(404, 'not_found');
  }

  /// base64url(SHA-256(base64url-decoded authKey)), unpadded.
  static String _hash(String authKeyB64) {
    final pad = '=' * ((4 - authKeyB64.length % 4) % 4);
    final bytes = base64Url.decode(authKeyB64 + pad);
    return base64Url.encode(sha256.convert(bytes).bytes).replaceAll('=', '');
  }

  static bool _isCookie(Map<String, dynamic> headers) =>
      headers['authorization'] == null;

  static String? _presented(Map<String, dynamic> headers, String? cookie) {
    final auth = headers['authorization'] as String?;
    if (auth != null && auth.startsWith('Bearer ')) return auth.substring(7);
    return cookie;
  }
}

class FakeDevice implements HttpClientAdapter {
  FakeDevice(this.server, this.browser);
  final FakeSyncServer server;
  final bool browser;
  String? cookie;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object? body;
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final c in requestStream) {
        bytes.addAll(c);
      }
      if (bytes.isNotEmpty) body = jsonDecode(utf8.decode(bytes));
    }
    final headers = {
      for (final e in options.headers.entries) e.key.toLowerCase(): e.value,
    };
    final (status, json, setCookie) = server.handle(
      options.method,
      options.uri,
      headers,
      body,
      browser ? cookie : null,
      origin: browser,
    );
    if (browser && setCookie != null) {
      cookie = setCookie.isEmpty ? null : setCookie;
    }
    final extra = server.takeHeaders();
    server.onHandled?.call('${options.method} ${options.uri.path}');
    if (server.loseAnswer.remove('${options.method} ${options.uri.path}')) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'answer lost (test)',
      );
    }
    return ResponseBody.fromString(
      json == null ? '' : jsonEncode(json),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        for (final e in extra.entries) e.key: [e.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
