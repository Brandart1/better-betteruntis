import 'dart:convert';
import 'dart:io';

import 'package:bbu_server/bbu_server.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request req(String method, String path, {Map<String, String>? headers}) =>
    Request(method, Uri.parse('http://localhost:8080$path'), headers: headers);

final okClient = MockClient((_) async => http.Response('{}', 200));

void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('bbu_web_');
    void write(String rel, String content) => (File(
      '${root.path}/$rel',
    )..createSync(recursive: true)).writeAsStringSync(content);
    write('index.html', '<!doctype html><title>app</title>');
    write('flutter_bootstrap.js', '// bootstrap');
    write('flutter_service_worker.js', '// sw');
    write('version.json', '{"version":"0.1.0"}');
    write('main.dart.js', '// main');
    write('main.dart.mjs', '// main mjs');
    write('main.dart.wasm', 'wasm');
    write('sqlite3.wasm', 'wasm');
    write('assets/fonts/MaterialIcons-Regular.otf', 'otf');
    write('assets/packages/x/Roboto.ttf', 'ttf');
    write('icons/Icon-192.png', 'png');
    write('assets/AssetManifest.bin', 'bin');
    // A secret next to (outside) the web root.
    File('${root.parent.path}/bbu_secret_${root.path.hashCode}.txt')
        .writeAsStringSync('secret');
  });

  tearDownAll(() {
    root.deleteSync(recursive: true);
    File('${root.parent.path}/bbu_secret_${root.path.hashCode}.txt')
        .deleteSync();
  });

  Handler handler({String? basicAuth, String? coep = 'credentialless'}) =>
      buildHandler(
        ServerConfig(webRoot: root.path, basicAuth: basicAuth, coep: coep),
        okClient,
      );

  group('static files', () {
    test('serves index.html at /', () async {
      final res = await handler()(req('GET', '/'));
      expect(res.statusCode, 200);
      expect(await res.readAsString(), contains('<title>app</title>'));
      expect(res.headers['content-type'], 'text/html; charset=utf-8');
      expect(res.headers['cache-control'], 'no-cache');
    });

    for (final path in [
      '/timetable',
      '/timetable/2026-11-10',
      '/settings/accounts/1',
    ]) {
      test('SPA fallback for $path', () async {
        final res = await handler()(req('GET', path));
        expect(res.statusCode, 200);
        expect(await res.readAsString(), contains('<title>app</title>'));
        expect(res.headers['cache-control'], 'no-cache');
      });
    }

    test('missing file with extension -> 404 (no fallback)', () async {
      expect((await handler()(req('GET', '/missing.js'))).statusCode, 404);
      expect((await handler()(req('GET', '/assets/nope.png'))).statusCode, 404);
    });

    final mime = {
      '/main.dart.js': 'text/javascript; charset=utf-8',
      '/main.dart.mjs': 'text/javascript; charset=utf-8',
      '/main.dart.wasm': 'application/wasm',
      '/sqlite3.wasm': 'application/wasm',
      '/version.json': 'application/json',
      '/assets/fonts/MaterialIcons-Regular.otf': 'font/otf',
      '/assets/packages/x/Roboto.ttf': 'font/ttf',
      '/icons/Icon-192.png': 'image/png',
      '/assets/AssetManifest.bin': 'application/octet-stream',
    };
    mime.forEach((path, type) {
      test('MIME type for $path', () async {
        final res = await handler()(req('GET', path));
        expect(res.statusCode, 200);
        expect(res.headers['content-type'], type);
      });
    });

    test('cache headers', () async {
      for (final p in [
        '/index.html',
        '/flutter_service_worker.js',
        '/version.json',
        '/flutter_bootstrap.js',
        '/main.dart.js',
      ]) {
        expect(
          (await handler()(req('GET', p))).headers['cache-control'],
          'no-cache',
          reason: p,
        );
      }
      expect(
        (await handler()(req('GET', '/assets/fonts/MaterialIcons-Regular.otf')))
            .headers['cache-control'],
        startsWith('public, max-age='),
      );
    });

    test('ETag revalidation returns 304', () async {
      final first = await handler()(req('GET', '/main.dart.js'));
      final etag = first.headers['etag']!;
      final second = await handler()(
        req('GET', '/main.dart.js', headers: {'if-none-match': etag}),
      );
      expect(second.statusCode, 304);
    });

    test('HEAD has no body', () async {
      final res = await handler()(req('HEAD', '/main.dart.js'));
      expect(res.statusCode, 200);
      expect(await res.readAsString(), isEmpty);
    });

    test('POST to static -> 405', () async {
      expect((await handler()(req('POST', '/index.html'))).statusCode, 405);
    });

    test('cannot escape the web root', () async {
      final name = 'bbu_secret_${root.path.hashCode}.txt';
      for (final p in [
        '/../$name',
        '/%2e%2e/$name',
        '/assets/..%2f..%2f$name',
        '/..%5c$name',
      ]) {
        final res = await handler()(req('GET', p));
        expect(await res.readAsString(), isNot(contains('secret')), reason: p);
        expect(res.statusCode, isNot(200), reason: p);
      }
    });

    test('directory path falls back to index.html', () async {
      final res = await handler()(req('GET', '/assets'));
      expect(res.statusCode, 200);
      expect(await res.readAsString(), contains('<title>app</title>'));
    });
  });

  group('security headers', () {
    test('present on static, proxy, healthz and errors', () async {
      for (final p in ['/', '/proxy/x.webuntis.com/x', '/healthz', '/x.js']) {
        final res = await handler()(req('GET', p));
        expect(res.headers['cross-origin-opener-policy'], 'same-origin');
        expect(res.headers['cross-origin-embedder-policy'], 'credentialless');
        expect(res.headers['x-content-type-options'], 'nosniff');
        expect(res.headers['referrer-policy'], 'no-referrer');
      }
    });

    test('BBU_COEP overrides or disables COEP', () async {
      final cfgDefault = ServerConfig.fromEnvironment({});
      expect(cfgDefault.coep, 'credentialless');
      final cfgCorp = ServerConfig.fromEnvironment({
        'BBU_COEP': 'require-corp',
      });
      expect(cfgCorp.coep, 'require-corp');
      final cfgOff = ServerConfig.fromEnvironment({'BBU_COEP': ''});
      expect(cfgOff.coep, isNull);

      final res = await handler(coep: null)(req('GET', '/'));
      expect(res.headers.containsKey('cross-origin-embedder-policy'), isFalse);
      expect(res.headers['cross-origin-opener-policy'], 'same-origin');
    });
  });

  test('/healthz', () async {
    final res = await handler()(req('GET', '/healthz'));
    expect(res.statusCode, 200);
    expect(await res.readAsString(), 'ok');
  });

  group('basic auth', () {
    String basic(String s) => 'Basic ${base64.encode(utf8.encode(s))}';
    late Handler h;
    setUp(() => h = handler(basicAuth: 'admin:p:ss wörd'));

    test('rejects missing / wrong credentials', () async {
      for (final headers in <Map<String, String>?>[
        null,
        {'authorization': basic('admin:wrong')},
        {'authorization': basic('admin:p:ss wörd2')},
        {'authorization': basic('admin:p:ss wör')},
        {'authorization': 'Basic !!!notbase64'},
        {'authorization': 'Bearer abc'},
        {'cookie': '$authCookieName=forged'},
      ]) {
        final res = await h(req('GET', '/', headers: headers));
        expect(res.statusCode, 401, reason: '$headers');
        expect(res.headers['www-authenticate'], startsWith('Basic realm='));
      }
    });

    test('proxy is protected too', () async {
      final res = await h(req('GET', '/proxy/x.webuntis.com/x'));
      expect(res.statusCode, 401);
    });

    test('healthz is exempt', () async {
      expect((await h(req('GET', '/healthz'))).statusCode, 200);
    });

    test('accepts correct credentials and issues a session cookie', () async {
      final res = await h(
        req('GET', '/', headers: {'authorization': basic('admin:p:ss wörd')}),
      );
      expect(res.statusCode, 200);
      final setCookie = res.headers['set-cookie']!;
      expect(setCookie, startsWith('$authCookieName='));
      expect(setCookie, contains('HttpOnly'));
      expect(setCookie, contains('SameSite=Strict'));

      // The cookie authorises requests whose Authorization header is the
      // app's own Bearer token (browsers then don't send basic creds).
      final cookie = setCookie.split(';').first;
      final proxied = await h(
        req(
          'GET',
          '/proxy/x.webuntis.com/WebUntis/api/rest/view/v1/app/data',
          headers: {'cookie': cookie, 'authorization': 'Bearer tok'},
        ),
      );
      expect(proxied.statusCode, 200);
    });

    test('cookie is tied to the password', () async {
      final res = await h(
        req('GET', '/', headers: {'authorization': basic('admin:p:ss wörd')}),
      );
      final cookie = res.headers['set-cookie']!.split(';').first;
      final other = handler(basicAuth: 'admin:other');
      expect(
        (await other(req('GET', '/', headers: {'cookie': cookie}))).statusCode,
        401,
      );
    });

    test('invalid BBU_BASIC_AUTH refuses to start', () {
      for (final v in ['nocolon', ':pw', 'user:']) {
        expect(
          () => ServerConfig.fromEnvironment({'BBU_BASIC_AUTH': v}),
          throwsFormatException,
          reason: v,
        );
      }
      expect(
        ServerConfig.fromEnvironment({'BBU_BASIC_AUTH': ''}).basicAuth,
        isNull,
      );
    });

    test('constantTimeEquals', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
      expect(constantTimeEquals([1, 2, 3, 4], [1, 2, 3]), isFalse);
      expect(constantTimeEquals([1, 2, 4], [1, 2, 3]), isFalse);
    });
  });

  test('PORT parsing', () {
    expect(ServerConfig.fromEnvironment({}).port, 8080);
    expect(ServerConfig.fromEnvironment({'PORT': '9000'}).port, 9000);
    expect(
      () => ServerConfig.fromEnvironment({'PORT': 'abc'}),
      throwsFormatException,
    );
  });
}
