import 'package:better_betteruntis/core/absence_details.dart';
import 'package:better_betteruntis/core/info.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/data/account_repository_impl.dart';
import 'package:better_betteruntis/data/db/database.dart';
import 'package:better_betteruntis/data/info_center_repository_impl.dart';
import 'package:better_betteruntis/data/master_data_store.dart';
import 'package:better_betteruntis/data/secret_store.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockApi extends Mock implements FullUntisApi {}

/// Only the contract interfaces, no [AbsenceReportApi].
class MockPlainApi extends Mock implements UntisApi, InfoCenterApi {}

void main() {
  late AppDatabase db;
  late MockApi api;
  late AccountRepositoryImpl accounts;
  late InfoCenterRepositoryImpl repo;
  late Account parent;
  var now = DateTime(2026, 11, 10, 12);
  final start = DateTime(2026, 11, 1);
  final end = DateTime(2026, 11, 10);
  final report = AbsenceReport(
    studentId: 11,
    start: DateTime(2026, 11, 10, 8),
    end: DateTime(2026, 11, 10, 13),
    reasonId: 1,
  );

  setUpAll(() {
    registerFallbackValue(const UntisCredentials.anonymous());
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(report);
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
    parent = await accounts.add(
      Account(
        id: 'p',
        school: school,
        username: 'parent',
        anonymous: false,
        displayName: 'Parent',
        elementType: ElementType.unknown,
        elementId: 900,
        children: const [
          AccountChild(id: 11, displayName: 'Child A'),
          AccountChild(id: 12, displayName: 'Child B'),
        ],
      ),
      's',
      masterData(),
    );
  });
  tearDown(() => db.close());

  When<Future<List<RawAbsence>>> whenRaw() => when(
    () => api.rawAbsences(
      host: any(named: 'host'),
      school: any(named: 'school'),
      auth: any(named: 'auth'),
      start: any(named: 'start'),
      end: any(named: 'end'),
      studentId: any(named: 'studentId'),
    ),
  );

  When<Future<void>> whenReport() => when(
    () => api.reportAbsence(
      host: any(named: 'host'),
      school: any(named: 'school'),
      auth: any(named: 'auth'),
      report: any(named: 'report'),
    ),
  );

  When<Future<AbsenceReportOptions>> whenOptions() => when(
    () => api.absenceReportOptions(
      host: any(named: 'host'),
      school: any(named: 'school'),
      auth: any(named: 'auth'),
      studentId: any(named: 'studentId'),
    ),
  );

  RawAbsence raw(int id) => RawAbsence(
    id: id,
    start: DateTime(2026, 11, 3, 8),
    end: DateTime(2026, 11, 3, 9),
    excused: true,
  );

  Future<int> rawCalls() async => verify(
    () => api.rawAbsences(
      host: any(named: 'host'),
      school: any(named: 'school'),
      auth: any(named: 'auth'),
      start: any(named: 'start'),
      end: any(named: 'end'),
      studentId: any(named: 'studentId'),
    ),
  ).callCount;

  test('report succeeds and drops cached absences of every child', () async {
    whenRaw().thenAnswer((_) async => [raw(1)]);
    whenReport().thenAnswer((_) async {});
    await repo.absences(parent, start, end).toList();
    await repo
        .absences(parent.copyWith(selectedChildId: 12), start, end)
        .toList();
    expect(await rawCalls(), 2);

    // Within maxAge the cache answers alone.
    final cachedOnly = await repo.absences(parent, start, end).toList();
    expect(cachedOnly, hasLength(1));
    verifyNever(
      () => api.rawAbsences(
        host: any(named: 'host'),
        school: any(named: 'school'),
        auth: any(named: 'auth'),
        start: any(named: 'start'),
        end: any(named: 'end'),
        studentId: any(named: 'studentId'),
      ),
    );

    await repo.reportAbsence(parent, report);
    final sent =
        verify(
              () => api.reportAbsence(
                host: 'demo.webuntis.com',
                school: any(named: 'school'),
                auth: any(named: 'auth'),
                report: captureAny(named: 'report'),
              ),
            ).captured.single
            as AbsenceReport;
    expect(sent.studentId, 11);

    whenRaw().thenAnswer((_) async => [raw(1), raw(2)]);
    final after = await repo.absences(parent, start, end).toList();
    // No cache: empty refreshing first, then the fresh list from the server.
    expect(after.first.data, isNull);
    expect(after.last.data, hasLength(2));
    await repo
        .absences(parent.copyWith(selectedChildId: 12), start, end)
        .toList();
    expect(await rawCalls(), 2);
  });

  test('a failed report keeps the cache and passes the error on', () async {
    whenRaw().thenAnswer((_) async => [raw(1)]);
    whenReport().thenThrow(
      const UntisException(UntisException.noRight, 'not allowed'),
    );
    await repo.absences(parent, start, end).toList();
    await expectLater(
      repo.reportAbsence(parent, report),
      throwsA(isA<UntisException>().having((e) => e.code, 'code', -8509)),
    );
    final again = await repo.absences(parent, start, end).toList();
    expect(again, hasLength(1)); // still served from cache
  });

  test('options fall back to master-data reasons', () async {
    await MasterDataStore(db).upsertLookups(
      'p',
      const AbsenceLookups(
        reasons: {2: 'Krankheit', 1: 'Arzttermin', 3: '---'},
      ),
    );
    whenOptions().thenAnswer(
      (_) async => const AbsenceReportOptions(allowed: true),
    );
    var o = await repo.absenceReportOptions(parent, 11);
    expect(o.reasons.map((r) => r.name), ['Arzttermin', 'Krankheit']);
    expect(o.allowed, isTrue);

    whenOptions().thenThrow(const UntisException(-8530, 'browser login'));
    o = await repo.absenceReportOptions(parent, 11);
    expect(o.reasons, hasLength(2));
    expect(o.notice, 'browser login');
    expect(o.allowed, isNull);

    // Offline is reported, not hidden behind master data.
    whenOptions().thenThrow(const UntisException(0, 'offline'));
    await expectLater(
      repo.absenceReportOptions(parent, 11),
      throwsA(isA<UntisException>()),
    );
  });

  test('options without any reasons anywhere rethrow', () async {
    whenOptions().thenThrow(const UntisException(-1, 'HTTP 500'));
    await expectLater(
      repo.absenceReportOptions(parent, 11),
      throwsA(isA<UntisException>().having((e) => e.message, 'm', 'HTTP 500')),
    );
  });

  test('an API without the capability fails clearly', () async {
    final plain = InfoCenterRepositoryImpl(
      api: MockPlainApi(),
      db: db,
      accounts: accounts,
    );
    await expectLater(
      plain.reportAbsence(parent, report),
      throwsA(isA<UntisException>()),
    );
  });

  test('demo API: reported absences show up for that child only', () async {
    final demoRepo = InfoCenterRepositoryImpl(
      api: FakeUntisApi(latency: Duration.zero),
      db: db,
      accounts: accounts,
      clock: () => now,
    );
    final o = await demoRepo.absenceReportOptions(parent, 11);
    expect(o.allowed, isTrue);
    expect(o.reasons, isNotEmpty);
    final before =
        (await demoRepo.absences(parent, start, end).toList()).last.data!;
    await demoRepo.reportAbsence(
      parent,
      AbsenceReport(
        studentId: 11,
        start: DateTime(2026, 11, 9, 8),
        end: DateTime(2026, 11, 9, 13),
        reasonId: 2,
        text: 'Fieber',
      ),
    );
    final after =
        (await demoRepo.absences(parent, start, end).toList()).last.data!;
    expect(after, hasLength(before.length + 1));
    final added = after.firstWhere((a) => a.text == 'Fieber');
    expect(added.reason, 'Arzttermin');
    expect(added.excused, isFalse);

    final other =
        (await demoRepo
                .absences(
                  parent.copyWith(selectedChildId: 12),
                  start,
                  end,
                  force: true,
                )
                .toList())
            .last
            .data!;
    expect(other.where((a) => a.text == 'Fieber'), isEmpty);

    // Overlapping the same child again is a conflict.
    await expectLater(
      demoRepo.reportAbsence(
        parent,
        AbsenceReport(
          studentId: 11,
          start: DateTime(2026, 11, 9, 9),
          end: DateTime(2026, 11, 9, 10),
        ),
      ),
      throwsA(isA<UntisException>()),
    );
  });
}
