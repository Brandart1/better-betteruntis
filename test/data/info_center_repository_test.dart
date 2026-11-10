import 'package:better_betteruntis/core/absence_details.dart';
import 'package:better_betteruntis/core/info.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/data/account_repository_impl.dart';
import 'package:better_betteruntis/data/db/database.dart';
import 'package:better_betteruntis/data/info_center_repository_impl.dart';
import 'package:better_betteruntis/data/master_data_store.dart';
import 'package:better_betteruntis/data/period_codec.dart';
import 'package:better_betteruntis/data/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockApi extends Mock implements FullUntisApi {}

/// Only the contract interfaces, no [AbsenceDetailsApi].
class MockPlainApi extends Mock implements UntisApi, InfoCenterApi {}

void main() {
  late AppDatabase db;
  late MockApi api;
  late AccountRepositoryImpl accounts;
  late InfoCenterRepositoryImpl repo;
  late DateTime now;
  late Account acc;
  final start = DateTime(2026, 11, 9);
  final end = DateTime(2026, 11, 22);

  setUpAll(() {
    registerFallbackValue(const UntisCredentials.anonymous());
    registerFallbackValue(const TimetableTarget(ElementType.student, 0));
    registerFallbackValue(DateTime(2000));
  });

  setUp(() async {
    db = memoryDb();
    api = MockApi();
    now = DateTime(2026, 11, 10, 12);
    accounts = AccountRepositoryImpl(db, MemorySecretStore());
    repo = InfoCenterRepositoryImpl(
      api: api,
      db: db,
      accounts: accounts,
      clock: () => now,
    );
    acc = await accounts.add(account('a'), 'secret', masterData());
  });
  tearDown(() => db.close());

  HomeworkItem hw(int id, [String text = 'Exercise']) => HomeworkItem(
    id: id,
    lessonId: 55,
    assignedOn: start,
    dueOn: DateTime(2026, 11, 12),
    text: text,
    subjectId: 21,
    teacherIds: const [11],
    attachments: const [(name: 'a.pdf', url: 'https://x.invalid/a')],
  );

  When<Future<List<HomeworkItem>>> whenHomework() => when(
    () => api.homework(
      host: any(named: 'host'),
      school: any(named: 'school'),
      auth: any(named: 'auth'),
      target: any(named: 'target'),
      start: any(named: 'start'),
      end: any(named: 'end'),
    ),
  );

  Future<List<Cached<List<HomeworkItem>>>> homework({bool force = false}) =>
      repo.homework(acc, start, end, force: force).toList();

  test('first load: empty refreshing, then fresh data (own target)', () async {
    whenHomework().thenAnswer((_) async => [hw(1)]);
    final events = await homework();
    expect(events, hasLength(2));
    expect(events[0].data, isNull);
    expect(events[0].refreshing, isTrue);
    expect(events[1].refreshing, isFalse);
    expect(events[1].data!.single.text, 'Exercise');
    expect(events[1].data!.single.attachments.single.name, 'a.pdf');
    expect(events[1].fetchedAt, now);
    verify(
      () => api.homework(
        host: 'demo.webuntis.com',
        school: 'demo-school',
        auth: any(named: 'auth'),
        target: const TimetableTarget(ElementType.student, 7),
        start: start,
        end: end,
      ),
    ).called(1);
  });

  test('within 10 min: cache only, no request; force refreshes', () async {
    whenHomework().thenAnswer((_) async => [hw(1)]);
    await homework();
    now = now.add(const Duration(minutes: 9));
    final cachedOnly = await homework();
    expect(cachedOnly, hasLength(1));
    expect(cachedOnly.single.refreshing, isFalse);
    expect(cachedOnly.single.data!.single.id, 1);
    verify(
      () => api.homework(
        host: any(named: 'host'),
        school: any(named: 'school'),
        auth: any(named: 'auth'),
        target: any(named: 'target'),
        start: any(named: 'start'),
        end: any(named: 'end'),
      ),
    ).called(1);

    whenHomework().thenAnswer((_) async => [hw(2, 'New')]);
    final forced = await homework(force: true);
    expect(forced.map((e) => e.refreshing), [true, false]);
    expect(forced[0].data!.single.id, 1); // cached first
    expect(forced[1].data!.single.text, 'New');
  });

  test('stale cache refreshes in the background', () async {
    whenHomework().thenAnswer((_) async => [hw(1)]);
    await homework();
    final firstAt = now;
    now = now.add(const Duration(minutes: 11));
    whenHomework().thenAnswer((_) async => [hw(2)]);
    final events = await homework();
    expect(events[0].data!.single.id, 1);
    expect(events[0].fetchedAt, firstAt);
    expect(events[0].refreshing, isTrue);
    expect(events[1].data!.single.id, 2);
    expect(events[1].fetchedAt, now);
  });

  test('error keeps the cached data and wraps non-Untis errors', () async {
    whenHomework().thenAnswer((_) async => [hw(1)]);
    await homework();
    whenHomework().thenThrow(StateError('boom'));
    final events = await homework(force: true);
    expect(events.last.data!.single.id, 1);
    expect(events.last.error!.code, -1);
    expect(events.last.refreshing, isFalse);

    whenHomework().thenThrow(const UntisException(0, 'offline'));
    final again = await homework(force: true);
    expect(again.last.error!.isNetwork, isTrue);
    expect(again.last.data, isNotNull);
  });

  test('error without cache: data null + error', () async {
    whenHomework().thenThrow(const UntisException(-8509, 'no right'));
    final events = await homework();
    expect(events.last.data, isNull);
    expect(events.last.error!.code, UntisException.noRight);
  });

  test('anonymous: empty homework/absences/inbox without requests', () async {
    final anon = await accounts.add(
      account('anon', anonymous: true),
      '',
      masterData(),
    );
    final h = await repo.homework(anon, start, end).toList();
    final a = await repo.absences(anon, start, end).toList();
    final i = await repo.inbox(anon).toList();
    for (final e in [h.single, a.single, i.single]) {
      expect(e.data, isEmpty);
      expect(e.error, isNull);
    }
    verifyZeroInteractions(api);
  });

  When<Future<List<OfficeHourItem>>> whenOfficeHours() => when(
    () => api.officeHours(
      host: any(named: 'host'),
      school: any(named: 'school'),
      auth: any(named: 'auth'),
      klasseId: any(named: 'klasseId'),
      start: any(named: 'start'),
    ),
  );

  List<int> officeHourKlassen() => verify(
    () => api.officeHours(
      host: any(named: 'host'),
      school: any(named: 'school'),
      auth: any(named: 'auth'),
      klasseId: captureAny(named: 'klasseId'),
      start: start,
    ),
  ).captured.cast<int>();

  final oneOfficeHour = [
    OfficeHourItem(
      id: 1,
      start: DateTime(2026, 11, 11, 10),
      end: DateTime(2026, 11, 11, 10, 45),
      teacherName: 'Erika Beispiel',
      registered: true,
    ),
  ];

  test('office hours default to all teachers (-1)', () async {
    whenOfficeHours().thenAnswer((_) async => oneOfficeHour);
    final events = await repo.officeHours(acc, start).toList();
    expect(events.last.data, hasLength(1));
    expect(officeHourKlassen(), [-1]);
  });

  test('office hours use the first class', () async {
    whenOfficeHours().thenAnswer((_) async => oneOfficeHour);
    final events = await repo
        .officeHours(acc, start, onlyMyClass: true)
        .toList();
    expect(events.last.data!.single.teacherName, 'Erika Beispiel');
    expect(events.last.data!.single.registered, isTrue);
    expect(officeHourKlassen(), [1]);
  });

  test('empty for the class -> retried once with -1', () async {
    whenOfficeHours().thenAnswer(
      (i) async => i.namedArguments[#klasseId] == -1 ? oneOfficeHour : [],
    );
    final events = await repo
        .officeHours(acc, start, onlyMyClass: true)
        .toList();
    expect(events.last.data, hasLength(1));
    expect(officeHourKlassen(), [1, -1]);
  });

  test('student without klassenIds still requests office hours', () async {
    whenOfficeHours().thenAnswer((_) async => oneOfficeHour);
    final noClass = await accounts.add(
      Account(
        id: 'nc',
        school: acc.school,
        username: 'u',
        anonymous: false,
        displayName: 'x',
        elementType: ElementType.student,
        elementId: 7,
      ),
      's',
      masterData(),
    );
    final events = await repo
        .officeHours(noClass, start, onlyMyClass: true)
        .toList();
    expect(events.last.data, hasLength(1));
    expect(officeHourKlassen(), [-1], reason: 'nothing cached: all classes');
  });

  test('student without klassenIds: class from the cached timetable', () async {
    whenOfficeHours().thenAnswer((_) async => oneOfficeHour);
    final noClass = await accounts.add(
      Account(
        id: 'nc',
        school: acc.school,
        username: 'u',
        anonymous: false,
        displayName: 'x',
        elementType: ElementType.student,
        elementId: 7,
      ),
      's',
      masterData(),
    );
    Period p(int id, int klasse) => Period(
      id: id,
      lessonId: id,
      start: DateTime(2026, 11, 9, 8),
      end: DateTime(2026, 11, 9, 9),
      elements: [
        ElementRef(type: ElementType.klasse, id: klasse, orgId: klasse),
      ],
      flags: const {PeriodFlag.regular},
    );
    await db
        .into(db.cachedWeeks)
        .insert(
          CachedWeeksCompanion.insert(
            accountId: 'nc',
            targetType: 'STUDENT',
            targetId: 7,
            weekStart: '2026-11-09',
            periodsJson: PeriodCodec.encodeList([p(1, 5), p(2, 5), p(3, 6)]),
            fetchedAt: 1,
          ),
        );
    await repo.officeHours(noClass, start, onlyMyClass: true).toList();
    expect(officeHourKlassen(), [5]);
  });

  group('parent accounts', () {
    late Account parent;
    setUp(() async {
      parent = await accounts.add(
        Account(
          id: 'p',
          school: acc.school,
          username: 'parent',
          anonymous: false,
          displayName: 'Parent',
          elementType: ElementType.unknown,
          elementId: 900,
          children: const [
            AccountChild(id: 11, displayName: 'Child A', klasseId: 3),
            AccountChild(id: 12, displayName: 'Child B'),
          ],
        ),
        's',
        masterData(),
      );
    });

    test('homework and exams use the selected child', () async {
      whenHomework().thenAnswer((_) async => []);
      when(
        () => api.exams(
          host: any(named: 'host'),
          school: any(named: 'school'),
          auth: any(named: 'auth'),
          target: any(named: 'target'),
          start: any(named: 'start'),
          end: any(named: 'end'),
        ),
      ).thenAnswer((_) async => []);
      await repo.homework(parent, start, end).toList();
      await repo
          .exams(parent.copyWith(selectedChildId: 12), start, end)
          .toList();
      final hwTarget = verify(
        () => api.homework(
          host: any(named: 'host'),
          school: any(named: 'school'),
          auth: any(named: 'auth'),
          target: captureAny(named: 'target'),
          start: any(named: 'start'),
          end: any(named: 'end'),
        ),
      ).captured.single;
      expect(hwTarget, const TimetableTarget(ElementType.student, 11));
      final examTarget = verify(
        () => api.exams(
          host: any(named: 'host'),
          school: any(named: 'school'),
          auth: any(named: 'auth'),
          target: captureAny(named: 'target'),
          start: any(named: 'start'),
          end: any(named: 'end'),
        ),
      ).captured.single;
      expect(examTarget, const TimetableTarget(ElementType.student, 12));
    });

    test('absences pass the child id', () async {
      when(
        () => api.rawAbsences(
          host: any(named: 'host'),
          school: any(named: 'school'),
          auth: any(named: 'auth'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          studentId: any(named: 'studentId'),
        ),
      ).thenAnswer((_) async => []);
      await repo.absences(parent, start, end).toList();
      final id = verify(
        () => api.rawAbsences(
          host: any(named: 'host'),
          school: any(named: 'school'),
          auth: any(named: 'auth'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          studentId: captureAny(named: 'studentId'),
        ),
      ).captured.single;
      expect(id, 11);
    });

    test("office hours use the child's class, else -1", () async {
      whenOfficeHours().thenAnswer((_) async => oneOfficeHour);
      await repo.officeHours(parent, start, onlyMyClass: true).toList();
      expect(officeHourKlassen(), [3]);
      await repo
          .officeHours(
            parent.copyWith(selectedChildId: 12),
            start,
            onlyMyClass: true,
          )
          .toList();
      expect(officeHourKlassen(), [-1]);
    });

    test('no children: homework/exams empty without requests', () async {
      final none = await accounts.add(
        Account(
          id: 'p0',
          school: acc.school,
          username: 'parent0',
          anonymous: false,
          displayName: 'Parent',
          elementType: ElementType.unknown,
        ),
        's',
        masterData(),
      );
      expect(
        (await repo.homework(none, start, end).toList()).single.data,
        isEmpty,
      );
      expect(
        (await repo.exams(none, start, end).toList()).single.data,
        isEmpty,
      );
      verifyZeroInteractions(api);
    });
  });

  group('absences', () {
    final rawItems = [
      RawAbsence(
        id: 1,
        start: DateTime(2026, 10, 1, 8),
        end: DateTime(2026, 10, 1, 13),
        excused: true,
        reasonId: 1,
        excuseStatusId: 5,
      ),
      RawAbsence(
        id: 2,
        start: DateTime(2026, 9, 1, 8),
        end: DateTime(2026, 9, 1, 9),
        excused: false,
        reasonId: 1,
        inlineReason: 'Inline reason',
      ),
    ];

    void whenRaw() => when(
      () => api.rawAbsences(
        host: any(named: 'host'),
        school: any(named: 'school'),
        auth: any(named: 'auth'),
        start: any(named: 'start'),
        end: any(named: 'end'),
      ),
    ).thenAnswer((_) async => rawItems);

    When<Future<AbsenceLookups>> whenLookups() => when(
      () => api.absenceLookups(
        host: any(named: 'host'),
        school: any(named: 'school'),
        auth: any(named: 'auth'),
      ),
    );

    test('resolved from lookups persisted at login', () async {
      final withLookups = await accounts.add(
        account('b'),
        'secret',
        const MasterDataWithLookups(
          timestamp: 1,
          lookups: AbsenceLookups(
            reasons: {1: 'Illness'},
            statuses: {5: 'excused'},
          ),
        ),
      );
      whenRaw();
      final events = await repo.absences(withLookups, start, end).toList();
      final items = events.last.data!;
      expect(items[0].reason, 'Illness');
      expect(items[0].excuseStatus, 'excused');
      expect(items[1].reason, 'Inline reason');
      verifyNever(
        () => api.absenceLookups(
          host: any(named: 'host'),
          school: any(named: 'school'),
          auth: any(named: 'auth'),
        ),
      );
    });

    test('missing lookups are loaded once and persisted', () async {
      whenRaw();
      whenLookups().thenAnswer(
        (_) async => const AbsenceLookups(
          reasons: {1: 'Illness'},
          statuses: {5: 'excused'},
        ),
      );
      final events = await repo.absences(acc, start, end).toList();
      expect(events.last.data!.first.reason, 'Illness');
      expect(events.last.data!.first.excuseStatus, 'excused');
      final rows = await db.select(db.absenceLookupEntries).get();
      expect(rows, hasLength(2));

      // A fresh repository (new session) finds them in the database.
      final repo2 = InfoCenterRepositoryImpl(
        api: api,
        db: db,
        accounts: accounts,
        clock: () => now,
      );
      final again = await repo2.absences(acc, start, end, force: true).toList();
      expect(again.last.data!.first.reason, 'Illness');
      verify(
        () => api.absenceLookups(
          host: any(named: 'host'),
          school: any(named: 'school'),
          auth: any(named: 'auth'),
        ),
      ).called(1);
    });

    test('lookup failure still shows absences without names', () async {
      whenRaw();
      whenLookups().thenThrow(const UntisException(-8509, 'no'));
      final events = await repo.absences(acc, start, end).toList();
      expect(events.last.error, isNull);
      expect(events.last.data!.first.reason, '');
      expect(events.last.data![1].reason, 'Inline reason');
    });

    test('APIs without AbsenceDetailsApi use the contract call', () async {
      final plain = MockPlainApi();
      when(
        () => plain.absences(
          host: any(named: 'host'),
          school: any(named: 'school'),
          auth: any(named: 'auth'),
          start: any(named: 'start'),
          end: any(named: 'end'),
        ),
      ).thenAnswer(
        (_) async => [
          AbsenceItem(
            id: 3,
            start: DateTime(2026, 10, 2),
            end: DateTime(2026, 10, 2, 1),
            excused: false,
            reason: 'R',
          ),
        ],
      );
      final r = InfoCenterRepositoryImpl(
        api: plain,
        db: db,
        accounts: accounts,
        clock: () => now,
      );
      final events = await r.absences(acc, start, end).toList();
      expect(events.last.data!.single.reason, 'R');
    });
  });

  test(
    'inbox + messagesOfDay are cached; inboxMessage falls back to cache',
    () async {
      when(
        () => api.inbox(
          host: any(named: 'host'),
          school: any(named: 'school'),
          auth: any(named: 'auth'),
        ),
      ).thenAnswer(
        (_) async => [
          InboxMessage(
            id: 1,
            subject: 'Trip',
            preview: 'Bring shoes',
            sender: 'Max Muster',
            sentAt: DateTime(2026, 11, 1, 8),
            isRead: true,
          ),
        ],
      );
      when(
        () => api.messagesOfDay(
          host: any(named: 'host'),
          school: any(named: 'school'),
          auth: any(named: 'auth'),
          date: any(named: 'date'),
        ),
      ).thenAnswer(
        (_) async => const [Message(id: 4, subject: 'Hello', bodyHtml: '<p/>')],
      );
      final inbox = await repo.inbox(acc).toList();
      expect(inbox.last.data!.single.sentAt, DateTime(2026, 11, 1, 8));
      expect(inbox.last.data!.single.isRead, isTrue);
      final cachedInbox = await repo.inbox(acc).toList();
      expect(cachedInbox.single.data!.single.sender, 'Max Muster');

      final mod = await repo
          .messagesOfDay(acc, DateTime(2026, 11, 10))
          .toList();
      expect(mod.last.data!.single.subject, 'Hello');

      var calls = 0;
      when(
        () => api.inboxMessage(
          host: any(named: 'host'),
          school: any(named: 'school'),
          auth: any(named: 'auth'),
          id: any(named: 'id'),
        ),
      ).thenAnswer((_) async {
        if (calls++ > 0) throw const UntisException(0, 'offline');
        return const InboxMessageDetail(
          id: 1,
          subject: 'Trip',
          bodyHtml: '<p>Hi</p>',
          sender: 'Max Muster',
          sentAt: null,
        );
      });
      expect((await repo.inboxMessage(acc, 1)).bodyHtml, '<p>Hi</p>');
      expect((await repo.inboxMessage(acc, 1)).bodyHtml, '<p>Hi</p>'); // cache
      await expectLater(
        repo.inboxMessage(acc, 2),
        throwsA(isA<UntisException>().having((e) => e.code, 'code', 0)),
      );
    },
  );

  test('account deletion removes its cache rows and lookups', () async {
    whenHomework().thenAnswer((_) async => [hw(1)]);
    final other = await accounts.add(
      account('b'),
      's',
      const MasterDataWithLookups(
        timestamp: 1,
        lookups: AbsenceLookups(reasons: {1: 'Illness'}),
      ),
    );
    await homework();
    await repo.homework(other, start, end).toList();
    expect(await db.select(db.infoCache).get(), hasLength(2));
    await accounts.delete('b');
    final rows = await db.select(db.infoCache).get();
    expect(rows.map((r) => r.accountId), ['a']);
    expect(await db.select(db.absenceLookupEntries).get(), isEmpty);
  });

  test('no cache row is written for an account deleted mid-fetch', () async {
    whenHomework().thenAnswer((_) async {
      await accounts.delete('a');
      return [hw(1)];
    });
    final events = await homework();
    expect(events.last.data, isNotNull);
    expect(await db.select(db.infoCache).get(), isEmpty);
  });

  test('master-data deltas upsert lookups', () async {
    final store = MasterDataStore(db);
    await store.upsertDelta(
      'a',
      const MasterDataWithLookups(
        timestamp: 1,
        lookups: AbsenceLookups(reasons: {1: 'Illness'}),
      ),
    );
    await store.upsertDelta(
      'a',
      const MasterDataWithLookups(
        timestamp: 2,
        lookups: AbsenceLookups(reasons: {2: 'Doctor'}, statuses: {5: 'ok'}),
      ),
    );
    await store.upsertDelta('a', masterData()); // plain MasterData: no-op
    final l = await store.loadLookups('a');
    expect(l.reasons, {1: 'Illness', 2: 'Doctor'});
    expect(l.statuses, {5: 'ok'});
  });
}
