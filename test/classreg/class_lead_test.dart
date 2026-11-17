import 'package:better_betteruntis/api/class_lead_parsers.dart';
import 'package:better_betteruntis/api/excuse_parsers.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/app/routing_api.dart';
import 'package:better_betteruntis/core/class_lead.dart';
import 'package:better_betteruntis/core/class_register.dart';
import 'package:better_betteruntis/core/excuses.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/data/class_lead_repository_impl.dart';
import 'package:better_betteruntis/data/class_register_repository_impl.dart';
import 'package:better_betteruntis/data/excuse_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/classreg/class_lead_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../api/absence_report_api_test.dart' show Adapter, Req, Resp, rpc;
import 'class_register_test.dart' show teacherAccount;
import 'excuses_test.dart' show creds, host, metaJson;

/// The demo teacher as class teacher of 9b (id 1).
Account classTeacher() {
  final t = teacherAccount();
  return Account(
    id: t.id,
    school: t.school,
    username: t.username,
    anonymous: false,
    displayName: t.displayName,
    elementType: t.elementType,
    elementId: t.elementId,
    klassenIds: const [1],
  );
}

/// The demo API, but without getClassregData2017.
class _NoClassregData extends FakeUntisApi {
  _NoClassregData() : super(latency: Duration.zero);

  @override
  Future<ClassLeadData> classLeadData({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int klasseId,
    required DateTime start,
    required DateTime end,
    required ExcuseMeta meta,
  }) async => throw const UntisException(-32601, 'method not found');
}

void main() {
  final meta = parseExcuseMeta(metaJson);

  final answer = {
    'absences': [
      {
        'id': 10,
        'studentId': 501,
        'klasseId': 1,
        'startDateTime': '2026-11-10T08:00Z',
        'endDateTime': '2026-11-10T09:40Z',
        'absenceReasonId': 1,
        'absenceReason': '',
        'excused': false,
        'owner': true,
        'text': 'Fieber',
        'excuse': null,
      },
      {
        'id': 11,
        'studentId': 501,
        'startDateTime': '2026-11-11T08:00',
        'endDateTime': '2026-11-11T08:45',
        'excused': true,
        'excuse': {
          'id': 1,
          'excuseStatusId': 4,
          'date': '2026-11-12',
          'number': 1,
          'text': 'Attest',
        },
      },
      {
        'id': 12,
        'studentId': 502,
        'startDateTime': '2026-11-12T10:00',
        'endDateTime': '2026-11-12T10:45',
        'excused': true,
      },
      {'id': 13},
    ],
    'classRegEvents': [
      {
        'id': 20,
        'elementType': 'STUDENT',
        'elementId': 502,
        'eventReasonId': 3,
        'dateTime': '2026-11-12T10:15',
        'text': 'Handy',
      },
      {
        'id': 21,
        'elementType': 'CLASS',
        'elementId': 1,
        'eventReasonId': 4,
        'dateTime': '2026-11-13T09:00',
        'text': '',
      },
      {'id': 22, 'elementType': 'STUDENT', 'elementId': 501, 'delete': true},
      {'id': 23, 'elementType': 'CLASS', 'elementId': 1, 'text': ''},
    ],
    'referencedStudents': [
      {'id': 501, 'firstName': 'Lena', 'lastName': 'Bauer', 'klasseId': 1},
      {'id': 502, 'firstName': 'Jonas', 'lastName': 'Berger', 'klasseId': 1},
    ],
  };

  group('getClassregData2017', () {
    test('params: class and days', () {
      expect(
        classregDataParams(1, DateTime(2026, 11, 4), DateTime(2026, 11, 17)),
        {'klasseId': 1, 'startDate': '2026-11-04', 'endDate': '2026-11-17'},
      );
    });

    test('answer: absences with excuse status, entries, pupils', () {
      final d = parseClassLeadData(answer, meta, reasons: {3: 'Störung'});
      expect(d.students, {501: 'Bauer Lena', 502: 'Berger Jonas'});
      expect(d.absences.map((a) => a.id), [10, 11, 12]);
      final open = d.absences[0];
      expect(open.studentName, 'Bauer Lena');
      expect(open.start, DateTime(2026, 11, 10, 8));
      expect(open.end, DateTime(2026, 11, 10, 9, 40));
      expect(open.reasonName, 'Krankheit'); // from the meta
      expect(open.text, 'Fieber');
      expect(open.type, ExcuseStatusType.open);
      expect(open.raw, isEmpty); // saved with submitExcuse2017
      expect(d.absences[1].status!.name, 'Attest');
      expect(d.absences[1].excuseText, 'Attest');
      // Excused without an excuse: the first EXCUSED status.
      expect(d.absences[2].status!.id, 1);

      expect(d.events.map((e) => e.id), [20, 21]);
      expect(d.events[0].studentId, 502);
      expect(d.events[0].studentName, 'Berger Jonas');
      expect(d.events[0].reasonName, 'Störung');
      expect(d.events[0].date, DateTime(2026, 11, 12, 10, 15));
      expect(d.events[1].isClassWide, isTrue);
      expect(d.events[1].reasonId, 4);
      expect(parseClassLeadData('junk', meta).absences, isEmpty);
    });

    test('request: JSON-RPC with auth, no REST', () async {
      final adapter = Adapter((Req r) {
        if (r.json?['method'] == 'getClassregData2017') return rpc(answer);
        return (status: 404, body: '', headers: const {}) as Resp;
      });
      final api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
      final d = await api.classLeadData(
        host: host,
        school: 's',
        auth: creds,
        klasseId: 1,
        start: DateTime(2026, 11, 4),
        end: DateTime(2026, 11, 17),
        meta: meta,
      );
      expect(d.absences, hasLength(3));
      final req = adapter.requests.single;
      expect(req.uri.path, contains('jsonrpc_intern.do'));
      expect(req.json!['method'], 'getClassregData2017');
      final params = ((req.json!['params'] as List).single as Map)
          .cast<String, Object?>();
      expect(params['klasseId'], 1);
      expect(params['startDate'], '2026-11-04');
      expect(params['endDate'], '2026-11-17');
      expect(params['auth'], isA<Map>());
    });

    test('top pupils: most absences, then time', () {
      final d = parseClassLeadData(answer, meta);
      final top = pupilsByAbsences(d.absences);
      expect(top.map((p) => (p.name, p.absences, p.open, p.minutes)), [
        ('Bauer Lena', 2, 1, 145),
        ('Berger Jonas', 1, 0, 45),
      ]);
      expect(pupilsByAbsences(d.absences, limit: 1), hasLength(1));
    });
  });

  group('demo and repository', () {
    late FakeUntisApi api;
    late InMemoryAccountRepository accounts;

    DateTime lastWeekday() {
      var d = DateTime.now();
      do {
        d = DateTime(d.year, d.month, d.day - 1);
      } while (d.weekday > 5);
      return d;
    }

    ClassLeadRepositoryImpl repoFor(FakeUntisApi fake) {
      final routed = RoutingUntisApi(real: fake, demo: fake);
      final timetables = FakeTimetableRepository();
      return ClassLeadRepositoryImpl(
        api: routed,
        accounts: accounts,
        timetables: timetables,
        excuses: ExcuseRepositoryImpl(
          api: routed,
          accounts: accounts,
          timetables: timetables,
        ),
        classRegister: ClassRegisterRepositoryImpl(
          api: routed,
          accounts: accounts,
          timetables: timetables,
        ),
      );
    }

    void seed(FakeUntisApi fake) {
      final day = lastWeekday();
      fake.registerAbsences[FakeUntisApi.demoPeriodId(day, 0)] = [
        ClassRegAbsence(
          id: 42,
          studentId: 501,
          start: DateTime(day.year, day.month, day.day, 8),
          end: DateTime(day.year, day.month, day.day, 8, 45),
          text: 'Fieber',
        ),
      ];
    }

    setUp(() {
      api = FakeUntisApi(latency: Duration.zero);
      accounts = InMemoryAccountRepository(initial: [classTeacher()]);
      accounts.secrets['teacher'] = 'S';
      seed(api);
    });

    test('classes: the led ones by name; none without klassenIds', () async {
      final repo = repoFor(api);
      expect((await repo.classes(classTeacher())).map((c) => c.name), ['9b']);
      expect(await repo.classes(teacherAccount()), isEmpty);
      expect(leadsClass(classTeacher()), isTrue);
      expect(leadsClass(teacherAccount()), isFalse);
      expect(leadsClass(demoAccount()), isFalse);
    });

    test(
      'dashboard: open absences, top pupils, entries newest first',
      () async {
        final repo = repoFor(api);
        final d = await repo.dashboard(
          classTeacher(),
          const ExcuseClass(id: 1, name: '9b'),
        );
        expect(api.classLeadCalls, [1]);
        expect(d.eventsAvailable, isTrue);
        expect(d.open.any((a) => a.id == 42), isTrue);
        expect(d.open.every((a) => a.type == ExcuseStatusType.open), isTrue);
        expect(d.topPupils, isNotEmpty);
        expect(d.topPupils.first.absences >= d.topPupils.last.absences, isTrue);
        expect(d.events, isNotEmpty);
        expect(d.events.first.reasonName, isNotEmpty);
        for (var i = 1; i < d.events.length; i++) {
          expect(d.events[i - 1].date!.isBefore(d.events[i].date!), isFalse);
        }
        final saved = d.withAbsence(
          d.open.firstWhere((a) => a.id == 42).withExcuse(meta.status(1), ''),
        );
        expect(saved.open.any((a) => a.id == 42), isFalse);
      },
    );

    test('no getClassregData2017: absences from the Excuses list', () async {
      final fake = _NoClassregData();
      seed(fake);
      final d = await repoFor(fake)
          .dashboard(classTeacher(), const ExcuseClass(id: 1, name: '9b'));
      expect(d.eventsAvailable, isFalse);
      expect(d.events, isEmpty);
      expect(d.open.any((a) => a.id == 42), isTrue);
    });

    Widget app(ClassLeadRepository repo, Account account) => ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(accounts),
        activeAccountProvider.overrideWith((ref) => Stream.value(account)),
        classLeadRepositoryProvider.overrideWithValue(repo),
        excuseRepositoryProvider.overrideWithValue(
          ExcuseRepositoryImpl(
            api: RoutingUntisApi(real: api, demo: api),
            accounts: accounts,
            timetables: FakeTimetableRepository(),
          ),
        ),
      ],
      child: const MaterialApp(home: ClassLeadScreen()),
    );

    testWidgets('dashboard: excuse an open absence from it', (t) async {
      await t.pumpWidget(app(repoFor(api), classTeacher()));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('classlead-class-name')),
        findsOneWidget,
      );
      expect(find.textContaining('Open absences ('), findsOneWidget);
      expect(
        find.byKey(const ValueKey('classlead-link-excuses')),
        findsOneWidget,
      );
      var tile = find.byKey(const ValueKey('classlead-absence-42'));
      if (tile.evaluate().isEmpty) {
        await t.tap(find.byKey(const ValueKey('classlead-open-more')));
        await t.pumpAndSettle();
        tile = find.byKey(const ValueKey('classlead-absence-42'));
      }
      await t.scrollUntilVisible(tile, 200);
      await t.tap(tile);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('excuse-quick-notExcused')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('excuse-text')), 'Keine');
      await t.tap(find.byKey(const ValueKey('excuse-save')));
      await t.pumpAndSettle();

      expect(api.saveExcuseCalls.single, (
        absenceId: 42,
        statusId: 2,
        text: 'Keine',
      ));
      expect(find.byKey(const ValueKey('classlead-absence-42')), findsNothing);
      expect(find.textContaining('Saved: Bauer Lena'), findsOneWidget);

      await t.scrollUntilVisible(find.text('Class register entries'), 200);
      expect(find.textContaining('Bauer Lena'), findsWidgets);
    });

    testWidgets('no led class: explanation', (t) async {
      await t.pumpWidget(app(repoFor(api), teacherAccount()));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('classlead-none')), findsOneWidget);
    });
  });
}
