// Previous lesson topics and class register entries ("Klassenbucheinträge"):
// parsers, requests, repository and the two sections of the class register
// screen (also with very large text).
import 'package:better_betteruntis/api/class_register_parsers.dart';
import 'package:better_betteruntis/api/parsers.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/core/class_register.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/data/class_register_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/classreg/class_register_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../api/absence_report_api_test.dart' show Adapter, rpc;

const creds = UntisCredentials.user('teacher', 'JBSWY3DPEHPK3PXP');

Account teacherAccount() {
  final d = demoAccount();
  return Account(
    id: 'teacher',
    school: d.school,
    username: 'teacher',
    anonymous: false,
    displayName: 'Demo Teacher',
    elementType: ElementType.teacher,
    elementId: FakeUntisApi.demoTeacherId,
  );
}

Period lesson(
  int id,
  DateTime start, {
  int lessonId = 1,
  int subject = 21,
  int klasse = 1,
}) => Period(
  id: id,
  lessonId: lessonId,
  start: start,
  end: start.add(const Duration(minutes: 45)),
  elements: [
    ElementRef(type: ElementType.klasse, id: klasse, orgId: klasse),
    ElementRef(type: ElementType.subject, id: subject, orgId: subject),
  ],
  flags: const {PeriodFlag.regular},
);

int idOf(DateTime d, int n) =>
    (d.year * 10000 + d.month * 100 + d.day) * 10 + n;

/// Per weekday: maths (lesson 1) at 08:00 and English (lesson 2, subject 23)
/// at 13:00, ids yyyymmddN.
List<Period> week(TimetableTarget _, DateTime monday) => [
  for (var d = 0; d < 5; d++) ...[
    lesson(
      idOf(DateTime(monday.year, monday.month, monday.day + d), 1),
      DateTime(monday.year, monday.month, monday.day + d, 8),
    ),
    lesson(
      idOf(DateTime(monday.year, monday.month, monday.day + d), 2),
      DateTime(monday.year, monday.month, monday.day + d, 13),
      lessonId: 2,
      subject: 23,
    ),
  ],
];

/// Wed 2026-11-11 08:00, maths.
final current = lesson(202611111, DateTime(2026, 11, 11, 8));

class FailingCreateApi extends FakeUntisApi {
  FailingCreateApi() : super(latency: Duration.zero);

  @override
  Future<void> createClassRegEvent({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    int? studentId,
    int? eventReasonId,
    required String text,
  }) async => throw const UntisException(-32601, 'Method not found');
}

void main() {
  group('parsers', () {
    test('entries per period, tolerant shapes', () {
      final d = parsePeriodData({
        'dataByTTId': {
          '101': {
            'classRegEvents': [
              {
                'id': 1,
                'studentId': 5,
                'eventReasonId': 3,
                'text': 'Homework missing',
                'date': 20261110,
              },
              {
                'eventId': '2',
                'student': {'id': 6, 'firstName': 'Mia', 'lastName': 'Hofmann'},
                'eventReason': {'id': 4, 'name': 'Lob'},
                'remark': 'Great talk',
                'startDateTime': '2026-11-10T08:10',
                'teacherName': 'MUE',
              },
              {'text': 'Whole class was loud', 'createDate': 1762761600000},
              {'id': 9, 'reason': 'Störung'},
              {'id': 10}, // nothing to show
              'junk',
            ],
          },
          '102': {
            'events': [
              {
                'id': 3,
                'studentIds': [7],
                'text': 'x',
              },
            ],
          },
        },
        // Also accepted: one top-level list with a ttId per item.
        'classRegEvents': [
          {'id': 4, 'ttId': 102, 'text': 'loose'},
          {'id': 5, 'ttId': 999, 'text': 'unknown lesson'},
        ],
      });
      final e = d.periods[101]!.events;
      expect(e, hasLength(4));
      expect(e[0].id, 1);
      expect(e[0].ttId, 101);
      expect(e[0].studentId, 5);
      expect(e[0].reasonId, 3);
      expect(e[0].text, 'Homework missing');
      expect(e[0].date, DateTime(2026, 11, 10));
      expect(e[1].id, 2);
      expect(e[1].studentId, 6);
      expect(e[1].studentName, 'Hofmann Mia');
      expect(e[1].reasonId, 4);
      expect(e[1].reasonName, 'Lob');
      expect(e[1].text, 'Great talk');
      expect(e[1].date, DateTime(2026, 11, 10, 8, 10));
      expect(e[1].author, 'MUE');
      expect(e[2].isClassWide, isTrue);
      expect(e[2].date, isNotNull);
      expect(e[3].reasonName, 'Störung');
      expect(e[3].text, '');
      final e2 = d.periods[102]!.events;
      expect(e2.map((x) => x.id), [3, 4]);
      expect(e2.first.studentId, 7);
      expect(d.periods.containsKey(999), isFalse);
    });

    test('entry without a date gets the lesson start', () {
      const e = ClassRegEvent(id: 1, text: 'x');
      final l = e.inLesson(7, DateTime(2026, 11, 10, 8));
      expect(l.ttId, 7);
      expect(l.date, DateTime(2026, 11, 10, 8));
    });

    test('event reasons from master data', () {
      final l = parseAbsenceLookups({
        'eventReasons': [
          {'id': 1, 'name': 'HÜ', 'longName': 'Hausübung fehlt'},
          {'id': 2, 'name': 'Lob'},
          {'name': 'no id'},
        ],
      });
      expect(l.eventReasons, {1: 'Hausübung fehlt', 2: 'Lob'});
      expect(l.isEmpty, isFalse);
    });
  });

  group('requests', () {
    late Adapter adapter;
    late UntisApiImpl api;
    setUp(() {
      adapter = Adapter(
        (r) => r.json!['method'] == 'getUserData2017'
            ? rpc({
                'masterData': {
                  'eventReasons': [
                    {'id': 3, 'longName': 'Störung'},
                  ],
                },
              })
            : rpc(null),
      );
      api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
    });

    Map<String, Object?> params() =>
        ((adapter.requests.last.json!['params'] as List).single as Map)
            .cast<String, Object?>();
    String method() => adapter.requests.last.json!['method'] as String;

    test('createClassRegEvent2017: params, logged body without auth', () async {
      await api.createClassRegEvent(
        host: 'h',
        school: 's',
        auth: creds,
        ttId: 5,
        studentId: 9,
        eventReasonId: 3,
        text: 'Homework missing',
      );
      expect(method(), 'createClassRegEvent2017');
      expect(params()['periodId'], 5);
      expect(params()['studentId'], 9);
      expect(params()['eventReasonId'], 3);
      expect(params()['text'], 'Homework missing');
      expect(params()['auth'], isA<Map>());
      final entry = api.debugLog.firstWhere(
        (e) => e.method == 'createClassRegEvent2017 request body',
      );
      expect(entry.json, contains('"periodId":5'));
      expect(entry.json, isNot(contains('otp')));

      // Whole class, no reason: those keys are left out.
      await api.createClassRegEvent(
        host: 'h',
        school: 's',
        auth: creds,
        ttId: 6,
        text: 'Loud',
      );
      expect(params().containsKey('studentId'), isFalse);
      expect(params().containsKey('eventReasonId'), isFalse);
    });

    test('event reasons: one getUserData2017 call, then remembered', () async {
      final r = await api.eventReasons(host: 'h', school: 's', auth: creds);
      expect(r, {3: 'Störung'});
      expect(method(), 'getUserData2017');
      final n = adapter.requests.length;
      await api.eventReasons(host: 'h', school: 's', auth: creds);
      expect(adapter.requests.length, n);
    });
  });

  group('repository', () {
    late FakeUntisApi api;
    late InMemoryAccountRepository accounts;
    late ClassRegisterRepositoryImpl repo;

    ClassRegisterRepositoryImpl build(
      FakeUntisApi api, {
      List<Period> Function(TimetableTarget, DateTime)? weekBuilder,
    }) => ClassRegisterRepositoryImpl(
      api: api,
      accounts: accounts,
      timetables: FakeTimetableRepository(weekBuilder: weekBuilder ?? week),
      clock: () => DateTime(2026, 11, 11, 12),
    );

    setUp(() {
      api = FakeUntisApi(latency: Duration.zero);
      accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      repo = build(api);
    });

    test('previous topics: same course, earlier, newest first', () async {
      api.registerTopics[202611101] = 'Fractions';
      api.registerTopics[202611091] = 'Decimals';
      // Same day, other course: never shown.
      api.registerTopics[202611102] = 'Shakespeare';
      final h = await repo.courseHistory(teacherAccount(), [current]);
      expect(h.topics, isNotEmpty);
      expect(h.topics.length, lessThanOrEqualTo(5));
      expect(h.topics.first.period.id, 202611101);
      expect(h.topics.first.register.topic, 'Fractions');
      expect(h.topics[1].period.id, 202611091);
      for (final l in h.topics) {
        expect(l.period.lessonId, 1);
        expect(l.period.start.isBefore(current.start), isTrue);
        expect(l.register.hasTopic, isTrue);
      }
      final starts = [for (final l in h.topics) l.period.start];
      expect(starts, [...starts]..sort((a, b) => b.compareTo(a)));
      expect(h.lessonsLoaded, 15);
      expect(h.students, isNotEmpty);
    });

    test('falls back to the same subject and class', () async {
      // No lesson ids: subject + class decide.
      List<Period> noIds(TimetableTarget t, DateTime m) => [
        for (final p in week(t, m))
          lesson(p.id, p.start, lessonId: 0, subject: p.id % 10 == 1 ? 21 : 23),
      ];
      repo = build(api, weekBuilder: noIds);
      api.registerTopics[202611101] = 'Fractions';
      api.registerTopics[202611102] = 'Shakespeare';
      final h = await repo.courseHistory(teacherAccount(), [
        lesson(202611111, DateTime(2026, 11, 11, 8), lessonId: 0),
      ]);
      expect(h.topics.first.register.topic, 'Fractions');
      expect(h.topics.every((l) => l.period.id % 10 == 1), isTrue);
    });

    test('create an entry; it shows in the lesson and later lessons', () async {
      final a = teacherAccount();
      await repo.createEvent(
        a,
        [current],
        const NewClassRegEvent(
          studentId: 502,
          reasonId: 4,
          text: ' Well done ',
        ),
      );
      final d = await repo.load(a, [current]);
      final e = d.periods[current.id]!.events.last;
      expect(e.studentId, 502);
      expect(e.reasonId, 4);
      expect(e.text, 'Well done');
      // From the next lesson of the course it is a recent entry.
      final next = lesson(202611121, DateTime(2026, 11, 12, 8));
      final h = await repo.courseHistory(a, [next]);
      final found = h.events.where((x) => x.text == 'Well done').single;
      expect(found.ttId, current.id);
      final dates = [for (final x in h.events) x.date!];
      expect(dates, [...dates]..sort((a, b) => b.compareTo(a)));
      expect(h.events.every((x) => x.ttId != next.id), isTrue);
    });

    test('create needs a text or a reason', () async {
      await expectLater(
        repo.createEvent(teacherAccount(), [
          current,
        ], const NewClassRegEvent(text: '  ')),
        throwsA(isA<UntisException>()),
      );
      expect(api.registerEvents, isEmpty);
    });

    test('event reasons (cached, never throw)', () async {
      expect(
        await repo.eventReasons(teacherAccount()),
        FakeUntisApi.demoEventReasons,
      );
      expect(await repo.eventReasons(demoAccount()), isEmpty);
    });

    test('no timetable at all: an error', () async {
      repo = ClassRegisterRepositoryImpl(
        api: api,
        accounts: accounts,
        timetables: FakeTimetableRepository(
          weekBuilder: week,
          watchError: const UntisException(0, 'offline'),
        ),
      );
      await expectLater(
        repo.courseHistory(teacherAccount(), [current]),
        throwsA(isA<UntisException>()),
      );
    });
  });

  group('screen', () {
    final listScroll = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    late FakeUntisApi api;
    late InMemoryAccountRepository accounts;

    Widget app(FakeUntisApi api, {double textScale = 1}) {
      final repo = ClassRegisterRepositoryImpl(
        api: api,
        accounts: accounts,
        timetables: FakeTimetableRepository(weekBuilder: week),
        clock: () => DateTime(2026, 11, 11, 12),
      );
      return ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(accounts),
          classRegisterRepositoryProvider.overrideWithValue(repo),
          nameResolverProvider.overrideWith((ref) => Stream.value(demoNames())),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: ClassRegisterScreen(
            account: teacherAccount(),
            periods: [current],
            title: 'Maths',
            subtitle: 'Wed 11 Nov',
          ),
        ),
      );
    }

    setUp(() {
      api = FakeUntisApi(latency: Duration.zero);
      accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
    });

    testWidgets('previous topics: listed, tap copies into the field', (
      t,
    ) async {
      api.registerTopics[202611101] = 'Fractions';
      api.registerTopics[202611091] = 'Decimals';
      api.registerTopics[202611061] = 'Percentages';
      await t.pumpWidget(app(api));
      await t.pumpAndSettle();
      expect(find.text('Previous topics'), findsOneWidget);
      final tile = find.byKey(const ValueKey('classreg-prev-topic-202611101'));
      expect(tile, findsOneWidget);
      await t.tap(tile);
      await t.pump();
      final field = t.widget<TextField>(
        find.byKey(const ValueKey('classreg-topic')),
      );
      expect(field.controller!.text, 'Fractions');
      // Two at first, the rest on demand.
      final tiles = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'classreg-prev-topic-',
            ),
      );
      expect(tiles, findsNWidgets(2));
      await t.tap(find.byKey(const ValueKey('classreg-prev-topics-more')));
      await t.pump();
      expect(tiles, findsNWidgets(3));
    });

    testWidgets('previous topics: error inline, retry', (t) async {
      final repo = ClassRegisterRepositoryImpl(
        api: api,
        accounts: accounts,
        timetables: FakeTimetableRepository(
          weekBuilder: week,
          watchError: const UntisException(0, 'No connection'),
        ),
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [classRegisterRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: ClassRegisterScreen(
              account: teacherAccount(),
              periods: [current],
              title: 'Maths',
              subtitle: '',
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      // The rest of the screen still works.
      expect(find.text('Bauer Lena'), findsOneWidget);
      expect(
        find.text('Could not load earlier lessons: No connection'),
        findsWidgets,
      );
      expect(
        find.byKey(const ValueKey('classreg-history-retry')),
        findsWidgets,
      );
    });

    testWidgets('entries: lesson and recent ones, create a new one', (t) async {
      // An entry in an earlier lesson of the course.
      api.registerEvents[202611101] = [
        const ClassRegEvent(id: 1, studentId: 503, reasonId: 1, text: 'Again'),
      ];
      await t.pumpWidget(app(api));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Hofmann Mia · Hausübung fehlt'),
        300,
        scrollable: listScroll,
      );
      // (The demo may seed an entry in this lesson too.)

      await t.scrollUntilVisible(
        find.byKey(const ValueKey('classreg-new-entry')),
        -300,
        scrollable: listScroll,
      );
      // Built is not enough: it may still be under the app bar.
      await t.ensureVisible(find.byKey(const ValueKey('classreg-new-entry')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('classreg-new-entry')));
      await t.pumpAndSettle();
      expect(find.text('New entry'), findsOneWidget);
      final send = find.byKey(const ValueKey('classreg-entry-send'));
      expect(t.widget<ButtonStyleButton>(send).onPressed, isNull);

      await t.tap(find.byKey(const ValueKey('classreg-entry-pupil')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('classreg-entry-pupil-502')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('classreg-entry-reason')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('classreg-entry-reason-4')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('classreg-entry-text')),
        'Great presentation',
      );
      await t.pump();
      await t.tap(send);
      await t.pumpAndSettle();

      final created = api.registerEvents[current.id]!.single;
      expect(created.studentId, 502);
      expect(created.reasonId, 4);
      expect(created.text, 'Great presentation');
      expect(find.text('Entry created'), findsOneWidget);
      expect(find.text('Fischer Jonas · Lob'), findsOneWidget);
    });

    testWidgets('create: the server error stays visible', (t) async {
      await t.pumpWidget(app(FailingCreateApi()));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('classreg-new-entry')),
        300,
        scrollable: listScroll,
      );
      await t.tap(find.byKey(const ValueKey('classreg-new-entry')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('classreg-entry-text')),
        'Loud',
      );
      await t.pump();
      await t.tap(find.byKey(const ValueKey('classreg-entry-send')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('classreg-entry-error')),
        findsOneWidget,
      );
      expect(find.textContaining('Method not found'), findsOneWidget);
      expect(find.textContaining('-32601'), findsOneWidget);
      // Still on the form, text kept.
      expect(find.text('Loud'), findsOneWidget);
    });

    for (final scale in [2.0, 2.5]) {
      testWidgets('large text ${scale * 100} %: nothing overflows', (t) async {
        t.view.physicalSize = const Size(360, 740) * 3;
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        api.registerTopics[202611101] =
            'A rather long topic: Bruchrechnen mit gemischten Zahlen';
        api.registerEvents[202611101] = [
          const ClassRegEvent(
            id: 1,
            studentId: 503,
            reasonId: 3,
            text: 'Unterrichtsstörung',
          ),
        ];
        await t.pumpWidget(app(api, textScale: scale));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final list = find.byType(Scrollable).first;
        for (var i = 0; i < 30; i++) {
          await t.drag(list, const Offset(0, -300));
          await t.pump();
          expect(t.takeException(), isNull);
        }
        await t.scrollUntilVisible(
          find.byKey(const ValueKey('classreg-new-entry')),
          -300,
          scrollable: listScroll,
        );
        await t.tap(find.byKey(const ValueKey('classreg-new-entry')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const ValueKey('classreg-entry-reason')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
