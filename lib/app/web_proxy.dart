/// Browser builds can't call WebUntis directly (CORS), so every request goes
/// through the relay of the Cloudflare Worker that also serves the web app
/// (`worker/src/proxy.ts`, same origin), which forwards
/// `<origin>/proxy/<host>/<path>?<query>` to `https://<host>/<path>?<query>`.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

/// The relay's stand-ins for cookies (worker/src/proxy.ts): a browser never
/// lets the app read WebUntis' `Set-Cookie` nor send a `Cookie`, so the
/// WebUntis website session (needed e.g. to report an absence) travels in
/// these headers instead.
const sessionRequestHeader = 'x-bbu-cookie';
const sessionResponseHeader = 'x-bbu-set-cookie';

/// Headers a browser refuses to set; the relay sets Origin / Referer of the
/// school's site itself when a session is sent.
const _browserOnly = {'cookie', 'origin', 'referer'};

/// Maps an absolute `https://host/...` URL onto the proxy at [origin].
/// Anything that isn't absolute https (e.g. already proxied) is returned
/// unchanged.
String proxiedUrl(String url, Uri origin) {
  final u = Uri.tryParse(url);
  if (u == null || u.scheme != 'https' || u.host.isEmpty) return url;
  final base = origin.replace(path: '', query: null, fragment: null);
  // Already rewritten (a request repeated after a rate limit).
  if (u.origin == base.origin && u.path.startsWith('/proxy/')) return url;
  final path = u.path.isEmpty ? '/' : u.path;
  return '${base.origin}/proxy/${u.host}$path${u.hasQuery ? '?${u.query}' : ''}';
}

/// Rewrites every request URL with [proxiedUrl]. The JSON-RPC client and the
/// REST calls pass absolute URLs as the request path, which this rewrites.
class WebProxyInterceptor extends Interceptor {
  WebProxyInterceptor(this.origin);

  final Uri origin;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final rewritten = proxiedUrl(options.uri.toString(), origin);
    options
      ..baseUrl = ''
      ..path = rewritten
      ..queryParameters = {};
    for (final name in [...options.headers.keys]) {
      final lower = name.toLowerCase();
      if (!_browserOnly.contains(lower)) continue;
      final value = options.headers.remove(name);
      if (lower == 'cookie' && value != null && '$value'.trim().isNotEmpty) {
        options.headers[sessionRequestHeader] = '$value';
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    exposeSessionCookies(response.headers);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response case final r?) exposeSessionCookies(r.headers);
    handler.next(err);
  }
}

/// Puts the relay's [sessionResponseHeader] back as `set-cookie`, where the
/// web session login looks for it.
void exposeSessionCookies(Headers headers) {
  final raw = headers.value(sessionResponseHeader);
  if (raw == null) return;
  try {
    final list = jsonDecode(raw);
    if (list is! List) return;
    headers.set('set-cookie', [for (final c in list) '$c']);
  } on FormatException {
    // Not from our relay: ignored.
  }
}
