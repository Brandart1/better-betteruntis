// Notes for teachers ("Notizen für Lehrkräfte", REST notesStaff) and the
// "Notes for pupils" section of a teacher's own lesson: parser, request
// shape, routing, repository against the demo API and the lesson sheet.
import 'dart:convert';

import 'package:better_betteruntis/api/teacher_tools_parsers.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/app/routing_api.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/teacher_tools.dart';
import 'package:better_betteruntis/data/teacher_tools_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/timetable/lesson_details_sheet.dart';
import 'package:better_betteruntis/ui/timetable/lesson_layout.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../api/absence_report_api_test.dart' show Adapter, Req, Resp, ok, rpc;
import 'teacher_tools_test.dart'
    show
        ApiTimetables,
        creds,
        demoSchoolNames,
        maths,
        ownDay,
        teacherAccount,
        tuesday;

void main() {
  group('parser', () {
    test('notesStaff as {value} or string, permissions, nesting', () {
      final n = parseStaffNotes({
        'id': 5,
        'notesAll': 'pupils',
        'notesStaff': {'value': 'Seating plan'},
        'permissions': ['WRITE_NOTES_ALL', 'WRITE_NOTES_STAFF'],
      })!;
      expect(n.text, 'Seating plan');
      expect(n.editable, isTrue);

      final readOnly = parseStaffNotes({
        'notesStaff': ' Hi ',
        'permissions': ['WRITE_NOTES_ALL'],
      })!;
      expect(readOnly.text, 'Hi');
      expect(readOnly.editable, isFalse);

      // No permissions list: editable (own lesson).
      expect(parseStaffNotes({'notesStaff': null})!.editable, isTrue);
      expect(
        parseStaffNotes({
          'calendarEntries': [
            {
              'notesStaff': {'text': 'nested'},
            },
          ],
        })!.text,
        'nested',
      );
      expect(
        parseStaffNotes({
          'data': {'notesStaff': 'in data'},
        })!.text,
        'in data',
      );
      expect(parseStaffNotes({'id': 1}), isNull);
      expect(parseStaffNotes('junk'), isNull);
      expect(staffNotesPayload('x'), {
        'notesStaff': {'value': 'x'},
      });
    });
  });

  group('requests', () {
    late Adapter adapter;
    late UntisApiImpl api;
    late Resp Function(Req r) handler;
    bool isToken(Req r) => r.json?['method'] == 'getAuthToken';

    setUp(() {
      handler = (_) => (status: 500, body: '', headers: const {});
      adapter = Adapter((r) => handler(r));
      api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
    });

    test('read: GET view/v2/calendar-entry/{id}/detail with the bearer '
        'token', () async {
      handler = (r) => isToken(r)
          ? rpc({'token': 'jwt-1'})
          : ok({
              'notesStaff': {'value': 'Seating plan'},
              'permissions': ['WRITE_NOTES_STAFF'],
            });
      final n = await api.lessonStaffNotes(
        host: 'h',
        school: 's',
        auth: creds,
        periodId: 202611102,
      );
      expect(n.text, 'Seating plan');
      expect(n.editable, isTrue);
      final get = adapter.requests.last;
      expect(get.method, 'GET');
      expect(
        get.uri.toString(),
        'https://h/WebUntis/api/rest/view/v2/calendar-entry/202611102/detail',
      );
      expect(get.headers['Authorization'], 'Bearer jwt-1');
      expect(get.json, isNull);
    });

    test('write: PATCH one period or the block, body logged', () async {
      handler = (r) => isToken(r)
          ? rpc({'token': 'jwt-1'})
          : ok({
              'notesStaff': {'value': 'Saved'},
            });
      final saved = await api.submitStaffNotes(
        host: 'h',
        school: 's',
        auth: creds,
        periodId: 7,
        text: 'Saved',
      );
      expect(saved!.text, 'Saved');
      var patch = adapter.requests.last;
      expect(patch.method, 'PATCH');
      expect(
        patch.uri.toString(),
        'https://h/WebUntis/api/rest/view/v1/calendar-entry/7',
      );
      expect(patch.headers['Authorization'], 'Bearer jwt-1');
      expect(patch.json, {
        'notesStaff': {'value': 'Saved'},
      });

      handler = (r) => isToken(r) ? rpc({'token': 'jwt-1'}) : ok(null);
      final none = await api.submitStaffNotes(
        host: 'h',
        school: 's',
        auth: creds,
        periodId: 7,
        text: '',
        wholeBlock: true,
      );
      expect(none, isNull);
      patch = adapter.requests.last;
      expect(
        patch.uri.toString(),
        'https://h/WebUntis/api/rest/view/v1/calendar-entry/7/block',
      );
      expect(patch.json, {
        'notesStaff': {'value': ''},
      });
      final body = api.debugLog.firstWhere(
        (e) => e.method == 'REST PATCH view/v1/calendar-entry/7 request body',
      );
      expect(jsonDecode(body.json), {
        'notesStaff': {'value': 'Saved'},
      });
      expect(api.debugLog.map((e) => e.json).join(), isNot(contains('jwt-1')));
    });

    test('errors carry the server message', () async {
      handler = (r) => isToken(r)
          ? rpc({'token': 'jwt-1'})
          : (
              status: 403,
              body: {
                'errors': [
                  {'code': 'NO_RIGHT', 'title': 'Not allowed'},
                ],
              },
              headers: const <String, List<String>>{},
            );
      await expectLater(
        api.submitStaffNotes(
          host: 'h',
          school: 's',
          auth: creds,
          periodId: 7,
          text: 'x',
        ),
        throwsA(
          isA<UntisException>()
              .having((e) => e.code, 'code', UntisException.noRight)
              .having((e) => e.message, 'message', contains('Not allowed')),
        ),
      );
      handler = (r) => isToken(r)
          ? rpc({'token': 'jwt-1'})
          : (
              status: 404,
              body: {'errorMessage': 'Entry not found'},
              headers: const <String, List<String>>{},
            );
      await expectLater(
        api.lessonStaffNotes(host: 'h', school: 's', auth: creds, periodId: 1),
        throwsA(
          isA<UntisException>().having(
            (e) => e.message,
            'message',
            'Entry not found',
          ),
        ),
      );
    });

    test('RoutingUntisApi forwards both calls', () async {
      final demo = FakeUntisApi(latency: Duration.zero);
      final routing = RoutingUntisApi(real: api, demo: demo);
      await routing.submitStaffNotes(
        host: 'x.invalid',
        school: 's',
        auth: creds,
        periodId: 3,
        text: 'Hi',
        wholeBlock: true,
      );
      expect(demo.staffNotesCalls.single, (
        periodId: 3,
        text: 'Hi',
        wholeBlock: true,
      ));
      final n = await routing.lessonStaffNotes(
        host: 'x.invalid',
        school: 's',
        auth: creds,
        periodId: 3,
      );
      expect(n.text, 'Hi');
    });
  });

  group('repository (demo API)', () {
    late FakeUntisApi api;
    late TeacherToolsRepositoryImpl repo;

    setUp(() {
      final accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      api = FakeUntisApi(latency: Duration.zero);
      repo = TeacherToolsRepositoryImpl(
        api: api,
        accounts: accounts,
        timetables: ApiTimetables(api),
      );
    });

    test(
      'stored per period, block via the first period, teachers only',
      () async {
        final a = teacherAccount();
        final p = await maths(api);
        expect((await repo.staffNotes(a, [p])).text, '');
        final saved = await repo.setStaffNotes(a, [p], '  Seating plan ');
        expect(saved.text, 'Seating plan');
        expect(api.staffNotes[p.id], 'Seating plan');
        expect(api.staffNotesCalls.last.wholeBlock, isFalse);
        expect((await repo.staffNotes(a, [p])).text, 'Seating plan');

        // A double lesson: one PATCH for the block.
        // The demo's Tuesday unit 4 maths stands in for the second period.
        final second = (await ownDay(
          api,
          tuesday,
        )).firstWhere((q) => q.id != p.id);
        await repo.setStaffNotes(a, [p, second], 'Both');
        expect(api.staffNotesCalls.last, (
          periodId: p.id,
          text: 'Both',
          wholeBlock: true,
        ));
        expect((await repo.staffNotes(a, [p, second])).text, 'Both');

        await repo.setStaffNotes(a, [p], '');
        expect(api.staffNotes, isEmpty);
        expect(
          () => repo.staffNotes(demoAccount(), [p]),
          throwsA(isA<UntisException>()),
        );
      },
    );
  });

  group('lesson sheet', () {
    late FakeUntisApi api;
    late TeacherToolsRepositoryImpl repo;
    late Period p;

    setUp(() {
      final accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      api = FakeUntisApi(latency: Duration.zero);
      repo = TeacherToolsRepositoryImpl(
        api: api,
        accounts: accounts,
        timetables: ApiTimetables(api),
      );
    });

    StaffNotesAccess demoAccess() => StaffNotesAccess(
      load: (b) => repo.staffNotes(teacherAccount(), b.periods),
      save: (b, text) => repo.setStaffNotes(teacherAccount(), b.periods, text),
    );

    Future<void> pump(
      WidgetTester t, {
      StaffNotesAccess? access,
      bool teacher = true,
    }) async {
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: LessonDetailsSheet(
                blocks: [
                  LessonBlock([p]),
                ],
                names: demoSchoolNames(),
                onEditLessonInfo: teacher ? (_) {} : null,
                staffNotes: access,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('teachers edit notes for teachers in the sheet', (t) async {
      api.periodInfos[202611102] = 'Bring your atlas';
      p = (await t.runAsync(() => maths(api)))!;
      api.staffNotes[p.id] = 'Old';
      await pump(t, access: demoAccess());
      expect(find.byKey(const ValueKey('staff-notes-loading')), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.text('Notes for pupils'), findsOneWidget);
      // The lesson info shows once, in its section.
      expect(find.text('Bring your atlas'), findsOneWidget);
      expect(find.text('Notes for teachers'), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('staff-notes-text'))).data,
        'Old',
      );

      await t.tap(find.byKey(const ValueKey('staff-notes-edit')));
      await t.pumpAndSettle();
      expect(find.text('Edit notes for teachers'), findsOneWidget);
      expect(find.textContaining('Only teachers see'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('lesson-details-field')),
        ' Seating plan ',
      );
      await t.tap(find.byKey(const ValueKey('lesson-details-save')));
      await t.pumpAndSettle();
      expect(api.staffNotes[p.id], 'Seating plan');
      expect(api.staffNotesCalls.single.wholeBlock, isFalse);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('staff-notes-text'))).data,
        'Seating plan',
      );
    });

    testWidgets('load and save errors show the server message', (t) async {
      p = (await t.runAsync(() => maths(api)))!;
      await pump(
        t,
        access: StaffNotesAccess(
          load: (_) async => throw const UntisException(-1, 'Entry not found'),
          save: (_, _) async => throw const UntisException(-1, 'nope'),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.textContaining('Entry not found'),
        findsOneWidget,
        reason: 'load error',
      );
      expect(find.byKey(const ValueKey('staff-notes-edit')), findsNothing);
      // The rest of the sheet still works.
      expect(find.byKey(const ValueKey('lesson-info-edit')), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      await pump(
        t,
        access: StaffNotesAccess(
          load: (_) async => const StaffNotes(),
          save: (_, _) async => throw const UntisException(-1, 'nope'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('staff-notes-edit')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('lesson-details-field')),
        'x',
      );
      await t.tap(find.byKey(const ValueKey('lesson-details-save')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('staff-notes-save-error')),
        findsOneWidget,
      );
      expect(find.textContaining('nope'), findsOneWidget);
    });

    testWidgets('without WRITE_NOTES_STAFF: read-only', (t) async {
      p = (await t.runAsync(() => maths(api)))!;
      await pump(
        t,
        access: StaffNotesAccess(
          load: (_) async => const StaffNotes(text: 'Fixed', editable: false),
          save: (_, _) async => const StaffNotes(),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Fixed'), findsOneWidget);
      expect(find.byKey(const ValueKey('staff-notes-edit')), findsNothing);
      expect(
        find.byKey(const ValueKey('staff-notes-readonly')),
        findsOneWidget,
      );
    });

    testWidgets('pupils see neither section', (t) async {
      api.periodInfos[202611102] = 'Atlas';
      p = (await t.runAsync(() => maths(api)))!;
      await pump(t, teacher: false);
      await t.pumpAndSettle();
      expect(find.text('Notes for teachers'), findsNothing);
      expect(find.text('Notes for pupils'), findsNothing);
      expect(find.byKey(const ValueKey('lesson-info-edit')), findsNothing);
      // The lesson info itself still shows, as before.
      expect(find.text('Atlas'), findsOneWidget);
    });
  });
}
