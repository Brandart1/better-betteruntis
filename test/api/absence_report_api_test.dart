import 'dart:convert';
import 'dart:typed_data';

import 'package:better_betteruntis/api/parsers.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/core/info.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Req = ({
  String method,
  Uri uri,
  Map<String, dynamic> headers,
  Map<String, Object?>? json,
});
typedef Resp = ({int status, Object? body, Map<String, List<String>> headers});

Resp ok(Object? body) => (status: 200, body: body, headers: const {});
Resp rpc(Object? result) => ok({'id': '1', 'jsonrpc': '2.0', 'result': result});

class Adapter implements HttpClientAdapter {
  Adapter(this.handler);
  final Resp Function(Req r) handler;
  final requests = <Req>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final c in requestStream) {
        bytes.addAll(c);
      }
    }
    final req = (
      method: o.method,
      uri: o.uri,
      headers: o.headers,
      json: bytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(bytes)) as Map<String, Object?>,
    );
    requests.add(req);
    final r = handler(req);
    return ResponseBody.fromString(
      r.body is String ? r.body as String : jsonEncode(r.body),
      r.status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        ...r.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const host = 'demo.webuntis.com';
const schoolName = 'demo school';
const creds = UntisCredentials.user('parent', 'JBSWY3DPEHPK3PXP');

final report = AbsenceReport(
  studentId: 1001,
  start: DateTime(2026, 11, 10, 7, 50),
  end: DateTime(2026, 11, 11, 13, 5),
  reasonId: 2,
  text: 'Fieber',
);

void main() {
  group('parsers', () {
    test('payload matches the web client (yyyymmdd / hhmm numbers)', () {
      expect(absenceReportPayload(report), {
        'studentId': 1001,
        'startDate': 20261110,
        'startTime': 750,
        'endDate': 20261111,
        'endTime': 1305,
        'reasonId': 2,
        'text': 'Fieber',
      });
      final noReason = AbsenceReport(
        studentId: 1,
        start: DateTime(2026, 1, 2, 8),
        end: DateTime(2026, 1, 2, 9),
      );
      expect(absenceReportPayload(noReason)['reasonId'], -1);
    });

    test('meta: reasons, default reason and times, tolerant', () {
      final o = parseAbsenceMeta({
        'data': {
          'absenceReasons': [
            {'id': 1, 'name': 'Krankheit'},
            {'id': 2, 'longName': 'Arzttermin', 'name': 'AT'},
            {'id': 3, 'name': '---'},
            {'id': 4, 'name': 'Alt', 'active': false},
            {'name': 'no id'},
            'junk',
          ],
          'defaultAbsenceReason': {'id': 2},
          'defaultStartTime': 750,
          'defaultEndTime': '16:00',
        },
      });
      expect(o.reasons.map((r) => (r.id, r.name)), [
        (1, 'Krankheit'),
        (2, 'Arzttermin'),
      ]);
      expect(o.defaultReasonId, 2);
      expect(o.defaultStartMinutes, 7 * 60 + 50);
      expect(o.defaultEndMinutes, 16 * 60);
      expect(o.allowed, isNull);

      final empty = parseAbsenceMeta('nonsense');
      expect(empty.reasons, isEmpty);
      expect(empty.defaultReasonId, isNull);
      // Unknown default ids are dropped.
      expect(
        parseAbsenceMeta({
          'reasons': [
            {'id': 1, 'name': 'A'},
          ],
          'defaultReasonId': 9,
        }).defaultReasonId,
        isNull,
      );
    });

    test('list flags: showCreateAbsence', () {
      expect(
        parseAbsenceListFlags({
          'data': {'absences': [], 'showCreateAbsence': false},
        }).allowed,
        isFalse,
      );
      expect(
        parseAbsenceListFlags({
          'data': {'showCreateAbsence': true},
        }).allowed,
        isTrue,
      );
      expect(parseAbsenceListFlags({'data': {}}).allowed, isNull);
    });

    test('write result: errors and conflicts throw, data passes', () {
      checkAbsenceWriteResult({
        'data': {'result': {}, 'conflicts': []},
      });
      checkAbsenceWriteResult(null);
      expect(
        () => checkAbsenceWriteResult({
          'errors': [
            {'code': 'X', 'title': 'Not allowed in the past'},
          ],
        }),
        throwsA(
          isA<UntisException>().having(
            (e) => e.message,
            'message',
            'Not allowed in the past',
          ),
        ),
      );
      expect(
        () => checkAbsenceWriteResult({
          'data': {
            'conflicts': [
              {'text': 'Already absent'},
            ],
          },
        }),
        throwsA(
          isA<UntisException>().having(
            (e) => e.message,
            'message',
            contains('Already absent'),
          ),
        ),
      );
    });
  });

  group('UntisApiImpl', () {
    late Adapter adapter;
    late UntisApiImpl api;
    late Resp Function(Req r) handler;

    setUp(() {
      handler = (_) => (status: 500, body: '', headers: const {});
      adapter = Adapter((r) => handler(r));
      api = UntisApiImpl(
        dio: Dio()..httpClientAdapter = adapter,
        now: () => DateTime(2026, 11, 10, 12),
      );
    });

    bool isToken(Req r) => r.json?['method'] == 'getAuthToken';

    test('report: POSTs the body with the bearer token and logs it', () async {
      handler = (r) => isToken(r)
          ? rpc({'token': 'jwt-secret-1'})
          : ok({
              'data': {
                'result': {'id': 77},
                'conflicts': [],
              },
            });
      await api.reportAbsence(
        host: host,
        school: schoolName,
        auth: creds,
        report: report,
      );
      final post = adapter.requests.last;
      expect(post.method, 'POST');
      expect(
        post.uri.toString(),
        'https://$host/WebUntis/api/classreg/absences/students/self',
      );
      expect(post.headers['Authorization'], 'Bearer jwt-secret-1');
      expect(post.json, absenceReportPayload(report));

      final log = api.debugLog;
      final body = log.firstWhere((e) => e.method.contains('request body'));
      expect(jsonDecode(body.json), absenceReportPayload(report));
      expect(
        log.last.method,
        allOf(contains('absences/students/self'), contains('HTTP 200')),
      );
      expect(log.last.json, contains('conflicts'));
      // The token never shows up in the log.
      expect(log.map((e) => e.json).join(), isNot(contains('jwt-secret-1')));
    });

    test('report: client-side validation sends nothing', () async {
      await expectLater(
        api.reportAbsence(
          host: host,
          school: schoolName,
          auth: creds,
          report: AbsenceReport(
            studentId: 1001,
            start: DateTime(2026, 11, 10, 10),
            end: DateTime(2026, 11, 10, 9),
          ),
        ),
        throwsA(isA<UntisException>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('report: 403 -> noRight', () async {
      handler = (r) => isToken(r)
          ? rpc({'token': 't'})
          : (status: 403, body: '', headers: const {});
      await expectLater(
        api.reportAbsence(
          host: host,
          school: schoolName,
          auth: creds,
          report: report,
        ),
        throwsA(
          isA<UntisException>().having(
            (e) => e.code,
            'code',
            UntisException.noRight,
          ),
        ),
      );
    });

    test('report: login redirect -> sessionRequired, Location logged '
        'without query', () async {
      handler = (r) => isToken(r)
          ? rpc({'token': 't'})
          : (
              status: 302,
              body: '',
              headers: {
                'location': [
                  'https://$host/WebUntis/index.do;jsessionid=abc?x=1',
                ],
              },
            );
      await expectLater(
        api.reportAbsence(
          host: host,
          school: schoolName,
          auth: creds,
          report: report,
        ),
        throwsA(
          isA<UntisException>().having(
            (e) => e.code,
            'code',
            UntisApiImpl.sessionRequired,
          ),
        ),
      );
      final last = api.debugLog.last;
      expect(last.method, contains('HTTP 302'));
      expect(last.json, contains('index.do'));
      expect(last.json, isNot(contains('jsessionid')));
    });

    test('report: HTML login page with 200 -> sessionRequired', () async {
      handler = (r) => isToken(r)
          ? rpc({'token': 't'})
          : ok('<!DOCTYPE html><html>login</html>');
      await expectLater(
        api.reportAbsence(
          host: host,
          school: schoolName,
          auth: creds,
          report: report,
        ),
        throwsA(
          isA<UntisException>().having(
            (e) => e.code,
            'code',
            UntisApiImpl.sessionRequired,
          ),
        ),
      );
    });

    test('report: 401 refreshes the token once', () async {
      var tokens = 0;
      handler = (r) {
        if (isToken(r)) return rpc({'token': 'jwt-${++tokens}'});
        return r.headers['Authorization'] == 'Bearer jwt-2'
            ? ok({
                'data': {'conflicts': []},
              })
            : (status: 401, body: '', headers: const {});
      };
      await api.reportAbsence(
        host: host,
        school: schoolName,
        auth: creds,
        report: report,
      );
      expect(tokens, 2);
    });

    bool isSession(Req r) => r.json?['method'] == 'getUserData2017';
    Resp session(String id) => (
      status: 200,
      body: {'id': '1', 'jsonrpc': '2.0', 'result': {}},
      headers: {
        'set-cookie': [
          'JSESSIONID=$id; Path=/WebUntis; Secure; HttpOnly',
          'traceId=t1; Path=/',
        ],
      },
    );

    test('report: sends the web session cookie from getUserData2017', () async {
      handler = (r) {
        if (isToken(r)) return rpc({'token': 't'});
        if (isSession(r)) return session('SESSION-SECRET');
        return ok({
          'data': {'conflicts': []},
        });
      };
      await api.reportAbsence(
        host: host,
        school: schoolName,
        auth: creds,
        report: report,
      );
      final login = adapter.requests.firstWhere(isSession);
      expect(login.uri.queryParameters, {
        'school': schoolName,
        'm': 'getUserData2017',
        'v': 'i2.2',
      });
      final post = adapter.requests.last;
      final b64 = base64.encode(utf8.encode(schoolName));
      expect(
        post.headers['Cookie'],
        'schoolname="_$b64"; JSESSIONID=SESSION-SECRET; traceId=t1',
      );
      expect(post.headers['Authorization'], 'Bearer t');
      final log = api.debugLog;
      expect(log.last.method, contains('(web session)'));
      final names = log.firstWhere((e) => e.method.contains('cookies'));
      expect(jsonDecode(names.json), {
        'names': ['JSESSIONID', 'traceId'],
      });
      expect(log.map((e) => e.json).join(), isNot(contains('SESSION-SECRET')));
    });

    test('CSRF token and tenant id from api/app/config are sent', () async {
      handler = (r) {
        if (isToken(r)) return rpc({'token': 't'});
        if (isSession(r)) return session('S');
        if (r.uri.path == '/WebUntis/api/app/config') {
          return ok({
            'data': {
              'tenant': {'id': 4711, 'displayName': 'X'},
              'user': {'name': 'Parent'},
              'csrfToken': 'CSRF-SECRET',
            },
          });
        }
        return ok({
          'data': {'conflicts': []},
        });
      };
      await api.reportAbsence(
        host: host,
        school: schoolName,
        auth: creds,
        report: report,
      );
      final post = adapter.requests.last;
      expect(post.headers['X-CSRF-TOKEN'], 'CSRF-SECRET');
      expect(post.headers['Tenant-Id'], '4711');
      final all = api.debugLog.map((e) => '${e.method} ${e.json}').join();
      expect(all, isNot(contains('CSRF-SECRET')));
      expect(all, isNot(contains('Parent')));
      expect(all, contains('data.csrfToken'));
      expect(all, contains('data.tenant.id'));
    });

    test('findSessionValues: loose key matching', () {
      final v = UntisApiImpl.findSessionValues({
        'tenantId': '12',
        'security': {'_csrf': 'abc'},
      });
      expect((v.csrf, v.csrfPath), ('abc', 'security._csrf'));
      expect((v.tenantId, v.tenantPath), ('12', 'tenantId'));
      final none = UntisApiImpl.findSessionValues('x');
      expect(none.csrf, isNull);
      expect(none.tenantId, isNull);
    });

    test('a cached session that gets redirected is reopened once', () async {
      var sessions = 0;
      handler = (r) {
        if (isToken(r)) return rpc({'token': 't'});
        if (isSession(r)) return session('S${++sessions}');
        if (r.headers['Cookie'].toString().contains('JSESSIONID=S2')) {
          return ok({
            'data': {'conflicts': []},
          });
        }
        if (r.method == 'GET') return ok({'data': {}});
        return (
          status: 302,
          body: '',
          headers: {
            'location': ['https://$host/WebUntis/index.do'],
          },
        );
      };
      await api.absenceReportOptions(
        host: host,
        school: schoolName,
        auth: creds,
        studentId: 1001,
      );
      expect(sessions, 1);
      await api.reportAbsence(
        host: host,
        school: schoolName,
        auth: creds,
        report: report,
      );
      expect(sessions, 2);
    });

    test('no JSESSIONID: falls back to the bearer token alone', () async {
      handler = (r) {
        if (isToken(r)) return rpc({'token': 't'});
        if (isSession(r)) return rpc({});
        return ok({
          'data': {'conflicts': []},
        });
      };
      await api.reportAbsence(
        host: host,
        school: schoolName,
        auth: creds,
        report: report,
      );
      expect(adapter.requests.last.headers['Cookie'], isNull);
      expect(api.debugLog.last.method, isNot(contains('web session')));
    });

    test('options: meta reasons + showCreateAbsence of the child', () async {
      handler = (r) {
        if (isToken(r)) return rpc({'token': 't'});
        if (r.uri.path.endsWith('/absences/meta')) {
          return ok({
            'data': {
              'absenceReasons': [
                {'id': 5, 'name': 'Krankmeldung durch Eltern'},
              ],
              'defaultAbsenceReason': {'id': 5},
            },
          });
        }
        return ok({
          'data': {'absences': [], 'showCreateAbsence': true},
        });
      };
      final o = await api.absenceReportOptions(
        host: host,
        school: schoolName,
        auth: creds,
        studentId: 1001,
      );
      expect(o.reasons.single.name, 'Krankmeldung durch Eltern');
      expect(o.defaultReasonId, 5);
      expect(o.allowed, isTrue);
      final list = adapter.requests.last.uri;
      expect(list.path, '/WebUntis/api/classreg/absences/students');
      expect(list.queryParameters, {
        'startDate': '20261110',
        'endDate': '20261110',
        'studentId': '1001',
        'excuseStatusId': '-1',
      });
    });

    test('options: one source failing is fine, both failing throws', () async {
      handler = (r) {
        if (isToken(r)) return rpc({'token': 't'});
        if (r.uri.path.endsWith('/absences/meta')) {
          return (status: 404, body: '', headers: const {});
        }
        return ok({
          'data': {
            'absenceReasons': [
              {'id': 1, 'name': 'Krankheit'},
            ],
            'showCreateAbsence': false,
          },
        });
      };
      final o = await api.absenceReportOptions(
        host: host,
        school: schoolName,
        auth: creds,
        studentId: 1001,
      );
      expect(o.allowed, isFalse);
      expect(o.reasons.single.id, 1);

      handler = (r) => isToken(r)
          ? rpc({'token': 't'})
          : (status: 403, body: '', headers: const {});
      await expectLater(
        api.absenceReportOptions(
          host: host,
          school: schoolName,
          auth: creds,
          studentId: 1001,
        ),
        throwsA(isA<UntisException>()),
      );
    });
  });
}
