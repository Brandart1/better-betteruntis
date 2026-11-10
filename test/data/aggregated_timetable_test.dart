import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/data/account_repository_impl.dart';
import 'package:better_betteruntis/data/aggregated_timetable.dart';
import 'package:better_betteruntis/data/db/database.dart';
import 'package:better_betteruntis/data/master_data_store.dart';
import 'package:better_betteruntis/data/secret_store.dart';
import 'package:better_betteruntis/data/timetable_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Hand-written API fake: counts calls per target and tracks concurrency.
class CountingApi implements UntisApi {
  CountingApi(this.handler);

  Future<TimetableResponse> Function(TimetableTarget target) handler;
  final calls = <TimetableTarget>[];
  Duration delay = Duration.zero;
  int inFlight = 0;
  int maxInFlight = 0;

  int callsOf(ElementType t) => calls.where((c) => c.type == t).length;

  @override
  Future<TimetableResponse> timetable({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
    required int masterDataTimestamp,
  }) async {
    calls.add(target);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      await Future<void>.delayed(delay);
      return await handler(target);
    } finally {
      inFlight--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const tABC = -5;
const tXYZ = -6;
const tDEF = -7;

ElementRef cls(int id) => ElementRef(type: ElementType.klasse, id: id, orgId: id);
ElementRef room(int id) => ElementRef(type: ElementType.room, id: id, orgId: id);
ElementRef named(int id, String s) => ElementRef(
  type: ElementType.teacher,
  id: id,
  orgId: id,
  inlineName: s,
  inlineLongName: '$s long',
);

Period at(int id, int hour, List<ElementRef> elements) => Period(
  id: id,
  lessonId: id,
  start: DateTime(2026, 11, 9, hour),
  end: DateTime(2026, 11, 9, hour, 45),
  elements: elements,
  flags: const {PeriodFlag.regular},
);

/// Class weeks: period 100 is shared by classes 1 and 2.
Map<int, List<Period>> classWeeks() => {
  1: [
    at(100, 9, [cls(1), named(tABC, 'ABC'), room(50)]),
    at(101, 10, [
      cls(1),
      const ElementRef(
        type: ElementType.teacher,
        id: tXYZ,
        orgId: tABC,
        inlineName: 'XYZ',
        inlineLongName: 'Xavier',
        orgInlineName: 'ABC',
        orgInlineLongName: 'ABC long',
      ),
      room(51),
    ]),
  ],
  2: [
    at(100, 9, [cls(2), named(tABC, 'ABC'), room(50)]),
  ],
  3: [
    at(102, 8, [cls(3), named(tDEF, 'DEF'), room(50)]),
  ],
};

MasterData schoolMaster({int classes = 3}) => MasterData(
  timestamp: 100,
  elements: [
    for (var i = 1; i <= classes; i++)
      MasterElement(
        type: ElementType.klasse,
        id: i,
        name: '${i}a',
        longName: 'Class ${i}a',
      ),
    const MasterElement(type: ElementType.room, id: 50, name: 'R50', longName: 'Room 50'),
    const MasterElement(type: ElementType.room, id: 51, name: 'R51', longName: 'Room 51'),
  ],
);

void main() {
  late AppDatabase db;
  late CountingApi api;
  late AccountRepositoryImpl accounts;
  late TimetableRepositoryImpl repo;
  late DateTime now;
  late Account acc;
  final monday = DateTime(2026, 11, 9);
  const noRight = UntisException(UntisException.noRight, 'no right');

  Future<TimetableResponse> school(TimetableTarget t) async {
    if (t.type != ElementType.klasse) throw noRight;
    return TimetableResponse(classWeeks()[t.id] ?? const [], null);
  }

  Future<void> setUpRepo({int classes = 3}) async {
    db = memoryDb();
    api = CountingApi(school);
    now = DateTime(2026, 11, 10, 12);
    accounts = AccountRepositoryImpl(db, MemorySecretStore());
    repo = TimetableRepositoryImpl(
      api: api,
      db: db,
      accounts: accounts,
      clock: () => now,
    );
    acc = await accounts.add(account('a'), 'secret', schoolMaster(classes: classes));
  }

  tearDown(() => db.close());

  Future<List<Period>> week(TimetableTarget t) async {
    await repo.refresh(acc, t, monday);
    return repo.watchWeek(acc, t, monday).first;
  }

  group('with three classes', () {
    setUp(() => setUpRepo());

    test('room: direct noRight falls back to class aggregation', () async {
      final ps = await week(const TimetableTarget(ElementType.room, 50));
      expect([for (final p in ps) p.id], [102, 100]); // sorted by start
      expect(api.callsOf(ElementType.room), 1);
      expect(api.callsOf(ElementType.klasse), 3);
      expect(repo.directAccessDenied(acc, ElementType.room), isTrue);
    });

    test('teacher: matches substitutions via orgId, never asks directly '
        'for synthetic ids', () async {
      final ps = await week(const TimetableTarget(ElementType.teacher, tABC));
      expect([for (final p in ps) p.id], [100, 101]);
      expect(api.callsOf(ElementType.teacher), 0);

      final xyz = await week(const TimetableTarget(ElementType.teacher, tXYZ));
      expect([for (final p in xyz) p.id], [101]);
    });

    test('dedupe merges the classes of a shared period', () async {
      final ps = await week(const TimetableTarget(ElementType.teacher, tABC));
      final shared = ps.firstWhere((p) => p.id == 100);
      expect(
        [for (final e in shared.ofType(ElementType.klasse)) e.id]..sort(),
        [1, 2],
      );
      expect(shared.ofType(ElementType.teacher), hasLength(1));
      expect(shared.ofType(ElementType.room), hasLength(1));
    });

    test('partial class failure still returns results', () async {
      api.handler = (t) async {
        if (t.type == ElementType.klasse && t.id == 2) {
          throw const UntisException(0, 'offline');
        }
        return school(t);
      };
      final ps = await week(const TimetableTarget(ElementType.room, 50));
      expect([for (final p in ps) p.id], [102, 100]);
      final scan = repo.lastScan(acc, monday)!;
      expect(scan.total, 3);
      expect(scan.failed, 1);
    });

    test('all classes failing propagates the error', () async {
      api.handler = (_) async => throw const UntisException(0, 'offline');
      await expectLater(
        repo.refresh(acc, const TimetableTarget(ElementType.teacher, tABC), monday),
        throwsA(isA<UntisException>().having((e) => e.isNetwork, 'network', isTrue)),
      );
    });

    test('a refused direct fetch is not retried', () async {
      const r50 = TimetableTarget(ElementType.room, 50);
      await repo.refresh(acc, r50, monday);
      now = now.add(const Duration(hours: 1)); // everything stale
      await repo.refresh(acc, r50, monday);
      await repo.refresh(acc, const TimetableTarget(ElementType.room, 51), monday);
      expect(api.callsOf(ElementType.room), 1);
      expect(api.callsOf(ElementType.klasse), 6);
    });

    test('network error on the direct fetch is not treated as "no right"',
        () async {
      api.handler = (t) async => t.type == ElementType.room
          ? throw const UntisException(0, 'offline')
          : school(t);
      await expectLater(
        repo.refresh(acc, const TimetableTarget(ElementType.room, 50), monday),
        throwsA(isA<UntisException>()),
      );
      expect(repo.directAccessDenied(acc, ElementType.room), isFalse);
      expect(api.callsOf(ElementType.klasse), 0);
    });

    test('empty direct week for a known element falls back', () async {
      api.handler = (t) async => t.type == ElementType.room
          ? const TimetableResponse([], null)
          : school(t);
      final ps = await week(const TimetableTarget(ElementType.room, 51));
      expect([for (final p in ps) p.id], [101]);
      expect(repo.directAccessDenied(acc, ElementType.room), isTrue);
    });

    test('direct access is used when permitted', () async {
      api.handler = (t) async => t.type == ElementType.room
          ? TimetableResponse([at(7, 8, [room(50)])], null)
          : school(t);
      final ps = await week(const TimetableTarget(ElementType.room, 50));
      expect([for (final p in ps) p.id], [7]);
      expect(api.callsOf(ElementType.klasse), 0);
    });

    test('discovered teachers are upserted and resolve; timestamp unchanged',
        () async {
      final progress = <(int, int)>[];
      await repo.discoverTeachers(
        acc,
        DateTime(2026, 11, 11),
        onProgress: (d, t) => progress.add((d, t)),
      );
      expect(progress.last, (3, 3));

      final names = await repo.watchNames(acc).first;
      expect(names.element(ElementType.teacher, tABC)!.name, 'ABC');
      expect(names.element(ElementType.teacher, tXYZ)!.longName, 'Xavier');
      expect(
        [for (final e in names.elementsOf(ElementType.teacher)) e.name],
        ['ABC', 'DEF', 'XYZ'],
      );
      expect((await accounts.get('a'))!.masterDataTimestamp, 100);

      // A normal delta upsert keeps them.
      await MasterDataStore(db).upsertDelta(
        'a',
        MasterData(timestamp: 200, elements: [teacher(1, 'MUE')]),
      );
      final after = await MasterDataStore(db).loadResolver('a');
      expect(after.element(ElementType.teacher, tDEF)?.name, 'DEF');
    });

    test('cache prevents refetch within maxAge', () async {
      await repo.refresh(acc, const TimetableTarget(ElementType.room, 50), monday);
      expect(api.callsOf(ElementType.klasse), 3);
      await repo.refresh(acc, const TimetableTarget(ElementType.teacher, tABC), monday);
      await repo.discoverTeachers(acc, monday);
      expect(api.callsOf(ElementType.klasse), 3);

      // A fresh aggregated week displays from cache without any request.
      api.calls.clear();
      final cached = await repo
          .watchWeek(acc, const TimetableTarget(ElementType.room, 50), monday)
          .first;
      await pumpEventQueue();
      expect(cached, hasLength(2));
      expect(api.calls, isEmpty);

      now = now.add(const Duration(minutes: 6));
      await repo.discoverTeachers(acc, monday);
      expect(api.callsOf(ElementType.klasse), 3);
    });

    test('concurrent aggregations of the same week share one run', () async {
      api.delay = const Duration(milliseconds: 5);
      await Future.wait([
        repo.refresh(acc, const TimetableTarget(ElementType.teacher, tABC), monday),
        repo.refresh(acc, const TimetableTarget(ElementType.teacher, tDEF), monday),
        repo.discoverTeachers(acc, monday),
      ]);
      expect(api.callsOf(ElementType.klasse), 3);
    });
  });

  test('concurrency never exceeds 3', () async {
    await setUpRepo(classes: 10);
    api.delay = const Duration(milliseconds: 5);
    var last = (0, 0);
    await repo.discoverTeachers(acc, monday, onProgress: (d, t) => last = (d, t));
    expect(api.callsOf(ElementType.klasse), 10);
    expect(api.maxInFlight, 3);
    expect(last, (10, 10));
  });

  group('pure helpers', () {
    test('mergePeriods unions elements without duplicates', () {
      final a = at(1, 8, [cls(1), named(tABC, 'ABC')]);
      final b = at(1, 8, [cls(2), named(tABC, 'ABC')]);
      final m = mergePeriods(a, b);
      expect(m.elements.map((e) => (e.type, e.id)).toList(), [
        (ElementType.klasse, 1),
        (ElementType.teacher, tABC),
        (ElementType.klasse, 2),
      ]);
    });

    test('discoveredTeachers collects current and original names', () {
      final found = discoveredTeachers(classWeeks()[1]!);
      expect(found.keys.toSet(), {tABC, tXYZ});
      expect(found[tABC]!.longName, 'ABC long');
    });

    test('runLimited keeps order', () async {
      final r = await runLimited([3, 1, 2], 2, (int x) async {
        await Future<void>.delayed(Duration(milliseconds: x));
        return x * 10;
      });
      expect(r, [30, 10, 20]);
    });
  });
}
