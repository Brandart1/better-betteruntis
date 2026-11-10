import 'dart:convert';
import 'dart:typed_data';

import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves JSON-RPC (getTimetable2017 without teachers, getAuthToken) and the
/// REST entries endpoint, which only accepts [validFormat] for STANDARD.
class _Server implements HttpClientAdapter {
  _Server({this.validFormat});
  final int? validFormat;
  final restCalls = <Uri>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    if (o.method == 'GET') {
      restCalls.add(o.uri);
      final f = int.parse(o.uri.queryParameters['format']!);
      if (f != validFormat) {
        return _json({
          'errorCode': 'NOT_FOUND',
          'validationErrors': [
            {'path': '', 'errorMessage': 'Timetable format not found'},
          ],
        }, 404);
      }
      return _json({
        'format': f,
        'days': [
          {
            'date': '2026-11-16',
            'gridEntries': [
              {
                'ids': [7],
                'duration': {'start': '2026-11-16T07:55', 'end': '2026-11-16T08:45'},
                'position2': [
                  {
                    'current': {'type': 'TEACHER', 'shortName': 'ABC', 'longName': 'Alpha Beta'},
                    'removed': null,
                  },
                ],
              },
            ],
          },
        ],
      }, 200);
    }
    final bytes = <int>[];
    await for (final c in body!) {
      bytes.addAll(c);
    }
    final method = (jsonDecode(utf8.decode(bytes)) as Map)['method'];
    final result = switch (method) {
      'getAuthToken' => {'token': 'jwt'},
      _ => {
        'timetable': {
          'periods': [
            {
              'id': 7,
              'lessonId': 1,
              'startDateTime': '2026-11-16T07:55',
              'endDateTime': '2026-11-16T08:45',
              'elements': [
                {'type': 'CLASS', 'id': 1, 'orgId': 1},
                {'type': 'ROOM', 'id': 2, 'orgId': 2},
              ],
              'is': ['REGULAR'],
            },
          ],
        },
      },
    };
    return _json({'jsonrpc': '2.0', 'id': '1', 'result': result}, 200);
  }

  ResponseBody _json(Object body, int status) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {Headers.contentTypeHeader: ['application/json']},
  );

  @override
  void close({bool force = false}) {}
}

Future<TimetableResponse> _classWeek(UntisApiImpl api, int classId) => api.timetable(
  host: 'x.webuntis.com',
  school: 's',
  auth: const UntisCredentials.user('u', 'GEZDGNBVGY3TQOJQ'),
  target: TimetableTarget(ElementType.klasse, classId),
  start: DateTime(2026, 11, 16),
  end: DateTime(2026, 11, 22),
  masterDataTimestamp: 0,
);

void main() {
  test('finds the working format once and reuses it', () async {
    final server = _Server(validFormat: 3);
    final api = UntisApiImpl(dio: Dio()..httpClientAdapter = server);

    final first = await _classWeek(api, 1);
    expect(first.periods.single.ofType(ElementType.teacher).single.inlineName, 'ABC');
    expect(server.restCalls.map((u) => u.queryParameters['format']), ['1', '2', '3']);

    server.restCalls.clear();
    await _classWeek(api, 2);
    expect(server.restCalls.map((u) => u.queryParameters['format']), ['3']);
    expect(server.restCalls.single.queryParameters['timetableType'], 'STANDARD');
  });

  test('concurrent requests share one discovery', () async {
    final server = _Server(validFormat: 2);
    final api = UntisApiImpl(dio: Dio()..httpClientAdapter = server);
    await Future.wait([for (var c = 1; c <= 3; c++) _classWeek(api, c)]);
    // Discovery: formats 1,2 (one request answers class 1); others: 1 each.
    expect(server.restCalls.where((u) => u.queryParameters['format'] == '1'), hasLength(1));
    expect(server.restCalls, hasLength(4));
  });

  test('no working format: timetable still loads, REST skipped afterwards', () async {
    final server = _Server(validFormat: null);
    final api = UntisApiImpl(dio: Dio()..httpClientAdapter = server);
    final res = await _classWeek(api, 1);
    expect(res.periods, hasLength(1));
    expect(res.periods.single.ofType(ElementType.teacher), isEmpty);
    final tried = server.restCalls.length;
    expect(tried, UntisApiImpl.formatCandidates('STANDARD').length);

    await _classWeek(api, 2);
    expect(server.restCalls.length, tried);
  });

  test('MY_TIMETABLE tries 4 first', () {
    expect(UntisApiImpl.formatCandidates('MY_TIMETABLE').first, 4);
    expect(UntisApiImpl.formatCandidates('STANDARD').first, 1);
  });
}
