/// Browser builds can't call WebUntis directly (CORS), so every request goes
/// through the self-hosted server (`server/`), which forwards
/// `<origin>/proxy/<host>/<path>?<query>` to `https://<host>/<path>?<query>`.
library;

import 'package:dio/dio.dart';

/// Maps an absolute `https://host/...` URL onto the proxy at [origin].
/// Anything that isn't absolute https (e.g. already proxied) is returned
/// unchanged.
String proxiedUrl(String url, Uri origin) {
  final u = Uri.tryParse(url);
  if (u == null || u.scheme != 'https' || u.host.isEmpty) return url;
  final base = origin.replace(path: '', query: null, fragment: null);
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
    handler.next(options);
  }
}
