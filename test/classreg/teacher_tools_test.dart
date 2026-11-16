// Room booking and exam creation for teachers: parsers, requests,
// repository (against the demo API), the lesson-sheet entries, the room
// booking screen, the exam editor (from a lesson and from the exam menu) and
// very large text.
import 'dart:convert';

import 'package:better_betteruntis/api/teacher_tools_parsers.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/core/class_register.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/teacher_tools.dart';
import 'package:better_betteruntis/core/info.dart';
import 'package:better_betteruntis/data/class_register_repository_impl.dart';
import 'package:better_betteruntis/data/name_resolver_impl.dart';
import 'package:better_betteruntis/data/teacher_tools_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_info.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/classreg/exam_editor_screen.dart';
import 'package:better_betteruntis/ui/classreg/room_booking_screen.dart';
import 'package:better_betteruntis/ui/classreg/teacher_exams_screen.dart';
import 'package:better_betteruntis/ui/timetable/lesson_details_sheet.dart';
import 'package:better_betteruntis/ui/timetable/lesson_layout.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../api/absence_report_api_test.dart' show Adapter, Req, Resp, ok, rpc;

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

/// Names and time grid of the demo school (rooms 31–36, units 08:00 + 50').
NameResolver demoSchoolNames() => NameResolverImpl(
  elements: FakeUntisApi.demoMasterData.elements,
  timeGrid: FakeUntisApi.demoMasterData.timeGrid,
);

/// Own timetable straight from the demo API, so room changes and exams the
/// API records show up.
class ApiTimetables implements TimetableRepository {
  ApiTimetables(this.api);
  final FakeUntisApi api;
  final refreshed = <DateTime>[];

  Future<List<Period>> _week(TimetableTarget t, DateTime monday) async =>
      (await api.timetable(
        host: 'h',
        school: 's',
        auth: creds,
        target: t,
        start: monday,
        end: DateTime(monday.year, monday.month, monday.day + 6),
        masterDataTimestamp: 0,
      )).periods;

  @override
  Stream<List<Period>> watchWeek(
    Account account,
    TimetableTarget target,
    DateTime weekStart,
  ) => Stream.fromFuture(_week(target, weekStart));

  @override
  Future<void> refresh(
    Account account,
    TimetableTarget target,
    DateTime weekStart,
  ) async => refreshed.add(weekStart);

  @override
  Stream<NameResolver> watchNames(Account account) =>
      Stream.value(demoSchoolNames());

  @override
  DateTime? lastRefreshed(Account a, TimetableTarget t, DateTime w) => null;

  @override
  Future<void> discoverTeachers(
    Account account,
    DateTime weekStart, {
    void Function(int done, int total)? onProgress,
  }) async {}
}

/// Tue 2026-11-10: unit 1 Physik (room 33), unit 2 Maths (room 31), unit 4
/// Maths — the demo teacher's lessons.
final tuesday = DateTime(2026, 11, 10);

Future<List<Period>> ownDay(FakeUntisApi api, DateTime day) async =>
    (await api.timetable(
      host: 'h',
      school: 's',
      auth: creds,
      target: const TimetableTarget(
        ElementType.teacher,
        FakeUntisApi.demoTeacherId,
      ),
      start: day,
      end: day,
      masterDataTimestamp: 0,
    )).periods;

Future<Period> maths(FakeUntisApi api) async =>
    (await ownDay(api, tuesday)).firstWhere((p) => p.id == 202611102);

class NoRoomChangeDataApi extends FakeUntisApi {
  NoRoomChangeDataApi() : super(latency: Duration.zero);

  @override
  Future<FreeRooms> roomChangeData({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> periodIds,
  }) async => throw const UntisException(-32601, 'Method not found');
}

class RejectingRoomApi extends FakeUntisApi {
  RejectingRoomApi() : super(latency: Duration.zero);

  @override
  Future<RoomChangeResult> submitRoomChange({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> periodIds,
    required int orgRoomId,
    required int roomId,
  }) async => const RoomChangeResult(
    errors: [
      TeacherToolError(
        code: 'NO_RIGHT',
        title: 'No right',
        details: 'Ask the office',
      ),
    ],
  );
}

class FailingExamApi extends FakeUntisApi {
  FailingExamApi() : super(latency: Duration.zero);

  @override
  Future<int?> createExam({
    required String host,
    required String school,
    required UntisCredentials auth,
    required NewExam exam,
  }) async => throw const UntisException(
    -1,
    "This school's WebUntis doesn't offer this function (HTTP 404).",
  );
}

/// A tall test view, so the whole (lazy) form is built.
void tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// No exam types in the master data; the school's exams have some.
class NoExamTypesApi extends FakeUntisApi {
  NoExamTypesApi() : super(latency: Duration.zero);

  @override
  Future<List<ExamType>> examTypes({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) async => const [];

  @override
  Future<List<ExamItem>> exams({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
  }) async => [
    for (final (i, type) in ['Test', 'Schularbeit', '', 'Test'].indexed)
      ExamItem(
        id: i,
        start: DateTime(2026, 11, 2 + i, 8),
        end: DateTime(2026, 11, 2 + i, 9),
        examType: type,
      ),
  ];
}

void main() {
  group('parsers', () {
    test('free rooms: tolerant shapes', () {
      expect(
        parseFreeRooms({
          'availableRoomIds': [3, '4', 3, null, 0],
          'errors': [],
        }).roomIds,
        [3, 4],
      );
      expect(
        parseFreeRooms({
          'roomIds': [
            {'id': 7},
            8,
          ],
        }).roomIds,
        [7, 8],
      );
      expect(parseFreeRooms([1, 2]).roomIds, [1, 2]);
      final withErrors = parseFreeRooms({
        'errors': [
          {'code': 'NO_RIGHT', 'title': 'No right', 'details': 'Ask admin'},
          'Plain text',
          {'x': 1},
        ],
      });
      expect(withErrors.roomIds, isEmpty);
      expect(withErrors.errors.map((e) => e.message), [
        'No right: Ask admin (NO_RIGHT)',
        'Plain text',
      ]);
      expect(parseFreeRooms(null).roomIds, isEmpty);
    });

    test('room change result', () {
      final ok = parseRoomChangeResult({
        'errors': [],
        'periods': [{}, {}],
      });
      expect(ok.ok, isTrue);
      expect(ok.periodCount, 2);
      final bad = parseRoomChangeResult({
        'errors': [
          {'code': 'ROOM_OCCUPIED', 'title': 'Room is occupied'},
        ],
      });
      expect(bad.ok, isFalse);
      expect(bad.errors.single.message, 'Room is occupied (ROOM_OCCUPIED)');
    });

    test('exam types from master data', () {
      final t = parseExamTypes({
        'examTypes': [
          {'id': 1, 'name': 'SA', 'longName': 'Schularbeit'},
          {'id': 2, 'name': 'T'},
          {'id': 2, 'name': 'dup'},
          {'id': 3, 'name': 'old', 'active': false},
          {'name': 'no id'},
        ],
      });
      expect([for (final e in t) e.displayName], ['Schularbeit', 'T']);
      expect(parseExamTypes({}), isEmpty);
    });

    test('exam payload, created id and errors', () {
      final p = examPayload(
        NewExam(
          examType: 'Test',
          name: ' Fractions ',
          start: DateTime(2026, 11, 10, 9, 40),
          end: DateTime(2026, 11, 10, 11, 15),
          roomIds: const [34],
          klasseIds: const [1],
          teacherIds: const [11],
          subjectId: 21,
          lessonId: 21,
          periodIds: const [202611102],
        ),
      );
      expect(p['name'], 'Fractions');
      expect(p['examDate'], 20261110);
      expect(p['startTime'], 940);
      expect(p['endTime'], 1115);
      expect(p['startDateTime'], '2026-11-10T09:40');
      expect(p['roomIds'], [34]);
      expect(p.containsKey('examTypeId'), isFalse);
      expect(
        parseCreatedExamId({
          'data': {'id': 5},
        }),
        5,
      );
      expect(
        parseCreatedExamId({
          'exam': {'examId': '6'},
        }),
        6,
      );
      expect(parseCreatedExamId(null), isNull);
      expect(
        parseExamErrors({
          'data': {'success': false, 'message': 'Overlap'},
        }).single.message,
        contains('Overlap'),
      );
      expect(
        parseExamErrors({
          'data': {'id': 5},
        }),
        isEmpty,
      );
    });
  });

  group('requests', () {
    late Adapter adapter;
    late UntisApiImpl api;
    late Resp Function(Req r) handler;
    setUp(() {
      handler = (_) => rpc({
        'availableRoomIds': [34],
      });
      adapter = Adapter((r) => handler(r));
      api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
    });

    Map<String, Object?> params() =>
        ((adapter.requests.last.json!['params'] as List).single as Map)
            .cast<String, Object?>();
    String method() => adapter.requests.last.json!['method'] as String;

    test('getRoomChangeData2017 and getAvailableRooms2017', () async {
      final r = await api.roomChangeData(
        host: 'h',
        school: 's',
        auth: creds,
        periodIds: [5, 6],
      );
      expect(method(), 'getRoomChangeData2017');
      expect(params()['periodIds'], [5, 6]);
      expect(params()['auth'], isA<Map>());
      expect(r.roomIds, [34]);
      await api.availableRooms(
        host: 'h',
        school: 's',
        auth: creds,
        start: DateTime(2026, 11, 10, 8),
        end: DateTime(2026, 11, 10, 9, 35),
      );
      expect(method(), 'getAvailableRooms2017');
      // The official app's format: local time with a literal 'Z'.
      expect(params()['startDateTime'], '2026-11-10T08:00Z');
      expect(params()['endDateTime'], '2026-11-10T09:35Z');
    });

    test('submitRoomChange2017: params, logged body without auth', () async {
      handler = (_) => rpc({
        'errors': [],
        'periods': [{}],
      });
      final r = await api.submitRoomChange(
        host: 'h',
        school: 's',
        auth: creds,
        periodIds: [5],
        orgRoomId: 31,
        roomId: 34,
      );
      expect(r.ok, isTrue);
      expect(method(), 'submitRoomChange2017');
      expect(params()['periodIds'], [5]);
      expect(params()['orgRoomId'], 31);
      expect(params()['roomId'], 34);
      final entry = api.debugLog.firstWhere(
        (e) => e.method == 'submitRoomChange2017 request body',
      );
      expect(entry.json, contains('"roomId":34'));
      expect(entry.json, isNot(contains('otp')));
    });

    test('submitPeriodInfo2017: params, success', () async {
      handler = (_) => rpc({'success': true});
      final ok = await api.submitPeriodInfo(
        host: 'h',
        school: 's',
        auth: creds,
        periodId: 7,
        text: 'Atlas',
      );
      expect(ok, isTrue);
      expect(method(), 'submitPeriodInfo2017');
      expect(params()['periodId'], 7);
      expect(params()['periodInfo'], 'Atlas');
      handler = (_) => rpc({'success': false});
      expect(
        await api.submitPeriodInfo(
          host: 'h',
          school: 's',
          auth: creds,
          periodId: 7,
          text: 'Atlas',
        ),
        isFalse,
      );
    });

    test('exam types: one getUserData2017 call, then remembered', () async {
      handler = (_) => rpc({
        'masterData': {
          'examTypes': [
            {'id': 1, 'name': 'SA'},
          ],
        },
      });
      final t = await api.examTypes(host: 'h', school: 's', auth: creds);
      expect(t.single.name, 'SA');
      expect(method(), 'getUserData2017');
      final n = adapter.requests.length;
      await api.examTypes(host: 'h', school: 's', auth: creds);
      expect(adapter.requests.length, n);
    });

    test(
      'createExam: POST api/exams, else classreg/exams; body logged',
      () async {
        handler = (r) {
          if (r.json?['method'] == 'getAuthToken') return rpc({'token': 'jwt'});
          if (r.uri.path == '/WebUntis/api/exams') {
            return (status: 404, body: '', headers: const {});
          }
          if (r.uri.path == '/WebUntis/api/classreg/exams') {
            return ok({
              'data': {'id': 42},
            });
          }
          return rpc({});
        };
        final exam = NewExam(
          name: 'Fractions',
          start: DateTime(2026, 11, 10, 9, 40),
          end: DateTime(2026, 11, 10, 10, 25),
          klasseIds: const [1],
        );
        final id = await api.createExam(
          host: 'h',
          school: 's',
          auth: creds,
          exam: exam,
        );
        expect(id, 42);
        final posts = adapter.requests
            .where((r) => r.method == 'POST')
            .toList();
        expect(posts.last.uri.path, '/WebUntis/api/classreg/exams');
        expect(posts.last.json, examPayload(exam));
        final body = api.debugLog.firstWhere(
          (e) => e.method == 'REST exams request body',
        );
        expect(jsonDecode(body.json), examPayload(exam));
        expect(api.debugLog.map((e) => e.json).join(), isNot(contains('jwt')));
      },
    );

    test('createExam: server errors in a 200 answer are thrown', () async {
      handler = (r) => r.json?['method'] == 'getAuthToken'
          ? rpc({'token': 'jwt'})
          : (r.uri.path.contains('/api/')
                ? ok({
                    'errors': [
                      {'title': 'Exam overlaps'},
                    ],
                  })
                : rpc({}));
      await expectLater(
        api.createExam(
          host: 'h',
          school: 's',
          auth: creds,
          exam: NewExam(
            name: 'X',
            start: DateTime(2026, 11, 10, 8),
            end: DateTime(2026, 11, 10, 9),
          ),
        ),
        throwsA(
          isA<UntisException>().having(
            (e) => e.message,
            'message',
            'Exam overlaps',
          ),
        ),
      );
    });
  });

  group('repository (demo API)', () {
    late FakeUntisApi api;
    late InMemoryAccountRepository accounts;
    late ApiTimetables timetables;
    late TeacherToolsRepositoryImpl repo;

    TeacherToolsRepositoryImpl build(FakeUntisApi a) {
      api = a;
      timetables = ApiTimetables(a);
      return TeacherToolsRepositoryImpl(
        api: a,
        accounts: accounts,
        timetables: timetables,
        clock: () => DateTime(2026, 11, 11, 12),
      );
    }

    setUp(() {
      accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      repo = build(FakeUntisApi(latency: Duration.zero));
    });

    test('only teachers', () {
      expect(
        () => repo.freeRoomsForLesson(demoAccount(), const []),
        throwsA(isA<UntisException>()),
      );
    });

    test('free rooms of a lesson: not its own room', () async {
      final p = await maths(api);
      final r = await repo.freeRoomsForLesson(teacherAccount(), [p]);
      expect(r.roomIds, isNot(contains(31)));
      expect(r.roomIds, containsAll([34, 35, 36]));
    });

    test('falls back to getAvailableRooms2017', () async {
      repo = build(NoRoomChangeDataApi());
      final p = await maths(api);
      final r = await repo.freeRoomsForLesson(teacherAccount(), [p]);
      expect(r.roomIds, containsAll([34, 35]));
      expect(r.roomIds, isNot(contains(31)));
    });

    test('book, then back to the planned room', () async {
      final a = teacherAccount();
      final p = await maths(api);
      final r = await repo.changeRoom(a, [p], orgRoomId: 31, roomId: 34);
      expect(r.ok, isTrue);
      expect(timetables.refreshed, [DateTime(2026, 11, 9)]);
      final moved = await maths(api);
      final room = bookableRoomOf(moved)!;
      expect((room.id, room.orgId), (34, 31));
      expect(moved.isIrregular, isTrue);
      // Booked rooms are busy for other lessons at that time.
      expect(
        (await repo.freeRoomsBetween(a, p.start, p.end)).roomIds,
        isNot(contains(34)),
      );
      // Back: orgRoomId is the room the lesson has now (34), not the
      // planned one — the server refused the planned one (teacher test).
      final back = RoomEdit.replace(room.id, 31);
      final r2 = await repo.changeRoom(
        a,
        [moved],
        orgRoomId: back.orgRoomId,
        roomId: back.roomId,
      );
      expect(r2.ok, isTrue);
      expect(api.roomChangeCalls.last.orgRoomId, 34);
      expect(bookableRoomOf(await maths(api))!.id, 31);
      expect(api.roomChanges, isEmpty);
      // The planned room as orgRoomId is refused like by the real server.
      await repo.changeRoom(a, [moved], orgRoomId: 31, roomId: 34);
      final wrong = await repo.changeRoom(
        a,
        [moved],
        orgRoomId: 31,
        roomId: 35,
      );
      expect(wrong.ok, isFalse);
      expect(wrong.errors.single.code, 'ROOM_NOT_IN_PERIOD');
    });

    test('lesson info goes to the server and shows in the timetable', () async {
      final a = teacherAccount();
      final p = await maths(api);
      await repo.setLessonInfo(a, [p], '  Bring your atlas ');
      expect(api.periodInfos[p.id], 'Bring your atlas');
      expect(timetables.refreshed, [DateTime(2026, 11, 9)]);
      expect((await maths(api)).infoText, 'Bring your atlas');
      await repo.setLessonInfo(a, [p], '');
      expect((await maths(api)).infoText, '');
      expect(
        () => repo.setLessonInfo(demoAccount(), [p], 'x'),
        throwsA(isA<UntisException>()),
      );
    });

    test('an occupied or unknown room: the server errors come back', () async {
      // Monday unit 3: Physik; the gym is booked on Mondays.
      final mon = (await ownDay(
        api,
        DateTime(2026, 11, 9),
      )).firstWhere((x) => x.id == 202611092);
      final busy = await repo.changeRoom(
        teacherAccount(),
        [mon],
        orgRoomId: 33,
        roomId: 36,
      );
      expect(busy.ok, isFalse);
      expect(busy.errors.single.code, 'ROOM_OCCUPIED');
      expect(timetables.refreshed, isEmpty);
      final unknown = await repo.changeRoom(
        teacherAccount(),
        [mon],
        orgRoomId: 33,
        roomId: 99,
      );
      expect(unknown.errors.single.code, 'ROOM_UNKNOWN');
      expect(api.roomChanges, isEmpty);
    });

    test('create an exam: in the timetable and the exam list', () async {
      final a = teacherAccount();
      final p = await maths(api);
      await repo.createExam(
        a,
        NewExam(
          examType: 'Test',
          name: 'Fractions',
          start: p.start,
          end: p.end.add(const Duration(minutes: 50)),
          klasseIds: const [1],
          roomIds: const [34],
          subjectId: 21,
          teacherIds: const [11],
          periodIds: [p.id],
        ),
      );
      expect(timetables.refreshed, [DateTime(2026, 11, 9)]);
      final day = await ownDay(api, tuesday);
      final exam = day.firstWhere((x) => x.id == p.id);
      expect(exam.isSchoolExam, isTrue);
      expect(exam.exam!.name, 'Fractions');
      final list = await api.exams(
        host: 'h',
        school: 's',
        auth: creds,
        target: const TimetableTarget(ElementType.teacher, 11),
        start: tuesday,
        end: DateTime(2026, 11, 11),
      );
      expect(list.where((e) => e.name == 'Fractions'), hasLength(1));
    });

    test('create needs a name or a type and a valid time', () async {
      final p = await maths(api);
      await expectLater(
        repo.createExam(teacherAccount(), NewExam(start: p.start, end: p.end)),
        throwsA(isA<UntisException>()),
      );
      await expectLater(
        repo.createExam(
          teacherAccount(),
          NewExam(name: 'X', start: p.end, end: p.start),
        ),
        throwsA(isA<UntisException>()),
      );
      expect(api.createExamCalls, isEmpty);
    });

    test('courses and lessons of a day', () async {
      final c = await repo.courses(teacherAccount());
      expect(c.subjectIds, containsAll([21, 24]));
      expect(c.subjectIds, isNot(contains(22)));
      expect(c.classesOf(21), {1});
      final day = await repo.lessonsOn(teacherAccount(), tuesday);
      expect([for (final p in day) p.id], [202611101, 202611102, 202611104]);
    });

    test('exam types never throw', () async {
      expect(
        await repo.examTypes(teacherAccount()),
        FakeUntisApi.demoExamTypes,
      );
      expect(await repo.examTypes(demoAccount()), isEmpty);
    });

    test('exam types: from the school\'s exams without master data', () async {
      final r = build(NoExamTypesApi());
      final types = await r.examTypes(teacherAccount());
      expect([for (final t in types) t.name], ['Schularbeit', 'Test']);
      expect(types.every((t) => t.id < 0), isTrue);
    });
  });

  group('screens', () {
    late FakeUntisApi api;
    late InMemoryAccountRepository accounts;

    Widget app(Widget home, {FakeUntisApi? fake, double textScale = 1}) {
      final a = fake ?? api;
      final timetables = ApiTimetables(a);
      return ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(accounts),
          nameResolverProvider.overrideWith(
            (ref) => Stream.value(demoSchoolNames()),
          ),
          teacherToolsRepositoryProvider.overrideWithValue(
            TeacherToolsRepositoryImpl(
              api: a,
              accounts: accounts,
              timetables: timetables,
              clock: () => DateTime(2026, 11, 10, 7),
            ),
          ),
          classRegisterRepositoryProvider.overrideWithValue(
            ClassRegisterRepositoryImpl(
              api: a,
              accounts: accounts,
              timetables: timetables,
            ),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: home,
        ),
      );
    }

    setUp(() {
      api = FakeUntisApi(latency: Duration.zero);
      accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
    });

    testWidgets('lesson sheet: room actions, create exam replaces mark', (
      t,
    ) async {
      tall(t);
      final p = await t.runAsync(() => maths(api));
      // With a note key, like after the lesson notes were applied.
      final block = LessonBlock([p!.withUserNote(noteKey: 'k')]);
      final actions = <(LessonBlock, RoomAction)>[];
      LessonBlock? exam;
      Future<void> pump({bool teacher = true, DateTime? now}) => t.pumpWidget(
        ProviderScope(
          overrides: [
            teacherToolsClockProvider.overrideWithValue(
              () => now ?? DateTime(2026, 11, 10, 7),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: LessonDetailsSheet(
                blocks: [block],
                names: demoSchoolNames(),
                onRoomAction: teacher ? (b, a) => actions.add((b, a)) : null,
                onCreateExam: teacher ? (b) => exam = b : null,
              ),
            ),
          ),
        ),
      );
      await pump(teacher: false);
      expect(find.byKey(const ValueKey('details-book-room')), findsNothing);
      expect(find.byKey(const ValueKey('room-add')), findsNothing);
      expect(find.byKey(const ValueKey('lesson-exam-create')), findsNothing);
      expect(find.byKey(const ValueKey('lesson-exam-add')), findsOneWidget);

      await pump();
      // The old separate button is gone: the room row has the actions.
      expect(find.byKey(const ValueKey('details-book-room')), findsNothing);
      expect(find.byKey(const ValueKey('lesson-exam-add')), findsNothing);
      await t.tap(find.byKey(const ValueKey('room-replace-31')));
      await t.tap(find.byKey(const ValueKey('room-remove-31')));
      await t.tap(find.byKey(const ValueKey('room-add')));
      expect(
        [for (final a in actions) (a.$2.kind, a.$2.room?.id)],
        [
          (RoomEditKind.replace, 31),
          (RoomEditKind.remove, 31),
          (RoomEditKind.add, null),
        ],
      );
      expect(actions.first.$1, same(block));
      await t.tap(find.byKey(const ValueKey('lesson-exam-create')));
      expect(exam, same(block));

      // Once the lesson has started, rooms can't change.
      await t.pumpWidget(const SizedBox());
      await pump(now: DateTime(2026, 11, 10, 9, 45));
      expect(find.byKey(const ValueKey('room-add')), findsNothing);
      expect(find.byKey(const ValueKey('room-replace-31')), findsNothing);
      expect(
        find.byKey(const ValueKey('details-rooms-locked')),
        findsOneWidget,
      );
    });

    testWidgets('lesson sheet: teachers add details on the server', (t) async {
      final p = await t.runAsync(() => maths(api));
      final block = LessonBlock([p!.withUserNote(noteKey: 'k')]);
      LessonBlock? edited;
      Future<void> pump({bool teacher = true}) => t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: LessonDetailsSheet(
                blocks: [block],
                names: demoSchoolNames(),
                onEditLessonInfo: teacher ? (b) => edited = b : null,
              ),
            ),
          ),
        ),
      );
      await pump(teacher: false);
      expect(find.byKey(const ValueKey('lesson-details-edit')), findsOneWidget);
      expect(find.byKey(const ValueKey('lesson-info-edit')), findsNothing);
      await pump();
      expect(find.byKey(const ValueKey('lesson-details-edit')), findsNothing);
      await t.tap(find.byKey(const ValueKey('lesson-info-edit')));
      expect(edited, same(block));
    });

    Future<String?> openBooking(
      WidgetTester t,
      Period p, {
      bool add = false,
    }) async {
      String? result;
      await t.pumpWidget(
        app(
          Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await openRoomBooking(
                  c,
                  account: teacherAccount(),
                  periods: [p],
                  title: 'Mathematik',
                  subtitle: 'Tue 10 Nov',
                  replacing: add ? null : bookableRoomOf(p),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      return result;
    }

    testWidgets('room booking: search, book, pops with the answer', (t) async {
      final p = (await t.runAsync(() => maths(api)))!;
      String? result;
      await t.pumpWidget(
        app(
          Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await openRoomBooking(
                  c,
                  account: teacherAccount(),
                  periods: [p],
                  title: 'Mathematik',
                  subtitle: 'Tue 10 Nov',
                  replacing: bookableRoomOf(p),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Room: Raum 101'), findsOneWidget);
      expect(find.byKey(const ValueKey('freeroom-34')), findsOneWidget);
      expect(find.byKey(const ValueKey('freeroom-31')), findsNothing);

      await t.enterText(find.byKey(const ValueKey('freeroom-search')), 'info');
      await t.pump();
      expect(find.byKey(const ValueKey('freeroom-35')), findsNothing);
      expect(find.byKey(const ValueKey('freeroom-34')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('freeroom-34')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('roombook-confirm')));
      await t.pumpAndSettle();
      expect(result, contains('Informatikraum'));
      expect(api.roomChanges[p.id], 34);
      expect(api.roomChangeCalls.single.orgRoomId, 31);
    });

    testWidgets('room booking: a changed room goes back via replace', (
      t,
    ) async {
      api.roomChanges[202611102] = 34;
      final p = (await t.runAsync(() => maths(api)))!;
      await openBooking(t, p);
      expect(
        find.text('Room: Informatikraum (planned: Raum 101)'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('roombook-back')), findsNothing);
      // The planned room is free again and listed first.
      expect(find.textContaining('Planned room'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('freeroom-31')));
      await t.pumpAndSettle();
      expect(
        find.text('Replace Informatikraum with Raum 101?'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('roombook-confirm')));
      await t.pumpAndSettle();
      expect(api.roomChanges, isEmpty);
      // The fix: orgRoomId is the current room, not the planned one.
      expect(api.roomChangeCalls.single.orgRoomId, 34);
      expect(api.roomChangeCalls.single.roomId, 31);
    });

    testWidgets('room booking: add a room (orgRoomId 0)', (t) async {
      final p = (await t.runAsync(() => maths(api)))!;
      await openBooking(t, p, add: true);
      expect(find.byKey(const ValueKey('roombook-adding')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('freeroom-35')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('roombook-confirm')));
      await t.pumpAndSettle();
      final c = api.roomChangeCalls.single;
      expect((c.orgRoomId, c.roomId), (0, 35));
      final now = (await t.runAsync(() => maths(api)))!;
      expect([for (final r in currentRoomsOf(now)) r.id], [31, 35]);
    });

    testWidgets('room booking: server errors are shown', (t) async {
      tall(t);
      api = RejectingRoomApi();
      final p = (await t.runAsync(() => maths(api)))!;
      final result = await openBooking(t, p);
      await t.tap(find.byKey(const ValueKey('freeroom-36')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('roombook-confirm')));
      await t.pumpAndSettle();
      expect(result, isNull);
      expect(find.byKey(const ValueKey('roombook-error')), findsOneWidget);
      expect(find.textContaining('No right: Ask the office'), findsOneWidget);
      expect(find.byType(RoomBookingScreen), findsOneWidget);
    });

    testWidgets('exam editor from a lesson: prefilled, two periods, room', (
      t,
    ) async {
      tall(t);
      final p = (await t.runAsync(() => maths(api)))!;
      bool? created;
      await t.pumpWidget(
        app(
          Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () async => created = await openExamEditor(
                  c,
                  account: teacherAccount(),
                  periods: [p],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Mathematik'), findsOneWidget);
      expect(find.text('09:40 – 10:25'), findsOneWidget);
      expect(find.text('Raum 101'), findsOneWidget);
      // Send needs a name or a type.
      final send = find.byKey(const ValueKey('exam-send'));
      expect(t.widget<FilledButton>(send).onPressed, isNull);

      await t.tap(find.byKey(const ValueKey('exam-type')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('exam-type-1')).last);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('exam-name')), 'Fractions');
      // Extend to the next period.
      await t.tap(find.byKey(const ValueKey('exam-unit-3')));
      await t.pump();
      expect(find.text('09:40 – 11:15 · 2 periods'), findsOneWidget);

      await t.ensureVisible(find.byKey(const ValueKey('exam-room')));
      await t.tap(find.byKey(const ValueKey('exam-room')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('freeroom-34')));
      await t.pumpAndSettle();
      expect(find.text('Informatikraum'), findsOneWidget);

      await t.ensureVisible(send);
      await t.tap(send);
      await t.pumpAndSettle();
      expect(created, isTrue);
      final e = api.createExamCalls.single;
      expect(e.examTypeId, 1);
      expect(e.examType, 'Schularbeit');
      expect(e.name, 'Fractions');
      expect(e.start, DateTime(2026, 11, 10, 9, 40));
      expect(e.end, DateTime(2026, 11, 10, 11, 15));
      expect(e.roomIds, [34]);
      expect(e.klasseIds, [1]);
      expect(e.subjectId, 21);
      expect(e.teacherIds, [11]);
      expect(e.periodIds, [p.id]);
      // The demo timetable shows it.
      final day = (await t.runAsync(() => ownDay(api, tuesday)))!;
      expect(day.firstWhere((x) => x.id == p.id).exam?.name, 'Fractions');
    });

    testWidgets('exam editor from the menu: subject, class, periods', (
      t,
    ) async {
      tall(t);
      await t.pumpWidget(app(ExamEditorScreen(account: teacherAccount())));
      await t.pumpAndSettle();
      // Pick Tuesday (the clock of the test repo is not used by the date
      // default; set it through the date picker's text input).
      await t.tap(find.byKey(const ValueKey('exam-date')));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.edit_outlined));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, '11/10/2026');
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('exam-subject')));
      await t.pumpAndSettle();
      // Only own subjects: Mathematik and Physik, not Deutsch.
      expect(find.byKey(const ValueKey('exam-subject-22')), findsNothing);
      await t.tap(find.byKey(const ValueKey('exam-subject-21')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilterChip>(find.byKey(const ValueKey('exam-class-1')))
            .selected,
        isTrue,
      );
      // Tuesday's maths lesson is unit 3 (index 2).
      expect(find.text('09:40 – 10:25'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('exam-type')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('exam-type-2')).last);
      await t.pumpAndSettle();
      final send = find.byKey(const ValueKey('exam-send'));
      await t.ensureVisible(send);
      await t.tap(send);
      await t.pumpAndSettle();
      final e = api.createExamCalls.single;
      expect(e.examType, 'Test');
      expect(e.start, DateTime(2026, 11, 10, 9, 40));
      expect(e.periodIds, [202611102]);
      expect(e.lessonId, 21);
    });

    testWidgets('exam editor: the server error stays visible', (t) async {
      tall(t);
      final fake = FailingExamApi();
      final p = (await t.runAsync(() => maths(fake)))!;
      await t.pumpWidget(
        app(
          ExamEditorScreen(account: teacherAccount(), periods: [p]),
          fake: fake,
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('exam-name')), 'X');
      await t.pump();
      final send = find.byKey(const ValueKey('exam-send'));
      await t.ensureVisible(send);
      await t.tap(send);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('exam-error')), findsOneWidget);
      expect(find.textContaining('HTTP 404'), findsOneWidget);
      expect(find.byType(ExamEditorScreen), findsOneWidget);
    });

    for (final scale in [2.0, 2.5]) {
      testWidgets('large text ${scale * 100} %: nothing overflows', (t) async {
        t.view.physicalSize = const Size(360, 740);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final p = (await t.runAsync(() => maths(api)))!;
        await t.pumpWidget(
          app(
            ExamEditorScreen(account: teacherAccount(), periods: [p]),
            textScale: scale,
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(
          find.byKey(const ValueKey('exam-send')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(t.takeException(), isNull);

        await t.pumpWidget(
          app(
            RoomBookingScreen(
              account: teacherAccount(),
              periods: [p],
              title: 'Mathematik',
              subtitle: 'Tue 10 Nov · 09:40 – 10:25 · 9b',
            ),
            textScale: scale,
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(
          find.byKey(const ValueKey('freeroom-34')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(t.takeException(), isNull);
      });
    }
  });

  group('exam menu', () {
    Future<void> pump(WidgetTester t, Account account) async {
      tall(t);
      final api = FakeUntisApi(latency: Duration.zero);
      final accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            accountRepositoryProvider.overrideWithValue(accounts),
            activeAccountProvider.overrideWith((ref) => Stream.value(account)),
            infoCenterRepositoryProvider.overrideWithValue(
              FakeInfoCenterRepository(),
            ),
            nameResolverProvider.overrideWith(
              (ref) => Stream.value(demoSchoolNames()),
            ),
            teacherToolsRepositoryProvider.overrideWithValue(
              TeacherToolsRepositoryImpl(
                api: api,
                accounts: accounts,
                timetables: ApiTimetables(api),
              ),
            ),
          ],
          child: const MaterialApp(home: TeacherExamsScreen()),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('teachers: exam list and "New exam"', (t) async {
      await pump(t, teacherAccount());
      expect(find.text('Upcoming'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('exams-new')));
      await t.pumpAndSettle();
      expect(find.byType(ExamEditorScreen), findsOneWidget);
      expect(find.text('Choose a subject'), findsOneWidget);
    });

    testWidgets('others: a hint, no button', (t) async {
      await pump(t, demoAccount());
      expect(find.byKey(const ValueKey('exams-new')), findsNothing);
      expect(
        find.text('Only teacher accounts can create exams.'),
        findsOneWidget,
      );
    });
  });
}
