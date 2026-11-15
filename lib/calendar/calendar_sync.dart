/// Calendar sync: keeps a timetable's lessons as events in device calendars.
///
/// A [CalendarSync] says which timetable goes where (one calendar per lesson
/// state, or none) and remembers the events it wrote. [syncCalendar] diffs
/// the wanted events for the sync window against those and creates, updates
/// or deletes only what changed. Events before the window (past weeks) are
/// left alone.
library;

import 'package:intl/intl.dart';

import '../core/models.dart';
import '../export/export_model.dart';
import '../export/ics_export.dart';
import 'device_calendar.dart';

/// Default names of new calendars, e.g. "10a – Substitutions".
String defaultCalendarName(String elementName, LessonStatus s) =>
    '$elementName – ${switch (s) {
      LessonStatus.regular => 'Timetable',
      LessonStatus.substitution => 'Substitutions',
      LessonStatus.exam => 'Exams',
      LessonStatus.cancelled => 'Cancelled',
    }}';

/// What the user picked for one lesson state.
sealed class CalendarChoice {
  const CalendarChoice();
}

/// Don't add lessons of this state.
class SkipCalendar extends CalendarChoice {
  const SkipCalendar();
  @override
  bool operator ==(Object other) => other is SkipCalendar;
  @override
  int get hashCode => 0;
}

/// A new calendar created by the app (colored from the settings).
class NewCalendar extends CalendarChoice {
  const NewCalendar();
  @override
  bool operator ==(Object other) => other is NewCalendar;
  @override
  int get hashCode => 1;
}

/// An existing calendar (the user's own, or one created earlier).
class ExistingCalendar extends CalendarChoice {
  const ExistingCalendar(this.id);
  final String id;
  @override
  bool operator ==(Object other) => other is ExistingCalendar && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// One event the sync wrote.
class SyncedEvent {
  const SyncedEvent({
    required this.eventId,
    required this.calendarId,
    required this.fingerprint,
    required this.day,
  });

  factory SyncedEvent.fromJson(Map<String, Object?> j) => SyncedEvent(
    eventId: j['e']! as String,
    calendarId: j['c']! as String,
    fingerprint: j['f']! as String,
    day: DateTime.parse(j['d']! as String),
  );

  final String eventId;
  final String calendarId;
  final String fingerprint;

  /// Day of the lesson (local midnight).
  final DateTime day;

  Map<String, Object?> toJson() => {
    'e': eventId,
    'c': calendarId,
    'f': fingerprint,
    'd': DateFormat('yyyy-MM-dd').format(day),
  };
}

class CalendarSync {
  const CalendarSync({
    required this.id,
    required this.accountId,
    required this.target,
    required this.elementName,
    this.calendars = const {},
    this.created = const {},
    this.weeks = 4,
    this.autoUpdate = true,
    this.lastSync,
    this.lastError,
    this.events = const {},
  });

  factory CalendarSync.fromJson(Map<String, Object?> j) {
    Map<String, Object?> map(Object? v) =>
        v is Map ? {for (final e in v.entries) '${e.key}': e.value} : {};
    return CalendarSync(
      id: j['id']! as String,
      accountId: j['account']! as String,
      target: TimetableTarget(
        ElementType.parse(j['type']),
        (j['target']! as num).toInt(),
      ),
      elementName: j['name'] as String? ?? '',
      calendars: {
        for (final e in map(j['calendars']).entries)
          if (LessonStatus.values.asNameMap()[e.key] case final s?)
            if (e.value case final String id) s: id,
      },
      created: {
        for (final e in map(j['created']).entries)
          e.key: (e.value! as num).toInt(),
      },
      weeks: (j['weeks'] as num?)?.toInt() ?? 4,
      autoUpdate: j['auto'] as bool? ?? true,
      lastSync: switch (j['lastSync']) {
        final num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
        _ => null,
      },
      lastError: j['lastError'] as String?,
      events: {
        for (final e in map(j['events']).entries)
          e.key: SyncedEvent.fromJson(map(e.value)),
      },
    );
  }

  final String id;
  final String accountId;
  final TimetableTarget target;

  /// "10a", "Anna Müller", … (also used for new calendar names).
  final String elementName;

  /// Lesson state → calendar id; a missing state is not added.
  final Map<LessonStatus, String> calendars;

  /// Calendars the app created: id → color last applied (ARGB).
  final Map<String, int> created;

  /// Weeks synced, starting with the current one.
  final int weeks;

  /// Sync automatically when the app is opened.
  final bool autoUpdate;
  final DateTime? lastSync;
  final String? lastError;

  /// Lesson key → written event.
  final Map<String, SyncedEvent> events;

  CalendarSync copyWith({
    String? elementName,
    Map<LessonStatus, String>? calendars,
    Map<String, int>? created,
    int? weeks,
    bool? autoUpdate,
    DateTime? lastSync,
    String? Function()? lastError,
    Map<String, SyncedEvent>? events,
  }) => CalendarSync(
    id: id,
    accountId: accountId,
    target: target,
    elementName: elementName ?? this.elementName,
    calendars: calendars ?? this.calendars,
    created: created ?? this.created,
    weeks: weeks ?? this.weeks,
    autoUpdate: autoUpdate ?? this.autoUpdate,
    lastSync: lastSync ?? this.lastSync,
    lastError: lastError != null ? lastError() : this.lastError,
    events: events ?? this.events,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'account': accountId,
    'type': target.type.apiName,
    'target': target.id,
    'name': elementName,
    'calendars': {for (final e in calendars.entries) e.key.name: e.value},
    'created': created,
    'weeks': weeks,
    'auto': autoUpdate,
    if (lastSync != null) 'lastSync': lastSync!.millisecondsSinceEpoch,
    if (lastError != null) 'lastError': lastError,
    'events': {for (final e in events.entries) e.key: e.value.toJson()},
  };
}

/// An event the sync wants in [calendarId].
class WantedEvent {
  const WantedEvent(this.calendarId, this.day, this.data);
  final String calendarId;
  final DateTime day;
  final CalendarEventData data;
}

DateTime _at(DateTime day, int minutes) =>
    DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

/// Wanted events for [lessons] (a week export's lessons, real states), keyed
/// by day, start, subject and classes (so a lesson that turns into a
/// substitution or gets cancelled keeps its key and is updated or moved).
Map<String, WantedEvent> wantedEvents(
  Iterable<ExportLesson> lessons,
  Map<LessonStatus, String> calendars, {
  bool showClasses = false,
}) {
  final out = <String, WantedEvent>{};
  final date = DateFormat('yyyy-MM-dd');
  for (final l in lessons) {
    final cal = calendars[l.status];
    if (cal == null) continue;
    final base =
        '${date.format(l.date)}|${l.start}|${l.subjectLabel}|'
        '${l.classes.join(',')}';
    var key = base;
    for (var n = 2; out.containsKey(key); n++) {
      key = '$base|$n';
    }
    out[key] = WantedEvent(
      cal,
      l.date,
      CalendarEventData(
        title: lessonEventTitle(l, showClasses: showClasses),
        start: _at(l.date, l.start),
        end: _at(l.date, l.end),
        description: lessonEventDescription(l),
        location: l.rooms.join(', '),
        free: l.status == LessonStatus.cancelled,
      ),
    );
  }
  return out;
}

class SyncCounts {
  const SyncCounts({
    this.created = 0,
    this.updated = 0,
    this.deleted = 0,
    this.unchanged = 0,
  });
  final int created;
  final int updated;
  final int deleted;
  final int unchanged;

  bool get changed => created + updated + deleted > 0;

  @override
  String toString() {
    if (!changed) return 'Calendar is up to date';
    return [
      if (created > 0) '$created added',
      if (updated > 0) '$updated updated',
      if (deleted > 0) '$deleted removed',
    ].join(', ');
  }
}

/// Result of [syncCalendar]. [events] always matches what is in the
/// calendars, also when [error] stopped the sync halfway, so it is what
/// gets saved.
class SyncOutcome {
  const SyncOutcome(this.events, this.counts, [this.error]);
  final Map<String, SyncedEvent> events;
  final SyncCounts counts;
  final Object? error;
}

/// Brings [events] (what was written before) in line with [wanted] for days
/// on the days [covers] accepts (loaded weeks, and the days after the
/// window, whose events are removed): creates, updates, moves and deletes
/// only what changed. Other days (past weeks, weeks that failed to load) are
/// left as they are.
Future<SyncOutcome> syncCalendar(
  DeviceCalendarApi api, {
  required Map<String, SyncedEvent> events,
  required Map<String, WantedEvent> wanted,
  required bool Function(DateTime day) covers,
}) async {
  final next = {...events};
  var created = 0, updated = 0, deleted = 0, unchanged = 0;
  SyncCounts counts() => SyncCounts(
    created: created,
    updated: updated,
    deleted: deleted,
    unchanged: unchanged,
  );

  try {
    // Removed lessons (and everything after the window when it shrank).
    for (final e in events.entries) {
      if (!covers(e.value.day) || wanted.containsKey(e.key)) continue;
      await api.deleteEvent(e.value.eventId);
      next.remove(e.key);
      deleted++;
    }

    for (final w in wanted.entries) {
      if (!covers(w.value.day)) continue;
      final old = events[w.key];
      final fp = w.value.data.fingerprint;
      if (old != null && old.calendarId == w.value.calendarId) {
        if (old.fingerprint == fp) {
          unchanged++;
          continue;
        }
        if (await api.updateEvent(old.eventId, w.value.data)) {
          next[w.key] = SyncedEvent(
            eventId: old.eventId,
            calendarId: old.calendarId,
            fingerprint: fp,
            day: w.value.day,
          );
          updated++;
          continue;
        }
        // Deleted by the user: write it again.
      } else if (old != null) {
        // Moved to another calendar (e.g. now cancelled).
        await api.deleteEvent(old.eventId);
      }
      next.remove(w.key);
      final id = await api.createEvent(w.value.calendarId, w.value.data);
      next[w.key] = SyncedEvent(
        eventId: id,
        calendarId: w.value.calendarId,
        fingerprint: fp,
        day: w.value.day,
      );
      if (old != null) {
        updated++;
      } else {
        created++;
      }
    }
  } catch (e) {
    return SyncOutcome(next, counts(), e);
  }
  return SyncOutcome(next, counts());
}
