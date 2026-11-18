import 'dart:convert';

import 'package:better_betteruntis/api/excuse_parsers.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/app/routing_api.dart';
import 'package:better_betteruntis/core/class_register.dart';
import 'package:better_betteruntis/core/excuses.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/data/excuse_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/classreg/excuses_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../api/absence_report_api_test.dart' show Adapter, Req, Resp, ok, rpc;
import 'class_register_test.dart' show teacherAccount;

const creds = UntisCredentials.user('teacher', 'JBSWY3DPEHPK3PXP');
const host = 'demo.webuntis.com';

const metaJson = {
  'classes': [
    {'id': 1, 'name': '9b'},
    {'id': 2, 'name': '10a'},
    {'name': 'no id'},
  ],
  'assignmentGroups': [],
  'reasons': [
    {'id': 1, 'name': 'Krankheit', 'automaticNotificationEnabled': false},
  ],
  'excuseStatuses': [
    {'id': 3, 'name': 'offen', 'type': 'OPEN'},
    {'id': 1, 'name': 'entschuldigt', 'type': 'EXCUSED'},
    {'id': 4, 'name': 'Attest', 'type': 'EXCUSED'},
    {'id': 2, 'name': 'nicht entschuldigt', 'type': 'NOT_EXCUSED'},
    {'id': 9, 'name': 'odd', 'type': 'WHATEVER'},
  ],
  'defaultExcuseStatusId': 3,
  'canEditReason': true,
};

Map<String, Object?> dto({int id = 77, bool editable = true}) => {
  'id': id,
  'duration': {'start': '2026-11-10T08:00:00Z', 'end': '2026-11-10T09:40:00Z'},
  'reason': {'id': 1, 'name': 'Krankheit'},
  'excuseStatus': {'id': 3, 'name': 'offen', 'type': 'OPEN'},
  'excuseText': '',
  'text': 'Fieber',
  'student': {'id': 501, 'name': 'Bauer Lena', 'studentOfAge': false},
  'studentOfAge': false,
  'editable': true,
  'deletable': true,
  'excuseStatusEditable': editable,
  'parentAutoNotificationStatus': 'SENT',
  'parentManualNotificationStatus': null,
};

void main() {
  final meta = parseExcuseMeta(metaJson);

  group('parsers', () {
    test('meta: classes, statuses by type, default', () {
      expect(meta.classes.map((c) => (c.id, c.name)), [(1, '9b'), (2, '10a')]);
      expect(meta.statuses.map((s) => s.id), [3, 1, 4, 2]);
      expect(meta.statusesOf(ExcuseStatusType.excused).map((s) => s.id), [
        1,
        4,
      ]);
      expect(meta.defaultExcuseStatusId, 3);
      expect(meta.reasons, {1: 'Krankheit'});
      expect(meta.rest, isTrue);
      expect(parseExcuseMeta('junk').statuses, isEmpty);
    });

    test('absence dto: local times (literal Z), status, flags', () {
      final a = parseSaaAbsences({
        'absences': [
          dto(),
          {'id': 1},
          'junk',
        ],
      }, meta).single;
      expect(a.id, 77);
      expect(a.studentId, 501);
      expect(a.studentName, 'Bauer Lena');
      expect(a.start, DateTime(2026, 11, 10, 8));
      expect(a.end, DateTime(2026, 11, 10, 9, 40));
      expect(a.reasonName, 'Krankheit');
      expect(a.text, 'Fieber');
      expect(a.type, ExcuseStatusType.open);
      expect(a.excuseStatusEditable, isTrue);
      expect(
        parseSaaAbsence(dto(editable: false), meta)!.excuseStatusEditable,
        isFalse,
      );
    });

    test('list payload', () {
      final q = ExcuseQuery(
        classId: 1,
        range: ExcuseRange.last14,
        start: DateTime(2026, 11, 4),
        end: DateTime(2026, 11, 17),
      );
      expect(saaListPayload(q), {
        'classId': 1,
        'dateRange': {
          'start': '2026-11-04T00:00:00Z',
          'end': '2026-11-17T23:59:00Z',
        },
        'dateRangeType': 'LAST_14_DAYS',
        'excuseStatusType': 'OPEN',
      });
      final all = ExcuseQuery(
        classId: 1,
        range: ExcuseRange.schoolYear,
        start: q.start,
        end: q.end,
        filter: ExcuseFilter.all,
      );
      expect(saaListPayload(all).containsKey('excuseStatusType'), isFalse);
      expect(saaListPayload(all)['dateRangeType'], 'SCHOOL_YEAR');
    });

    test('save payload copies the dto, only the excuse changes', () {
      final a = parseSaaAbsence(dto(), meta)!;
      expect(saaSavePayload(a, meta.status(1)!, ' Brief der Eltern '), {
        'saveStrategy': 'ABSENCE_WRITE',
        'itemToSave': {
          'id': 77,
          'studentId': 501,
          'duration': {
            'start': '2026-11-10T08:00:00Z',
            'end': '2026-11-10T09:40:00Z',
          },
          'reasonId': 1,
          'excuseStatusId': 1,
          'excuseText': 'Brief der Eltern',
          'text': 'Fieber',
          'studentOfAge': false,
          'parentAutoNotificationStatus': 'SENT',
          'parentManualNotificationStatus': null,
        },
      });
    });

    test('status types guessed from names (fallback)', () {
      expect(
        guessExcuseStatusType('nicht entschuldigt'),
        ExcuseStatusType.notExcused,
      );
      expect(
        guessExcuseStatusType('unentschuldigt'),
        ExcuseStatusType.notExcused,
      );
      expect(guessExcuseStatusType('entschuldigt'), ExcuseStatusType.excused);
      expect(guessExcuseStatusType('Attest'), ExcuseStatusType.excused);
      expect(guessExcuseStatusType('offen'), ExcuseStatusType.open);
      final m = excuseMetaFromLookups({1: 'entschuldigt', 2: 'offen'}, {});
      expect(m.rest, isFalse);
      expect(m.statusesOf(ExcuseStatusType.excused).single.id, 1);
    });

    test('ranges', () {
      final wed = DateTime(2026, 11, 18, 15);
      final week = ExcuseRange.week.days(wed);
      expect(week.start, DateTime(2026, 11, 16));
      expect(week.end, DateTime(2026, 11, 22));
      expect(ExcuseRange.last14.days(wed).start, DateTime(2026, 11, 5));
      expect(ExcuseRange.month.days(wed).end, DateTime(2026, 11, 30));
      final y = SchoolYear(
        id: 1,
        name: '2026/27',
        start: DateTime(2026, 9, 7),
        end: DateTime(2027, 7, 2),
      );
      expect(ExcuseRange.schoolYear.days(wed, year: y).start, y.start);
    });
  });

  group('REST requests', () {
    late Adapter adapter;
    late UntisApiImpl api;
    late Resp Function(Req r) handler;

    setUp(() {
      handler = (_) => (status: 500, body: '', headers: const {});
      adapter = Adapter((r) => handler(r));
      api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
    });

    bool isToken(Req r) => r.json?['method'] == 'getAuthToken';
    String path(Req r) => r.uri.path;
    final query = ExcuseQuery(
      classId: 1,
      range: ExcuseRange.last14,
      start: DateTime(2026, 11, 4),
      end: DateTime(2026, 11, 17),
    );

    test('meta, list and save with the bearer token', () async {
      handler = (r) {
        if (isToken(r)) return rpc({'token': 'jwt'});
        return switch ((r.method, path(r))) {
          ('GET', '/WebUntis/api/rest/view/v1/classreg/absences/meta') => ok(
            metaJson,
          ),
          ('POST', '/WebUntis/api/rest/view/v4/classreg/absences') => ok({
            'absences': [dto()],
            'dateRangeType': 'LAST_14_DAYS',
          }),
          ('PUT', '/WebUntis/api/rest/view/v3/classreg/absences') => ok({
            'modifiedAbsences': [
              {
                ...dto(),
                'excuseStatus': {
                  'id': 1,
                  'name': 'entschuldigt',
                  'type': 'EXCUSED',
                },
                'excuseText': 'ok',
              },
            ],
            'attendances': [],
            'conflicts': [],
          }),
          _ => (status: 500, body: '', headers: const {}),
        };
      };
      final m = await api.excuseMeta(host: host, school: 's', auth: creds);
      expect(m.rest, isTrue);
      expect(adapter.requests.last.headers['Authorization'], 'Bearer jwt');
      final list = await api.excuseAbsences(
        host: host,
        school: 's',
        auth: creds,
        meta: m,
        query: query,
      );
      expect(adapter.requests.last.json, saaListPayload(query));
      final saved = await api.saveExcuse(
        host: host,
        school: 's',
        auth: creds,
        meta: m,
        absence: list.single,
        status: m.status(1)!,
        text: 'ok',
      );
      final put = adapter.requests.last;
      expect(put.method, 'PUT');
      expect(put.json, saaSavePayload(list.single, m.status(1)!, 'ok'));
      expect(saved!.type, ExcuseStatusType.excused);
      expect(saved.excuseText, 'ok');
      // Request body logged, no credentials.
      final body = api.debugLog.lastWhere(
        (e) => e.method == 'REST SAA PUT absences request body',
      );
      expect(jsonDecode(body.json), put.json);
      expect(body.json, isNot(contains('JBSWY3DPEHPK3PXP')));
    });

    test('conflicts: not saved, error', () async {
      handler = (r) => isToken(r)
          ? rpc({'token': 'jwt'})
          : ok({
              'modifiedAbsences': [],
              'conflicts': [dto(id: 78)],
            });
      final a = parseSaaAbsence(dto(), meta)!;
      await expectLater(
        api.saveExcuse(
          host: host,
          school: 's',
          auth: creds,
          meta: meta,
          absence: a,
          status: meta.status(1)!,
          text: '',
        ),
        throwsA(
          isA<UntisException>().having(
            (e) => e.message,
            'message',
            contains('not saved'),
          ),
        ),
      );
    });

    test('403: only class teachers', () async {
      handler = (r) => isToken(r)
          ? rpc({'token': 'jwt'})
          : (status: 403, body: '', headers: const {});
      await expectLater(
        api.excuseAbsences(
          host: host,
          school: 's',
          auth: creds,
          meta: meta,
          query: query,
        ),
        throwsA(
          isA<UntisException>()
              .having((e) => e.code, 'code', UntisException.noRight)
              .having(
                (e) => e.message,
                'message',
                contains('Only class teachers'),
              ),
        ),
      );
    });

    test('404: master data statuses, class list, submitExcuse2017', () async {
      handler = (r) {
        final m = r.json?['method'];
        if (m == 'getAuthToken') return rpc({'token': 'jwt'});
        if (m == 'getUserData2017') {
          return rpc({
            'masterData': {
              'excuseStatuses': [
                {'id': 1, 'name': 'entschuldigt'},
                {'id': 2, 'name': 'nicht entschuldigt'},
              ],
              'absenceReasons': [],
            },
          });
        }
        if (m == 'getStudentAbsences2017') {
          return rpc({
            'absences': [
              {
                'id': 5,
                'studentId': 501,
                'startDate': 20261110,
                'startTime': 800,
                'endDate': 20261110,
                'endTime': 845,
                'isExcused': false,
              },
            ],
          });
        }
        if (m == 'submitExcuse2017') {
          return rpc({'absence': {}, 'errors': []});
        }
        return (status: 404, body: '', headers: const {});
      };
      final m = await api.excuseMeta(host: host, school: 's', auth: creds);
      expect(m.rest, isFalse);
      expect(m.statusesOf(ExcuseStatusType.notExcused).single.id, 2);
      final list = await api.excuseAbsences(
        host: host,
        school: 's',
        auth: creds,
        meta: m,
        query: query,
      );
      expect(list, isNotEmpty);
      await api.saveExcuse(
        host: host,
        school: 's',
        auth: creds,
        meta: m,
        absence: list.first,
        status: m.status(1)!,
        text: ' Attest ',
      );
      final params =
          ((adapter.requests.last.json!['params'] as List).single as Map)
              .cast<String, Object?>();
      expect(adapter.requests.last.json!['method'], 'submitExcuse2017');
      expect(params['absenceId'], list.first.id);
      expect(params['excuseStatusId'], 1);
      expect(params.containsKey('date'), isTrue);
      expect(params['date'], isNull);
      expect(params['text'], 'Attest');
    });

    test('submitExcuse2017 errors: not saved', () {
      expect(
        submitExcuseErrors({
          'errors': [
            {'code': 'X', 'message': 'locked'},
          ],
        }),
        ['locked'],
      );
      expect(submitExcuseErrors({'absence': {}}), isEmpty);
    });
  });

  group('demo and repository', () {
    late FakeUntisApi api;
    late InMemoryAccountRepository accounts;
    late ExcuseRepositoryImpl repo;

    /// The latest weekday before today: always in the last 14 days.
    DateTime lastWeekday() {
      var d = DateTime.now();
      do {
        d = DateTime(d.year, d.month, d.day - 1);
      } while (d.weekday > 5);
      return d;
    }

    setUp(() {
      api = FakeUntisApi(latency: Duration.zero);
      accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      repo = ExcuseRepositoryImpl(
        api: RoutingUntisApi(real: api, demo: api),
        accounts: accounts,
        timetables: FakeTimetableRepository(),
      );
      final day = lastWeekday();
      api.registerAbsences[FakeUntisApi.demoPeriodId(day, 0)] = [
        ClassRegAbsence(
          id: 42,
          studentId: 501,
          start: DateTime(day.year, day.month, day.day, 8),
          end: DateTime(day.year, day.month, day.day, 8, 45),
          text: 'Fieber',
        ),
      ];
    });

    test('meta, filtered list, save updates the demo', () async {
      final a = teacherAccount();
      final meta = await repo.meta(a);
      expect(meta.classes.single.name, '9b');
      final open = await repo.absences(
        a,
        classId: 1,
        range: ExcuseRange.last14,
        filter: ExcuseFilter.open,
      );
      expect(open.every((x) => x.type == ExcuseStatusType.open), isTrue);
      final mine = open.firstWhere((x) => x.id == 42);
      expect(mine.studentName, 'Bauer Lena');
      final saved = await repo.save(
        a,
        mine,
        status: meta.status(4)!,
        text: 'Attest liegt vor',
      );
      expect(saved.type, ExcuseStatusType.excused);
      expect(api.saveExcuseCalls.single, (
        absenceId: 42,
        statusId: 4,
        text: 'Attest liegt vor',
      ));
      final excused = await repo.absences(
        a,
        classId: 1,
        range: ExcuseRange.last14,
        filter: ExcuseFilter.excused,
      );
      final again = excused.firstWhere((x) => x.id == 42);
      expect(again.excuseText, 'Attest liegt vor');
      expect(again.status!.name, 'ärztliches Attest');
      expect(
        (await repo.absences(
          a,
          classId: 1,
          range: ExcuseRange.last14,
          filter: ExcuseFilter.open,
        )).any((x) => x.id == 42),
        isFalse,
      );
    });

    test('read-only absences and non-teachers are refused', () async {
      final a = teacherAccount();
      final meta = await repo.meta(a);
      final locked = ExcuseAbsence(
        id: 1,
        start: DateTime(2026),
        end: DateTime(2026),
        excuseStatusEditable: false,
      );
      await expectLater(
        repo.save(a, locked, status: meta.status(1)!, text: ''),
        throwsA(isA<UntisException>()),
      );
      expect(api.saveExcuseCalls, isEmpty);
      await expectLater(
        repo.meta(demoAccount()),
        throwsA(isA<UntisException>()),
      );
    });

    Widget app() => ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(accounts),
        activeAccountProvider.overrideWith(
          (ref) => Stream.value(teacherAccount()),
        ),
        excuseRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: ExcusesScreen()),
    );

    testWidgets('excuse an absence: quick button, chooser, text, save', (
      t,
    ) async {
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      final tile = find.byKey(const ValueKey('excuse-42'));
      await t.scrollUntilVisible(tile, 200);
      expect(
        find.descendant(of: tile, matching: find.text('offen')),
        findsOneWidget,
      );
      await t.tap(tile);
      await t.pumpAndSettle();

      // Two EXCUSED statuses: the quick button asks which.
      await t.tap(find.byKey(const ValueKey('excuse-quick-excused')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('excuse-choose-1')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('excuse-text')),
        'Entschuldigung der Eltern',
      );
      await t.tap(find.byKey(const ValueKey('excuse-save')));
      await t.pumpAndSettle();

      expect(api.saveExcuseCalls.single, (
        absenceId: 42,
        statusId: 1,
        text: 'Entschuldigung der Eltern',
      ));
      // Filter "Open": the excused absence leaves the list.
      expect(find.byKey(const ValueKey('excuse-42')), findsNothing);
      expect(find.textContaining('Saved: Bauer Lena'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('excuses-filter-excused')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(tile, 200);
      expect(
        find.descendant(of: tile, matching: find.text('entschuldigt')),
        findsOneWidget,
      );
    });

    testWidgets('a refused save stays in the sheet with the error', (t) async {
      api.excuseSaveError = const UntisException(
        UntisException.noRight,
        'Only class teachers may excuse absences of this class (HTTP 403).',
      );
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      final tile = find.byKey(const ValueKey('excuse-42'));
      await t.scrollUntilVisible(tile, 200);
      await t.tap(tile);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('excuse-quick-notExcused')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('excuse-save')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('excuse-error')), findsOneWidget);
      expect(find.textContaining('Only class teachers'), findsOneWidget);
      expect(find.byKey(const ValueKey('excuse-save')), findsOneWidget);
    });
  });
}
