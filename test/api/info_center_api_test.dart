import 'dart:convert';
import 'dart:typed_data';

import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Req = ({
  String httpMethod,
  Uri uri,
  Map<String, dynamic> headers,
  String? rpcMethod,
  Map<String, Object?>? params,
});
typedef Resp = ({int status, Object? body});

/// Serves JSON-RPC POSTs and REST GETs.
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
    String? m;
    Map<String, Object?>? p;
    if (bytes.isNotEmpty) {
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      m = j['method'] as String;
      p = (j['params'] as List).first as Map<String, Object?>;
    }
    final req = (
      httpMethod: o.method,
      uri: o.uri,
      headers: o.headers,
      rpcMethod: m,
      params: p,
    );
    requests.add(req);
    final r = handler(req);
    return ResponseBody.fromString(
      r.body is String ? r.body as String : jsonEncode(r.body),
      r.status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Resp rpc(Object? result) =>
    (status: 200, body: {'id': '1', 'jsonrpc': '2.0', 'result': result});

const host = 'demo.webuntis.com';
const schoolName = 'demo school';
const creds = UntisCredentials.user('max', 'JBSWY3DPEHPK3PXP');

const school = School(
  schoolId: 1,
  loginName: schoolName,
  displayName: 'Demo',
  address: '',
  host: host,
);

void main() {
  late Adapter adapter;
  late UntisApiImpl api;
  late Resp Function(Req r) handler;

  setUp(() {
    handler = (_) => (status: 500, body: '');
    adapter = Adapter((r) => handler(r));
    api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
  });

  List<String?> rpcCalls() => [for (final r in adapter.requests) r.rpcMethod];

  test('homework sends id/type/range/auth and joins lessons', () async {
    handler = (r) => rpc({
      'homeWorks': [
        {
          'id': 1,
          'lessonId': 55,
          'startDate': '2026-11-09',
          'endDate': '2026-11-11',
          'text': 'Exercise 3',
        },
      ],
      'lessonsById': {
        '55': {
          'id': 55,
          'subjectId': 21,
          'klassenIds': [1],
          'teacherIds': [11],
        },
      },
    });
    final items = await api.homework(
      host: host,
      school: schoolName,
      auth: creds,
      target: const TimetableTarget(ElementType.student, 7),
      start: DateTime(2026, 11, 9),
      end: DateTime(2026, 11, 22),
    );
    final p = adapter.requests.single.params!;
    expect(adapter.requests.single.rpcMethod, 'getHomeWork2017');
    expect(p['id'], 7);
    expect(p['type'], 'STUDENT');
    expect(p['startDate'], '2026-11-09');
    expect(p['endDate'], '2026-11-22');
    expect((p['auth'] as Map)['user'], 'max');
    expect(items.single.subjectId, 21);
    expect(items.single.teacherIds, [11]);
  });

  test('exams + office hours params', () async {
    handler = (r) => rpc(
      r.rpcMethod == 'getExams2017'
          ? {
              'exams': [
                {'id': 1, 'startDateTime': '2026-11-20T08:00'},
              ],
            }
          : {
              'officeHours': [
                {
                  'id': 2,
                  'startDateTime': '2026-11-11T10:00',
                  'endDateTime': '2026-11-11T10:45',
                  'displayNameTeacher': 'Erika Beispiel',
                },
              ],
            },
    );
    final exams = await api.exams(
      host: host,
      school: schoolName,
      auth: creds,
      target: const TimetableTarget(ElementType.klasse, 3),
      start: DateTime(2026, 11, 1),
      end: DateTime(2026, 11, 30),
    );
    final oh = await api.officeHours(
      host: host,
      school: schoolName,
      auth: creds,
      klasseId: 3,
      start: DateTime(2026, 11, 9),
    );
    expect(exams.single.id, 1);
    expect(oh.single.teacherName, 'Erika Beispiel');
    expect(adapter.requests[0].params!['type'], 'CLASS');
    expect(adapter.requests[1].rpcMethod, 'getOfficeHours2017');
    expect(adapter.requests[1].params!['klasseId'], 3);
    expect(adapter.requests[1].params!['startDate'], '2026-11-09');
  });

  group('absences', () {
    final absencesResult = {
      'absences': [
        {
          'id': 1,
          'startDateTime': '2026-10-01T08:00',
          'endDateTime': '2026-10-01T13:00',
          'excused': true,
          'absenceReasonId': 1,
          'absenceReason': '',
          'excuse': {'excuseStatusId': 5},
        },
      ],
    };
    final masterData = {
      'timeStamp': 1,
      'absenceReasons': [
        {'id': 1, 'name': 'K', 'longName': 'Illness', 'active': false},
      ],
      'excuseStatuses': [
        {'id': 5, 'name': 'e', 'longName': 'excused', 'excused': true},
      ],
    };

    test('params and names resolved from login master data', () async {
      handler = (r) => switch (r.rpcMethod) {
        'getAppSharedSecret' => rpc('SECRET'),
        'getUserData2017' => rpc({
          'masterData': masterData,
          'userData': {'elemType': 'STUDENT', 'elemId': 7},
        }),
        _ => rpc(absencesResult),
      };
      await api.login(school: school, username: 'max', passwordOrKey: 'pw');
      final items = await api.absences(
        host: host,
        school: schoolName,
        auth: creds,
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 11, 10),
      );
      final p = adapter.requests.last.params!;
      expect(adapter.requests.last.rpcMethod, 'getStudentAbsences2017');
      expect(p['startDate'], '2026-09-01');
      expect(p['endDate'], '2026-11-10');
      expect(p['includeExcused'], isTrue);
      expect(p['includeUnExcused'], isTrue);
      expect(items.single.reason, 'Illness');
      expect(items.single.excuseStatus, 'excused');
      expect(rpcCalls().where((m) => m == 'getUserData2017'), hasLength(1));
    });

    test('loads lookups once when not seen this session', () async {
      handler = (r) => switch (r.rpcMethod) {
        'getUserData2017' => rpc({'masterData': masterData}),
        _ => rpc(absencesResult),
      };
      for (var i = 0; i < 2; i++) {
        final items = await api.absences(
          host: host,
          school: schoolName,
          auth: creds,
          start: DateTime(2026, 9, 1),
          end: DateTime(2026, 11, 10),
        );
        expect(items.single.reason, 'Illness');
      }
      expect(rpcCalls(), [
        'getStudentAbsences2017',
        'getUserData2017',
        'getStudentAbsences2017',
      ]);
      final lookups = await api.absenceLookups(
        host: host,
        school: schoolName,
        auth: creds,
      );
      expect(lookups.statuses, {5: 'excused'});
    });
  });

  group('REST inbox', () {
    Resp token(Req r) => rpc({'token': 'jwt-1'});

    test('bearer token, merged lists, debug log', () async {
      handler = (r) => r.rpcMethod == 'getAuthToken'
          ? token(r)
          : (
              status: 200,
              body: {
                'incomingMessages': [
                  {
                    'id': 1,
                    'subject': 'Old',
                    'sentDateTime': '2026-11-01T08:00:00',
                  },
                ],
                'readConfirmationMessages': [
                  {
                    'id': 2,
                    'subject': 'New',
                    'sentDateTime': '2026-11-08T08:00:00',
                  },
                ],
              },
            );
      final items = await api.inbox(
        host: host,
        school: schoolName,
        auth: creds,
      );
      expect(items.map((m) => m.subject), ['New', 'Old']);
      final get = adapter.requests.last;
      expect(get.httpMethod, 'GET');
      expect(
        get.uri.toString(),
        'https://$host/WebUntis/api/rest/view/v1/messages',
      );
      expect(get.headers['Authorization'], 'Bearer jwt-1');
      expect(
        api.debugLog.last.method,
        allOf(contains('REST messages'), contains('HTTP 200')),
      );
      expect(api.debugLog.last.json, contains('incomingMessages'));

      // Token is cached for the detail call.
      handler = (r) => (
        status: 200,
        body: {'id': 2, 'subject': 'New', 'content': '<p>Hi</p>'},
      );
      final d = await api.inboxMessage(
        host: host,
        school: schoolName,
        auth: creds,
        id: 2,
      );
      expect(d.bodyHtml, '<p>Hi</p>');
      expect(
        adapter.requests.last.uri.path,
        '/WebUntis/api/rest/view/v1/messages/2',
      );
      expect(rpcCalls().where((m) => m == 'getAuthToken'), hasLength(1));
    });

    test('403 maps to noRight with the server message', () async {
      handler = (r) => r.rpcMethod == 'getAuthToken'
          ? token(r)
          : (
              status: 403,
              body: {'errorCode': 'FORBIDDEN', 'errorMessage': 'Not allowed'},
            );
      await expectLater(
        api.inbox(host: host, school: schoolName, auth: creds),
        throwsA(
          isA<UntisException>()
              .having((e) => e.code, 'code', UntisException.noRight)
              .having((e) => e.message, 'message', 'Not allowed'),
        ),
      );
    });

    test('404 maps to -1 (not a network error)', () async {
      handler = (r) => r.rpcMethod == 'getAuthToken'
          ? token(r)
          : (
              status: 404,
              body: {
                'errorCode': 'NOT_FOUND',
                'requestId': 'abc',
                'validationErrors': [],
              },
            );
      await expectLater(
        api.inboxMessage(host: host, school: schoolName, auth: creds, id: 5),
        throwsA(
          isA<UntisException>()
              .having((e) => e.code, 'code', -1)
              .having((e) => e.message, 'message', 'NOT_FOUND'),
        ),
      );
    });

    test('401 refreshes the token and retries once', () async {
      var tokens = 0;
      handler = (r) {
        if (r.rpcMethod == 'getAuthToken') {
          return rpc({'token': 'jwt-${++tokens}'});
        }
        return r.headers['Authorization'] == 'Bearer jwt-1'
            ? (status: 401, body: '')
            : (status: 200, body: {'incomingMessages': []});
      };
      expect(
        await api.inbox(host: host, school: schoolName, auth: creds),
        isEmpty,
      );
      expect(tokens, 2);
    });
  });
}
