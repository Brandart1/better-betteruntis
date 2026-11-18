import 'dart:convert';

import 'package:better_betteruntis/api/substitution_parsers.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/app/routing_api.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/substitution_planning.dart';
import 'package:better_betteruntis/data/substitution_planning_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/classreg/substitution_requests_screen.dart';
import 'package:better_betteruntis/ui/classreg/teacher_absences_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../api/absence_report_api_test.dart' show Adapter, Req, Resp, ok, rpc;
import 'class_register_test.dart' show teacherAccount;

const creds = UntisCredentials.user('teacher', 'JBSWY3DPEHPK3PXP');
const host = 'demo.webuntis.com';

Map<String, Object?> requestDto({
  int? conflictId = 555,
  String state = 'PENDING',
}) => {
  'period': {
    'wuId': 123456,
    'startDateTime': '2026-11-18T09:50:00Z',
    'endDateTime': '2026-11-18T10:35:00Z',
    'unitOfDay': 3,
    'isCanceled': false,
    'periodType': 'NORMAL_TEACHING_PERIOD',
    'subject': {'displayName': 'E'},
    'klassen': [
      {
        'klasse': {'displayName': '9b'},
        'hasOpenConflicts': true,
      },
    ],
    'rooms': [
      {
        'currentRoom': {'id': 31, 'displayName': 'R102'},
      },
    ],
    'teachers': [
      {
        'currentTeacher': null,
        'removedTeacher': {'id': 13, 'displayName': 'WEB'},
        'conflictState': 'ASK_TEACHER',
      },
    ],
  },
  'periodConflict': conflictId == null
      ? null
      : {
          'id': conflictId,
          'startDateTime': '2026-11-18T09:50:00Z',
          'endDateTime': '2026-11-18T10:35:00Z',
          'unitOfDay': 3,
          'subject': {'displayName': 'Englisch'},
          'klassen': [
            {'displayName': '9b'},
          ],
          'rooms': [
            {'displayName': 'R102'},
          ],
          'originalTeacher': {'id': 13, 'displayName': 'Weber'},
          'askTeacherStats': {'asked': 3, 'declined': 1},
        },
  'state': state,
};

const absencesJson = {
  'groups': [
    {
      'group': {
        'absence': {
          'wuAbsenceId': 8801,
          'teacher': {'id': 11, 'displayName': 'MUE'},
          'reason': {'id': 2, 'displayName': 'Fortbildung'},
          'startDateTime': '2026-11-10T07:00:00Z',
          'endDateTime': '2026-11-10T19:00:00Z',
          'note': 'Blätter im Fach',
          'missedPeriods': 2,
        },
      },
      'periods': [
        {
          'startDateTime': '2026-11-10T08:55:00Z',
          'endDateTime': '2026-11-10T09:40:00Z',
          'subject': {'displayName': 'PH'},
          'klassen': [
            {
              'klasse': {'displayName': '9b'},
            },
          ],
          'teachers': [
            {
              'currentTeacher': {'id': 12, 'displayName': 'SCH'},
              'removedTeacher': {'id': 11, 'displayName': 'MUE'},
              'conflictState': 'SUBSTITUTION',
            },
          ],
        },
        {
          'startDateTime': '2026-11-10T08:00:00Z',
          'endDateTime': '2026-11-10T08:45:00Z',
          'subject': {'displayName': 'M'},
          'teachers': [
            {
              'currentTeacher': null,
              'removedTeacher': {'id': 11, 'displayName': 'MUE'},
              'conflictState': 'OPEN_CONFLICT',
            },
          ],
        },
      ],
    },
    {
      'group': {
        'overbooking': {'id': 1},
      },
      'periods': [],
    },
  ],
};

/// Records the weeks refreshed.
class _Timetables extends FakeTimetableRepository {
  final weeks = <DateTime>[];

  @override
  Future<void> refresh(
    Account account,
    TimetableTarget target,
    DateTime weekStart,
  ) {
    weeks.add(weekStart);
    return super.refresh(account, target, weekStart);
  }
}

void main() {
  group('parsers', () {
    test('request: conflict id, names from both shapes, state', () {
      final r = parseSubstitutionRequest(requestDto())!;
      expect(r.id, 555);
      expect(r.periodId, 123456);
      expect(r.start, DateTime(2026, 11, 18, 9, 50));
      expect(r.end, DateTime(2026, 11, 18, 10, 35));
      expect(r.unitOfDay, 3);
      expect(r.subject, 'Englisch');
      expect(r.classes, ['9b']);
      expect(r.rooms, ['R102']);
      expect(r.absentTeacher, 'Weber');
      expect(r.isPending, isTrue);

      // No conflict: the period's wuId and names.
      final p = parseSubstitutionRequest(
        requestDto(conflictId: null, state: 'TAKEN'),
      )!;
      expect(p.id, 123456);
      expect(p.subject, 'E');
      expect(p.classes, ['9b']);
      expect(p.rooms, ['R102']);
      expect(p.absentTeacher, 'WEB');
      expect(p.state, SubstitutionRequestState.taken);

      expect(
        parseSubstitutionRequests({
          'substitutionRequests': [requestDto(), 'junk', <String, Object?>{}],
        }),
        hasLength(1),
      );
      expect(parseSubstitutionRequests(null), isEmpty);
      expect(
        SubstitutionRequestState.parse('DECLINE'),
        SubstitutionRequestState.declined,
      );
      expect(
        SubstitutionRequestState.parse('NEW'),
        SubstitutionRequestState.unknown,
      );
    });

    test('date-times: Z dropped (local), offsets converted', () {
      expect(
        parseSpDateTime('2026-11-18T09:50:00Z'),
        DateTime(2026, 11, 18, 9, 50),
      );
      expect(
        parseSpDateTime('2026-11-18T09:50:00'),
        DateTime(2026, 11, 18, 9, 50),
      );
      expect(
        parseSpDateTime('2026-11-18T09:50:00+01:00'),
        DateTime.utc(2026, 11, 18, 8, 50).toLocal(),
      );
      expect(parseSpDateTime(''), isNull);
      expect(parseSpDateTime(5), isNull);
    });

    test('own absences: only absence groups, lessons sorted', () {
      final a = parseTeacherAbsences(absencesJson).single;
      expect(a.id, 8801);
      expect(a.start, DateTime(2026, 11, 10, 7));
      expect(a.end, DateTime(2026, 11, 10, 19));
      expect(a.reason, 'Fortbildung');
      expect(a.note, 'Blätter im Fach');
      expect(a.missedPeriods, 2);
      expect(a.lessons.map((l) => l.subject), ['M', 'PH']);
      expect(a.lessons.first.substitute, '');
      expect(a.lessons.first.state, 'OPEN_CONFLICT');
      expect(a.lessons.last.substitute, 'SCH');
      expect(a.lessons.last.classes, ['9b']);
    });

    test('form and create payload', () {
      final f = parseTeacherAbsenceForm({
        'startDateTime': '2026-11-17T07:00:00Z',
        'endDateTime': '2026-11-17T19:00:00Z',
        'reasons': [
          {'id': 1, 'displayName': 'Krankheit'},
          {'displayName': 'no id'},
        ],
        'teachers': [
          {'id': 11, 'displayName': 'MUE'},
        ],
      });
      expect(f.reasons.map((r) => (r.id, r.name)), [(1, 'Krankheit')]);
      expect(f.start, DateTime(2026, 11, 17, 7));
      expect(f.end, DateTime(2026, 11, 17, 19));

      final draft = TeacherAbsenceDraft(
        teacherId: 11,
        start: DateTime(2026, 11, 18, 7, 5),
        end: DateTime(2026, 11, 19, 19),
        reasonId: 1,
        note: ' Blätter im Fach ',
      );
      expect(teacherAbsencePayload(draft), {
        'id': 0,
        'teacherId': 11,
        'startDateTime': '2026-11-18T07:05:00',
        'endDateTime': '2026-11-19T19:00:00',
        'reasonId': 1,
        'note': 'Blätter im Fach',
      });
      final noReason = teacherAbsencePayload(
        TeacherAbsenceDraft(teacherId: 11, start: draft.start, end: draft.end),
      );
      expect(noReason.containsKey('reasonId'), isFalse);
      expect(noReason['note'], '');
      expect(createdTeacherAbsenceId({'id': 77}), 77);
      expect(createdTeacherAbsenceId({'id': 0}), isNull);
      expect(createdTeacherAbsenceId(null), isNull);
    });

    test('tenant id is URL-encoded like Java URLEncoder', () {
      expect(substitutionTenantId('gym musterstadt'), 'gym+musterstadt');
      expect(substitutionTenantId('Schule-Ä/1'), 'Schule-%C3%84%2F1');
    });
  });

  group('requests', () {
    late Adapter adapter;
    late UntisApiImpl api;
    late Resp Function(Req r) handler;

    setUp(() {
      handler = (_) => (status: 500, body: '', headers: const {});
      adapter = Adapter((r) => handler(r));
      api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
    });

    bool isToken(Req r) => r.json?['method'] == 'getAuthToken';
    final request = parseSubstitutionRequest(requestDto())!;

    test(
      'substitution host: bearer token, X-TenantID, no school query',
      () async {
        handler = (r) {
          if (isToken(r)) return rpc({'token': 'jwt'});
          return switch ((r.method, r.uri.host, r.uri.path)) {
            (
              'GET',
              'substitution.webuntis.com',
              '/api/v2/view/ask-teacher-requests-view',
            ) =>
              ok({
                'substitutionRequests': [requestDto()],
              }),
            (
              'POST',
              'substitution.webuntis.com',
              '/api/v2/periods/555/changes/ask-teacher/teacher/accept' ||
                  '/api/v2/periods/555/changes/ask-teacher/teacher/decline',
            ) =>
              (status: 204, body: '', headers: const {}),
            (
              'GET',
              'substitution.webuntis.com',
              '/api/v2/view/teacher-absences',
            ) =>
              ok(absencesJson),
            _ => (status: 500, body: '', headers: const {}),
          };
        };
        final list = await api.substitutionRequests(
          host: host,
          school: 'gym musterstadt',
          auth: creds,
        );
        expect(list.single.id, 555);
        final get = adapter.requests.last;
        expect(get.headers['Authorization'], 'Bearer jwt');
        expect(get.headers['X-TenantID'], 'gym+musterstadt');
        expect(get.uri.query, isEmpty);

        await api.answerSubstitutionRequest(
          host: host,
          school: 'gym musterstadt',
          auth: creds,
          request: request,
          accept: true,
        );
        final accept = adapter.requests.last;
        expect(accept.method, 'POST');
        expect(accept.uri.path, endsWith('/teacher/accept'));
        expect(accept.json, isNull);
        expect(accept.headers['X-TenantID'], 'gym+musterstadt');

        await api.answerSubstitutionRequest(
          host: host,
          school: 'gym musterstadt',
          auth: creds,
          request: request,
          accept: false,
        );
        expect(adapter.requests.last.uri.path, endsWith('/teacher/decline'));

        final absences = await api.teacherAbsences(
          host: host,
          school: 'gym musterstadt',
          auth: creds,
        );
        expect(absences.single.id, 8801);
        expect(adapter.requests.last.headers['X-TenantID'], 'gym+musterstadt');
      },
    );

    test('404 on the substitution host: no online planning', () async {
      handler = (r) => isToken(r)
          ? rpc({'token': 'jwt'})
          : (status: 404, body: '', headers: const {});
      await expectLater(
        api.substitutionRequests(host: host, school: 's', auth: creds),
        throwsA(
          isA<UntisException>()
              .having(
                (e) => e.code,
                'code',
                UntisApiImpl.substitutionPlanningMissing,
              )
              .having(
                (e) => e.message,
                'message',
                contains("doesn't use online substitution planning"),
              ),
        ),
      );
    });

    test('403 with the server message', () async {
      handler = (r) => isToken(r)
          ? rpc({'token': 'jwt'})
          : (
              status: 403,
              body: {'errorMessage': 'Request already taken'},
              headers: const {},
            );
      await expectLater(
        api.answerSubstitutionRequest(
          host: host,
          school: 's',
          auth: creds,
          request: request,
          accept: true,
        ),
        throwsA(
          isA<UntisException>()
              .having((e) => e.code, 'code', UntisException.noRight)
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains('could not be accepted'),
                  contains('Request already taken'),
                ),
              ),
        ),
      );
    });

    test('home cells decide availability (REST, ?school=)', () async {
      var status = 200;
      handler = (r) {
        if (isToken(r)) return rpc({'token': 'jwt'});
        if (r.uri.path == '/WebUntis/api/rest/view/v2/home') {
          return status == 200
              ? ok({
                  'schoolName': 'x',
                  'sections': [
                    {
                      'cells': [
                        {'type': 'MY_EVENTS'},
                        {'type': 'TEACHER_ABSENCES', 'badge': null},
                      ],
                    },
                    {
                      'cells': [
                        {'type': 'FUTURE_THING'},
                      ],
                    },
                  ],
                })
              : (status: status, body: '', headers: const {});
        }
        return (status: 500, body: '', headers: const {});
      };
      final a = await api.homeAvailability(
        host: host,
        school: 's s',
        auth: creds,
      );
      expect(a.teacherAbsences, isTrue);
      expect(a.substitutionRequests, isFalse);
      final req = adapter.requests.last;
      expect(req.uri.queryParameters['school'], 's s');
      expect(req.headers.containsKey('X-TenantID'), isFalse);
      status = 404;
      await expectLater(
        api.homeAvailability(host: host, school: 's', auth: creds),
        throwsA(isA<UntisException>()),
      );
    });

    test('absence form and create go to WebUntis REST', () async {
      handler = (r) {
        if (isToken(r)) return rpc({'token': 'jwt'});
        return switch ((r.method, r.uri.host, r.uri.path)) {
          ('GET', host, '/WebUntis/api/rest/view/v1/teacher-absences/form') =>
            ok({
              'reasons': [
                {'id': 1, 'displayName': 'Krankheit'},
              ],
            }),
          ('POST', host, '/WebUntis/api/rest/view/v1/teacher-absences') => ok({
            'id': 4711,
            'teacherId': 11,
          }),
          _ => (status: 500, body: '', headers: const {}),
        };
      };
      final form = await api.teacherAbsenceForm(
        host: host,
        school: 's',
        auth: creds,
      );
      expect(form.reasons.single.name, 'Krankheit');
      expect(adapter.requests.last.uri.queryParameters['school'], 's');
      expect(adapter.requests.last.headers.containsKey('X-TenantID'), isFalse);
      final draft = TeacherAbsenceDraft(
        teacherId: 11,
        start: DateTime(2026, 11, 18, 7),
        end: DateTime(2026, 11, 18, 19),
        reasonId: 1,
        note: 'Blätter im Fach',
      );
      final id = await api.createTeacherAbsence(
        host: host,
        school: 's',
        auth: creds,
        draft: draft,
      );
      expect(id, 4711);
      expect(adapter.requests.last.uri.queryParameters['school'], 's');
      final post = adapter.requests.last;
      expect(post.headers['Authorization'], 'Bearer jwt');
      expect(post.json, teacherAbsencePayload(draft));
      final logged = api.debugLog.lastWhere(
        (e) => e.method == 'REST POST teacher-absences request body',
      );
      expect(jsonDecode(logged.json), post.json);
      expect(logged.json, isNot(contains('JBSWY3DPEHPK3PXP')));
      expect(logged.json, isNot(contains('jwt')));
    });

    test('404 on the absence form: explained', () async {
      handler = (r) => isToken(r)
          ? rpc({'token': 'jwt'})
          : (status: 404, body: '', headers: const {});
      await expectLater(
        api.teacherAbsenceForm(host: host, school: 's', auth: creds),
        throwsA(
          isA<UntisException>().having(
            (e) => e.message,
            'message',
            contains('no teacher absence reporting'),
          ),
        ),
      );
    });
  });

  group('demo and repository', () {
    late FakeUntisApi api;
    late InMemoryAccountRepository accounts;
    late _Timetables timetables;
    late SubstitutionPlanningRepositoryImpl repo;

    setUp(() {
      api = FakeUntisApi(latency: Duration.zero);
      accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      timetables = _Timetables();
      repo = SubstitutionPlanningRepositoryImpl(
        api: RoutingUntisApi(real: api, demo: api),
        accounts: accounts,
        timetables: timetables,
      );
    });

    DateTime monday(DateTime d) =>
        DateTime(d.year, d.month, d.day - (d.weekday - 1));

    test('requests: open first; accept refreshes the week', () async {
      final a = teacherAccount();
      final list = await repo.requests(a);
      expect(list.map((r) => r.id), [9101, 9102, 9100]);
      final first = list.first;
      final updated = await repo.answer(a, first, accept: true);
      expect(updated.state, SubstitutionRequestState.accepted);
      expect(api.substitutionAnswerCalls.single, (id: 9101, accept: true));
      expect(timetables.weeks, [monday(first.start)]);

      await repo.answer(a, list[1], accept: false);
      expect(api.substitutionAnswerCalls.last, (id: 9102, accept: false));
      // Declining refreshes nothing.
      expect(timetables.weeks, hasLength(1));
      // Answered requests can't be answered again.
      await expectLater(
        repo.answer(a, list.last, accept: true),
        throwsA(isA<UntisException>()),
      );
      final again = await repo.requests(a);
      expect(again.every((r) => !r.isPending), isTrue);
    });

    test('availability: demo offers both, pupils none, cached', () async {
      final a = teacherAccount();
      final o = await repo.availability(a);
      expect(o.teacherAbsences && o.substitutionRequests, isTrue);
      expect(
        await repo.availability(demoAccount()),
        SubstitutionAvailability.none,
      );
    });

    test('report an absence: own teacher id, weeks refreshed', () async {
      final a = teacherAccount();
      final form = await repo.form(a);
      expect(form.reasons.map((r) => r.name), contains('Krankheit'));
      final start = DateTime(2026, 11, 20, 7);
      final end = DateTime(2026, 11, 24, 19);
      await repo.reportAbsence(
        a,
        start: start,
        end: end,
        reasonId: 1,
        note: ' Aufgaben im Fach ',
      );
      final d = api.teacherAbsenceCalls.single;
      expect(d.teacherId, FakeUntisApi.demoTeacherId);
      expect(d.start, start);
      expect(d.end, end);
      expect(d.reasonId, 1);
      expect(d.note, 'Aufgaben im Fach');
      expect(timetables.weeks, [
        DateTime(2026, 11, 16),
        DateTime(2026, 11, 23),
      ]);
      final list = await repo.absences(a);
      expect(list.any((x) => x.note == 'Aufgaben im Fach'), isTrue);
      await expectLater(
        repo.reportAbsence(a, start: end, end: start),
        throwsA(isA<UntisException>()),
      );
      await expectLater(
        repo.requests(demoAccount()),
        throwsA(isA<UntisException>()),
      );
    });

    Widget app(Widget home) => ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(accounts),
        activeAccountProvider.overrideWith(
          (ref) => Stream.value(teacherAccount()),
        ),
        substitutionPlanningRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(home: home),
    );

    testWidgets('accept a substitution request', (t) async {
      await t.pumpWidget(app(const SubstitutionRequestsScreen()));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('substitution-accept-9100')),
        findsNothing,
      );
      expect(find.text('Instead of Weber'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('substitution-accept-9101')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('substitution-confirm')));
      await t.pumpAndSettle();
      expect(api.substitutionAnswerCalls.single, (id: 9101, accept: true));
      expect(
        find.byKey(const ValueKey('substitution-accept-9101')),
        findsNothing,
      );
      final state = t.widget<Text>(
        find.byKey(const ValueKey('substitution-state-9101')),
      );
      expect(state.data, 'Accepted');
      expect(find.textContaining('Accepted: you substitute'), findsOneWidget);
    });

    testWidgets('404: no online substitution planning', (t) async {
      api.substitutionError = const UntisException(
        UntisApiImpl.substitutionPlanningMissing,
        "Your school doesn't use online substitution planning "
        '(substitution.webuntis.com answered HTTP 404).',
      );
      await t.pumpWidget(app(const SubstitutionRequestsScreen()));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('substitution-error')), findsOneWidget);
      expect(
        find.textContaining("doesn't use online substitution planning"),
        findsOneWidget,
      );
    });

    testWidgets('report an absence for tomorrow with a note', (t) async {
      await t.pumpWidget(app(const TeacherAbsencesScreen()));
      await t.pumpAndSettle();
      expect(find.textContaining('Fortbildung'), findsOneWidget);
      expect(find.textContaining('substitute: SCH'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('teacher-absence-new')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('teacher-absence-reason')));
      await t.pumpAndSettle();
      await t.tap(find.text('Krankheit').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('teacher-absence-tomorrow')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('teacher-absence-note')),
        'Arbeitsblätter liegen im Fach',
      );
      await t.tap(find.byKey(const ValueKey('teacher-absence-save')));
      await t.pumpAndSettle();

      final d = api.teacherAbsenceCalls.single;
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      expect(d.teacherId, FakeUntisApi.demoTeacherId);
      expect(d.reasonId, 1);
      expect(d.start, DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 7));
      expect(d.end, DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 19));
      expect(d.note, 'Arbeitsblätter liegen im Fach');
      // Back on the list, reloaded.
      expect(find.text('Absence reported.'), findsOneWidget);
      expect(
        find.textContaining('Arbeitsblätter liegen im Fach'),
        findsOneWidget,
      );
      expect(timetables.weeks, isNotEmpty);
    });

    testWidgets('a refused report stays in the form with the error', (t) async {
      await t.pumpWidget(app(const TeacherAbsencesScreen()));
      await t.pumpAndSettle();
      api.substitutionError = const UntisException(
        UntisException.noRight,
        'Your account may not report absences (HTTP 403).',
      );
      await t.tap(find.byKey(const ValueKey('teacher-absence-new')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('teacher-absence-save')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('teacher-absence-error')),
        findsOneWidget,
      );
      expect(find.textContaining('may not report absences'), findsOneWidget);
      expect(api.teacherAbsenceCalls, isEmpty);
    });
  });
}
