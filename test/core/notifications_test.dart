import 'dart:async';

import 'package:better_betteruntis/core/change_sources.dart';
import 'package:better_betteruntis/core/info.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/notifications.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/data/name_resolver_impl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _school = School(
  schoolId: 1,
  loginName: 's',
  displayName: 'School',
  address: '',
  host: 'x.webuntis.com',
);

Account _account(String id, {String name = 'Max'}) => Account(
  id: id,
  school: _school,
  username: 'u$id',
  anonymous: false,
  displayName: name,
  elementType: ElementType.student,
  elementId: 7,
);

final _names = NameResolverImpl(
  elements: const [
    MasterElement(
      type: ElementType.subject,
      id: 1,
      name: 'M',
      longName: 'Maths',
    ),
    MasterElement(
      type: ElementType.subject,
      id: 2,
      name: 'D',
      longName: 'German',
    ),
    MasterElement(
      type: ElementType.teacher,
      id: 10,
      name: 'MUE',
      longName: 'Müller',
    ),
    MasterElement(
      type: ElementType.teacher,
      id: 11,
      name: 'HUB',
      longName: 'Huber',
    ),
    MasterElement(
      type: ElementType.room,
      id: 20,
      name: 'R1',
      longName: 'Room 1',
    ),
    MasterElement(
      type: ElementType.room,
      id: 21,
      name: 'R7',
      longName: 'Room 7',
    ),
  ],
);

ElementRef _ref(ElementType t, int id, [int? org]) =>
    ElementRef(type: t, id: id, orgId: org ?? id);

Period _period(
  int id,
  DateTime start, {
  int minutes = 50,
  int subject = 1,
  int teacher = 10,
  int? orgTeacher,
  int room = 20,
  int? orgRoom,
  Set<PeriodFlag> flags = const {PeriodFlag.regular},
  String substitutionText = '',
}) => Period(
  id: id,
  lessonId: id,
  start: start,
  end: start.add(Duration(minutes: minutes)),
  elements: [
    _ref(ElementType.subject, subject),
    _ref(ElementType.teacher, teacher, orgTeacher),
    _ref(ElementType.room, room, orgRoom),
  ],
  flags: flags,
  substitutionText: substitutionText,
);

ChangeItem _item(String key, [String sig = 'a', bool silent = false]) =>
    ChangeItem(key: key, signature: sig, text: key, silent: silent);

class FakeNotifier implements LocalNotifier {
  final shown = <AppNotification>[];
  bool fail = false;
  bool grant = true;
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> show(AppNotification n) async {
    if (fail) throw StateError('no channel');
    shown.add(n);
  }

  @override
  Stream<String> get taps => const Stream.empty();

  @override
  Future<String?> takeLaunchPayload() async => null;
}

class FakeSource extends ChangeSource {
  FakeSource(this.id, {this.kindEnabled});

  @override
  final String id;
  final bool Function(NotificationSettings s)? kindEnabled;
  List<ChangeItem>? items = [];
  bool throws = false;
  String scopeValue = '';
  int calls = 0;

  @override
  bool enabledIn(NotificationSettings s) => kindEnabled?.call(s) ?? true;

  @override
  String scope(Account account, NotificationSettings s) => scopeValue;

  @override
  Future<List<ChangeItem>?> current(
    Account account,
    NotificationSettings s,
    DateTime now,
  ) async {
    calls++;
    if (throws) throw const UntisException(0, 'offline');
    return items;
  }

  @override
  String title(int count) => '$count $id';

  @override
  NotificationTarget target(Account account, List<ChangeItem> fresh) =>
      NotificationTarget.inbox(account.id);
}

void main() {
  group('NotificationSettings', () {
    test('defaults: off, both kinds, 2 days', () {
      const s = NotificationSettings();
      expect(s.enabled, isFalse);
      expect(s.timetable, isTrue);
      expect(s.messages, isTrue);
      expect(s.daysAhead, 2);
    });

    test('JSON round-trip and tolerant parse', () {
      const s = NotificationSettings(
        enabled: true,
        timetable: false,
        messages: true,
        daysAhead: 5,
      );
      expect(NotificationSettings.fromJson(s.toJson()), s);
      expect(NotificationSettings.fromJson('x'), const NotificationSettings());
      final t = NotificationSettings.fromJson({
        'enabled': 'yes',
        'daysAhead': 99,
      });
      expect(t.enabled, isFalse);
      expect(t.daysAhead, NotificationSettings.maxDaysAhead);
      expect(const NotificationSettings().copyWith(daysAhead: -3).daysAhead, 0);
    });

    test('prefs are per account', () {
      final p = const NotificationPrefs().withAccount(
        'a',
        const NotificationSettings(enabled: true),
      );
      expect(p.of('a').enabled, isTrue);
      expect(p.of('b').enabled, isFalse);
      expect(p.anyEnabled, isTrue);
      expect(NotificationPrefs.fromJson(p.toJson()), p);
      expect(NotificationPrefs.fromJson(null).anyEnabled, isFalse);
    });

    test('notifier persists to the settings store and loads it', () async {
      final store = MemorySettingsStore();
      final c = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      c
          .read(notificationPrefsProvider.notifier)
          .update('a', (s) => s.copyWith(enabled: true, daysAhead: 3));
      await Future<void>.delayed(Duration.zero);
      expect(
        NotificationPrefs.fromJson(store.values[NotificationPrefs.storeKey])
            .of('a')
            .daysAhead,
        3,
      );

      final c2 = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c2.dispose);
      expect(c2.read(notificationPrefsProvider).of('a').enabled, isTrue);
    });
  });

  group('diffChanges', () {
    test('first run (no state) is only the baseline', () {
      final d = diffChanges(null, [_item('1'), _item('2')]);
      expect(d.fresh, isEmpty);
      expect(d.seen, {'1': 'a', '2': 'a'});
    });

    test('new keys and changed signatures are fresh, known ones not', () {
      final d = diffChanges(
        {'1': 'a', '2': 'a'},
        [_item('1'), _item('2', 'b'), _item('3')],
      );
      expect(d.fresh.map((i) => i.key), ['2', '3']);
      expect(d.seen, {'1': 'a', '2': 'b', '3': 'a'});
    });

    test('silent items are recorded but not fresh; gone items dropped', () {
      final d = diffChanges({'1': 'a'}, [_item('2', 'a', true)]);
      expect(d.fresh, isEmpty);
      expect(d.seen, {'2': 'a'});
    });

    test('a duplicate key is fresh once', () {
      final d = diffChanges({}, [_item('1'), _item('1')]);
      expect(d.fresh, hasLength(1));
    });
  });

  group('ids and payloads', () {
    test('notification ids are stable, distinct and below 2^30', () {
      final a = notificationId('acc-1', 'timetable');
      expect(notificationId('acc-1', 'timetable'), a);
      expect(notificationId('acc-1', 'messages'), isNot(a));
      for (final id in [
        a,
        notificationId('x' * 500, 'messages'),
        notificationId('', ''),
      ]) {
        expect(id, inInclusiveRange(0, 0x3FFFFFFF));
      }
    });

    test('target payload round-trip', () {
      final t = NotificationTarget.parse(
        NotificationTarget.timetable('acc', DateTime(2026, 11, 18)).payload,
      )!;
      expect(t.accountId, 'acc');
      expect(t.kind, NotificationTarget.timetableKind);
      expect(t.day, DateTime(2026, 11, 18));
      final i = NotificationTarget.parse(
        const NotificationTarget.inbox('acc').payload,
      )!;
      expect(i.kind, NotificationTarget.inboxKind);
      expect(i.day, isNull);
      expect(NotificationTarget.parse(''), isNull);
      expect(NotificationTarget.parse(null), isNull);
    });
  });

  group('timetable changes', () {
    // Wednesday.
    final now = DateTime(2026, 11, 18, 7);
    final days = notificationDays(now, 2);

    test('days ahead skip the weekend', () {
      expect(days, [
        DateTime(2026, 11, 18),
        DateTime(2026, 11, 19),
        DateTime(2026, 11, 20),
      ]);
      expect(notificationDays(DateTime(2026, 11, 20, 12), 2), [
        DateTime(2026, 11, 20),
        DateTime(2026, 11, 23),
        DateTime(2026, 11, 24),
      ]);
      expect(notificationDays(now, 0), [DateTime(2026, 11, 18)]);
    });

    test(
      'finds cancellations, substitutions, room changes; skips the rest',
      () {
        final periods = [
          _period(1, DateTime(2026, 11, 18, 8)), // regular
          _period(2, DateTime(2026, 11, 18, 9), flags: {PeriodFlag.cancelled}),
          _period(3, DateTime(2026, 11, 19, 8), teacher: 11, orgTeacher: 10),
          _period(
            4,
            DateTime(2026, 11, 19, 9),
            room: 21,
            orgRoom: 20,
            subject: 2,
          ),
          // Outside the window / already over.
          _period(5, DateTime(2026, 11, 25, 8), flags: {PeriodFlag.cancelled}),
          _period(6, DateTime(2026, 11, 18, 5), flags: {PeriodFlag.cancelled}),
          _period(
            7,
            DateTime(2026, 11, 20, 10),
            flags: {PeriodFlag.irregular},
            substitutionText: 'Supplierung',
          ),
        ];
        final items = timetableChanges(periods, _names, days: days, now: now);
        expect(items.map((i) => i.key), [
          '2026-11-18|2',
          '2026-11-19|3',
          '2026-11-19|4',
          '2026-11-20|7',
        ]);
        expect(items.map((i) => i.text), [
          'M cancelled',
          'M: teacher MUE → HUB',
          'D: room R1 → R7',
          'M changed – Supplierung',
        ]);
      },
    );

    test('signature changes when a substitution becomes a cancellation', () {
      final sub = timetableChanges(
        [_period(3, DateTime(2026, 11, 19, 8), teacher: 11, orgTeacher: 10)],
        _names,
        days: days,
        now: now,
      ).single;
      final cancelled = timetableChanges(
        [
          _period(
            3,
            DateTime(2026, 11, 19, 8),
            teacher: 11,
            orgTeacher: 10,
            flags: {PeriodFlag.cancelled},
          ),
        ],
        _names,
        days: days,
        now: now,
      ).single;
      expect(cancelled.key, sub.key);
      expect(cancelled.signature, isNot(sub.signature));
    });

    test('lines merge consecutive lessons with the same change', () {
      final items = timetableChanges(
        [
          _period(1, DateTime(2026, 11, 18, 8), flags: {PeriodFlag.cancelled}),
          _period(
            2,
            DateTime(2026, 11, 18, 8, 50),
            flags: {PeriodFlag.cancelled},
          ),
          _period(3, DateTime(2026, 11, 19, 8), teacher: 11, orgTeacher: 10),
        ],
        _names,
        days: days,
        now: now,
      );
      expect(timetableLines(items), [
        'Wed 18.11. 08:00–09:40: M cancelled',
        'Thu 19.11. 08:00–08:50: M: teacher MUE → HUB',
      ]);
    });
  });

  test('messages: unread are news, read only recorded', () {
    final items = messageChanges([
      InboxMessage(
        id: 1,
        subject: 'Trip',
        preview: '',
        sender: 'Office',
        sentAt: null,
      ),
      const InboxMessage(
        id: 2,
        subject: '',
        preview: '',
        sender: '',
        sentAt: null,
        isRead: true,
      ),
    ]);
    expect(items.map((i) => i.text), ['Office: Trip', '(no subject)']);
    expect(items.map((i) => i.silent), [false, true]);
  });

  group('ChangeChecker', () {
    late MemoryNotificationStateStore store;
    late FakeNotifier notifier;
    late FakeSource timetable;
    late FakeSource messages;
    var now = DateTime(2026, 11, 18, 7);
    final accounts = [_account('a'), _account('b', name: 'Lisa')];
    final on = NotificationPrefs({
      'a': const NotificationSettings(enabled: true),
      'b': const NotificationSettings(enabled: true),
    });

    ChangeChecker checker() => ChangeChecker(
      sources: [timetable, messages],
      stateStore: store,
      notifier: notifier,
      clock: () => now,
      maxLines: 2,
    );

    setUp(() {
      store = MemoryNotificationStateStore();
      notifier = FakeNotifier();
      timetable = FakeSource('timetable', kindEnabled: (s) => s.timetable);
      messages = FakeSource('messages', kindEnabled: (s) => s.messages);
      now = DateTime(2026, 11, 18, 7);
    });

    test('first run is quiet, then each change is notified once', () async {
      timetable.items = [_item('x')];
      expect(await checker().run(accounts, on), isEmpty);

      timetable.items = [_item('x'), _item('y'), _item('z'), _item('w')];
      messages.items = [_item('m1')];
      // A new checker: the state comes from the store, not from memory.
      final shown = await checker().run(accounts, on);
      // One notification per account and source.
      expect(shown, hasLength(4));
      final a = shown.firstWhere(
        (n) => n.id == notificationId('a', 'timetable'),
      );
      expect(a.title, '3 timetable · Max');
      expect(a.body, 'y\nz\n+1 more');

      expect(await checker().run(accounts, on), isEmpty);
    });

    test('accounts with notifications off are not checked', () async {
      final prefs = NotificationPrefs({
        'a': const NotificationSettings(enabled: true, messages: false),
      });
      await checker().run(accounts, prefs);
      expect(timetable.calls, 1);
      expect(messages.calls, 0);
    });

    test('a kind turned off and on again starts quiet', () async {
      timetable.items = [_item('x')];
      await checker().run(accounts, on);
      final off = NotificationPrefs({
        'a': const NotificationSettings(enabled: true, timetable: false),
        'b': const NotificationSettings(enabled: true),
      });
      await checker().run(accounts, off);
      timetable.items = [_item('x'), _item('y')];
      final shown = await checker().run(accounts, on);
      // Account b kept its state and gets y; a starts over.
      expect(shown.map((n) => n.id), [notificationId('b', 'timetable')]);
    });

    test('a changed scope only records a new baseline', () async {
      timetable.items = [_item('x')];
      await checker().run(accounts, on);
      timetable
        ..scopeValue = 'child-2'
        ..items = [_item('y')];
      expect(await checker().run(accounts, on), isEmpty);
    });

    test('an unavailable source keeps its state', () async {
      timetable.items = [_item('x')];
      await checker().run(accounts, on);
      timetable.throws = true;
      await checker().run(accounts, on);
      timetable
        ..throws = false
        ..items = null;
      await checker().run(accounts, on);
      timetable.items = [_item('x')];
      expect(await checker().run(accounts, on), isEmpty);
    });

    test('not shown (notifier failed): tried again next time', () async {
      await checker().run(accounts, on);
      timetable.items = [_item('x')];
      notifier.fail = true;
      expect(await checker().run(accounts, on), isEmpty);
      notifier.fail = false;
      expect(await checker().run(accounts, on), hasLength(2));
    });

    test('minInterval skips a check right after another one', () async {
      await checker().run(accounts, on);
      now = now.add(const Duration(minutes: 2));
      await checker().run(
        accounts,
        on,
        minInterval: const Duration(minutes: 10),
      );
      expect(timetable.calls, 2); // only the first run
      now = now.add(const Duration(minutes: 20));
      await checker().run(
        accounts,
        on,
        minInterval: const Duration(minutes: 10),
      );
      expect(timetable.calls, 4);
    });

    test('state of deleted accounts is dropped', () async {
      timetable.items = [_item('x')];
      await checker().run(accounts, on);
      await checker().run([accounts.first], on);
      final state = NotificationState.fromJson(await store.load());
      expect(state.accounts.keys, ['a']);
    });

    test('concurrent runs share one check', () async {
      final c = checker();
      await Future.wait([c.run(accounts, on), c.run(accounts, on)]);
      expect(timetable.calls, 2);
    });
  });

  group('TimetableChangeSource', () {
    test('loads the own timetable for the days ahead', () async {
      final repo = _FakeTimetables({
        '2026-11-16': [
          _period(2, DateTime(2026, 11, 18, 9), flags: {PeriodFlag.cancelled}),
        ],
        '2026-11-23': [
          _period(9, DateTime(2026, 11, 23, 9), flags: {PeriodFlag.cancelled}),
        ],
      });
      final source = TimetableChangeSource(repo);
      final items = await source.current(
        _account('a'),
        const NotificationSettings(enabled: true, daysAhead: 3),
        DateTime(2026, 11, 18, 7),
      );
      expect(items!.map((i) => i.key), ['2026-11-18|2', '2026-11-23|9']);
      expect(repo.refreshed, ['2026-11-16', '2026-11-23']);
      final target = source.target(_account('a'), items);
      expect(target.day, DateTime(2026, 11, 18));
    });

    test('a failed refresh makes the source unavailable', () async {
      final repo = _FakeTimetables({})..fail = true;
      final checker = ChangeChecker(
        sources: [TimetableChangeSource(repo)],
        stateStore: MemoryNotificationStateStore(),
        notifier: FakeNotifier(),
      );
      expect(
        await checker.run([
          _account('a'),
        ], NotificationPrefs({'a': const NotificationSettings(enabled: true)})),
        isEmpty,
      );
    });
  });
}

class _FakeTimetables implements TimetableRepository {
  _FakeTimetables(this.weeks);

  final Map<String, List<Period>> weeks;
  final refreshed = <String>[];
  bool fail = false;

  @override
  Future<List<Period>> week(Account a, TimetableTarget t, DateTime w) =>
      watchWeek(a, t, w).first;

  @override
  Future<void> refresh(Account a, TimetableTarget t, DateTime weekStart) async {
    if (fail) throw const UntisException(0, 'offline');
    refreshed.add(ymd(weekStart));
  }

  @override
  Stream<List<Period>> watchWeek(
    Account a,
    TimetableTarget t,
    DateTime weekStart,
  ) => Stream.value(weeks[ymd(weekStart)] ?? const []);

  @override
  Stream<NameResolver> watchNames(Account a) => Stream.value(_names);

  @override
  DateTime? lastRefreshed(Account a, TimetableTarget t, DateTime w) => null;

  @override
  Future<void> discoverTeachers(
    Account account,
    DateTime weekStart, {
    void Function(int done, int total)? onProgress,
  }) async {}
}
