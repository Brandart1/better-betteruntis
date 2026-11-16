// Room edits of a lesson (replace / remove / add), room bookings without a
// lesson and the free-room filter in Browse → Rooms: params, the guessed
// booking request (through RoutingUntisApi), repository against the demo
// API, and the screens.
import 'dart:convert';

import 'package:better_betteruntis/api/teacher_tools_parsers.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/app/routing_api.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/teacher_tools.dart';
import 'package:better_betteruntis/data/teacher_tools_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/classreg/free_room_booking_screen.dart';
import 'package:better_betteruntis/ui/classreg/room_booking_screen.dart';
import 'package:better_betteruntis/ui/shell/element_picker_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../api/absence_report_api_test.dart' show Adapter, Req, Resp, ok, rpc;
import 'teacher_tools_test.dart'
    show ApiTimetables, creds, demoSchoolNames, maths, ownDay, teacherAccount;

/// Tue 2026-11-10, 08:00–08:45: the demo teacher has no lesson then.
final freeSlot = TimeSlot(
  DateTime(2026, 11, 10, 8),
  DateTime(2026, 11, 10, 8, 45),
);

/// The demo API refuses getAvailableRooms2017 (like a school that doesn't
/// let this account see free rooms).
class NoFreeRoomsApi extends FakeUntisApi {
  NoFreeRoomsApi() : super(latency: Duration.zero);

  @override
  Future<FreeRooms> availableRooms({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
  }) async => throw const UntisException(UntisException.noRight, 'No right');
}

void main() {
  group('params', () {
    test('room edits: orgRoomId is the current room, 0 = add / remove', () {
      const r = RoomEdit.replace(34, 31);
      expect((r.orgRoomId, r.roomId, r.kind), (34, 31, RoomEditKind.replace));
      const a = RoomEdit.add(35);
      expect((a.orgRoomId, a.roomId), (0, 35));
      const d = RoomEdit.remove(34);
      expect((d.orgRoomId, d.roomId), (34, 0));
    });

    test('booking slots: once, daily (no weekends), weekly, every n', () {
      final s = DateTime(2026, 11, 13, 9, 40); // a Friday
      final e = DateTime(2026, 11, 13, 10, 25);
      expect(bookingSlots(start: s, end: e), [TimeSlot(s, e)]);
      final daily = bookingSlots(
        start: s,
        end: e,
        repeat: BookingRepeat.daily,
        until: DateTime(2026, 11, 17),
      );
      expect([for (final x in daily) x.start.day], [13, 16, 17]);
      expect(daily.last.end, DateTime(2026, 11, 17, 10, 25));
      final weekly = bookingSlots(
        start: s,
        end: e,
        repeat: BookingRepeat.weekly,
        until: DateTime(2026, 12, 4),
      );
      expect([for (final x in weekly) x.start.day], [13, 20, 27, 4]);
      final biweekly = bookingSlots(
        start: s,
        end: e,
        repeat: BookingRepeat.biweekly,
        until: DateTime(2026, 12, 4),
      );
      expect([for (final x in biweekly) x.start.day], [13, 27]);
      final every3 = bookingSlots(
        start: s,
        end: e,
        repeat: BookingRepeat.everyNDays,
        everyDays: 3,
        until: DateTime(2026, 11, 23),
      );
      // 13 (Fri), 16 (Mon), 19 (Thu), 22 (Sun, skipped).
      expect([for (final x in every3) x.start.day], [13, 16, 19]);
      final many = bookingSlots(
        start: s,
        end: e,
        repeat: BookingRepeat.daily,
        until: DateTime(2028, 1, 1),
      );
      expect(many, hasLength(maxBookingSlots));
    });

    test('booking payloads and answers', () {
      final b = RoomBookingRequest(
        roomId: 34,
        start: DateTime(2026, 11, 10, 8),
        end: DateTime(2026, 11, 10, 8, 45),
        text: ' Robotics ',
        teacherId: 11,
      );
      expect(roomBookingCalendarPayload(b), {
        'startDateTime': '2026-11-10T08:00:00',
        'endDateTime': '2026-11-10T08:45:00',
        'rooms': {
          'value': [34],
        },
        'teachers': [
          {'value': 11},
        ],
        'notesAll': {'value': 'Robotics'},
      });
      expect(roomBookingClassicPayload(b), {
        'roomId': 34,
        'roomIds': [34],
        'date': 20261110,
        'startTime': 800,
        'endTime': 845,
        'startDateTime': '2026-11-10T08:00',
        'endDateTime': '2026-11-10T08:45',
        'teacherId': 11,
        'text': 'Robotics',
      });
      expect(
        parseRoomBookingResult({
          'data': {'id': 7},
        }).id,
        7,
      );
      expect(
        parseRoomBookingResult({
          'booking': {'id': 8},
        }).id,
        8,
      );
      final failed = parseRoomBookingResult({
        'validationErrors': [
          {'message': 'Room occupied'},
        ],
      });
      expect(failed.ok, isFalse);
      expect(failed.errors.single.message, 'Room occupied');
      expect(
        formatAvailableRoomsDateTime(DateTime(2026, 1, 2, 3, 4)),
        '2026-01-02T03:04Z',
      );
    });
  });

  group('requests (through RoutingUntisApi)', () {
    late Adapter adapter;
    late RoutingUntisApi api;
    late UntisApiImpl real;
    late Resp Function(Req r) handler;
    setUp(() {
      handler = (_) => rpc({});
      adapter = Adapter((r) => handler(r));
      real = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
      api = RoutingUntisApi(
        real: real,
        demo: FakeUntisApi(latency: Duration.zero),
      );
    });

    final booking = RoomBookingRequest(
      roomId: 34,
      start: DateTime(2026, 11, 10, 8),
      end: DateTime(2026, 11, 10, 8, 45),
      teacherId: 11,
    );

    test('room edits send the given ids', () async {
      handler = (_) => rpc({'errors': [], 'periods': []});
      for (final e in const [
        RoomEdit.replace(34, 31),
        RoomEdit.add(35),
        RoomEdit.remove(34),
      ]) {
        await api.submitRoomChange(
          host: 'h',
          school: 's',
          auth: creds,
          periodIds: const [5],
          orgRoomId: e.orgRoomId,
          roomId: e.roomId,
        );
        final p = (adapter.requests.last.json!['params'] as List).single as Map;
        expect((p['orgRoomId'], p['roomId']), (e.orgRoomId, e.roomId));
      }
    });

    test('booking: calendar-entry, else api/bookings; bodies logged', () async {
      handler = (r) {
        if (r.json?['method'] == 'getAuthToken') return rpc({'token': 'jwt'});
        if (r.uri.path == '/WebUntis/api/rest/view/v1/calendar-entry') {
          return (status: 404, body: '', headers: const {});
        }
        if (r.uri.path == '/WebUntis/api/bookings') return ok({'id': 99});
        return rpc({});
      };
      final r = await api.createRoomBooking(
        host: 'h',
        school: 's',
        auth: creds,
        booking: booking,
      );
      expect(r.ok, isTrue);
      expect(r.id, 99);
      final posts = adapter.requests.where((r) => r.method == 'POST').toList();
      expect(
        posts.map((p) => p.uri.path),
        containsAllInOrder([
          '/WebUntis/api/rest/view/v1/calendar-entry',
          '/WebUntis/api/bookings',
        ]),
      );
      expect(posts.last.json, roomBookingClassicPayload(booking));
      final logged = api.debugLog.where(
        (e) => e.method.endsWith('request body'),
      );
      expect(
        logged.map((e) => e.method),
        containsAll([
          'REST POST /WebUntis/api/rest/view/v1/calendar-entry request body',
          'REST POST /WebUntis/api/bookings request body',
        ]),
      );
      expect(
        jsonDecode(logged.first.json),
        roomBookingCalendarPayload(booking),
      );
      // The answers are logged too, never the token.
      expect(
        api.debugLog.map((e) => e.method),
        contains(startsWith('REST POST /WebUntis/api/bookings [HTTP 200]')),
      );
      expect(api.debugLog.map((e) => e.json).join(), isNot(contains('jwt')));
    });

    test('booking: no endpoint answers → a clear error', () async {
      handler = (r) => r.json?['method'] == 'getAuthToken'
          ? rpc({'token': 'jwt'})
          : (r.uri.path.contains('/api/') && !r.uri.path.contains('jsonrpc')
                ? (status: 404, body: '', headers: const {})
                : rpc({}));
      await expectLater(
        api.createRoomBooking(
          host: 'h',
          school: 's',
          auth: creds,
          booking: booking,
        ),
        throwsA(
          isA<UntisException>().having(
            (e) => e.message,
            'message',
            contains('book on the WebUntis website'),
          ),
        ),
      );
    });

    test('booking: errors in a 200 answer come back', () async {
      handler = (r) => r.json?['method'] == 'getAuthToken'
          ? rpc({'token': 'jwt'})
          : (r.uri.path.contains('calendar-entry')
                ? ok({
                    'errors': [
                      {'title': 'No right to book rooms'},
                    ],
                  })
                : rpc({}));
      final r = await api.createRoomBooking(
        host: 'h',
        school: 's',
        auth: creds,
        booking: booking,
      );
      expect(r.ok, isFalse);
      expect(r.errors.single.message, 'No right to book rooms');
    });
  });

  group('repository (demo API through RoutingUntisApi)', () {
    late FakeUntisApi fake;
    late InMemoryAccountRepository accounts;
    late ApiTimetables timetables;
    late TeacherToolsRepositoryImpl repo;

    setUp(() {
      fake = FakeUntisApi(latency: Duration.zero);
      accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      timetables = ApiTimetables(fake);
      repo = TeacherToolsRepositoryImpl(
        // The demo host routes to the fake, like in the app.
        api: RoutingUntisApi(real: FakeUntisApi(), demo: fake),
        accounts: accounts,
        timetables: timetables,
        clock: () => DateTime(2026, 11, 9, 7),
      );
      expect(teacherAccount().host, endsWith('.invalid'));
    });

    test('add a room, then remove both rooms', () async {
      final a = teacherAccount();
      final p = await maths(fake);
      const add = RoomEdit.add(35);
      expect(
        (await repo.changeRoom(
          a,
          [p],
          orgRoomId: add.orgRoomId,
          roomId: add.roomId,
        )).ok,
        isTrue,
      );
      final two = await maths(fake);
      expect([for (final r in currentRoomsOf(two)) r.id], [31, 35]);
      expect(two.elements.last.change, ElementChange.added);
      // The added room is busy for others.
      expect(
        (await repo.freeRoomsBetween(a, p.start, p.end)).roomIds,
        isNot(contains(35)),
      );
      const rm = RoomEdit.remove(35);
      await repo.changeRoom(
        a,
        [two],
        orgRoomId: rm.orgRoomId,
        roomId: rm.roomId,
      );
      const rmMain = RoomEdit.remove(31);
      await repo.changeRoom(
        a,
        [two],
        orgRoomId: rmMain.orgRoomId,
        roomId: rmMain.roomId,
      );
      final none = await maths(fake);
      expect(currentRoomsOf(none), isEmpty);
      expect(bookableRoomOf(none)!.change, ElementChange.removed);
      // Adding the planned room back restores the lesson.
      await repo.changeRoom(a, [none], orgRoomId: 0, roomId: 31);
      final back = await maths(fake);
      expect(bookableRoomOf(back)!.change, ElementChange.regular);
      expect(fake.removedRooms, isEmpty);
      expect(fake.addedRooms, isEmpty);
    });

    test('free rooms for several slots: free on all, partly free', () async {
      final a = teacherAccount();
      // Book R110 (34) on the first slot only.
      await repo.bookRoom(a, roomId: 34, slots: [freeSlot]);
      final next = TimeSlot(
        freeSlot.start.add(const Duration(days: 7)),
        freeSlot.end.add(const Duration(days: 7)),
      );
      final r = await repo.freeRoomsForSlots(a, [freeSlot, next]);
      expect(r.slotCount, 2);
      expect(r.roomIds, isNot(contains(34)));
      expect(r.partlyFree[34], 1);
    });

    test('booking is denied during an own lesson', () async {
      final a = teacherAccount();
      final p = await maths(fake);
      final slot = TimeSlot(p.start, p.end);
      expect((await repo.lessonsDuring(a, [slot])).single.id, p.id);
      expect(await repo.lessonsDuring(a, [freeSlot]), isEmpty);
      await expectLater(
        repo.bookRoom(a, roomId: 35, slots: [freeSlot, slot]),
        throwsA(
          isA<UntisException>().having(
            (e) => e.message,
            'message',
            contains('You have a lesson'),
          ),
        ),
      );
      expect(fake.roomBookingCalls, isEmpty);
    });

    test(
      'a booking shows in the teacher\'s and the room\'s timetable',
      () async {
        final a = teacherAccount();
        final free = await repo.freeRoomsForSlots(a, [freeSlot]);
        final room = free.roomIds.first;
        final out = await repo.bookRoom(
          a,
          roomId: room,
          slots: [freeSlot],
          text: 'Robotics',
        );
        expect(out.single.ok, isTrue);
        expect(timetables.refreshed, [DateTime(2026, 11, 9)]);
        expect(
          fake.roomBookingCalls.single.teacherId,
          FakeUntisApi.demoTeacherId,
        );
        final mine = (await ownDay(
          fake,
          freeSlot.start,
        )).where((p) => p.isRoomBooking && p.lessonText == 'Robotics');
        expect(mine, hasLength(1));
        expect(currentRoomsOf(mine.single).single.id, room);
        final roomWeek = (await fake.timetable(
          host: 'h',
          school: 's',
          auth: creds,
          target: TimetableTarget(ElementType.room, room),
          start: freeSlot.start,
          end: freeSlot.start,
          masterDataTimestamp: 0,
        )).periods;
        expect(
          roomWeek.where((p) => p.isRoomBooking && p.lessonText == 'Robotics'),
          hasLength(1),
        );
        // Now busy.
        expect(
          (await repo.freeRoomsForSlots(a, [freeSlot])).roomIds,
          isNot(contains(room)),
        );
        // Booking it again: the server's error comes back for that slot.
        final again = await repo.bookRoom(a, roomId: room, slots: [freeSlot]);
        expect(again.single.ok, isFalse);
        expect(again.single.error, contains('Room is occupied'));
      },
    );

    test('free rooms for Browse: any account', () async {
      accounts = InMemoryAccountRepository(
        initial: [teacherAccount(), demoAccount()],
      );
      repo = TeacherToolsRepositoryImpl(
        api: fake,
        accounts: accounts,
        timetables: timetables,
      );
      final r = await repo.freeRoomsAt(
        demoAccount(),
        DateTime(2026, 11, 10, 9, 40),
        DateTime(2026, 11, 10, 10, 25),
      );
      expect(r.roomIds, isNot(contains(31)));
      expect(r.roomIds, contains(34));
    });
  });

  group('screens', () {
    late FakeUntisApi api;
    late InMemoryAccountRepository accounts;

    Widget app(
      Widget home, {
      FakeUntisApi? fake,
      Account? account,
      DateTime? now,
    }) {
      final a = fake ?? api;
      final acc = account ?? teacherAccount();
      accounts = InMemoryAccountRepository(initial: [acc]);
      accounts.secrets[acc.id] = 'S';
      final clock = now ?? DateTime(2026, 11, 10, 7);
      return ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(accounts),
          nameResolverProvider.overrideWith(
            (ref) => Stream.value(demoSchoolNames()),
          ),
          teacherToolsClockProvider.overrideWithValue(() => clock),
          teacherToolsRepositoryProvider.overrideWithValue(
            TeacherToolsRepositoryImpl(
              api: a,
              accounts: accounts,
              timetables: ApiTimetables(a),
              clock: () => clock,
            ),
          ),
        ],
        child: MaterialApp(home: home),
      );
    }

    void tall(WidgetTester t) {
      t.view.physicalSize = const Size(800, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
    }

    setUp(() => api = FakeUntisApi(latency: Duration.zero));

    testWidgets('lesson room: remove asks first, then sends roomId 0', (
      t,
    ) async {
      final p = (await t.runAsync(() => maths(api)))!;
      await t.pumpWidget(
        app(
          Consumer(
            builder: (c, ref, _) {
              ref.watch(nameResolverProvider);
              return Scaffold(
                body: TextButton(
                  onPressed: () => runRoomAction(
                    c,
                    ref,
                    account: teacherAccount(),
                    periods: [p],
                    action: RoomAction.remove(bookableRoomOf(p)!),
                    title: 'Mathematik',
                    subtitle: 'Tue 10 Nov',
                  ),
                  child: const Text('remove'),
                ),
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('remove'));
      await t.pumpAndSettle();
      expect(find.text('Remove Raum 101?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(api.roomChangeCalls, isEmpty);
      await t.tap(find.text('remove'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('roomremove-confirm')));
      await t.pumpAndSettle();
      final c = api.roomChangeCalls.single;
      expect((c.orgRoomId, c.roomId), (31, 0));
      expect(find.text('Room removed: Raum 101.'), findsOneWidget);
    });

    testWidgets('book a room: lesson numbers, weekly, pick, book', (t) async {
      tall(t);
      await t.pumpWidget(app(const FreeRoomBookingScreen()));
      await t.pumpAndSettle();
      // Default: the next lesson of today (Tue 07:00 → lesson 1).
      expect(find.text('From 08:00'), findsNothing); // lessons mode
      expect(find.textContaining('Lesson 1 (08:00–08:45)'), findsWidgets);
      await t.tap(find.byKey(const ValueKey('freebook-repeat-weekly')));
      await t.pumpAndSettle();
      expect(find.textContaining('5 dates'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('freebook-find')));
      await t.pumpAndSettle();
      expect(find.text('Free rooms'), findsWidgets);
      final free = find.byWidgetPredicate(
        (w) =>
            w is ListTile &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('freeroom-') &&
            (w.key! as ValueKey<String>).value != 'freeroom-search',
      );
      expect(free, findsWidgets);
      await t.tap(free.first);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('freebook-confirm')));
      await t.pumpAndSettle();
      expect(api.roomBookingCalls, hasLength(5));
      expect(find.byKey(const ValueKey('freebook-done')), findsOneWidget);
      expect(api.roomBookings, hasLength(5));
    });

    testWidgets('book a room: denied during an own lesson', (t) async {
      tall(t);
      // Tue 09:00: the next lesson (9:40, lesson 3) is the teacher's Maths.
      await t.pumpWidget(
        app(const FreeRoomBookingScreen(), now: DateTime(2026, 11, 10, 9)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('freebook-find')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('freebook-error')), findsOneWidget);
      expect(find.textContaining('You have a lesson'), findsOneWidget);
      expect(find.textContaining('Mathematik'), findsOneWidget);
      expect(api.roomBookingCalls, isEmpty);
    });

    testWidgets('book a room: only teachers', (t) async {
      await t.pumpWidget(
        app(const FreeRoomBookingScreen(), account: demoAccount()),
      );
      await t.pumpAndSettle();
      expect(
        find.text('Only teacher accounts can book rooms.'),
        findsOneWidget,
      );
    });

    Finder roomTile(String name) => find.widgetWithText(ListTile, name);

    Future<void> openRooms(WidgetTester t) async {
      await t.tap(find.text('Rooms'));
      await t.pumpAndSettle();
    }

    testWidgets('browse: free-room filter, this / next lesson, off', (t) async {
      tall(t);
      // Tue 09:50: lesson 3 (Maths in Raum 101) is running.
      await t.pumpWidget(
        app(const ElementPickerScreen(), now: DateTime(2026, 11, 10, 9, 50)),
      );
      await t.pumpAndSettle();
      await openRooms(t);
      expect(roomTile('Raum 101'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('freefilter-now')));
      await t.pumpAndSettle();
      expect(roomTile('Raum 101'), findsNothing);
      expect(roomTile('Informatikraum'), findsOneWidget);
      expect(find.byKey(const ValueKey('freefilter-summary')), findsOneWidget);
      expect(find.textContaining('09:40–10:25'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('freefilter-next')));
      await t.pumpAndSettle();
      expect(find.textContaining('10:30–11:15'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('freefilter-off')));
      await t.pumpAndSettle();
      expect(roomTile('Raum 101'), findsOneWidget);
      expect(find.byKey(const ValueKey('freefilter-summary')), findsNothing);
    });

    testWidgets('browse: custom time as lessons', (t) async {
      tall(t);
      await t.pumpWidget(
        app(const ElementPickerScreen(), now: DateTime(2026, 11, 10, 7)),
      );
      await t.pumpAndSettle();
      await openRooms(t);
      await t.tap(find.byKey(const ValueKey('freefilter-custom')));
      await t.pumpAndSettle();
      expect(find.text('Free rooms when?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('freefilter-apply')));
      await t.pumpAndSettle();
      expect(find.textContaining('08:00–08:45'), findsOneWidget);
      expect(find.byKey(const ValueKey('freefilter-summary')), findsOneWidget);
    });

    testWidgets('browse: a refusal shows the error and turns the filter off', (
      t,
    ) async {
      tall(t);
      final acc = Account(
        id: 'pupil-refused',
        school: demoAccount().school,
        username: 'pupil',
        anonymous: false,
        displayName: 'Pupil',
        elementType: ElementType.student,
        elementId: 1001,
      );
      await t.pumpWidget(
        app(
          const ElementPickerScreen(),
          fake: NoFreeRoomsApi(),
          account: acc,
          now: DateTime(2026, 11, 10, 9, 50),
        ),
      );
      await t.pumpAndSettle();
      await openRooms(t);
      await t.tap(find.byKey(const ValueKey('freefilter-now')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('freefilter-error')), findsOneWidget);
      expect(roomTile('Raum 101'), findsOneWidget);
      // "No right": hidden for this account from now on.
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        app(const ElementPickerScreen(), fake: NoFreeRoomsApi(), account: acc),
      );
      await t.pumpAndSettle();
      await openRooms(t);
      expect(find.byKey(const ValueKey('freefilter')), findsNothing);
    });
  });
}
