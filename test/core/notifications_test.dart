import 'dart:async';

import 'package:better_betteruntis/core/change_sources.dart';
import 'package:better_betteruntis/core/daily_notifications.dart';
import 'package:better_betteruntis/core/info.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/lesson_notes.dart';
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
  FakeNotifier({this.canSchedule = false});
  final shown = <AppNotification>[];

  /// Pending scheduled notifications by id.
  final scheduled = <int, (AppNotification, DateTime)>{};
  bool fail = false;

  @override
  final bool canSchedule;

  @override
  Future<void> schedule(AppNotification n, DateTime at) async =>
      scheduled[n.id] = (n, at);

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<bool> exactTimeAllowed() async => true;

  @override
  Future<void> requestExactTime() async {}
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

  group('daily settings', () {
    test('defaults', () {
      const s = NotificationSettings();
      expect(s.dailySummary, isTrue);
      expect(s.dailyMinute, 420);
      expect(s.examReminderDays, 0);
      expect(s.homeworkReminderDays, 0);
    });

    test('JSON round-trip', () {
      const s = NotificationSettings(
        enabled: true,
        dailySummary: false,
        dailyMinute: 18 * 60 + 5,
        examReminderDays: 3,
        homeworkReminderDays: 1,
      );
      expect(NotificationSettings.fromJson(s.toJson()), s);
      expect(NotificationSettings.fromJson(s.toJson()).hashCode, s.hashCode);
      expect(s, isNot(s.copyWith(dailyMinute: 0)));
    });

    test('clamping', () {
      final t = NotificationSettings.fromJson({
        'dailyMinute': 5000,
        'examReminderDays': 99,
        'homeworkReminderDays': -4,
      });
      expect(t.dailyMinute, 1439);
      expect(t.examReminderDays, 7);
      expect(t.homeworkReminderDays, 0);
      const d = NotificationSettings();
      expect(d.copyWith(dailyMinute: -5).dailyMinute, 0);
      expect(d.copyWith(dailyMinute: 9999).dailyMinute, 1439);
      expect(d.copyWith(examReminderDays: 30).examReminderDays, 7);
      expect(d.copyWith(homeworkReminderDays: -1).homeworkReminderDays, 0);
    });

    test('old JSON without the new fields gets the defaults', () {
      final s = NotificationSettings.fromJson({
        'enabled': true,
        'timetable': false,
        'messages': true,
        'daysAhead': 4,
      });
      expect(s.enabled, isTrue);
      expect(s.daysAhead, 4);
      expect(s.dailySummary, isTrue);
      expect(s.dailyMinute, 420);
      expect(s.examReminderDays, 0);
      expect(s.homeworkReminderDays, 0);
      final w = NotificationSettings.fromJson({
        'dailySummary': 'x',
        'dailyMinute': 'x',
        'examReminderDays': null,
      });
      expect(w.dailySummary, isTrue);
      expect(w.dailyMinute, 420);
    });

    test('hasDaily', () {
      expect(const NotificationSettings().hasDaily, isFalse); // disabled
      expect(const NotificationSettings(enabled: true).hasDaily, isTrue);
      expect(
        const NotificationSettings(enabled: true, dailySummary: false).hasDaily,
        isFalse,
      );
      expect(
        const NotificationSettings(
          enabled: true,
          dailySummary: false,
          homeworkReminderDays: 1,
        ).hasDaily,
        isTrue,
      );
      expect(
        const NotificationSettings(
          enabled: true,
          dailySummary: false,
          examReminderDays: 2,
        ).hasDaily,
        isTrue,
      );
    });

    test('state keeps the daily map in JSON', () {
      final s = NotificationState(daily: {'a': '2026-11-18'});
      final back = NotificationState.fromJson(s.toJson());
      expect(back.daily, {'a': '2026-11-18'});
      expect(NotificationState().toJson().containsKey('daily'), isFalse);
    });
  });

  group('backgroundMinIntervalAt', () {
    const on = NotificationPrefs({'a': NotificationSettings(enabled: true)});
    const ten = Duration(minutes: 10);
    const forty = Duration(minutes: 40);

    test('weekday inside and outside the window', () {
      // Wednesday; default 07:00 -> from 06:00 until 18:00.
      expect(backgroundMinIntervalAt(DateTime(2026, 11, 18, 6), on), ten);
      expect(backgroundMinIntervalAt(DateTime(2026, 11, 18, 12), on), ten);
      expect(backgroundMinIntervalAt(DateTime(2026, 11, 18, 17, 59), on), ten);
      expect(backgroundMinIntervalAt(DateTime(2026, 11, 18, 5, 59), on), forty);
      expect(backgroundMinIntervalAt(DateTime(2026, 11, 18, 18), on), forty);
    });

    test('weekend is calm', () {
      expect(backgroundMinIntervalAt(DateTime(2026, 11, 21, 7), on), forty);
      expect(backgroundMinIntervalAt(DateTime(2026, 11, 22, 7), on), forty);
    });

    test('custom earliest time and accounts without daily', () {
      final prefs = NotificationPrefs({
        'a': const NotificationSettings(enabled: true, dailyMinute: 8 * 60),
        'b': const NotificationSettings(enabled: true, dailyMinute: 5 * 60),
        // No daily at all: does not count.
        'c': const NotificationSettings(
          enabled: true,
          dailySummary: false,
          dailyMinute: 3 * 60,
        ),
      });
      expect(backgroundMinIntervalAt(DateTime(2026, 11, 18, 4), prefs), ten);
      expect(
        backgroundMinIntervalAt(DateTime(2026, 11, 18, 3, 59), prefs),
        forty,
      );
      final late = NotificationPrefs({
        'a': const NotificationSettings(enabled: true, dailyMinute: 9 * 60),
      });
      expect(backgroundMinIntervalAt(DateTime(2026, 11, 18, 7), late), forty);
      expect(backgroundMinIntervalAt(DateTime(2026, 11, 18, 8), late), ten);
    });

    test('no daily time: the 07:00 default', () {
      const none = NotificationPrefs();
      expect(backgroundMinIntervalAt(DateTime(2026, 11, 18, 6), none), ten);
      expect(backgroundMinIntervalAt(DateTime(2026, 11, 18, 5), none), forty);
    });
  });

  group('dailySummary and dailyReminders', () {
    final acc = _account('a');
    final wed = DateTime(2026, 11, 18);
    const s = NotificationSettings(enabled: true);

    ExamItem exam(DateTime start, {CustomSource? custom, String type = ''}) =>
        ExamItem(
          id: 1,
          start: start,
          end: start.add(const Duration(hours: 1)),
          subjectId: 1,
          examType: type,
          custom: custom,
        );

    HomeworkItem hw(DateTime due, {bool done = false, CustomSource? custom}) =>
        HomeworkItem(
          id: 1,
          lessonId: 1,
          assignedOn: DateTime(2026, 11, 10),
          dueOn: due,
          text: 'p. 34\nsecond line',
          subjectId: 2,
          completed: done,
          custom: custom,
        );

    test('no changes', () {
      final n = dailySummary(
        acc,
        wed,
        [_period(1, DateTime(2026, 11, 18, 8))],
        _names,
        const [],
      )!;
      expect(n.title, 'Wed 18.11.: no changes · Max');
      expect(n.body, 'Your timetable is as planned.');
      expect(n.id, dailySummaryId('a'));
      expect(NotificationTarget.parse(n.payload)!.day, wed);
    });

    test('changes and tests', () {
      final n = dailySummary(
        acc,
        wed,
        [
          _period(1, DateTime(2026, 11, 18, 8)),
          _period(2, DateTime(2026, 11, 18, 9), flags: {PeriodFlag.cancelled}),
          // Another day: ignored.
          _period(3, DateTime(2026, 11, 19, 9), flags: {PeriodFlag.cancelled}),
        ],
        _names,
        [
          exam(DateTime(2026, 11, 18, 10), type: 'Schularbeit'),
          exam(DateTime(2026, 11, 19, 10)),
        ],
      )!;
      expect(n.title, 'Wed 18.11.: 1 change, 1 test · Max');
      expect(
        n.body,
        '09:00–09:50: M cancelled\nTest 10:00: Maths · Schularbeit',
      );
    });

    test('plural and only tests', () {
      final n = dailySummary(acc, wed, const [], _names, [
        exam(DateTime(2026, 11, 18, 8)),
        exam(DateTime(2026, 11, 18, 10)),
      ])!;
      expect(n.title, 'Wed 18.11.: 2 tests · Max');
    });

    test('null without lessons and tests (weekend, holiday)', () {
      expect(
        dailySummary(acc, DateTime(2026, 11, 21), const [], _names, const []),
        isNull,
      );
      // Lessons only on another day.
      expect(
        dailySummary(
          acc,
          DateTime(2026, 11, 21),
          [_period(1, DateTime(2026, 11, 20, 8))],
          _names,
          const [],
        ),
        isNull,
      );
    });

    test('custom exam is marked as own', () {
      final label = examLabel(
        exam(
          DateTime(2026, 11, 18, 10),
          custom: const CustomSource(noteKeys: ['k']),
        ),
        _names,
      );
      expect(label, 'Maths (own)');
      expect(examLabel(exam(DateTime(2026, 11, 18, 10)), _names), 'Maths');
    });

    test('homework label', () {
      expect(homeworkLabel(hw(wed), _names), 'German: p. 34');
      expect(
        homeworkLabel(
          hw(wed, custom: const CustomSource(noteKeys: ['k'])),
          _names,
        ),
        'German: p. 34 (own)',
      );
    });

    test('reminders: day offsets and nothing to say', () {
      final settings = s.copyWith(examReminderDays: 2, homeworkReminderDays: 1);
      final exams = [
        exam(DateTime(2026, 11, 20, 8)), // +2
        exam(DateTime(2026, 11, 19, 8)), // +1: not asked for
      ];
      final homework = [
        hw(DateTime(2026, 11, 19)), // +1
        hw(DateTime(2026, 11, 20)), // +2: not asked for
      ];
      final n = dailyReminders(
        acc,
        wed,
        settings,
        _names,
        exams: exams,
        homework: homework,
      )!;
      expect(n.id, dailyRemindersId('a'));
      expect(n.title, 'Coming up · Max');
      expect(
        n.body,
        'Test Fri 20.11. 08:00: Maths\nHomework for Thu 19.11.: German: p. 34',
      );
      // The earliest of the days.
      expect(NotificationTarget.parse(n.payload)!.day, DateTime(2026, 11, 19));

      expect(
        dailyReminders(acc, wed, s, _names, exams: exams, homework: homework),
        isNull,
      );
      expect(
        dailyReminders(
          acc,
          wed,
          settings,
          _names,
          exams: const [],
          homework: const [],
        ),
        isNull,
      );
    });

    test('completed homework is skipped, only exams give the exam day', () {
      final settings = s.copyWith(examReminderDays: 2, homeworkReminderDays: 1);
      expect(
        dailyReminders(
          acc,
          wed,
          settings,
          _names,
          exams: const [],
          homework: [hw(DateTime(2026, 11, 19), done: true)],
        ),
        isNull,
      );
      final n = dailyReminders(
        acc,
        wed,
        settings,
        _names,
        exams: [exam(DateTime(2026, 11, 20, 8))],
        homework: [hw(DateTime(2026, 11, 19), done: true)],
      )!;
      expect(n.body, 'Test Fri 20.11. 08:00: Maths');
      expect(NotificationTarget.parse(n.payload)!.day, DateTime(2026, 11, 20));
    });
  });

  group('ChangeChecker daily', () {
    late MemoryNotificationStateStore store;
    late FakeSource timetable;
    late _FakePlanner planner;
    final acc = [_account('a')];
    var now = DateTime(2026, 11, 18, 6);
    const dailyOn = NotificationPrefs({
      'a': NotificationSettings(enabled: true),
    });
    final today = DateTime(2026, 11, 18);
    final sumId = dailySummaryId('a');
    final remId = dailyRemindersId('a');

    ChangeChecker checker(FakeNotifier notifier) => ChangeChecker(
      sources: [timetable],
      stateStore: store,
      notifier: notifier,
      daily: planner,
      clock: () => now,
    );

    ChangeItem change(String key, DateTime start) => ChangeItem(
      key: key,
      signature: 'a',
      text: key,
      start: start,
      end: start.add(const Duration(minutes: 50)),
    );

    Future<NotificationState> state() async =>
        NotificationState.fromJson(await store.load());

    setUp(() {
      store = MemoryNotificationStateStore();
      timetable = FakeSource('timetable');
      planner = _FakePlanner();
      now = DateTime(2026, 11, 18, 6);
    });

    test(
      'before the time: today is silent, summary scheduled for today',
      () async {
        final n = FakeNotifier(canSchedule: true);
        await checker(n).run(acc, dailyOn); // baseline
        timetable.items = [change('x', DateTime(2026, 11, 18, 9))];
        final shown = await checker(n).run(acc, dailyOn);
        expect(shown, isEmpty);
        expect(n.shown, isEmpty);
        expect(n.scheduled[sumId]!.$2, DateTime(2026, 11, 18, 7));
        expect(n.scheduled[remId]!.$2, DateTime(2026, 11, 18, 7));
        expect(planner.calls.last, ('a', today));
        expect((await state()).daily['a'], '2026-11-18');

        // A change on another day is not held back.
        timetable.items = [
          change('x', DateTime(2026, 11, 18, 9)),
          change('y', DateTime(2026, 11, 19, 9)),
        ];
        expect(await checker(n).run(acc, dailyOn), hasLength(1));
      },
    );

    test(
      'after the time: new change is notified, tomorrow scheduled',
      () async {
        now = DateTime(2026, 11, 18, 8);
        store.state = {
          'daily': {'a': '2026-11-18'},
        };
        final n = FakeNotifier(canSchedule: true);
        await checker(n).run(acc, dailyOn); // baseline
        timetable.items = [change('x', DateTime(2026, 11, 18, 9))];
        final shown = await checker(n).run(acc, dailyOn);
        expect(shown, hasLength(1));
        expect(shown.single.id, notificationId('a', 'timetable'));
        expect(n.shown, hasLength(1)); // no summary: already done
        expect(planner.calls.map((c) => c.$2).toSet(), {
          DateTime(2026, 11, 19),
        });
        expect(n.scheduled[sumId]!.$2, DateTime(2026, 11, 19, 7));
        expect((await state()).daily['a'], '2026-11-19');
      },
    );

    test('overdue without scheduling: shown late once, today silent', () async {
      now = DateTime(2026, 11, 18, 9);
      final n = FakeNotifier();
      const off = NotificationPrefs({
        'a': NotificationSettings(enabled: true, dailySummary: false),
      });
      await checker(n).run(acc, off); // baseline, no daily
      expect(planner.calls, isEmpty);

      timetable.items = [change('x', DateTime(2026, 11, 18, 10))];
      final shown = await checker(n).run(acc, dailyOn);
      expect(shown.map((e) => e.id), [sumId, remId]);
      expect(n.shown, hasLength(2));
      expect(planner.calls, [('a', today)]);
      expect((await state()).daily['a'], '2026-11-18');

      now = DateTime(2026, 11, 18, 9, 30);
      expect(await checker(n).run(acc, dailyOn), isEmpty);
      expect(n.shown, hasLength(2));
      expect(planner.calls, hasLength(1));
    });

    test('more than 10 hours late: not shown', () async {
      now = DateTime(2026, 11, 18, 17, 30);
      final n = FakeNotifier();
      await checker(n).run(acc, dailyOn);
      timetable.items = [change('x', DateTime(2026, 11, 18, 18))];
      final shown = await checker(n).run(acc, dailyOn);
      // Only the ordinary change notification.
      expect(shown.map((e) => e.id), [notificationId('a', 'timetable')]);
      expect(planner.calls, isEmpty);
      expect((await state()).daily, isEmpty);
    });

    test('digest null (offline): state.daily not advanced', () async {
      planner.fn = (_, _) => null;
      final n = FakeNotifier(canSchedule: true);
      await checker(n).run(acc, dailyOn);
      expect(planner.calls, isNotEmpty);
      expect(n.scheduled, isEmpty);
      expect((await state()).daily, isEmpty);

      // Overdue and offline: nothing shown and not marked.
      now = DateTime(2026, 11, 18, 9);
      final web = FakeNotifier();
      await checker(web).run(acc, dailyOn);
      expect(web.shown, isEmpty);
      expect((await state()).daily, isEmpty);
    });

    test('turning daily off cancels both ids and drops the state', () async {
      final n = FakeNotifier(canSchedule: true);
      await checker(n).run(acc, dailyOn);
      expect(n.scheduled.keys, unorderedEquals([sumId, remId]));
      expect((await state()).daily['a'], isNotNull);

      const off = NotificationPrefs({
        'a': NotificationSettings(enabled: true, dailySummary: false),
      });
      await checker(n).run(acc, off);
      expect(n.scheduled, isEmpty);
      expect((await state()).daily, isEmpty);
    });

    test('a removed account cancels its ids', () async {
      final n = FakeNotifier(canSchedule: true);
      await checker(n).run(acc, dailyOn);
      await checker(n).run([_account('b')], dailyOn);
      expect(n.scheduled, isEmpty);
      expect((await state()).daily, isEmpty);
    });

    test('a digest without summary cancels the summary id', () async {
      final n = FakeNotifier(canSchedule: true);
      await checker(n).run(acc, dailyOn);
      expect(n.scheduled.keys, unorderedEquals([sumId, remId]));
      planner.fn = (a, d) => DailyDigest(reminders: _note(remId));
      await checker(n).run(acc, dailyOn);
      expect(n.scheduled.keys, [remId]);
    });
  });

  group('RepositoryDailyPlanner', () {
    final wedPeriods = {
      '2026-11-16': [
        _period(2, DateTime(2026, 11, 18, 9), flags: {PeriodFlag.cancelled}),
      ],
    };
    final wed = DateTime(2026, 11, 18);

    test('summary from the week, tests error still gives own tests', () async {
      final info = _FakeInfo()..examsError = true;
      final planner = RepositoryDailyPlanner(
        timetables: _FakeTimetables(wedPeriods),
        info: info,
        notes: () async => {
          'a|2026-11-18|1000|5|1': const LessonNote(exam: true),
        },
      );
      final d = (await planner.digest(
        _account('a'),
        const NotificationSettings(enabled: true),
        wed,
      ))!;
      expect(d.summary!.title, 'Wed 18.11.: 1 change, 1 test · Max');
      expect(d.summary!.body, contains('Test 10:00: Maths (own)'));
      expect(d.reminders, isNull);
    });

    test('reminders from school and own homework', () async {
      final info = _FakeInfo()
        ..homeworkItems = [
          HomeworkItem(
            id: 1,
            lessonId: 1,
            assignedOn: wed,
            dueOn: DateTime(2026, 11, 19),
            text: 'p. 1',
            subjectId: 2,
          ),
        ];
      final planner = RepositoryDailyPlanner(
        timetables: _FakeTimetables(wedPeriods),
        info: info,
        notes: () async => {
          'a|2026-11-19|0800|6|1': const LessonNote(homework: 'worksheet'),
        },
      );
      final d = (await planner.digest(
        _account('a'),
        const NotificationSettings(
          enabled: true,
          dailySummary: false,
          homeworkReminderDays: 1,
        ),
        wed,
      ))!;
      expect(d.summary, isNull);
      expect(
        d.reminders!.body,
        'Homework for Thu 19.11.: German: p. 1\n'
        'Homework for Thu 19.11.: Maths: worksheet (own)',
      );
    });

    test('week failure propagates (the checker keeps its state)', () async {
      final repo = _FakeTimetables({})..failWeek = true;
      final planner = RepositoryDailyPlanner(
        timetables: repo,
        info: _FakeInfo(),
        notes: () async => {},
      );
      await expectLater(
        planner.digest(_account('a'), const NotificationSettings(), wed),
        throwsA(isA<UntisException>()),
      );
    });
  });
}

class _FakeTimetables implements TimetableRepository {
  _FakeTimetables(this.weeks);

  final Map<String, List<Period>> weeks;
  final refreshed = <String>[];
  bool fail = false;
  bool failWeek = false;

  @override
  Future<List<Period>> week(Account a, TimetableTarget t, DateTime w) async {
    if (failWeek) throw const UntisException(0, 'offline');
    return watchWeek(a, t, w).first;
  }

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

class _FakePlanner implements DailyPlanner {
  final calls = <(String, DateTime)>[];
  DailyDigest? Function(Account, DateTime) fn = (a, d) => DailyDigest(
    summary: _note(dailySummaryId(a.id)),
    reminders: _note(dailyRemindersId(a.id)),
  );

  @override
  Future<DailyDigest?> digest(
    Account account,
    NotificationSettings s,
    DateTime day,
  ) async {
    calls.add((account.id, day));
    return fn(account, day);
  }
}

AppNotification _note(int id) =>
    AppNotification(id: id, title: 't$id', body: 'b', payload: '');

class _FakeInfo implements InfoCenterRepository {
  bool examsError = false;
  List<HomeworkItem> homeworkItems = [];

  @override
  Stream<Cached<List<ExamItem>>> exams(
    Account a,
    DateTime start,
    DateTime end, {
    bool force = false,
  }) => examsError
      ? Stream.error(const UntisException(0, 'no access'))
      : Stream.value(const Cached(data: <ExamItem>[]));

  @override
  Stream<Cached<List<HomeworkItem>>> homework(
    Account a,
    DateTime start,
    DateTime end, {
    bool force = false,
  }) => Stream.value(Cached(data: homeworkItems));

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
