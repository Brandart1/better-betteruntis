import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import 'config.dart';
import 'proxy.dart';
import 'static_files.dart';

/// Builds the complete request handler.
///
/// [client] is the upstream HTTP client (injected so tests can fake it).
Handler buildHandler(ServerConfig config, http.Client client, {LogFn? log}) {
  final logFn = log ?? ((_) {});
  final proxy = WebUntisProxy(
    client: client,
    allowlist: config.allowlist,
    maxRequestBodyBytes: config.maxRequestBodyBytes,
    maxResponseBodyBytes: config.maxResponseBodyBytes,
    timeout: config.upstreamTimeout,
    log: logFn,
  );
  final statics = StaticFiles(config.webRoot);

  Future<Response> router(Request request) async {
    final path = request.requestedUri.path;
    if (path == '/healthz') {
      return Response.ok(
        'ok',
        headers: {
          'content-type': 'text/plain; charset=utf-8',
          'cache-control': 'no-store',
        },
      );
    }
    if (path == '/proxy' || path.startsWith(proxyPrefix)) {
      return proxy(request);
    }
    final sw = Stopwatch()..start();
    final res = await statics(request);
    if (res.statusCode >= 400) {
      // Static requests are only logged on errors to keep logs quiet.
      logFn(
        'static ${request.method} $path ${res.statusCode} '
        '${sw.elapsedMilliseconds}ms',
      );
    }
    return res;
  }

  return const Pipeline()
      .addMiddleware(_securityHeaders(config.coep))
      .addMiddleware(_basicAuth(config.basicAuth))
      .addHandler(router);
}

Middleware _securityHeaders(String? coep) {
  final headers = {
    'cross-origin-opener-policy': 'same-origin',
    'cross-origin-embedder-policy': ?coep,
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
  };
  return (inner) => (request) async {
    final res = await inner(request);
    return res.change(headers: headers);
  };
}

/// Name of the cookie that carries the basic-auth session.
const authCookieName = 'bbu_auth';

/// HTTP basic auth over everything except `/healthz`.
///
/// The app's REST calls set their own `Authorization: Bearer ...` header,
/// which replaces the browser's cached basic credentials for that request.
/// So after a successful basic login we also set an HttpOnly, SameSite=Strict
/// cookie holding HMAC-SHA256(credentials, "bbu-session-v1"), and accept
/// either the basic header or that cookie. The cookie value changes when the
/// password changes and is never forwarded upstream.
Middleware _basicAuth(String? credentials) {
  if (credentials == null) return (inner) => inner;
  final expected = utf8.encode(credentials);
  final token = Hmac(
    sha256,
    expected,
  ).convert(utf8.encode('bbu-session-v1')).toString();
  final tokenBytes = utf8.encode(token);

  return (inner) => (request) async {
    if (request.requestedUri.path == '/healthz') return inner(request);
    final cookie = _cookieValue(request.headers['cookie'], authCookieName);
    if (cookie != null && constantTimeEquals(utf8.encode(cookie), tokenBytes)) {
      return inner(request);
    }
    if (_basicMatches(request.headers['authorization'], expected)) {
      final res = await inner(request);
      final secure =
          request.requestedUri.scheme == 'https' ||
              request.headers['x-forwarded-proto'] == 'https'
          ? '; Secure'
          : '';
      return res.change(
        headers: {
          'set-cookie':
              '$authCookieName=$token; Path=/; HttpOnly; '
              'SameSite=Strict; Max-Age=2592000$secure',
        },
      );
    }
    return Response.unauthorized(
      'Authentication required',
      headers: {
        'www-authenticate': 'Basic realm="BetterBetterUntis", charset="UTF-8"',
        'content-type': 'text/plain; charset=utf-8',
        'cache-control': 'no-store',
      },
    );
  };
}

String? _cookieValue(String? header, String name) {
  if (header == null) return null;
  for (final part in header.split(';')) {
    final i = part.indexOf('=');
    if (i < 0) continue;
    if (part.substring(0, i).trim() == name) {
      return part.substring(i + 1).trim();
    }
  }
  return null;
}

bool _basicMatches(String? header, List<int> expected) {
  if (header == null) return false;
  final parts = header.trim().split(RegExp(r'\s+'));
  if (parts.length != 2 || parts[0].toLowerCase() != 'basic') return false;
  List<int> given;
  try {
    given = base64.decode(parts[1]);
  } on FormatException {
    return false;
  }
  return constantTimeEquals(given, expected);
}

/// Compares two byte lists in time that depends only on [expected]'s length.
bool constantTimeEquals(List<int> given, List<int> expected) {
  var diff = given.length ^ expected.length;
  for (var i = 0; i < expected.length; i++) {
    final g = i < given.length ? given[i] : 0;
    diff |= g ^ expected[i];
  }
  return diff == 0;
}
