import 'dart:convert';

import 'package:better_betteruntis/api/json_rpc.dart';
import 'package:better_betteruntis/api/parsers.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'info_center_api_test.dart' show Adapter, Req, Resp, rpc;

const _creds = UntisCredentials.user('max', 'JBSWY3DPEHPK3PXP');

Resp _err(int code, String msg) => (
  status: 200,
  body: {
    'id': '1',
    'jsonrpc': '2.0',
    'error': {'code': code, 'message': msg},
  },
);

void main() {
  group('parseLoginResult: parent accounts', () {
    test('children with id/displayName/klasseId; unknown own element', () {
      final r = parseLoginResult({
        'userData': {
          'elemType': 'LEGAL_GUARDIAN',
          'elemId': 900,
          'displayName': 'Parent Example',
          'klassenIds': <int>[],
          'children': [
            {'id': 11, 'displayName': 'Child A', 'klasseId': 3},
            {'id': '12', 'longName': 'Child B', 'klassenIds': [4, 5]},
            {'studentId': 13, 'firstName': 'Child', 'lastName': 'C'},
            {'name': 'no id'},
            {'id': 11, 'displayName': 'duplicate'},
          ],
        },
        'masterData': {'timeStamp': 1},
      }, secret: 's');
      expect(r.elementType, ElementType.unknown);
      expect(r.children.map((c) => (c.id, c.displayName, c.klasseId)), [
        (11, 'Child A', 3),
        (12, 'Child B', 4),
        (13, 'Child C', null),
      ]);
      expect(r.children.every((c) => c.type == ElementType.student), isTrue);
    });

    test('students: no children; junk children are ignored', () {
      final r = parseLoginResult({
        'userData': {'elemType': 'STUDENT', 'elemId': 7, 'children': 'x'},
      }, secret: 's');
      expect(r.children, isEmpty);
      expect(parseChildren(null), isEmpty);
      expect(parseChildren([1, 'a', null]), isEmpty);
    });

    test('a child type is kept when it is a timetable type', () {
      final c = parseChildren([
        {'id': 1, 'type': 'STUDENT'},
        {'id': 2, 'type': 'LEGAL_GUARDIAN'},
        {'id': 3, 'klasse': {'id': 9}},
      ]);
      expect(c.map((e) => e.type), everyElement(ElementType.student));
      expect(c[0].displayName, '#1');
      expect(c[2].klasseId, 9);
    });
  });

  group('parseOfficeHourItems variants', () {
    test('top-level list, int date + hhmm ints, teacher map, room list', () {
      final items = parseOfficeHourItems([
        {
          'id': 1,
          'date': 20261111,
          'startTime': 1345,
          'endTime': 1430,
          'teacher': {'displayName': 'Teacher One'},
          'rooms': ['R1', {'name': 'R2'}],
        },
      ]);
      final o = items.single;
      expect(o.start, DateTime(2026, 11, 11, 13, 45));
      expect(o.end, DateTime(2026, 11, 11, 14, 30));
      expect(o.teacherName, 'Teacher One');
      expect(o.rooms, 'R1, R2');
    });

    test('startDateTime strings and teacherName / displayNameRooms', () {
      final items = parseOfficeHourItems({
        'officeHours': [
          {
            'id': 2,
            'startDateTime': '2026-11-12T08:00',
            'endDateTime': '2026-11-12T08:45',
            'teacherName': 'Teacher Two',
            'displayNameRooms': 'A 1',
          },
        ],
      });
      expect(items.single.start, DateTime(2026, 11, 12, 8));
      expect(items.single.end, DateTime(2026, 11, 12, 8, 45));
      expect(items.single.teacherName, 'Teacher Two');
      expect(items.single.rooms, 'A 1');
    });

    test('string date and "1345"/"T14:30" times; garbage is skipped', () {
      final items = parseOfficeHourItems({
        'officeHours': [
          {
            'startDate': '20261113',
            'startTime': '1345',
            'endTime': 'T14:30',
            'displayNameTeacher': 'Teacher Three',
          },
          {'teacherName': 'no date'},
          'junk',
        ],
      });
      expect(items.single.start, DateTime(2026, 11, 13, 13, 45));
      expect(items.single.end, DateTime(2026, 11, 13, 14, 30));
    });

    test('epoch milliseconds', () {
      final s = DateTime(2026, 11, 14, 9);
      final items = parseOfficeHourItems({
        'officeHours': [
          {
            'startDateTime': s.millisecondsSinceEpoch,
            'endDateTime': s
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
          },
        ],
      });
      expect(items.single.start, s);
    });
  });

  group('API', () {
    late Adapter adapter;
    late UntisApiImpl api;
    late Resp Function(Req r) handler;

    setUp(() {
      handler = (_) => rpc(<String, Object?>{});
      adapter = Adapter((r) => handler(r));
      api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
    });

    test('timetable with an unknown type fails without a request', () async {
      await expectLater(
        api.timetable(
          host: 'h',
          school: 's',
          auth: _creds,
          target: const TimetableTarget(ElementType.unknown, 5),
          start: DateTime(2026, 11, 9),
          end: DateTime(2026, 11, 15),
          masterDataTimestamp: 0,
        ),
        throwsA(isA<UntisException>().having((e) => e.isNetwork, 'net', false)),
      );
      expect(adapter.requests, isEmpty);
    });

    test('absences: students send no studentId', () async {
      handler = (_) => rpc({'absences': <Object>[]});
      await api.rawAbsences(
        host: 'h',
        school: 's',
        auth: _creds,
        start: DateTime(2026, 9),
        end: DateTime(2026, 11),
      );
      expect(adapter.requests.single.params!.containsKey('studentId'), isFalse);
    });

    test('absences: parents send studentId, retry without on error', () async {
      handler = (r) => r.params!.containsKey('studentId')
          ? _err(-32602, 'bad params')
          : rpc({'absences': <Object>[]});
      final res = await api.rawAbsences(
        host: 'h',
        school: 's',
        auth: _creds,
        start: DateTime(2026, 9),
        end: DateTime(2026, 11),
        studentId: 11,
      );
      expect(res, isEmpty);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.first.params!['studentId'], 11);
      expect(adapter.requests.last.params!.containsKey('studentId'), isFalse);
    });

    test('login parses children; debug log keeps userData and hides secret', () async {
      handler = (r) => switch (r.rpcMethod) {
        'getAppSharedSecret' => rpc('TOPSECRETVALUE'),
        _ => rpc({
          'userData': {
            'elemType': 'LEGAL_GUARDIAN',
            'elemId': 1,
            'children': [
              {'id': 11, 'displayName': 'Child A'},
            ],
          },
          'masterData': {
            'timeStamp': 1,
            'teachers': [
              {'id': 1, 'name': 'T'},
            ],
          },
          'messengerSettings': {'serverUrl': 'x', 'token': 'MSGTOKEN'},
        }),
      };
      final r = await api.login(
        school: const School(
          schoolId: 1,
          loginName: 's',
          displayName: 'S',
          address: '',
          host: 'h',
        ),
        username: 'parent',
        passwordOrKey: 'pw',
      );
      expect(r.children.single.id, 11);
      final log = api.debugLog;
      final all = log.map((e) => e.json).join('\n');
      expect(all, isNot(contains('TOPSECRETVALUE')));
      expect(all, isNot(contains('MSGTOKEN')));
      expect(all, isNot(contains('pw')));
      final summary = log.firstWhere(
        (e) => e.method.contains('userData only'),
      );
      final j = jsonDecode(summary.json) as Map;
      expect(j['result']['userData']['children'], hasLength(1));
      expect(j['result']['masterData']['teachers'], '<1 entries>');

      // Pinned: 40 more calls don't push the login response out.
      handler = (_) => rpc({'messages': <Object>[]});
      for (var i = 0; i < 40; i++) {
        await api.messagesOfDay(
          host: 'h',
          school: 's',
          auth: _creds,
          date: DateTime(2026),
        );
      }
      expect(
        api.debugLog.where((e) => e.method.startsWith('getUserData2017')),
        hasLength(2),
      );
    });

    test('office hours: label shows klasseId and each klasse is kept', () async {
      handler = (_) => rpc({'officeHours': <Object>[]});
      for (final k in [3, -1]) {
        await api.officeHours(
          host: 'h',
          school: 's',
          auth: _creds,
          klasseId: k,
          start: DateTime(2026, 11, 9),
        );
      }
      final labels = api.debugLog.map((e) => e.method).toList();
      expect(labels, [
        'getOfficeHours2017 klasseId=3 2026-11-09 [HTTP 200]',
        'getOfficeHours2017 klasseId=-1 2026-11-09 [HTTP 200]',
      ]);
    });
  });

  test('redactResult keeps errors and the shape only', () {
    expect(
      JsonRpcClient.redactResult('{"result":"abc"}'),
      '{"result":"<redacted string, 3 chars>"}',
    );
    expect(
      JsonRpcClient.redactResult('{"error":{"code":-8504}}'),
      '{"error":{"code":-8504}}',
    );
  });
}
