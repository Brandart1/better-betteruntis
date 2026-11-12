import 'package:better_betteruntis/api/class_register_parsers.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../api/absence_report_api_test.dart' show Adapter, rpc;

const creds = UntisCredentials.user('teacher', 'JBSWY3DPEHPK3PXP');

void main() {
  group('parsers', () {
    test('period data: registers by ttId and students, tolerant', () {
      final d = parsePeriodData({
        'dataByTTId': {
          '101': {
            'ttId': 101,
            'absenceChecked': true,
            'studentIds': [1, 2, '3', null],
            'absences': [
              {
                'id': 7,
                'studentId': 2,
                'startDateTime': '2026-11-10T08:00',
                'endDateTime': '2026-11-10T08:45',
                'absenceReasonId': 4,
                'excused': true,
              },
              {'id': 8},
              'junk',
            ],
            'topic': {'text': 'Fractions'},
          },
          '102': {'topic': 'Plain string'},
          'x': {},
          '103': 'junk',
        },
        'referencedStudents': [
          {'id': 1, 'firstName': 'Lena', 'lastName': 'Bauer', 'klasseId': 5},
          {'id': 2, 'displayName': 'Jonas F.'},
          {'id': 3},
          {'firstName': 'no id'},
        ],
      });
      expect(d.periods.keys, unorderedEquals([101, 102]));
      final r = d.periods[101]!;
      expect(r.absenceChecked, isTrue);
      expect(r.studentIds, [1, 2, 3]);
      expect(r.absences.single.id, 7);
      expect(r.absences.single.excused, isTrue);
      expect(r.absences.single.reasonId, 4);
      expect(r.topic, 'Fractions');
      expect(r.isIncomplete, isFalse);
      expect(d.periods[102]!.topic, 'Plain string');
      expect(d.periods[102]!.isIncomplete, isTrue);
      expect(d.students[1]!.displayName, 'Bauer Lena');
      expect(d.students[1]!.klasseId, 5);
      expect(d.students[2]!.displayName, 'Jonas F.');
      expect(d.students[3]!.displayName, '#3');
      expect(d.students.length, 3);
    });

    test('garbage gives empty data', () {
      expect(parsePeriodData(null).periods, isEmpty);
      expect(parsePeriodData('x').students, isEmpty);
    });

    test('time format', () {
      expect(formatUntisTime(DateTime(2026, 1, 1, 8, 5)), 'T08:05');
    });
  });

  group('requests', () {
    late Adapter adapter;
    late UntisApiImpl api;
    setUp(() {
      adapter = Adapter((r) => rpc({'dataByTTId': {}}));
      api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
    });

    Map<String, Object?> params() =>
        ((adapter.requests.last.json!['params'] as List).single as Map)
            .cast<String, Object?>();
    String method() => adapter.requests.last.json!['method'] as String;

    test('methods and params', () async {
      await api.periodData(host: 'h', school: 's', auth: creds, ttIds: [1, 2]);
      expect(method(), 'getPeriodData2017');
      expect(params()['ttIds'], [1, 2]);
      expect(params()['auth'], isA<Map>());

      await api.submitLessonTopic(
        host: 'h',
        school: 's',
        auth: creds,
        ttId: 5,
        topic: 'Topic',
      );
      expect(method(), 'submitLessonTopic');
      expect(params()['lessonTopic'], 'Topic');
      expect(params()['ttId'], 5);

      await api.createAbsence(
        host: 'h',
        school: 's',
        auth: creds,
        ttId: 5,
        studentId: 9,
        start: DateTime(2026, 11, 10, 8),
        end: DateTime(2026, 11, 10, 8, 45),
      );
      expect(method(), 'createImmediateAbsence2017');
      expect(params()['periodId'], 5);
      expect(params()['studentId'], 9);
      expect(params()['startTime'], 'T08:00');
      expect(params()['endTime'], 'T08:45');

      await api.deleteAbsence(
        host: 'h',
        school: 's',
        auth: creds,
        absenceId: 3,
      );
      expect(method(), 'deleteAbsence2017');
      expect(params()['absenceId'], 3);

      await api.submitAbsencesChecked(
        host: 'h',
        school: 's',
        auth: creds,
        ttIds: [5, 6],
      );
      expect(method(), 'submitAbsencesChecked2017');
      expect(params()['ttIds'], [5, 6]);
    });

    test('empty id lists send nothing', () async {
      await api.periodData(host: 'h', school: 's', auth: creds, ttIds: []);
      await api.submitAbsencesChecked(
        host: 'h',
        school: 's',
        auth: creds,
        ttIds: [],
      );
      expect(adapter.requests, isEmpty);
    });

    test('write request bodies are logged without auth', () async {
      await api.submitLessonTopic(
        host: 'h',
        school: 's',
        auth: creds,
        ttId: 5,
        topic: 'T',
      );
      final entry = api.debugLog.firstWhere(
        (e) => e.method == 'submitLessonTopic request body',
      );
      expect(entry.json, contains('"ttId":5'));
      expect(entry.json, isNot(contains('otp')));
    });
  });
}
