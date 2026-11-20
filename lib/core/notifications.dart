/// Local notifications about changes that matter: substitutions,
/// cancellations and room changes in the own timetable, new inbox messages,
/// and more kinds through [ChangeSource].
///
/// Everything here is pure Dart: settings per account, the "last seen" state
/// with its de-duplication ([diffChanges]), the check itself
/// ([ChangeChecker]) and the [LocalNotifier] contract. The platform side
/// (flutter_local_notifications, the Android background check, the web
/// in-app snackbar) lives in lib/app/notifications/.
///
/// Nothing leaves the device: the check uses the same WebUntis requests as
/// the timetable and the Info center, with the stored credentials.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'settings.dart';

// ---- Settings ----------------------------------------------------------

/// Notification options of one account. Off by default.
class NotificationSettings {
  const NotificationSettings({
    this.enabled = false,
    this.timetable = true,
    this.messages = true,
    this.daysAhead = defaultDaysAhead,
    this.dailySummary = true,
    this.dailyMinute = defaultDailyMinute,
    this.examReminderDays = 0,
    this.homeworkReminderDays = 0,
  });

  static const defaultDaysAhead = 2;
  static const maxDaysAhead = 7;

  /// 07:00.
  static const defaultDailyMinute = 7 * 60;
  static const maxReminderDays = 7;

  final bool enabled;

  /// Substitutions, cancellations, room changes in the own timetable.
  final bool timetable;

  /// New (unread) inbox messages.
  final bool messages;

  /// School days after today that are checked (today always is).
  /// Saturdays and Sundays don't count.
  final int daysAhead;

  /// Every day at [dailyMinute]: today's changes and tests in one
  /// notification. Changes to today found after that time are notified
  /// right away; before it they wait for the summary.
  final bool dailySummary;

  /// Time of the daily summary and the reminders, minutes after midnight.
  final int dailyMinute;

  /// Reminder about tests this many days before (at [dailyMinute]); 0 = off.
  final int examReminderDays;

  /// Reminder about homework due in this many days (at [dailyMinute]);
  /// 0 = off.
  final int homeworkReminderDays;

  /// Whether anything is delivered at [dailyMinute].
  bool get hasDaily =>
      enabled &&
      (dailySummary || examReminderDays > 0 || homeworkReminderDays > 0);

  NotificationSettings copyWith({
    bool? enabled,
    bool? timetable,
    bool? messages,
    int? daysAhead,
    bool? dailySummary,
    int? dailyMinute,
    int? examReminderDays,
    int? homeworkReminderDays,
  }) => NotificationSettings(
    enabled: enabled ?? this.enabled,
    timetable: timetable ?? this.timetable,
    messages: messages ?? this.messages,
    daysAhead: (daysAhead ?? this.daysAhead).clamp(0, maxDaysAhead),
    dailySummary: dailySummary ?? this.dailySummary,
    dailyMinute: (dailyMinute ?? this.dailyMinute).clamp(0, 24 * 60 - 1),
    examReminderDays: (examReminderDays ?? this.examReminderDays).clamp(
      0,
      maxReminderDays,
    ),
    homeworkReminderDays: (homeworkReminderDays ?? this.homeworkReminderDays)
        .clamp(0, maxReminderDays),
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'timetable': timetable,
    'messages': messages,
    'daysAhead': daysAhead,
    'dailySummary': dailySummary,
    'dailyMinute': dailyMinute,
    'examReminderDays': examReminderDays,
    'homeworkReminderDays': homeworkReminderDays,
  };

  /// Tolerant parse: wrong or missing fields fall back to the defaults.
  factory NotificationSettings.fromJson(Object? json) {
    const d = NotificationSettings();
    if (json is! Map) return d;
    bool b(String k, bool def) => json[k] is bool ? json[k] as bool : def;
    final days = json['daysAhead'];
    int n(String k, int def, int max) =>
        json[k] is num ? (json[k] as num).toInt().clamp(0, max) : def;
    return NotificationSettings(
      enabled: b('enabled', d.enabled),
      timetable: b('timetable', d.timetable),
      messages: b('messages', d.messages),
      daysAhead: days is num
          ? days.toInt().clamp(0, maxDaysAhead)
          : d.daysAhead,
      dailySummary: b('dailySummary', d.dailySummary),
      dailyMinute: n('dailyMinute', d.dailyMinute, 24 * 60 - 1),
      examReminderDays: n('examReminderDays', 0, maxReminderDays),
      homeworkReminderDays: n('homeworkReminderDays', 0, maxReminderDays),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationSettings &&
      other.enabled == enabled &&
      other.timetable == timetable &&
      other.messages == messages &&
      other.daysAhead == daysAhead &&
      other.dailySummary == dailySummary &&
      other.dailyMinute == dailyMinute &&
      other.examReminderDays == examReminderDays &&
      other.homeworkReminderDays == homeworkReminderDays;

  @override
  int get hashCode => Object.hash(
    enabled,
    timetable,
    messages,
    daysAhead,
    dailySummary,
    dailyMinute,
    examReminderDays,
    homeworkReminderDays,
  );
}

/// [NotificationSettings] of every account, keyed by account id. Stored on
/// this device only (not synced).
class NotificationPrefs {
  const NotificationPrefs([this.byAccount = const {}]);

  /// Settings store key.
  static const storeKey = 'notifications';

  final Map<String, NotificationSettings> byAccount;

  NotificationSettings of(String accountId) =>
      byAccount[accountId] ?? const NotificationSettings();

  bool get anyEnabled => byAccount.values.any((s) => s.enabled);

  NotificationPrefs withAccount(String accountId, NotificationSettings s) =>
      NotificationPrefs(Map.unmodifiable({...byAccount, accountId: s}));

  Map<String, Object?> toJson() => {
    for (final e in byAccount.entries) e.key: e.value.toJson(),
  };

  factory NotificationPrefs.fromJson(Object? json) {
    if (json is! Map) return const NotificationPrefs();
    return NotificationPrefs(
      Map.unmodifiable({
        for (final e in json.entries)
          if (e.key is String)
            e.key as String: NotificationSettings.fromJson(e.value),
      }),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! NotificationPrefs) return false;
    if (other.byAccount.length != byAccount.length) return false;
    for (final e in byAccount.entries) {
      if (other.byAccount[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered([
    for (final e in byAccount.entries) Object.hash(e.key, e.value),
  ]);
}

final notificationPrefsProvider =
    NotifierProvider<NotificationPrefsNotifier, NotificationPrefs>(
      NotificationPrefsNotifier.new,
    );

class NotificationPrefsNotifier extends Notifier<NotificationPrefs> {
  bool _changed = false;
  Future<void> _loading = Future.value();

  @override
  NotificationPrefs build() {
    final store = ref.watch(settingsStoreProvider);
    final cached = store.peek(NotificationPrefs.storeKey);
    if (cached != null) {
      _loading = Future.value();
      return NotificationPrefs.fromJson(cached);
    }
    _loading = _load(store);
    return const NotificationPrefs();
  }

  /// Completes once the stored prefs are loaded (or found missing).
  Future<void> get ready => _loading;

  Future<void> _load(SettingsStore store) async {
    try {
      final raw = await store.read(NotificationPrefs.storeKey);
      if (!ref.mounted || _changed || raw == null) return;
      state = NotificationPrefs.fromJson(raw);
    } catch (_) {
      // Unreadable: keep defaults (everything off).
    }
  }

  void setAccount(String accountId, NotificationSettings s) {
    _changed = true;
    final next = state.withAccount(accountId, s);
    if (next == state) return;
    state = next;
    unawaited(
      ref
          .read(settingsStoreProvider)
          .write(NotificationPrefs.storeKey, next.toJson())
          .catchError((_) {}),
    );
  }

  void update(
    String accountId,
    NotificationSettings Function(NotificationSettings s) change,
  ) => setAccount(accountId, change(state.of(accountId)));
}

// ---- Changes and de-duplication -----------------------------------------

/// One thing a [ChangeSource] currently reports, e.g. a cancelled lesson or
/// an inbox message.
class ChangeItem {
  const ChangeItem({
    required this.key,
    required this.signature,
    required this.text,
    this.start,
    this.end,
    this.silent = false,
  });

  /// Stable identity (e.g. `2026-11-18|4711` for a period).
  final String key;

  /// What the change looks like now; a different signature for the same
  /// [key] is a new change (e.g. a substitution that became a cancellation).
  final String signature;

  /// Human-readable description without the time, e.g. "M cancelled".
  final String text;

  /// Timetable changes: when the lesson is.
  final DateTime? start;
  final DateTime? end;

  /// Recorded as seen but never notified (e.g. a message already read).
  final bool silent;

  ChangeItem asSilent() => ChangeItem(
    key: key,
    signature: signature,
    text: text,
    start: start,
    end: end,
    silent: true,
  );
}

/// Result of [diffChanges].
class ChangeDiff {
  const ChangeDiff(this.fresh, this.seen);

  /// Items to notify about.
  final List<ChangeItem> fresh;

  /// The new "seen" state (key → signature) to persist.
  final Map<String, String> seen;
}

/// Compares [current] with what was [seen] before. With [seen] null (first
/// run, or the source's scope changed) nothing is fresh: the current items
/// are only recorded as the baseline. Items that disappeared are dropped
/// from the state, so a change that comes back later is notified again.
ChangeDiff diffChanges(Map<String, String>? seen, List<ChangeItem> current) {
  final next = <String, String>{for (final i in current) i.key: i.signature};
  if (seen == null) return ChangeDiff(const [], next);
  final fresh = [
    for (final i in current)
      if (!i.silent && seen[i.key] != i.signature) i,
  ];
  // Same key reported twice in one run: notify once.
  final unique = <String>{};
  fresh.retainWhere((i) => unique.add(i.key));
  return ChangeDiff(fresh, next);
}

// ---- Persisted state ------------------------------------------------------

/// Where the "already notified" state lives. Kept apart from the settings
/// file: the Android background check runs in its own isolate and must not
/// overwrite settings the app changed meanwhile (or vice versa). [load]
/// always reads the current contents.
abstract interface class NotificationStateStore {
  Future<Map<String, Object?>> load();
  Future<void> save(Map<String, Object?> state);
}

class MemoryNotificationStateStore implements NotificationStateStore {
  MemoryNotificationStateStore([Map<String, Object?>? initial])
    : state = {...?initial};

  Map<String, Object?> state;

  @override
  Future<Map<String, Object?>> load() async => _decode(_encode(state)); // deep copy, like a file round trip

  @override
  Future<void> save(Map<String, Object?> s) async =>
      state = _decode(_encode(s));

  static Object? _encode(Object? v) =>
      v is Map ? {for (final e in v.entries) '${e.key}': _encode(e.value)} : v;
  static Map<String, Object?> _decode(Object? v) =>
      v is Map ? {for (final e in v.entries) '${e.key}': e.value} : {};
}

/// Parsed state: when the last check ran and, per account and source, the
/// scope and seen items; per account the last day whose daily summary and
/// reminders were shown or handed to the OS ([daily], `yyyy-mm-dd`).
class NotificationState {
  NotificationState({
    this.lastCheck,
    Map<String, Map<String, SourceState>>? accounts,
    Map<String, String>? daily,
  }) : accounts = accounts ?? {},
       daily = daily ?? {};

  DateTime? lastCheck;
  final Map<String, Map<String, SourceState>> accounts;
  final Map<String, String> daily;

  factory NotificationState.fromJson(Map<String, Object?> json) {
    final at = json['lastCheck'];
    final accounts = <String, Map<String, SourceState>>{};
    if (json['accounts'] case final Map a) {
      for (final e in a.entries) {
        if (e.key is! String || e.value is! Map) continue;
        final sources = <String, SourceState>{};
        for (final s in (e.value as Map).entries) {
          final parsed = SourceState.fromJson(s.value);
          if (s.key is String && parsed != null) sources[s.key] = parsed;
        }
        accounts[e.key as String] = sources;
      }
    }
    final daily = <String, String>{};
    if (json['daily'] case final Map d) {
      for (final e in d.entries) {
        if (e.key is String && e.value is String) {
          daily[e.key as String] = e.value as String;
        }
      }
    }
    return NotificationState(
      lastCheck: at is String ? DateTime.tryParse(at) : null,
      accounts: accounts,
      daily: daily,
    );
  }

  Map<String, Object?> toJson() => {
    if (lastCheck != null) 'lastCheck': lastCheck!.toUtc().toIso8601String(),
    'accounts': {
      for (final a in accounts.entries)
        a.key: {for (final s in a.value.entries) s.key: s.value.toJson()},
    },
    if (daily.isNotEmpty) 'daily': daily,
  };
}

class SourceState {
  const SourceState(this.scope, this.seen);
  final String scope;
  final Map<String, String> seen;

  static SourceState? fromJson(Object? json) {
    if (json is! Map) return null;
    final seen = <String, String>{};
    if (json['seen'] case final Map m) {
      for (final e in m.entries) {
        if (e.key is String && e.value is String) {
          seen[e.key as String] = e.value as String;
        }
      }
    }
    return SourceState('${json['scope'] ?? ''}', seen);
  }

  Map<String, Object?> toJson() => {'scope': scope, 'seen': seen};
}

// ---- Sources ----------------------------------------------------------------

/// A kind of change that can be notified. Add new kinds by implementing this and passing the source to
/// [ChangeChecker]; state, de-duplication and grouping come for free.
abstract class ChangeSource {
  const ChangeSource();

  /// Stable id, used in the state and in the notification payload.
  String get id;

  /// Whether the user wants this kind for the account.
  bool enabledIn(NotificationSettings s);

  /// Identifies what [current] looks at (e.g. timetable element and days).
  /// When it changes, the next run only records a new baseline.
  String scope(Account account, NotificationSettings s) => '';

  /// Everything the source reports right now, or null when it can't tell
  /// (offline, no right, …): the source is then skipped and its state kept.
  Future<List<ChangeItem>?> current(
    Account account,
    NotificationSettings s,
    DateTime now,
  );

  /// Notification title for [count] new items.
  String title(int count);

  /// Body lines for the new items (may merge items).
  List<String> lines(List<ChangeItem> fresh) => [for (final i in fresh) i.text];

  /// Where tapping the notification leads (see [NotificationTarget]).
  NotificationTarget target(Account account, List<ChangeItem> fresh);
}

/// What a tapped notification opens.
class NotificationTarget {
  const NotificationTarget.timetable(this.accountId, DateTime this.day)
    : kind = timetableKind;
  const NotificationTarget.inbox(this.accountId) : kind = inboxKind, day = null;
  const NotificationTarget._(this.accountId, this.kind, this.day);

  static const timetableKind = 'timetable';
  static const inboxKind = 'inbox';

  final String accountId;
  final String kind;
  final DateTime? day;

  /// `accountId|kind[|yyyy-mm-dd]`. Account ids contain no `|`.
  String get payload => [accountId, kind, if (day != null) ymd(day!)].join('|');

  static NotificationTarget? parse(String? payload) {
    if (payload == null) return null;
    final p = payload.split('|');
    if (p.length < 2 || p[0].isEmpty) return null;
    DateTime? day;
    if (p.length > 2) {
      final d = p[2].split('-').map(int.tryParse).toList();
      if (d.length == 3 && !d.contains(null)) {
        day = DateTime(d[0]!, d[1]!, d[2]!);
      }
    }
    return NotificationTarget._(p[0], p[1], day);
  }
}

// ---- Daily summary and reminders -------------------------------------------

/// What the daily time of one day brings: the summary of that day's
/// changes and tests, and reminders about upcoming tests and homework.
/// Either may be null (nothing to say).
class DailyDigest {
  const DailyDigest({this.summary, this.reminders});
  final AppNotification? summary;
  final AppNotification? reminders;
}

/// Builds the [DailyDigest] of an account for a day (see
/// lib/core/daily_notifications.dart).
abstract interface class DailyPlanner {
  /// Null when it can't tell (offline, no timetable): nothing changes then.
  Future<DailyDigest?> digest(
    Account account,
    NotificationSettings s,
    DateTime day,
  );
}

/// When the daily notifications of [day] are due.
DateTime dailyAt(DateTime day, int minute) =>
    DateTime(day.year, day.month, day.day, minute ~/ 60, minute % 60);

/// A summary that couldn't be delivered on time (the app wasn't running
/// and the OS can't schedule, e.g. the web) is still shown this long after.
const dailyLateLimit = Duration(hours: 10);

/// The Android background task wakes up every 15 minutes; it actually
/// checks that often on school days from an hour before the earliest daily
/// time (07:00 when no account has one) until 18:00, else about every 45
/// minutes. (A wake-up shortly after a check, e.g. by the app, is skipped.)
Duration backgroundMinIntervalAt(DateTime now, NotificationPrefs prefs) {
  const busy = Duration(minutes: 10);
  const calm = Duration(minutes: 40);
  if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
    return calm;
  }
  final minutes = [
    for (final s in prefs.byAccount.values)
      if (s.hasDaily) s.dailyMinute,
  ];
  final first = minutes.isEmpty
      ? NotificationSettings.defaultDailyMinute
      : minutes.reduce((a, b) => a < b ? a : b);
  final minute = now.hour * 60 + now.minute;
  return minute >= first - 60 && minute < 18 * 60 ? busy : calm;
}

int dailySummaryId(String accountId) =>
    notificationId(accountId, 'daily-summary');
int dailyRemindersId(String accountId) =>
    notificationId(accountId, 'daily-reminders');

// ---- Notifier ------------------------------------------------------------------

/// One notification to show.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  /// Fits in 31 bits (see [notificationId]).
  final int id;
  final String title;
  final String body;
  final String payload;
}

/// Shows notifications. Implemented with flutter_local_notifications on
/// Android/iOS and as an in-app snackbar on the web; tests use a fake.
abstract interface class LocalNotifier {
  /// Asks the OS for permission (Android 13+, iOS). True when granted (or
  /// not needed).
  Future<bool> requestPermission();

  Future<void> show(AppNotification n);

  /// Whether [schedule] works here (the OS shows the notification at the
  /// time, also while the app is closed). Not on the web.
  bool get canSchedule;

  /// Shows [n] at [at] (replacing a pending one with the same id).
  Future<void> schedule(AppNotification n, DateTime at);

  /// Removes a pending (scheduled) notification.
  Future<void> cancel(int id);

  /// Android 12+: whether scheduled notifications may come at the exact
  /// time (else Android delivers them some minutes later). True elsewhere.
  Future<bool> exactTimeAllowed();

  /// Opens the system page where the user allows exact alarms (Android).
  Future<void> requestExactTime();

  /// Payloads of tapped notifications while the app runs.
  Stream<String> get taps;

  /// The payload of the notification that launched the app, once.
  Future<String?> takeLaunchPayload();
}

/// Does nothing (default until main.dart overrides it, and in tests).
class NoopLocalNotifier implements LocalNotifier {
  const NoopLocalNotifier();
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> show(AppNotification n) async {}
  @override
  bool get canSchedule => false;
  @override
  Future<void> schedule(AppNotification n, DateTime at) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<bool> exactTimeAllowed() async => true;
  @override
  Future<void> requestExactTime() async {}
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Future<String?> takeLaunchPayload() async => null;
}

final localNotifierProvider = Provider<LocalNotifier>(
  (ref) => const NoopLocalNotifier(),
);

final notificationStateStoreProvider = Provider<NotificationStateStore>(
  (ref) => MemoryNotificationStateStore(),
);

/// Turns the OS background check on or off (Android: WorkManager). The
/// default does nothing; main.dart overrides it.
typedef BackgroundScheduler = Future<void> Function({required bool enabled});

final backgroundSchedulerProvider = Provider<BackgroundScheduler>(
  (ref) => ({required bool enabled}) async {},
);

/// Whether this platform checks in the background while the app is closed
/// (only Android). Shown in the settings.
final backgroundChecksSupportedProvider = Provider<bool>((ref) => false);

/// Stable notification id per account and source, below 2^30 so it is a
/// positive 32-bit int everywhere (no 64-bit arithmetic on the web).
int notificationId(String accountId, String sourceId) {
  var h = 17;
  for (final c in '$accountId|$sourceId'.codeUnits) {
    h = (h * 31 + c) & 0x3FFFFFFF;
  }
  return h;
}

// ---- The check -------------------------------------------------------------------

/// Runs all sources for every account that has notifications on, shows one
/// notification per account and source with everything new, and saves the
/// state. Runs are serialized per checker.
class ChangeChecker {
  ChangeChecker({
    required this.sources,
    required this.stateStore,
    required this.notifier,
    this.daily,
    DateTime Function()? clock,
    this.maxLines = 5,
  }) : clock = clock ?? DateTime.now;

  final List<ChangeSource> sources;

  /// Daily summary and reminders; null = none (tests of the sources).
  final DailyPlanner? daily;
  final NotificationStateStore stateStore;
  final LocalNotifier notifier;
  final DateTime Function() clock;
  final int maxLines;

  Future<List<AppNotification>>? _running;

  /// Checks now unless the last check (in any isolate) is less than
  /// [minInterval] ago. Returns the notifications shown.
  Future<List<AppNotification>> run(
    List<Account> accounts,
    NotificationPrefs prefs, {
    Duration minInterval = Duration.zero,
  }) {
    final r = _running;
    if (r != null) return r;
    final f = _run(accounts, prefs, minInterval).whenComplete(() {
      _running = null;
    });
    return _running = f;
  }

  Future<List<AppNotification>> _run(
    List<Account> accounts,
    NotificationPrefs prefs,
    Duration minInterval,
  ) async {
    final now = clock();
    var state = NotificationState.fromJson(await stateStore.load());
    final last = state.lastCheck;
    if (minInterval > Duration.zero &&
        last != null &&
        now.difference(last) < minInterval &&
        !now.isBefore(last)) {
      return const [];
    }
    // Claim the run early, so a check in another isolate skips meanwhile.
    state.lastCheck = now;
    await stateStore.save(state.toJson());

    final results = <String, Map<String, SourceState>>{};
    final shown = <AppNotification>[];
    final ids = {for (final a in accounts) a.id};
    final today = DateTime(now.year, now.month, now.day);

    // Daily summary of today still to come (scheduled, or overdue and shown
    // in this run): today's changes wait for it instead of their own
    // notification.
    final overdue = <String>{};
    final quiet = <String>{};
    if (daily != null) {
      for (final a in accounts) {
        final s = prefs.of(a.id);
        if (!s.hasDaily) continue;
        final at = dailyAt(today, s.dailyMinute);
        final done = state.daily[a.id];
        final late =
            !now.isBefore(at) &&
            now.isBefore(at.add(dailyLateLimit)) &&
            (done == null || done.compareTo(ymd(today)) < 0);
        if (late) overdue.add(a.id);
        if (s.dailySummary && (now.isBefore(at) || late)) quiet.add(a.id);
      }
    }

    for (final a in accounts) {
      final s = prefs.of(a.id);
      if (!s.enabled) continue;
      for (final source in sources) {
        if (!source.enabledIn(s)) continue;
        final List<ChangeItem>? items;
        try {
          items = await source.current(a, s, now);
        } catch (_) {
          continue; // keep the old state
        }
        if (items == null) continue;
        final current = quiet.contains(a.id)
            ? [
                for (final i in items)
                  i.start != null && ymd(i.start!) == ymd(today)
                      ? i.asSilent()
                      : i,
              ]
            : items;
        final scope = source.scope(a, s);
        final before = state.accounts[a.id]?[source.id];
        final diff = diffChanges(
          before == null || before.scope != scope ? null : before.seen,
          current,
        );
        (results[a.id] ??= {})[source.id] = SourceState(scope, diff.seen);
        if (diff.fresh.isEmpty) continue;
        final n = _notification(a, source, diff.fresh);
        try {
          await notifier.show(n);
          shown.add(n);
        } catch (_) {
          // Not shown: forget the fresh items so the next run tries again.
          results[a.id]![source.id] = SourceState(
            scope,
            {...diff.seen}
              ..removeWhere((k, _) => diff.fresh.any((i) => i.key == k)),
          );
        }
      }
    }

    final dailyDone = await _runDaily(accounts, prefs, now, overdue, shown);

    // Merge with what is on disk now (another isolate may have saved).
    final dailyBefore = state.daily;
    state = NotificationState.fromJson(await stateStore.load());
    state.lastCheck = now;
    state.accounts.removeWhere((id, _) => !ids.contains(id));
    for (final id in {...dailyBefore.keys, ...state.daily.keys}) {
      final a = accounts.where((a) => a.id == id).firstOrNull;
      if (a != null && prefs.of(id).hasDaily) continue;
      // Off or account gone: nothing may come at the daily time any more.
      state.daily.remove(id);
      if (notifier.canSchedule) {
        for (final n in [dailySummaryId(id), dailyRemindersId(id)]) {
          try {
            await notifier.cancel(n);
          } catch (_) {}
        }
      }
    }
    state.daily.addAll(dailyDone);
    for (final a in accounts) {
      final s = prefs.of(a.id);
      final sourcesOf = state.accounts[a.id] ??= {};
      // Off (account or kind): forget, so turning it on again starts quiet.
      sourcesOf.removeWhere(
        (id, _) =>
            !s.enabled ||
            !sources.any((src) => src.id == id && src.enabledIn(s)),
      );
      sourcesOf.addAll(results[a.id] ?? const {});
      if (sourcesOf.isEmpty) state.accounts.remove(a.id);
    }
    await stateStore.save(state.toJson());
    return shown;
  }

  /// Shows overdue daily notifications and hands the next ones to the OS.
  /// Returns the days handled per account.
  Future<Map<String, String>> _runDaily(
    List<Account> accounts,
    NotificationPrefs prefs,
    DateTime now,
    Set<String> overdue,
    List<AppNotification> shown,
  ) async {
    final planner = daily;
    final done = <String, String>{};
    if (planner == null) return done;
    final today = DateTime(now.year, now.month, now.day);
    for (final a in accounts) {
      final s = prefs.of(a.id);
      if (!s.hasDaily) continue;
      try {
        if (overdue.contains(a.id)) {
          final d = await planner.digest(a, s, today);
          if (d != null) {
            for (final n in [d.summary, d.reminders].nonNulls) {
              await notifier.show(n);
              shown.add(n);
            }
            done[a.id] = ymd(today);
          }
        }
        if (!notifier.canSchedule) continue;
        final next = now.isBefore(dailyAt(today, s.dailyMinute))
            ? today
            : DateTime(today.year, today.month, today.day + 1);
        final d = await planner.digest(a, s, next);
        if (d == null) continue;
        final at = dailyAt(next, s.dailyMinute);
        for (final (id, n) in [
          (dailySummaryId(a.id), d.summary),
          (dailyRemindersId(a.id), d.reminders),
        ]) {
          if (n == null) {
            await notifier.cancel(id);
          } else {
            await notifier.schedule(n, at);
          }
        }
        done[a.id] = ymd(next);
      } catch (e) {
        // Offline or the OS refused: the next run tries again.
      }
    }
    return done;
  }

  AppNotification _notification(
    Account a,
    ChangeSource source,
    List<ChangeItem> fresh,
  ) {
    final lines = source.lines(fresh);
    final body = [
      ...lines.take(maxLines),
      if (lines.length > maxLines) '+${lines.length - maxLines} more',
    ].join('\n');
    return AppNotification(
      id: notificationId(a.id, source.id),
      title: '${source.title(fresh.length)} · ${a.label}',
      body: body,
      payload: source.target(a, fresh).payload,
    );
  }
}

// ---- Formatting helpers ------------------------------------------------------------

/// `yyyy-mm-dd`.
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Tue 18.11."
String shortDay(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day}.${d.month}.';

/// "08:50"
String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
