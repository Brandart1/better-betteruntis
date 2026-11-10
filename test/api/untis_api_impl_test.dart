import 'dart:convert';
import 'dart:typed_data';

import 'package:better_betteruntis/api/totp.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Handler = ({Object? body, String contentType, int status}) Function(
  String method,
  Map<String, Object?> params,
);

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final Handler handler;
  final requests = <({Uri uri, String method, Map<String, Object?> params})>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final c in requestStream) {
        bytes.addAll(c);
      }
    }
    final req = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    final method = req['method'] as String;
    final params = (req['params'] as List).first as Map<String, Object?>;
    requests.add((uri: options.uri, method: method, params: params));
    final r = handler(method, params);
    final text = r.body is String ? r.body as String : jsonEncode(r.body);
    return ResponseBody.fromString(
      text,
      r.status,
      headers: {
        Headers.contentTypeHeader: [r.contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

({Object? body, String contentType, int status}) ok(
  Object? result, {
  String contentType = 'application/json',
}) => (
  body: {'id': '1', 'jsonrpc': '2.0', 'result': result},
  contentType: contentType,
  status: 200,
);

({Object? body, String contentType, int status}) err(int code, String msg) => (
  body: {
    'id': '1',
    'jsonrpc': '2.0',
    'error': {
      'code': code,
      'message': msg,
      'data': {'exceptionTypeName': 'X', 'message': msg},
    },
  },
  contentType: 'application/json',
  status: 200,
);

const school = School(
  schoolId: 1,
  loginName: 'demo school',
  displayName: 'Demo',
  address: '',
  host: 'demo.webuntis.com',
);

final userData = {
  'masterData': {
    'timeStamp': 42,
    'teachers': [
      {'id': 1, 'name': 'MUE'},
    ],
  },
  'userData': {'elemId': 7, 'elemType': 'STUDENT', 'displayName': 'Max'},
};

final fixedNow = DateTime.fromMillisecondsSinceEpoch(1731230000000);

(UntisApiImpl, FakeAdapter) make(Handler h) {
  final adapter = FakeAdapter(h);
  final dio = Dio()..httpClientAdapter = adapter;
  return (UntisApiImpl(dio: dio, now: () => fixedNow), adapter);
}

void main() {
  test('getAppSharedSecret -8504 falls back to password as secret', () async {
    final (api, a) = make(
      (m, p) => m == 'getAppSharedSecret'
          ? err(-8504, 'bad credentials')
          : ok(userData),
    );
    final r = await api.login(
      school: school,
      username: 'max',
      passwordOrKey: 'JBSWY3DPEHPK3PXP',
    );
    expect(r.secret, 'JBSWY3DPEHPK3PXP');
    expect(r.displayName, 'Max');
    expect(r.elementId, 7);
    expect(r.masterData.timestamp, 42);
    expect(a.requests.map((r) => r.method), [
      'getAppSharedSecret',
      'getUserData2017',
    ]);
    final uri = a.requests.last.uri;
    expect(uri.host, 'demo.webuntis.com');
    expect(uri.path, '/WebUntis/jsonrpc_intern.do');
    expect(uri.queryParameters['school'], 'demo school');
    final p = a.requests.last.params;
    expect(p['elementId'], 0);
    expect(p['deviceOs'], 'AND');
    final auth = p['auth'] as Map;
    expect(auth['user'], 'max');
    expect(auth['clientTime'], fixedNow.millisecondsSinceEpoch);
    expect(
      auth['otp'],
      totp('JBSWY3DPEHPK3PXP', fixedNow.millisecondsSinceEpoch),
    );
  });

  test('shared secret from server is used', () async {
    final (api, a) = make(
      (m, p) => m == 'getAppSharedSecret' ? ok('SECRETXYZ') : ok(userData),
    );
    final r = await api.login(
      school: school,
      username: 'max',
      passwordOrKey: 'pw',
      twoFactorToken: '123456',
    );
    expect(r.secret, 'SECRETXYZ');
    expect(a.requests.first.params, {
      'userName': 'max',
      'password': 'pw',
      'token': '123456',
    });
  });

  test('-8519 propagates', () async {
    final (api, a) = make(
      (m, p) => m == 'getAppSharedSecret' ? err(-8519, '2fa') : ok(userData),
    );
    await expectLater(
      api.login(school: school, username: 'max', passwordOrKey: 'pw'),
      throwsA(
        isA<UntisException>().having(
          (e) => e.code,
          'code',
          UntisException.twoFactorRequired,
        ),
      ),
    );
    expect(a.requests, hasLength(1));
  });

  test('anonymous login skips secret, uses #anonymous# otp 0', () async {
    final (api, a) = make((m, p) => ok(userData));
    await api.login(
      school: school,
      username: '',
      passwordOrKey: '',
      anonymous: true,
      hostOverride: 'https://custom.example.org/x',
    );
    expect(a.requests.single.method, 'getUserData2017');
    expect(a.requests.single.uri.host, 'custom.example.org');
    final auth = a.requests.single.params['auth'] as Map;
    expect(auth['user'], '#anonymous#');
    expect(auth['otp'], 0);
  });

  test('error mapping on getUserData2017', () async {
    final (api, _) = make((m, p) => err(-8524, 'client time'));
    await expectLater(
      api.login(
        school: school,
        username: 'u',
        passwordOrKey: 'k',
        skipAppSecret: true,
      ),
      throwsA(
        isA<UntisException>()
            .having((e) => e.code, 'code', -8524)
            .having((e) => e.message, 'message', 'client time'),
      ),
    );
  });

  test('non-JSON and HTTP errors map to code 0', () async {
    final (api, _) = make(
      (m, p) =>
          (body: '<html>oops</html>', contentType: 'text/html', status: 502),
    );
    await expectLater(
      api.searchSchools('foo'),
      throwsA(isA<UntisException>().having((e) => e.isNetwork, 'net', isTrue)),
    );
    expect(api.debugLog.single.json, '<html>oops</html>');
  });

  test(
    'searchSchools: application/json-rpc decoded; digits -> schoolid',
    () async {
      final (api, a) = make(
        (m, p) => ok({
          'schools': [
            {
              'loginName': 'demo',
              'schoolId': 123,
              'displayName': 'Demo',
              'serverUrl': 'https://demo.webuntis.com/WebUntis',
            },
          ],
        }, contentType: 'application/json-rpc'),
      );
      final schools = await api.searchSchools(' 123 ');
      expect(schools.single.host, 'demo.webuntis.com');
      expect(a.requests.single.params, {'schoolid': 123});
      expect(a.requests.single.uri.toString(), UntisApiImpl.schoolSearchUrl);
      await api.searchSchools('demo');
      expect(a.requests.last.params, {'search': 'demo'});
      expect(api.debugLog.map((e) => e.method), [
        'searchSchool',
        'searchSchool',
      ]);
    },
  );

  test('searchSchools -6003 throws', () async {
    final (api, _) = make((m, p) => err(-6003, 'too many'));
    await expectLater(
      api.searchSchools('a'),
      throwsA(
        isA<UntisException>().having(
          (e) => e.code,
          'code',
          UntisException.tooManyResults,
        ),
      ),
    );
  });

  test('timetable params and parsing', () async {
    final (api, a) = make(
      (m, p) => ok({
        'timetable': {
          'periods': [
            {
              'id': 1,
              'startDateTime': '2025-09-15T08:00',
              'endDateTime': '2025-09-15T08:45',
              'elements': [
                {'type': 'TEACHER', 'id': 1},
              ],
            },
          ],
        },
        'masterData': {'timeStamp': 99},
      }),
    );
    final r = await api.timetable(
      host: 'h.example',
      school: 's',
      auth: const UntisCredentials.user('u', 'GEZDGNBVGY3TQOJQ'),
      target: const TimetableTarget(ElementType.klasse, 10),
      start: DateTime(2025, 9, 15),
      end: DateTime(2025, 9, 19, 23, 59),
      masterDataTimestamp: 5,
    );
    expect(r.periods.single.elements.single.orgId, 1);
    expect(r.masterDataDelta!.timestamp, 99);
    final p = a.requests.single.params;
    expect(p['type'], 'CLASS');
    expect(p['id'], 10);
    expect(p['startDate'], '2025-09-15');
    expect(p['endDate'], '2025-09-19');
    expect(p['masterDataTimestamp'], 5);
    expect(p['timetableTimestamp'], 0);
    expect(p['timetableTimestamps'], isEmpty);
  });

  test('messagesOfDay', () async {
    final (api, a) = make(
      (m, p) => ok({
        'messages': [
          {'id': 1, 'subject': 'S', 'body': '<p>b</p>'},
        ],
      }),
    );
    final msgs = await api.messagesOfDay(
      host: 'h',
      school: 's',
      auth: const UntisCredentials.anonymous(),
      date: DateTime(2025, 9, 15),
    );
    expect(msgs.single.subject, 'S');
    expect(a.requests.single.method, 'getMessagesOfDay2017');
    expect(a.requests.single.params['date'], '2025-09-15');
  });

  test('debug log keeps last 30', () async {
    final (api, _) = make((m, p) => ok({'messages': []}));
    for (var i = 0; i < 35; i++) {
      await api.messagesOfDay(
        host: 'h',
        school: 's',
        auth: const UntisCredentials.anonymous(),
        date: DateTime(2025),
      );
    }
    expect(api.debugLog, hasLength(30));
  });
}
