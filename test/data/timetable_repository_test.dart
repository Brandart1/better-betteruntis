import 'dart:async';

import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/data/account_repository_impl.dart';
import 'package:better_betteruntis/data/db/database.dart';
import 'package:better_betteruntis/data/secret_store.dart';
import 'package:better_betteruntis/data/timetable_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockApi extends Mock implements UntisApi {}

void main() {
  late AppDatabase db;
  late MockApi api;
  late AccountRepositoryImpl accounts;
  late TimetableRepositoryImpl repo;
  late DateTime now;
  late Account acc;
  const target = TimetableTarget(ElementType.student, 7);
  final wednesday = DateTime(2026, 11, 11);
  final monday = DateTime(2026, 11, 9);

  setUpAll(() {
    registerFallbackValue(const UntisCredentials.anonymous());
    registerFallbackValue(target);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() async {
    db = memoryDb();
    api = MockApi();
    now = DateTime(2026, 11, 10, 12);
    accounts = AccountRepositoryImpl(db, MemorySecretStore());
    repo = TimetableRepositoryImpl(
      api: api,
      db: db,
      accounts: accounts,
      clock: () => now,
    );
    acc = await accounts.add(account('a'), 'secret', masterData(ts: 100));
  });
  tearDown(() => db.close());

  When<Future<TimetableResponse>> whenTimetable() => when(
    () => api.timetable(
      host: any(named: 'host'),
      school: any(named: 'school'),
      auth: any(named: 'auth'),
      target: any(named: 'target'),
      start: any(named: 'start'),
      end: any(named: 'end'),
      masterDataTimestamp: any(named: 'masterDataTimestamp'),
    ),
  );

  test('mondayOf normalizes', () {
    expect(mondayOf(DateTime(2026, 11, 15, 23)), monday);
    expect(mondayOf(monday), monday);
  });

  test(
    'refresh calls Mon..Sun, applies delta + timestamp, then caches',
    () async {
      final names = <NameResolver>[];
      final nameSub = repo.watchNames(acc).listen(names.add);
      whenTimetable().thenAnswer(
        (_) async => TimetableResponse(
          [
            period(
              1,
              elements: const [
                ElementRef(type: ElementType.teacher, id: 5, orgId: 5),
              ],
            ),
          ],
          MasterData(
            timestamp: 200,
            elements: [teacher(5, 'NEW'), teacher(1, 'MUE2')],
          ),
        ),
      );
      await repo.refresh(acc, target, wednesday);
      verify(
        () => api.timetable(
          host: any(named: 'host', that: equals('demo.webuntis.com')),
          school: any(named: 'school', that: equals('demo-school')),
          auth: any(named: 'auth'),
          target: any(named: 'target', that: equals(target)),
          start: any(named: 'start', that: equals(monday)),
          end: any(named: 'end', that: equals(DateTime(2026, 11, 15))),
          masterDataTimestamp: any(
            named: 'masterDataTimestamp',
            that: equals(100),
          ),
        ),
      ).called(1);
      expect((await accounts.get('a'))!.masterDataTimestamp, 200);
      expect(repo.lastRefreshed(acc, target, monday), now);

      await pumpEventQueue();
      final r = names.last;
      expect(
        r.shortName(
          const ElementRef(type: ElementType.teacher, id: 5, orgId: 5),
        ),
        'NEW',
      );
      expect(
        r.shortName(
          const ElementRef(type: ElementType.teacher, id: 1, orgId: 1),
        ),
        'MUE2',
      );
      // Not in the delta: still there (upsert, not replace).
      expect(
        r.shortName(
          const ElementRef(type: ElementType.teacher, id: 2, orgId: 2),
        ),
        'OLD',
      );
      await nameSub.cancel();

      // Next refresh uses the persisted timestamp even with a stale Account.
      await repo.refresh(acc, target, monday);
      verify(
        () => api.timetable(
          host: any(named: 'host'),
          school: any(named: 'school'),
          auth: any(named: 'auth'),
          target: any(named: 'target'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          masterDataTimestamp: any(
            named: 'masterDataTimestamp',
            that: equals(200),
          ),
        ),
      ).called(1);
    },
  );

  test('cache-first, then background refresh emits new data', () async {
    whenTimetable().thenAnswer(
      (_) async => TimetableResponse([period(1)], null),
    );
    await repo.refresh(acc, target, monday);

    now = now.add(const Duration(minutes: 10)); // stale
    final refreshed = Completer<TimetableResponse>();
    whenTimetable().thenAnswer((_) => refreshed.future);

    final events = <List<int>>[];
    final sub = repo
        .watchWeek(acc, target, wednesday)
        .listen((ps) => events.add([for (final p in ps) p.id]));
    await pumpEventQueue();
    expect(events, [
      [1],
    ]);

    refreshed.complete(TimetableResponse([period(1), period(2)], null));
    await pumpEventQueue();
    expect(events.last, [1, 2]);
    expect(repo.lastRefreshed(acc, target, monday), now);
    await sub.cancel();
  });

  test('fresh cache does not hit the network', () async {
    whenTimetable().thenAnswer(
      (_) async => TimetableResponse([period(1)], null),
    );
    await repo.refresh(acc, target, monday);
    clearInteractions(api);
    now = now.add(const Duration(minutes: 1));
    final first = await repo.watchWeek(acc, target, monday).first;
    expect(first.single.id, 1);
    await pumpEventQueue();
    verifyNever(
      () => api.timetable(
        host: any(named: 'host'),
        school: any(named: 'school'),
        auth: any(named: 'auth'),
        target: any(named: 'target'),
        start: any(named: 'start'),
        end: any(named: 'end'),
        masterDataTimestamp: any(named: 'masterDataTimestamp'),
      ),
    );
  });

  test('refresh failure with cache keeps the stream alive', () async {
    whenTimetable().thenAnswer(
      (_) async => TimetableResponse([period(1)], null),
    );
    await repo.refresh(acc, target, monday);
    now = now.add(const Duration(hours: 1));
    whenTimetable().thenThrow(const UntisException(0, 'offline'));

    final errors = <UntisException?>[];
    final errSub = repo.errors.listen(errors.add);
    final events = <List<Period>>[];
    final streamErrors = <Object>[];
    final sub = repo
        .watchWeek(acc, target, monday)
        .listen(events.add, onError: streamErrors.add);
    await pumpEventQueue();

    expect(events, hasLength(1));
    expect(streamErrors, isEmpty);
    expect(errors.single!.isNetwork, isTrue);
    expect(repo.lastError, isNotNull);

    // Later successful refresh still reaches the open stream.
    whenTimetable().thenAnswer(
      (_) async => TimetableResponse([period(3)], null),
    );
    await repo.refresh(acc, target, monday);
    await pumpEventQueue();
    expect(events.last.single.id, 3);
    await sub.cancel();
    await errSub.cancel();
  });

  test('refresh failure without cache errors the stream', () async {
    whenTimetable().thenThrow(StateError('boom'));
    final streamErrors = <Object>[];
    final sub = repo
        .watchWeek(acc, target, monday)
        .listen((_) {}, onError: streamErrors.add);
    await pumpEventQueue();
    expect(streamErrors.single, isA<UntisException>());
    await sub.cancel();
  });

  test('deleting an account removes its cache', () async {
    whenTimetable().thenAnswer(
      (_) async => TimetableResponse([period(1)], null),
    );
    await repo.refresh(acc, target, monday);
    await accounts.delete('a');
    expect(await repo.loadLastRefreshed(acc, target, monday), isNull);
  });
}
