import 'dart:async';
import 'dart:io' show SocketException, HttpException, HandshakeException;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import 'host_allowlist.dart';

/// Path prefix of the proxy endpoint.
const proxyPrefix = '/proxy/';

/// Request headers copied from the browser to the upstream request.
/// Everything else (cookies, Origin, Referer, X-Forwarded-*, ...) is dropped.
const forwardedRequestHeaders = [
  'content-type',
  'accept',
  'accept-language',
  'authorization',
];

const upstreamUserAgent = 'BetterBetterUntis-Web/1.0';

const _allowedMethods = {'GET', 'POST', 'HEAD'};

typedef LogFn = void Function(String message);

/// Forwards `/proxy/<host>/<rest>?<query>` to `https://<host>/<rest>?<query>`
/// for allowlisted hosts.
class WebUntisProxy {
  WebUntisProxy({
    required this.client,
    required this.allowlist,
    this.maxRequestBodyBytes = 1024 * 1024,
    this.maxResponseBodyBytes = 32 * 1024 * 1024,
    this.timeout = const Duration(seconds: 45),
    LogFn? log,
  }) : _log = log ?? ((_) {});

  final http.Client client;
  final HostAllowlist allowlist;
  final int maxRequestBodyBytes;
  final int maxResponseBodyBytes;
  final Duration timeout;
  final LogFn _log;

  Future<Response> call(Request request) async {
    final sw = Stopwatch()..start();
    final target = parseTarget(request.requestedUri, allowlist);
    if (target == null) {
      // Deliberately does not echo the requested host.
      _log(
        'proxy ${request.method} <rejected> 403 ${sw.elapsedMilliseconds}ms',
      );
      return _error(403, 'Forbidden upstream host');
    }
    final logPrefix = 'proxy ${request.method} ${target.host}${target.path}';

    Response done(Response r) {
      _log('$logPrefix ${r.statusCode} ${sw.elapsedMilliseconds}ms');
      return r;
    }

    if (!_allowedMethods.contains(request.method)) {
      return done(
        _error(405, 'Method not allowed', {'allow': 'GET, POST, HEAD'}),
      );
    }

    final Uint8List body;
    try {
      body = await _readBody(request);
    } on _TooLarge {
      return done(_error(413, 'Request body too large'));
    }

    final upstream = http.Request(request.method, target)
      ..followRedirects = false
      ..persistentConnection = true;
    for (final name in forwardedRequestHeaders) {
      final v = request.headers[name];
      if (v == null) continue;
      // Only bearer tokens go upstream. Browsers attach cached HTTP basic
      // credentials (BBU_BASIC_AUTH) to same-origin fetches; those must
      // never leak to WebUntis.
      if (name == 'authorization' && !_isBearer(v)) continue;
      upstream.headers[name] = v;
    }
    upstream.headers['user-agent'] = upstreamUserAgent;
    if (body.isNotEmpty) upstream.bodyBytes = body;

    final deadline = DateTime.now().add(timeout);
    try {
      final streamed = await client.send(upstream).timeout(timeout);
      final remaining = deadline.difference(DateTime.now());
      final bytes = await _collect(
        streamed.stream,
        maxResponseBodyBytes,
      ).timeout(remaining.isNegative ? Duration.zero : remaining);

      final headers = <String, String>{'cache-control': 'no-store'};
      final ct = streamed.headers['content-type'];
      if (ct != null) headers['content-type'] = ct;
      return done(
        Response(
          streamed.statusCode,
          body: request.method == 'HEAD' ? null : bytes,
          headers: headers,
        ),
      );
    } on TimeoutException {
      return done(_error(504, 'Upstream timeout'));
    } on _TooLarge {
      return done(_error(502, 'Upstream response too large'));
    } on http.ClientException {
      return done(_error(502, 'Upstream connection failed'));
    } on SocketException {
      return done(_error(502, 'Upstream connection failed'));
    } on HandshakeException {
      return done(_error(502, 'Upstream TLS handshake failed'));
    } on HttpException {
      return done(_error(502, 'Upstream protocol error'));
    }
  }

  Future<Uint8List> _readBody(Request request) async {
    final declared = request.contentLength;
    if (declared != null && declared > maxRequestBodyBytes) {
      throw _TooLarge();
    }
    return _collect(request.read(), maxRequestBodyBytes);
  }
}

/// Parses and validates the proxy target from a request URI.
///
/// Returns null if the URI is not a well-formed proxy request for an
/// allowlisted host. The host segment is validated in its raw (still
/// percent-encoded) form, so `%2F`, `%40`, `@`, `:port` etc. are all rejected.
/// The upstream [Uri] is assembled from parts so the path cannot alter the
/// authority.
Uri? parseTarget(Uri requested, HostAllowlist allowlist) {
  final path = requested.path; // percent-encoded, dot-segments resolved
  if (!path.startsWith(proxyPrefix)) return null;
  final afterPrefix = path.substring(proxyPrefix.length);
  final slash = afterPrefix.indexOf('/');
  final rawHost = slash < 0 ? afterPrefix : afterPrefix.substring(0, slash);
  final rest = slash < 0 ? '/' : afterPrefix.substring(slash);

  final host = rawHost.toLowerCase();
  if (!isValidHostname(host) || !allowlist.allows(host)) return null;

  // Belt and braces: no dot segments, empty segments or backslashes in the
  // forwarded path (WebUntis never needs them).
  final segments = rest.substring(1).split('/');
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    final lower = s.toLowerCase();
    if (s.isEmpty && i != segments.length - 1) return null;
    if (lower == '.' ||
        lower == '..' ||
        lower == '%2e' ||
        lower == '%2e%2e' ||
        lower == '.%2e' ||
        lower == '%2e.' ||
        lower.contains('%5c') ||
        lower.contains('%00')) {
      return null;
    }
  }

  return Uri(
    scheme: 'https',
    host: host,
    path: rest,
    query: requested.hasQuery ? requested.query : null,
  );
}

bool _isBearer(String v) => v.trimLeft().toLowerCase().startsWith('bearer ');

class _TooLarge implements Exception {}

Future<Uint8List> _collect(Stream<List<int>> stream, int limit) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (builder.length + chunk.length > limit) throw _TooLarge();
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Response _error(int status, String message, [Map<String, String>? extra]) =>
    Response(
      status,
      body: message,
      headers: {
        'content-type': 'text/plain; charset=utf-8',
        'cache-control': 'no-store',
        ...?extra,
      },
    );
