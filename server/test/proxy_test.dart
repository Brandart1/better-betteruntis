import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bbu_server/bbu_server.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Records upstream requests and replies with a canned response.
class Recorder {
  final requests = <http.Request>[];

  MockClient client({
    int status = 200,
    String body = '{"ok":true}',
    Map<String, String> headers = const {
      'content-type': 'application/json;charset=UTF-8',
      'set-cookie': 'JSESSIONID=abc; Path=/',
      'x-powered-by': 'untis',
      'access-control-allow-origin': '*',
      'location': 'https://evil.com/',
    },
  }) => MockClient((req) async {
    requests.add(req);
    return http.Response(body, status, headers: headers);
  });
}

Handler handlerWith(
  http.Client client, {
  ServerConfig? config,
  List<String>? logs,
}) => buildHandler(
  config ?? ServerConfig(webRoot: Directory.systemTemp.path),
  client,
  log: logs?.add,
);

Request req(
  String method,
  String pathAndQuery, {
  Map<String, String>? headers,
  Object? body,
}) => Request(
  method,
  Uri.parse('http://localhost:8080$pathAndQuery'),
  headers: headers,
  body: body,
);

void main() {
  group('host allowlist', () {
    final allow = HostAllowlist.parse('webuntis.com,*.webuntis.com');

    test('accepts exact and wildcard hosts', () {
      expect(allow.allows('webuntis.com'), isTrue);
      expect(allow.allows('mese.webuntis.com'), isTrue);
      expect(allow.allows('a.b.webuntis.com'), isTrue);
      expect(allow.allows('schoolsearch.webuntis.com'), isTrue);
    });

    test('rejects look-alikes', () {
      for (final h in [
        'evil.com',
        'webuntis.com.evil.com',
        'evilwebuntis.com',
        'xwebuntis.com',
        '.webuntis.com',
        'a..webuntis.com',
        'a.webuntis.com.',
        '-a.webuntis.com',
        'user@x.webuntis.com',
        'x.webuntis.com:444',
        'WEBUNTIS.COM', // allows() expects pre-lowercased input
        '127.0.0.1',
        '',
      ]) {
        expect(allow.allows(h), isFalse, reason: h);
      }
    });

    test('wildcard without exact does not match bare suffix', () {
      final a = HostAllowlist.parse('*.example.org');
      expect(a.allows('example.org'), isFalse);
      expect(a.allows('x.example.org'), isTrue);
    });

    test('invalid allowlist entries are rejected at startup', () {
      expect(() => HostAllowlist.parse(''), throwsFormatException);
      expect(() => HostAllowlist.parse('*.'), throwsFormatException);
      expect(() => HostAllowlist.parse('a.com:80'), throwsFormatException);
      expect(() => HostAllowlist.parse('*'), throwsFormatException);
    });
  });

  group('proxy target', () {
    late Recorder rec;
    late Handler h;
    setUp(() {
      rec = Recorder();
      h = handlerWith(rec.client());
    });

    for (final path in [
      '/proxy/evil.com/WebUntis/jsonrpc.do',
      '/proxy/webuntis.com.evil.com/x',
      '/proxy/user@x.webuntis.com/x',
      '/proxy/user%40x.webuntis.com/x',
      '/proxy/x.webuntis.com:444/x',
      '/proxy/x.webuntis.com%3A444/x',
      '/proxy/evil.com%2Fx.webuntis.com/x',
      '/proxy/evil.com%2F@x.webuntis.com/x',
      '/proxy/x.webuntis.com%2F..%2F..%2Fevil.com/x',
      '/proxy/evil.com%23.webuntis.com/x',
      '/proxy/evil.com%5c.webuntis.com/x',
      '/proxy/127.0.0.1/x',
      '/proxy/localhost/x',
      '/proxy/',
      '/proxy',
      '/proxy//x.webuntis.com/x',
      '/proxy/x.webuntis.com//evil.com/x',
      '/proxy/x.webuntis.com/%2e%2e/evil.com/x',
      '/proxy/x.webuntis.com/a%5c..%5cb',
    ]) {
      test('rejects $path', () async {
        final res = await h(req('GET', path));
        expect(res.statusCode, 403, reason: path);
        expect(rec.requests, isEmpty);
      });
    }

    test('dot segments are resolved before routing (cannot escape)', () async {
      // Uri parsing resolves /proxy/x.webuntis.com/../evil.com/y to
      // /proxy/evil.com/y, which is then rejected.
      final res = await h(req('GET', '/proxy/x.webuntis.com/../evil.com/y'));
      expect(res.statusCode, 403);
      expect(rec.requests, isEmpty);
    });

    test('uppercase host is normalised', () async {
      final res = await h(req('GET', '/proxy/MESE.WebUntis.com/WebUntis/'));
      expect(res.statusCode, 200);
      expect(rec.requests.single.url.host, 'mese.webuntis.com');
    });

    test('builds https URL and preserves the query verbatim', () async {
      final res = await h(
        req(
          'POST',
          '/proxy/mese.webuntis.com/WebUntis/jsonrpc_intern.do'
              '?m=getUserData2017&school=Gym%20Musterstadt&v=i2.2&a=%2F%3D',
          headers: {'content-type': 'application/json'},
          body: '{"id":"1","method":"getUserData2017"}',
        ),
      );
      expect(res.statusCode, 200);
      final u = rec.requests.single.url;
      expect(
        u.toString(),
        'https://mese.webuntis.com/WebUntis/jsonrpc_intern.do'
        '?m=getUserData2017&school=Gym%20Musterstadt&v=i2.2&a=%2F%3D',
      );
      expect(u.scheme, 'https');
      expect(u.port, 443);
      expect(u.userInfo, isEmpty);
    });

    test('encoded slashes in the path stay inside the path', () async {
      await h(req('GET', '/proxy/x.webuntis.com/a%2F%2Fevil.com/b'));
      final u = rec.requests.single.url;
      expect(u.host, 'x.webuntis.com');
      expect(u.path, '/a%2F%2Fevil.com/b');
    });

    test('bare host forwards to /', () async {
      await h(req('GET', '/proxy/schoolsearch.webuntis.com'));
      expect(
        rec.requests.single.url.toString(),
        'https://schoolsearch.webuntis.com/',
      );
    });

    test('custom allowlist from environment', () async {
      final cfg = ServerConfig.fromEnvironment({
        'BBU_ALLOWED_HOSTS': 'untis.example.org',
        'BBU_WEB_ROOT': Directory.systemTemp.path,
      });
      final h2 = handlerWith(rec.client(), config: cfg);
      expect(
        (await h2(req('GET', '/proxy/untis.example.org/x'))).statusCode,
        200,
      );
      expect((await h2(req('GET', '/proxy/x.webuntis.com/x'))).statusCode, 403);
    });
  });

  group('proxy forwarding', () {
    late Recorder rec;
    late Handler h;
    late List<String> logs;
    setUp(() {
      rec = Recorder();
      logs = [];
      h = handlerWith(rec.client(), logs: logs);
    });

    test('forwards only allowed request headers and a neutral UA', () async {
      await h(
        req(
          'GET',
          '/proxy/x.webuntis.com/WebUntis/api/rest/view/v1/app/data',
          headers: {
            'authorization': 'Bearer tok123',
            'accept': 'application/json',
            'accept-language': 'de',
            'content-type': 'application/json',
            'cookie': 'bbu_auth=secret',
            'origin': 'https://home.lan',
            'referer': 'https://home.lan/timetable',
            'user-agent': 'Mozilla/5.0',
            'x-forwarded-for': '10.0.0.1',
            'accept-encoding': 'br',
          },
        ),
      );
      final sent = rec.requests.single.headers;
      expect(sent.keys.toSet(), {
        'authorization',
        'accept',
        'accept-language',
        'content-type',
        'user-agent',
      });
      expect(sent['authorization'], 'Bearer tok123');
      expect(sent['user-agent'], upstreamUserAgent);
    });

    test('basic-auth credentials are never forwarded upstream', () async {
      await h(
        req(
          'POST',
          '/proxy/x.webuntis.com/WebUntis/jsonrpc_intern.do',
          headers: {'authorization': 'Basic dXNlcjpwYXNz'},
          body: '{}',
        ),
      );
      expect(rec.requests.single.headers.containsKey('authorization'), isFalse);
    });

    test('forwards the body byte-for-byte', () async {
      final body = utf8.encode('{"params":[{"auth":{"user":"ä"}}]}');
      await h(
        req(
          'POST',
          '/proxy/x.webuntis.com/WebUntis/jsonrpc_intern.do',
          headers: {'content-type': 'application/json'},
          body: body,
        ),
      );
      expect(rec.requests.single.method, 'POST');
      expect(rec.requests.single.bodyBytes, body);
      expect(rec.requests.single.headers['content-type'], 'application/json');
    });

    test('returns only status, body and content-type', () async {
      final h2 = handlerWith(rec.client(status: 418, body: 'teapot'));
      final res = await h2(req('GET', '/proxy/x.webuntis.com/x'));
      expect(res.statusCode, 418);
      expect(await res.readAsString(), 'teapot');
      expect(res.headers['content-type'], 'application/json;charset=UTF-8');
      expect(res.headers['cache-control'], 'no-store');
      expect(res.headers.containsKey('set-cookie'), isFalse);
      expect(res.headers.containsKey('x-powered-by'), isFalse);
      expect(res.headers.containsKey('access-control-allow-origin'), isFalse);
      expect(res.headers.containsKey('location'), isFalse);
    });

    test('redirects are not followed', () async {
      await h(req('GET', '/proxy/x.webuntis.com/x'));
      expect(rec.requests.single.followRedirects, isFalse);
    });

    test('HEAD is forwarded without body', () async {
      final res = await h(req('HEAD', '/proxy/x.webuntis.com/x'));
      expect(res.statusCode, 200);
      expect(rec.requests.single.method, 'HEAD');
      expect(await res.readAsString(), isEmpty);
    });

    for (final m in ['PUT', 'DELETE', 'PATCH', 'OPTIONS', 'CONNECT', 'TRACE']) {
      test('rejects method $m', () async {
        final res = await h(req(m, '/proxy/x.webuntis.com/x'));
        expect(res.statusCode, 405);
        expect(rec.requests, isEmpty);
      });
    }

    test('request body over the limit -> 413', () async {
      final big = List.filled(1024 * 1024 + 1, 0x61);
      final res = await h(req('POST', '/proxy/x.webuntis.com/x', body: big));
      expect(res.statusCode, 413);
      expect(rec.requests, isEmpty);
    });

    test(
      'streamed body over the limit without content-length -> 413',
      () async {
        final stream = Stream<List<int>>.fromIterable(
          List.generate(17, (_) => List.filled(64 * 1024, 0x61)),
        );
        final res = await h(
          req('POST', '/proxy/x.webuntis.com/x', body: stream),
        );
        expect(res.statusCode, 413);
        expect(rec.requests, isEmpty);
      },
    );

    test('logs method, host, path and status but no secrets', () async {
      await h(
        req(
          'POST',
          '/proxy/x.webuntis.com/WebUntis/jsonrpc_intern.do?school=secretschool',
          headers: {'authorization': 'Bearer tok123'},
          body: '{"password":"hunter2"}',
        ),
      );
      expect(logs, hasLength(1));
      final line = logs.single;
      expect(
        line,
        contains('POST x.webuntis.com/WebUntis/jsonrpc_intern.do 200'),
      );
      expect(line, isNot(contains('secretschool')));
      expect(line, isNot(contains('tok123')));
      expect(line, isNot(contains('hunter2')));
    });

    test('rejected host is not echoed into the log', () async {
      await h(req('GET', '/proxy/evil.com/x'));
      expect(logs.single, isNot(contains('evil.com')));
    });
  });

  group('upstream failures', () {
    test('timeout -> 504', () async {
      final never = MockClient((_) => Completer<http.Response>().future);
      final h = handlerWith(
        never,
        config: ServerConfig(
          webRoot: Directory.systemTemp.path,
          upstreamTimeout: const Duration(milliseconds: 50),
        ),
      );
      final res = await h(req('GET', '/proxy/x.webuntis.com/x'));
      expect(res.statusCode, 504);
    });

    test('slow response body also counts towards the timeout', () async {
      final slow = MockClient.streaming((r, _) async {
        final c = StreamController<List<int>>();
        c.add([1]); // never closed
        return http.StreamedResponse(c.stream, 200);
      });
      final h = handlerWith(
        slow,
        config: ServerConfig(
          webRoot: Directory.systemTemp.path,
          upstreamTimeout: const Duration(milliseconds: 50),
        ),
      );
      expect((await h(req('GET', '/proxy/x.webuntis.com/x'))).statusCode, 504);
    });

    test('ClientException -> 502', () async {
      final failing = MockClient((_) => throw http.ClientException('refused'));
      final res = await handlerWith(failing)(
        req('GET', '/proxy/x.webuntis.com/x'),
      );
      expect(res.statusCode, 502);
    });

    test('SocketException -> 502', () async {
      final failing = MockClient(
        (_) => throw const SocketException('Failed host lookup'),
      );
      final res = await handlerWith(failing)(
        req('GET', '/proxy/x.webuntis.com/x'),
      );
      expect(res.statusCode, 502);
    });

    test('oversized upstream response -> 502', () async {
      final big = MockClient((_) async => http.Response('x' * 2000, 200));
      final h = handlerWith(
        big,
        config: ServerConfig(
          webRoot: Directory.systemTemp.path,
          maxResponseBodyBytes: 1000,
        ),
      );
      expect((await h(req('GET', '/proxy/x.webuntis.com/x'))).statusCode, 502);
    });
  });
}
