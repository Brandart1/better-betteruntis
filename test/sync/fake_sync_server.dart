/// In-memory stand-in for the Worker's sync API (worker/src/sync/), used
/// as a dio [HttpClientAdapter]: sessions, last-write-wins notes with seqs,
/// tombstones, E2E header (create once, PATCH with the same check, PUT
/// deletes plaintext notes), account deletion, clock skew, 401.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class FakeIdentity {
  int lastSeq = 0;
  final Map<String, Map<String, Object?>> notes = {};
  Map<String, Object?>? header;
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

  FakeIdentity? identity(String host, String school, String userId) =>
      identities['$host|$school|$userId'];

  /// A device: an adapter; with [browser] it keeps the session cookie and
  /// sends it when no bearer token is given.
  FakeDevice device({bool browser = false}) => FakeDevice(this, browser);

  (int, Object?, String?) handle(
    String method,
    Uri uri,
    Map<String, dynamic> headers,
    Object? body,
    String? cookie,
  ) {
    final path = uri.path;
    log.add('$method $path');
    if (forceStatus != null) {
      return (forceStatus!, {'error': 'forced', 'message': 'forced'}, null);
    }
    (int, Object?, String?) err(int s, String code) =>
        (s, {'error': code, 'message': code}, null);

    if (path == '/api/sync/session' && method == 'POST') {
      final b = body as Map;
      final t = '${b['untisToken']}';
      if (!t.startsWith('untis:')) return err(401, 'invalid_token');
      final host = '${b['host']}'.toLowerCase();
      final school = '${b['school']}'.toLowerCase();
      final user = t.substring('untis:'.length);
      final key = '$host|$school|$user';
      final ident = identities.putIfAbsent(key, FakeIdentity.new);
      final token = 'tok${_tokens++}';
      sessions[token] = key;
      return (
        200,
        {
          'token': token,
          'expiresAt': now().add(const Duration(days: 90)).toIso8601String(),
          'identity': {'host': host, 'school': school, 'userId': user},
          'e2e': ident.header != null,
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
          },
          null,
        );
      case ('PUT', '/api/sync/notes'):
        putRequests++;
        final list = (body as Map)['notes'] as List;
        if (list.length > 500) return err(413, 'batch_too_large');
        final e2e = ident.header != null;
        final limit = now().millisecondsSinceEpoch + 5 * 60 * 1000;
        for (final n in list.cast<Map>()) {
          if ((n['blob'] != null) != e2e) {
            return err(409, e2e ? 'e2e_required' : 'e2e_not_enabled');
          }
          if ((n['updatedAt'] as int) > limit) return err(400, 'clock_skew');
        }
        final keys = <String>[];
        for (final n in list.cast<Map>()) {
          final k = n['key'] as String;
          keys.add(k);
          final old = ident.notes[k];
          final at = n['updatedAt'] as int;
          if (old == null || at > (old['updatedAt'] as int)) {
            ident.notes[k] = {
              'key': k,
              if (e2e)
                'blob': n['blob']
              else ...{
                'exam': n['exam'],
                'text': n['text'],
              },
              'updatedAt': at,
              'deleted': n['deleted'],
              'seq': ++ident.lastSeq,
            };
          }
        }
        return (
          200,
          {
            'notes': [for (final k in keys.toSet()) ident.notes[k]],
            'latestSeq': ident.lastSeq,
            'e2e': e2e,
          },
          null,
        );
      case ('GET', '/api/sync/e2e'):
        if (ident.header == null) return err(404, 'e2e_not_enabled');
        return (200, ident.header, null);
      case ('PUT', '/api/sync/e2e'):
        if (ident.header != null) return err(409, 'e2e_exists');
        ident.header = Map<String, Object?>.from(body as Map);
        ident.notes.removeWhere((_, n) => n['blob'] == null);
        return (201, ident.header, null);
      case ('PATCH', '/api/sync/e2e'):
        if (ident.header == null) return err(404, 'e2e_not_enabled');
        final h = Map<String, Object?>.from(body as Map);
        if (h['check'] != ident.header!['check']) {
          return err(409, 'e2e_check_mismatch');
        }
        ident.header = h;
        return (200, h, null);
      case ('DELETE', '/api/sync/account'):
        identities.remove(key);
        sessions.removeWhere((_, v) => v == key);
        return (204, null, '');
    }
    return err(404, 'not_found');
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
    );
    if (browser && setCookie != null) {
      cookie = setCookie.isEmpty ? null : setCookie;
    }
    return ResponseBody.fromString(
      json == null ? '' : jsonEncode(json),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
