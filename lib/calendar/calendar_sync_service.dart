/// Stores the calendar syncs and runs them (on save, "Sync now", and when
/// the app is opened or comes back to the foreground).
library;

import 'dart:async';

import 'package:flutter/material.dart' show ColorScheme, Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/interfaces.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../core/settings.dart';
import '../export/export_model.dart';
import '../ui/export/export_service.dart' show loadWeek;
import 'calendar_sync.dart';
import 'device_calendar.dart';

/// Seed of the app's color scheme (lib/ui/shell/app.dart).
const kAppSeedColor = Color(0xFF3F6FD8);

/// Calendar color per lesson state: the custom state colors from the
/// timetable settings, else the app's own (light theme) colors for them.
Map<LessonStatus, int> calendarColors(TimetableSettings s) {
  final cs = ColorScheme.fromSeed(seedColor: kAppSeedColor);
  return {
    LessonStatus.regular: s.regularColor ?? cs.primary.toARGB32(),
    LessonStatus.substitution: s.irregularColor ?? cs.tertiary.toARGB32(),
    LessonStatus.exam: s.examColor ?? cs.error.toARGB32(),
    LessonStatus.cancelled: s.cancelledColor ?? cs.outline.toARGB32(),
  };
}

/// Automatic syncs run at most this often.
const kAutoSyncInterval = Duration(minutes: 30);

DateTime _monday(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

String calendarErrorText(Object e) => switch (e) {
  CalendarAccessException() => e.message,
  UntisException(isNetwork: true) ||
  UntisException(isTimeout: true) => 'No connection.',
  UntisException() => e.message,
  _ => 'Calendar error: $e',
};

final calendarSyncsProvider =
    NotifierProvider<CalendarSyncsNotifier, List<CalendarSync>>(
      CalendarSyncsNotifier.new,
    );

class CalendarSyncsNotifier extends Notifier<List<CalendarSync>> {
  static const storeKey = 'calendarSync';
  bool _changed = false;
  Future<void>? _loaded;
  final _running = <String, Future<SyncCounts>>{};

  DeviceCalendarApi get _api => ref.read(deviceCalendarProvider);

  @override
  List<CalendarSync> build() {
    final store = ref.watch(settingsStoreProvider);
    final cached = store.peek(storeKey);
    if (cached != null) return _decode(cached);
    _loaded = _load(store);
    return const [];
  }

  static List<CalendarSync> _decode(Object? raw) {
    if (raw is! List) return const [];
    final out = <CalendarSync>[];
    for (final j in raw) {
      try {
        if (j is Map) {
          out.add(
            CalendarSync.fromJson({
              for (final e in j.entries) '${e.key}': e.value,
            }),
          );
        }
      } catch (_) {
        // Skip a broken entry.
      }
    }
    return out;
  }

  Future<void> _load(SettingsStore store) async {
    try {
      final raw = await store.read(storeKey);
      if (!ref.mounted || _changed || raw == null) return;
      state = _decode(raw);
    } catch (_) {}
  }

  Future<void> _ready() async => _loaded;

  void _set(List<CalendarSync> v) {
    _changed = true;
    state = v;
    unawaited(
      ref
          .read(settingsStoreProvider)
          .write(storeKey, [for (final s in v) s.toJson()])
          .catchError((_) {}),
    );
  }

  void _put(CalendarSync s) {
    final i = state.indexWhere((x) => x.id == s.id);
    _set(i < 0 ? [...state, s] : ([...state]..[i] = s));
  }

  CalendarSync? byId(String id) {
    for (final s in state) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Existing sync of [target] in [accountId], if any.
  CalendarSync? forTarget(String accountId, TimetableTarget target) {
    for (final s in state) {
      if (s.accountId == accountId && s.target == target) return s;
    }
    return null;
  }

  /// Creates or changes a sync: creates the [NewCalendar]s, stores it and
  /// runs it once. Calendars the app created earlier and no longer uses are
  /// deleted.
  Future<SyncCounts> save(
    CalendarSync draft,
    Map<LessonStatus, CalendarChoice> choices,
  ) async {
    await _ready();
    await _api.requestAccess();
    final colors = calendarColors(ref.read(timetableSettingsProvider));
    final calendars = <LessonStatus, String>{};
    final created = {...draft.created};
    for (final s in LessonStatus.values) {
      switch (choices[s] ?? const SkipCalendar()) {
        case SkipCalendar():
          break;
        case ExistingCalendar(:final id):
          calendars[s] = id;
        case NewCalendar():
          final id = await _api.createCalendar(
            defaultCalendarName(draft.elementName, s),
            colors[s]!,
          );
          calendars[s] = id;
          created[id] = colors[s]!;
      }
    }
    final sync = draft.copyWith(calendars: calendars, created: created);
    _put(sync);
    return run(sync.id);
  }

  /// Removes a sync. Deletes the calendars the app created for it and, with
  /// [deleteEvents], its events in the user's own calendars.
  Future<void> remove(String id, {bool deleteEvents = true}) async {
    await _ready();
    final s = byId(id);
    if (s == null) return;
    await _running[id];
    _set([
      for (final x in state)
        if (x.id != id) x,
    ]);
    if (!_api.supported) return;
    try {
      await _api.requestAccess();
      if (deleteEvents) {
        for (final e in s.events.values) {
          if (!s.created.containsKey(e.calendarId)) {
            await _api.deleteEvent(e.eventId);
          }
        }
      }
      for (final c in s.created.keys) {
        await _api.deleteCalendar(c);
      }
    } catch (_) {
      // The sync is gone either way; leftovers can be deleted by hand.
    }
  }

  /// Deletes device calendars (with their events). Syncs stop using them;
  /// a sync left without any calendar is removed. Returns how many syncs were
  /// removed.
  Future<int> deleteCalendars(Set<String> ids) async {
    await _ready();
    for (final id in [..._running.keys]) {
      try {
        await _running[id];
      } catch (_) {}
    }
    await _api.requestAccess();
    var removed = 0;
    final next = <CalendarSync>[];
    for (final s in state) {
      if (!s.calendars.values.any(ids.contains) &&
          !s.created.keys.any(ids.contains)) {
        next.add(s);
        continue;
      }
      final calendars = {
        for (final e in s.calendars.entries)
          if (!ids.contains(e.value)) e.key: e.value,
      };
      if (calendars.isEmpty) {
        removed++;
        continue;
      }
      next.add(
        s.copyWith(
          calendars: calendars,
          created: {
            for (final e in s.created.entries)
              if (!ids.contains(e.key)) e.key: e.value,
          },
          events: {
            for (final e in s.events.entries)
              if (!ids.contains(e.value.calendarId)) e.key: e.value,
          },
        ),
      );
    }
    _set(next);
    for (final id in ids) {
      await _api.deleteCalendar(id);
    }
    return removed;
  }

  /// Runs every sync that has auto-update on and wasn't synced in the last
  /// [kAutoSyncInterval] (all of them with [force]).
  Future<void> syncDue({bool force = false, DateTime? now}) async {
    await _ready();
    if (!_api.supported) return;
    final t = now ?? DateTime.now();
    for (final s in [...state]) {
      if (!s.autoUpdate) continue;
      final last = s.lastSync;
      if (!force && last != null && t.difference(last) < kAutoSyncInterval) {
        continue;
      }
      try {
        await run(s.id, now: t);
      } catch (_) {
        // Recorded in lastError.
      }
    }
  }

  /// Syncs one timetable now. Throws on errors (also stored as lastError).
  Future<SyncCounts> run(String id, {DateTime? now}) =>
      _running[id] ??= _run(id, now ?? DateTime.now()).whenComplete(() {
        // Block body: returning the removed future would make whenComplete wait
        // for itself.
        _running.remove(id);
      });

  Future<SyncCounts> _run(String id, DateTime now) async {
    await _ready();
    var sync = byId(id);
    if (sync == null) return const SyncCounts();
    try {
      await _api.requestAccess();
      sync = await _repairCalendars(sync);

      final accounts = await ref
          .read(accountRepositoryProvider)
          .watchAccounts()
          .first;
      final account = accounts
          .where((a) => a.id == sync!.accountId)
          .firstOrNull;
      if (account == null) {
        throw const CalendarAccessException('The account was removed.');
      }
      final repo = ref.read(timetableRepositoryProvider);
      final names = await repo
          .watchNames(account)
          .first
          .timeout(const Duration(seconds: 30));

      // Load the weeks: fresh where possible, else cached.
      final first = _monday(now);
      final loaded = <DateTime>{};
      final periods = <Period>[];
      Object? lastError;
      for (var i = 0; i < sync.weeks; i++) {
        final w = DateTime(first.year, first.month, first.day + 7 * i);
        try {
          await repo.refresh(account, sync.target, w);
        } catch (_) {
          // Offline: the cache below may still have it.
        }
        try {
          periods.addAll(await loadWeek(repo, account, sync.target, w));
          loaded.add(w);
        } catch (e) {
          lastError = e;
        }
      }
      if (loaded.isEmpty) {
        throw lastError ??
            const CalendarAccessException('Could not load the timetable.');
      }

      final lessons = buildExportLessons(
        periods,
        names,
        regular: false,
        palette: null,
      );
      final end = DateTime(first.year, first.month, first.day + 7 * sync.weeks);
      final wanted = wantedEvents(
        lessons,
        sync.calendars,
        showClasses:
            sync.target.type != ElementType.klasse &&
            sync.target.type != ElementType.student,
      );
      final outcome = await syncCalendar(
        _api,
        events: sync.events,
        wanted: wanted,
        covers: (d) => !d.isBefore(end) || loaded.contains(_monday(d)),
      );
      final error = outcome.error;
      sync = sync.copyWith(
        events: outcome.events,
        lastSync: error == null ? now : null,
        lastError: () => error == null ? null : calendarErrorText(error),
      );
      _put(sync);
      if (error != null) throw error;
      return outcome.counts;
    } catch (e) {
      final s = byId(id);
      if (s != null) _put(s.copyWith(lastError: () => calendarErrorText(e)));
      rethrow;
    }
  }

  /// Recreates app-made calendars the user deleted, drops own calendars
  /// that are gone, applies changed colors and deletes created calendars no
  /// longer used.
  Future<CalendarSync> _repairCalendars(CalendarSync sync) async {
    final present = {for (final c in await _api.calendars()) c.id};
    final colors = calendarColors(ref.read(timetableSettingsProvider));
    final calendars = {...sync.calendars};
    final created = {...sync.created};
    final events = {...sync.events};

    for (final s in LessonStatus.values) {
      final id = calendars[s];
      if (id == null || present.contains(id)) continue;
      events.removeWhere((_, e) => e.calendarId == id);
      if (created.remove(id) != null) {
        final fresh = await _api.createCalendar(
          defaultCalendarName(sync.elementName, s),
          colors[s]!,
        );
        calendars[s] = fresh;
        created[fresh] = colors[s]!;
      } else {
        calendars.remove(s);
      }
    }
    for (final e in [...created.entries]) {
      final states = [
        for (final c in calendars.entries)
          if (c.value == e.key) c.key,
      ];
      if (states.isEmpty) {
        // No longer used (choices changed): its events go with it.
        await _api.deleteCalendar(e.key);
        created.remove(e.key);
        events.removeWhere((_, ev) => ev.calendarId == e.key);
        continue;
      }
      final color = colors[states.first]!;
      if (e.value != color) {
        await _api.updateCalendar(e.key, color: color);
        created[e.key] = color;
      }
    }
    final next = sync.copyWith(
      calendars: calendars,
      created: created,
      events: events,
    );
    _put(next);
    return next;
  }
}
