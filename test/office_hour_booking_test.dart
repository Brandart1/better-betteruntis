// Booking office hours (parents / pupils): parsers, request params, the
// demo API round trip, the repository and the info center flow.
import 'package:better_betteruntis/api/office_hour_parsers.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/core/info.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/office_hour_booking.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/data/office_hour_booking_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_info.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/infocenter/info_center_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'api/absence_report_api_test.dart' show Adapter, rpc;

const creds = UntisCredentials.user('parent', 'JBSWY3DPEHPK3PXP');

final day = DateTime(2026, 11, 24);
OfficeHourItem item({int id = 7, int teacherId = 3}) => OfficeHourItem(
  id: id,
  start: DateTime(2026, 11, 24, 10),
  end: DateTime(2026, 11, 24, 10, 30),
  teacherName: 'Anna Müller',
  teacherId: teacherId,
  registrationPossible: true,
);

/// An API without booking.
class PlainApi implements UntisApi {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class NoAccounts implements AccountRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Office hours and bookings straight from the demo API.
class ApiInfoRepo extends FakeInfoCenterRepository {
  ApiInfoRepo(this.api) : super(latency: Duration.zero);
  final FakeUntisApi api;

  @override
  Stream<Cached<List<OfficeHourItem>>> officeHours(
    Account a,
    DateTime start, {
    bool force = false,
    bool onlyMyClass = false,
  }) async* {
    final next = DateTime.now().add(const Duration(days: 7));
    yield Cached(
      data: await api.officeHours(
        host: 'h',
        school: 's',
        auth: creds,
        klasseId: 1,
        start: next,
      ),
      fetchedAt: DateTime.now(),
    );
  }
}

class ApiBooking implements OfficeHourBookingRepository {
  ApiBooking(this.api);
  final FakeUntisApi api;

  @override
  bool supports(Account account) => true;

  @override
  Future<OfficeHourSlots> slots(Account account, OfficeHourItem o) =>
      api.officeHourSlots(host: 'h', school: 's', auth: creds, officeHour: o);

  @override
  Future<OfficeHourSlots> book(
    Account account,
    OfficeHourItem o,
    OfficeHourSlot slot, {
    required String userText,
    String teacherText = '',
  }) => api.bookOfficeHour(
    host: 'h',
    school: 's',
    auth: creds,
    officeHour: o,
    slot: slot,
    userText: userText,
  );

  @override
  Future<void> cancel(
    Account account,
    OfficeHourItem o, {
    String userText = '',
  }) =>
      api.cancelOfficeHour(host: 'h', school: 's', auth: creds, officeHour: o);
}

void main() {
  group('parser', () {
    test('times on the day, states, sorted, texts trimmed', () {
      final r = parseOfficeHourSlots({
        'teacherText': '  Be brief ',
        'userText': ' hi ',
        'timeSlots': [
          {'startTime': 'T10:10', 'endTime': 'T10:20', 'state': 'SELF'},
          {'startTime': 'T10:00', 'endTime': 'T10:10', 'state': 'free'},
          {'startTime': 'T10:20', 'endTime': 'T10:30', 'state': 'OTHER'},
          {'startTime': 'T10:30', 'endTime': 'T10:40', 'state': 'WAT'},
          {'startTime': 'T10:40', 'state': 'FREE'},
          {'endTime': 'T10:50', 'state': 'FREE'},
          'junk',
        ],
      }, day);
      expect(r.teacherText, 'Be brief');
      expect(r.userText, 'hi');
      expect(r.slots.map((s) => s.start.minute), [0, 10, 20, 30]);
      expect(r.slots.first.start, DateTime(2026, 11, 24, 10));
      expect(r.slots.map((s) => s.state), [
        OfficeHourSlotState.free,
        OfficeHourSlotState.self,
        OfficeHourSlotState.other,
        OfficeHourSlotState.other,
      ]);
      expect(r.mine!.start.minute, 10);
    });

    test('full date-times and garbage', () {
      final r = parseOfficeHourSlots({
        'timeSlots': [
          {
            'startTime': '2026-11-25T09:00',
            'endTime': '2026-11-25T09:15',
            'state': 'FREE',
          },
        ],
      }, day);
      expect(r.slots.single.start, DateTime(2026, 11, 25, 9));
      expect(r.slots.single.end, DateTime(2026, 11, 25, 9, 15));
      expect(parseOfficeHourSlots(null, day).slots, isEmpty);
      expect(parseOfficeHourSlots({'timeSlots': 5}, day).slots, isEmpty);
    });
  });

  test('params: literal Z, trimmed userText', () {
    final slot = OfficeHourSlot(
      start: DateTime(2026, 11, 24, 10, 10),
      end: DateTime(2026, 11, 24, 10, 20),
      state: OfficeHourSlotState.free,
    );
    expect(officeHourSlotsParams(item()), {'periodId': 7, 'teacherId': 3});
    final p = bookOfficeHourParams(item(), slot, userText: '  hello \n');
    expect(p['startDateTime'], '2026-11-24T10:10Z');
    expect(p['endDateTime'], '2026-11-24T10:20Z');
    expect(p['userText'], 'hello');
    expect(p['teacherText'], '');
    expect(p['periodId'], 7);
    expect(cancelOfficeHourParams(item(), userText: ' x ')['userText'], 'x');
  });

  test('real API sends the calls and parses the answer', () async {
    final adapter = Adapter((r) {
      final m = r.json?['method'];
      if (m == 'getOfficeHourRegistrations2017' ||
          m == 'submitOfficeHourRegistration2017') {
        return rpc({
          'timeSlots': [
            {'startTime': 'T10:00', 'endTime': 'T10:10', 'state': 'SELF'},
          ],
        });
      }
      return rpc(null);
    });
    final api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
    final slots = await api.bookOfficeHour(
      host: 'h',
      school: 's',
      auth: creds,
      officeHour: item(),
      slot: OfficeHourSlot(
        start: DateTime(2026, 11, 24, 10),
        end: DateTime(2026, 11, 24, 10, 10),
        state: OfficeHourSlotState.free,
      ),
      userText: ' hi ',
    );
    expect(slots.mine, isNotNull);
    expect(
      adapter.requests.last.json!['method'],
      'submitOfficeHourRegistration2017',
    );
    await api.cancelOfficeHour(
      host: 'h',
      school: 's',
      auth: creds,
      officeHour: item(),
    );
    expect(
      adapter.requests.last.json!['method'],
      'deleteOfficeHourRegistration2017',
    );
    expect(
      api.debugLog.map((e) => e.method),
      containsAll([
        'submitOfficeHourRegistration2017 request body',
        'deleteOfficeHourRegistration2017 request body',
      ]),
    );
  });

  group('demo API', () {
    final api = FakeUntisApi(latency: Duration.zero);
    Future<OfficeHourSlots> slots(OfficeHourItem o) =>
        api.officeHourSlots(host: 'h', school: 's', auth: creds, officeHour: o);

    test('book and cancel round trip', () async {
      final o = (await api.officeHours(
        host: 'h',
        school: 's',
        auth: creds,
        klasseId: 1,
        start: DateTime.now(),
      )).firstWhere((o) => o.id == 1);
      final before = await slots(o);
      expect(before.slots.length, 4);
      expect(before.slots[2].state, OfficeHourSlotState.other);
      expect(before.mine, isNull);
      expect(before.teacherText, isNotEmpty);

      final after = await api.bookOfficeHour(
        host: 'h',
        school: 's',
        auth: creds,
        officeHour: o,
        slot: before.slots[0],
        userText: ' note ',
      );
      expect(after.mine!.start, before.slots[0].start);
      expect(after.userText, 'note');

      Future<bool> registered() async => (await api.officeHours(
        host: 'h',
        school: 's',
        auth: creds,
        klasseId: 1,
        start: DateTime.now(),
      )).firstWhere((x) => x.id == 1).registered;
      expect(await registered(), isTrue);

      await expectLater(
        api.bookOfficeHour(
          host: 'h',
          school: 's',
          auth: creds,
          officeHour: o,
          slot: before.slots[2],
          userText: '',
        ),
        throwsA(isA<UntisException>()),
      );

      await api.cancelOfficeHour(
        host: 'h',
        school: 's',
        auth: creds,
        officeHour: o,
      );
      expect((await slots(o)).mine, isNull);
      expect(await registered(), isFalse);
    });
  });

  test('repository: unsupported API', () async {
    final repo = OfficeHourBookingRepositoryImpl(
      api: PlainApi(),
      accounts: NoAccounts(),
    );
    expect(repo.supports(demoAccount()), isFalse);
    expect(const NoOfficeHourBooking().supports(demoAccount()), isFalse);
    await expectLater(
      repo.slots(demoAccount(), item()),
      throwsA(isA<UntisException>()),
    );
    expect(
      OfficeHourBookingRepositoryImpl(
        api: FakeUntisApi(latency: Duration.zero),
        accounts: NoAccounts(),
      ).supports(demoAccount()),
      isTrue,
    );
  });

  testWidgets('book a time, then cancel it', (tester) async {
    tester.view.physicalSize = const Size(420, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeUntisApi(latency: Duration.zero);
    final router = GoRouter(
      initialLocation: '/info',
      routes: [
        GoRoute(path: '/info', builder: (_, _) => const InfoCenterScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          infoCenterRepositoryProvider.overrideWithValue(ApiInfoRepo(api)),
          officeHourBookingRepositoryProvider.overrideWithValue(
            ApiBooking(api),
          ),
          activeAccountProvider.overrideWith(
            (ref) => Stream.value(demoAccount()),
          ),
          nameResolverProvider.overrideWith(
            (ref) => Stream<NameResolver>.value(FakeNameResolver()),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Office hours'),
      ),
    );
    await tester.pumpAndSettle();

    final book1 = find.byKey(const ValueKey('officehour-1-book'));
    expect(find.text('Book a time'), findsWidgets);
    expect(find.text('Your booking'), findsOneWidget); // demo hour 2
    await tester.ensureVisible(book1);
    await tester.tap(book1);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('officehour-teacher-text')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('officehour-booked')), findsNothing);

    // The third slot is taken by someone else.
    final slots = find.byWidgetPredicate((w) => w is ChoiceChip);
    expect(slots, findsNWidgets(4));
    expect(tester.widget<ChoiceChip>(slots.at(2)).onSelected, isNull);
    await tester.tap(slots.at(1));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('officehour-note')),
      'About maths',
    );
    await tester.tap(find.byKey(const ValueKey('officehour-book')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('officehour-teacher-text')),
      findsNothing,
      reason: 'sheet closed',
    );
    expect(api.officeHourBookings[1]!.text, 'About maths');
    expect(find.text('Registered'), findsNWidgets(2));
    expect(find.text('Your booking'), findsNWidgets(2));

    await tester.ensureVisible(book1);
    await tester.tap(book1);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('officehour-booked')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('officehour-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('officehour-cancel-confirm')));
    await tester.pumpAndSettle();

    expect(api.officeHourBookings, isEmpty);
    expect(find.text('Registered'), findsOneWidget);
    expect(find.byKey(const ValueKey('officehour-teacher-text')), findsNothing);
  });
}
