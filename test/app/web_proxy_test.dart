import 'package:better_betteruntis/app/web_proxy.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final origin = Uri.parse('https://untis.home.lan:8443/some/route?x=1#frag');

  test('maps absolute https URLs onto the proxy, keeping the query', () {
    expect(
      proxiedUrl('https://nessa.webuntis.com/WebUntis/jsonrpc_intern.do?school=a%20b', origin),
      'https://untis.home.lan:8443/proxy/nessa.webuntis.com/WebUntis/jsonrpc_intern.do?school=a%20b',
    );
    expect(
      proxiedUrl('https://schoolsearch.webuntis.com/schoolquery2', origin),
      'https://untis.home.lan:8443/proxy/schoolsearch.webuntis.com/schoolquery2',
    );
  });

  test('leaves non-https and relative URLs alone', () {
    expect(proxiedUrl('/proxy/x/y', origin), '/proxy/x/y');
    expect(proxiedUrl('http://x.webuntis.com/a', origin), 'http://x.webuntis.com/a');
  });

  test('interceptor folds query parameters into the rewritten path', () {
    final opts = RequestOptions(
      path: 'https://x.webuntis.com/WebUntis/api/rest/view/v1/timetable/entries',
      queryParameters: {'start': '2026-11-09', 'format': 4},
    );
    late RequestOptions seen;
    WebProxyInterceptor(origin).onRequest(opts, _Capture((o) => seen = o));
    expect(
      seen.uri.toString(),
      'https://untis.home.lan:8443/proxy/x.webuntis.com/WebUntis/api/rest/view/v1/timetable/entries?start=2026-11-09&format=4',
    );
  });
}

class _Capture extends RequestInterceptorHandler {
  _Capture(this.onNext);
  final void Function(RequestOptions) onNext;
  @override
  void next(RequestOptions requestOptions) => onNext(requestOptions);
}
