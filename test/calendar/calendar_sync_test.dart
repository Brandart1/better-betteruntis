import 'package:better_betteruntis/calendar/calendar_sync.dart';
import 'package:better_betteruntis/calendar/calendar_sync_service.dart';
import 'package:better_betteruntis/calendar/device_calendar.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/export/export_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../export/export_test_helpers.dart';
import 'fake_device_calendar.dart';

void main() {
  final names = FakeNameResolver();
  const cals = {
    LessonStatus.regular: 'personal',
    LessonStatus.substitution: 'personal',
    LessonStatus.exam: 'personal',
    LessonStatus.cancelled: 'cancelled',
  };

  Map<String, WantedEvent> wanted(List<Period> periods) => wantedEvents(
    buildExportLessons(periods, names, regular: false, palette: null),
    cals,
  );

  group('syncCalendar', () {
    late FakeDeviceCalendar api;
    setUp(() {
      api = FakeDeviceCalendar();
      api.cals['cancelled'] = FakeCalendar('Cancelled', 0xFF777777);
    });

    test('creates once, then only writes what changed', () async {
      final math = period(mon, 1, h: 8, subject: DemoIds.m);
      final german = period(mon, 2, h: 9, subject: DemoIds.d);
      var out = await syncCalendar(
        api,
        events: const {},
        wanted: wanted([math, german]),
        covers: (_) => true,
      );
      expect(out.error, isNull);
      expect(out.counts.created, 2);
      expect(api.eventCount, 2);
      final first = api.eventsIn('personal').first;
      expect(first.start, DateTime(2026, 11, 9, 8));
      expect(first.end, DateTime(2026, 11, 9, 8, 45));

      // Same data: nothing written.
      api.log.clear();
      out = await syncCalendar(
        api,
        events: out.events,
        wanted: wanted([math, german]),
        covers: (_) => true,
      );
      expect(api.log, isEmpty);
      expect(out.counts.unchanged, 2);
      expect(out.counts.changed, isFalse);

      // German cancelled: moved to the cancelled calendar, marked free.
      final cancelled = period(
        mon,
        2,
        h: 9,
        subject: DemoIds.d,
        flags: const {PeriodFlag.cancelled},
      );
      out = await syncCalendar(
        api,
        events: out.events,
        wanted: wanted([math, cancelled]),
        covers: (_) => true,
      );
      expect(out.counts.updated, 1);
      expect(api.eventsIn('personal'), hasLength(1));
      final c = api.eventsIn('cancelled').single;
      expect(c.title, startsWith('Cancelled: '));
      expect(c.free, isTrue);

      // Substitute room: updated in place.
      final moved = period(
        mon,
        1,
        h: 8,
        subject: DemoIds.m,
        room: el(ElementType.room, DemoIds.r102),
      );
      api.log.clear();
      out = await syncCalendar(
        api,
        events: out.events,
        wanted: wanted([moved, cancelled]),
        covers: (_) => true,
      );
      expect(api.log, ['updateEvent']);
      expect(api.eventsIn('personal').single.location, 'R102');

      // Lesson gone: deleted.
      out = await syncCalendar(
        api,
        events: out.events,
        wanted: wanted([moved]),
        covers: (_) => true,
      );
      expect(out.counts.deleted, 1);
      expect(api.eventsIn('cancelled'), isEmpty);
      expect(out.events, hasLength(1));
    });

    test('days outside the scope are left alone', () async {
      final a = period(mon, 1, h: 8);
      final out = await syncCalendar(
        api,
        events: const {},
        wanted: wanted([a]),
        covers: (_) => true,
      );
      // The week failed to load: nothing is wanted, but nothing is deleted.
      final again = await syncCalendar(
        api,
        events: out.events,
        wanted: const {},
        covers: (_) => false,
      );
      expect(again.counts.deleted, 0);
      expect(api.eventCount, 1);
    });

    test('an event deleted by the user is written again', () async {
      final a = period(mon, 1, h: 8);
      final b = period(mon, 1, h: 8, infoText: 'Bring a calculator');
      final out = await syncCalendar(
        api,
        events: const {},
        wanted: wanted([a]),
        covers: (_) => true,
      );
      api.userDeletes(out.events.values.single.eventId);
      final again = await syncCalendar(
        api,
        events: out.events,
        wanted: wanted([b]),
        covers: (_) => true,
      );
      expect(again.error, isNull);
      expect(api.eventCount, 1);
      expect(
        again.events.values.single.eventId,
        isNot(out.events.values.single.eventId),
      );
    });

    test('a failure keeps what was already written', () async {
      api.failOnCreate = 2;
      final out = await syncCalendar(
        api,
        events: const {},
        wanted: wanted([period(mon, 1, h: 8), period(mon, 1, h: 10)]),
        covers: (_) => true,
      );
      expect(out.error, isA<StateError>());
      expect(out.events, hasLength(1));
      expect(api.eventCount, 1);
    });
  });

  test('sync round-trips through JSON', () {
    final s = CalendarSync(
      id: 'a:CLASS:40',
      accountId: 'a',
      target: const TimetableTarget(ElementType.klasse, 40),
      elementName: '10a',
      calendars: const {LessonStatus.regular: 'c1', LessonStatus.exam: 'c2'},
      created: const {'c1': 0xFF112233},
      weeks: 8,
      autoUpdate: false,
      lastSync: DateTime(2026, 11, 14, 10),
      events: {
        'k': SyncedEvent(
          eventId: 'e',
          calendarId: 'c1',
          fingerprint: 'f',
          day: DateTime(2026, 11, 16),
        ),
      },
    );
    final r = CalendarSync.fromJson(s.toJson());
    expect(r.target, s.target);
    expect(r.calendars, s.calendars);
    expect(r.created, s.created);
    expect(r.weeks, 8);
    expect(r.autoUpdate, isFalse);
    expect(r.lastSync, s.lastSync);
    expect(r.events['k']!.day, DateTime(2026, 11, 16));
  });

  group('CalendarSyncsNotifier', () {
    late FakeDeviceCalendar api;
    late ProviderContainer c;
    final account = demoAccount();
    const target = TimetableTarget(ElementType.klasse, DemoIds.klasse);

    setUp(() {
      api = FakeDeviceCalendar();
      c = ProviderContainer(
        overrides: [
          deviceCalendarProvider.overrideWithValue(api),
          settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
          accountRepositoryProvider.overrideWithValue(
            InMemoryAccountRepository(initial: [account]),
          ),
          timetableRepositoryProvider.overrideWithValue(
            FakeTimetableRepository(weekBuilder: (_, w) => buildDemoWeek(w)),
          ),
        ],
      );
      addTearDown(c.dispose);
    });

    CalendarSync draft() => CalendarSync(
      id: 'sync',
      accountId: account.id,
      target: target,
      elementName: '10a',
      weeks: 2,
    );

    test('new calendars per state with the settings colors', () async {
      c
          .read(timetableSettingsProvider.notifier)
          .update((s) => s.copyWith(examColor: 0xFF123456));
      final n = c.read(calendarSyncsProvider.notifier);
      final counts = await n.save(draft(), {
        for (final s in LessonStatus.values) s: const NewCalendar(),
      });
      expect(counts.created, greaterThan(0));
      final byName = {for (final x in api.cals.values) x.name: x};
      expect(
        byName.keys,
        containsAll([
          '10a – Timetable',
          '10a – Substitutions',
          '10a – Exams',
          '10a – Cancelled',
        ]),
      );
      expect(byName['10a – Exams']!.color, 0xFF123456);
      // The demo weeks have regular lessons and cancellations.
      expect(byName['10a – Timetable']!.events, isNotEmpty);
      expect(byName['10a – Cancelled']!.events, isNotEmpty);
      expect(api.eventsIn('personal'), isEmpty);

      // Second run: nothing changes.
      api.log.clear();
      final again = await n.run('sync');
      expect(again.changed, isFalse);
      expect(api.log, isEmpty);
      expect(c.read(calendarSyncsProvider).single.lastError, isNull);

      // A new exam color is applied to the created calendar.
      c
          .read(timetableSettingsProvider.notifier)
          .update((s) => s.copyWith(examColor: 0xFF654321));
      await n.run('sync');
      expect(byName['10a – Exams']!.color, 0xFF654321);

      // Removing the sync deletes the created calendars.
      await n.remove('sync');
      expect(api.cals.keys, ['personal']);
      expect(c.read(calendarSyncsProvider), isEmpty);
    });

    test('existing calendar, skipped states, and removal cleans up', () async {
      final n = c.read(calendarSyncsProvider.notifier);
      await n.save(draft(), {
        LessonStatus.regular: const ExistingCalendar('personal'),
        LessonStatus.substitution: const ExistingCalendar('personal'),
        LessonStatus.exam: const ExistingCalendar('personal'),
        LessonStatus.cancelled: const SkipCalendar(),
      });
      expect(api.cals.keys, ['personal']);
      final events = api.eventsIn('personal');
      expect(events, isNotEmpty);
      expect(events.any((e) => e.title.startsWith('Cancelled')), isFalse);

      await n.remove('sync');
      expect(api.eventsIn('personal'), isEmpty);
      expect(api.cals.keys, ['personal']);
    });

    test('a created calendar the user deleted is recreated', () async {
      final n = c.read(calendarSyncsProvider.notifier);
      await n.save(draft(), {
        LessonStatus.regular: const NewCalendar(),
        LessonStatus.cancelled: const SkipCalendar(),
      });
      final id = c.read(calendarSyncsProvider).single.calendars.values.single;
      api.cals.remove(id);
      await n.run('sync');
      final s = c.read(calendarSyncsProvider).single;
      final fresh = s.calendars[LessonStatus.regular]!;
      expect(fresh, isNot(id));
      expect(api.eventsIn(fresh), isNotEmpty);
    });

    test(
      'deleting phone calendars: syncs forget them, not recreated',
      () async {
        final n = c.read(calendarSyncsProvider.notifier);
        await n.save(draft(), {
          LessonStatus.regular: const NewCalendar(),
          LessonStatus.substitution: const ExistingCalendar('personal'),
          LessonStatus.exam: const SkipCalendar(),
          LessonStatus.cancelled: const SkipCalendar(),
        });
        final own = c
            .read(calendarSyncsProvider)
            .single
            .calendars[LessonStatus.regular]!;
        expect(await n.deleteCalendars({own}), 0);
        expect(api.cals.containsKey(own), isFalse);
        final s = c.read(calendarSyncsProvider).single;
        expect(s.calendars.keys, [LessonStatus.substitution]);
        expect(s.created, isEmpty);
        await n.run('sync');
        expect(api.cals.keys, ['personal']);

        // Last calendar gone: the sync is removed.
        final other = await api.createCalendar('Other', 0xFF000000);
        await n.save(draft(), {LessonStatus.regular: ExistingCalendar(other)});
        expect(await n.deleteCalendars({other}), 1);
        expect(c.read(calendarSyncsProvider), isEmpty);
      },
    );

    test('no calendar access is reported', () async {
      api.granted = false;
      final n = c.read(calendarSyncsProvider.notifier);
      await expectLater(
        n.save(draft(), {LessonStatus.regular: const NewCalendar()}),
        throwsA(isA<CalendarAccessException>()),
      );
    });

    test('automatic sync skips recent and manual syncs', () async {
      final n = c.read(calendarSyncsProvider.notifier);
      await n.save(draft(), {LessonStatus.regular: const NewCalendar()});
      final last = c.read(calendarSyncsProvider).single.lastSync!;
      api.log.clear();
      await n.syncDue(now: last.add(const Duration(minutes: 5)));
      expect(c.read(calendarSyncsProvider).single.lastSync, last);
      await n.syncDue(now: last.add(const Duration(hours: 1)));
      expect(c.read(calendarSyncsProvider).single.lastSync, isNot(last));
    });
  });
}
