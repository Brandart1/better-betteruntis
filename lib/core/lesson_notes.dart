/// The user's own additions to lessons, kept on the device only: marking a
/// lesson as an exam and entering lesson details (e.g. "mündliche
/// Wiederholung", exam topics). They are applied to the periods wherever the
/// timetable is shown or exported.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'settings.dart';

/// What the user added to one lesson.
///
/// For the optional sync (lib/sync/) every note carries [updatedAt] and
/// deletions are kept as tombstones ([deleted]) so they reach other devices.
/// Equality compares the content ([exam], [text], [deleted]) only, not the
/// sync metadata.
class LessonNote {
  const LessonNote({
    this.exam = false,
    this.text = '',
    this.updatedAt = 0,
    this.deleted = false,
    this.dirty = false,
    this.base,
  });

  /// A deleted note, kept so the deletion can be synced.
  const LessonNote.tombstone(this.updatedAt, {this.dirty = false, this.base})
    : exam = false,
      text = '',
      deleted = true;

  /// Marked as an exam by the user.
  final bool exam;

  /// Lesson details entered by the user.
  final String text;

  /// Last change, in milliseconds since the epoch (UTC). 0 for notes stored
  /// before sync existed (older than anything synced).
  final int updatedAt;

  /// Tombstone: the note was removed at [updatedAt].
  final bool deleted;

  /// Changed on this device and not yet acknowledged by the sync server.
  final bool dirty;

  /// For a [dirty] note: [updatedAt] of the acknowledged (synced or
  /// pre-sync) version this change replaces, if there was one. A change is
  /// always stamped above it, also when its stamp is clamped later.
  final int? base;

  bool get isEmpty => deleted || (!exam && text.trim().isEmpty);

  LessonNote copyWith({bool? exam, String? text}) => LessonNote(
    exam: exam ?? this.exam,
    text: text ?? this.text,
    updatedAt: updatedAt,
    dirty: dirty,
    base: base,
  );

  Map<String, Object?> toJson() => {
    if (exam) 'exam': true,
    if (text.isNotEmpty) 'text': text,
    if (updatedAt != 0) 'updatedAt': updatedAt,
    if (deleted) 'deleted': true,
    if (dirty) 'dirty': true,
    if (dirty && base != null) 'base': base,
  };

  factory LessonNote.fromJson(Map<String, Object?> j) {
    final at = j['updatedAt'];
    final base = j['base'];
    final dirty = j['dirty'] == true;
    return LessonNote(
      exam: j['exam'] == true,
      text: '${j['text'] ?? ''}',
      updatedAt: at is num ? at.toInt() : 0,
      deleted: j['deleted'] == true,
      dirty: dirty,
      base: dirty && base is num ? base.toInt() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LessonNote &&
      other.exam == exam &&
      other.text == text &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(exam, text, deleted);

  @override
  String toString() =>
      'LessonNote(exam: $exam, text: $text, updatedAt: $updatedAt'
      '${deleted ? ', deleted' : ''}${dirty ? ', dirty' : ''})';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Identifies one lesson occurrence of an account: date, start time, the
/// Untis lesson and its subjects (or its title for lessons without one).
/// The same lesson matches in class, teacher and room timetables.
String lessonNoteKey(String accountId, Period p) {
  final s = p.start;
  final subjects = [
    for (final e in p.ofType(ElementType.subject))
      e.orgId != 0 ? e.orgId : e.id,
  ]..sort();
  final what = subjects.isNotEmpty ? subjects.join(',') : p.lessonText.trim();
  return [
    accountId,
    '${s.year}-${_two(s.month)}-${_two(s.day)}',
    '${_two(s.hour)}${_two(s.minute)}',
    p.lessonId,
    what,
  ].join('|');
}

/// [periods] with the user's notes of [accountId] applied (tombstones are
/// ignored). Every period gets its [Period.noteKey], so the lesson details
/// can add a note later.
List<Period> applyLessonNotes(
  List<Period> periods,
  String accountId,
  Map<String, LessonNote> notes,
) => [
  for (final p in periods)
    () {
      final key = lessonNoteKey(accountId, p);
      final found = notes[key];
      final n = found == null || found.isEmpty ? null : found;
      return p.withUserNote(
        noteKey: key,
        userExam: n?.exam ?? false,
        userNote: n?.text.trim() ?? '',
      );
    }(),
];

/// Clock for [LessonNote.updatedAt] (overridden in tests).
final lessonNotesClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// All notes of all accounts by [lessonNoteKey], including tombstones (use
/// [LessonNote.isEmpty] or [applyLessonNotes] to skip them).
final lessonNotesProvider =
    NotifierProvider<LessonNotesNotifier, Map<String, LessonNote>>(
      LessonNotesNotifier.new,
    );

class LessonNotesNotifier extends Notifier<Map<String, LessonNote>> {
  static const storeKey = 'lessonNotes';

  /// Tombstones of accounts that don't sync are dropped after this long.
  static const tombstoneMaxAge = Duration(days: 180);

  bool _changed = false;
  Future<void> _loading = Future.value();
  Future<bool> _lastWrite = Future.value(true);

  @override
  Map<String, LessonNote> build() {
    final store = ref.watch(settingsStoreProvider);
    final cached = store.peek(storeKey);
    if (cached != null) {
      _loading = Future.value();
      return _decode(cached);
    }
    _loading = _load(store);
    return const {};
  }

  /// Completes once the stored notes are loaded.
  Future<void> get ready => _loading;

  /// Completes once the latest change is written to the settings store:
  /// true if it was stored, false if writing failed (the change is then
  /// only in memory). After a failed write the current notes are written
  /// again once.
  Future<bool> get saved async {
    final ok = await _lastWrite;
    if (ok || !ref.mounted) return ok;
    _persist(state);
    return _lastWrite;
  }

  static Map<String, LessonNote> _decode(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, LessonNote>{};
    for (final e in raw.entries) {
      final v = e.value;
      if (v is! Map) continue;
      final n = LessonNote.fromJson({
        for (final f in v.entries) '${f.key}': f.value,
      });
      // Tombstones are kept; empty legacy entries are dropped.
      if (!n.isEmpty || n.deleted) out['${e.key}'] = n;
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

  void _commit(Map<String, LessonNote> next) {
    _changed = true;
    state = next;
    _persist(next);
  }

  void _persist(Map<String, LessonNote> next) {
    Future<bool> write;
    try {
      write = ref
          .read(settingsStoreProvider)
          .write(storeKey, {
            for (final e in next.entries) e.key: e.value.toJson(),
          })
          .then((_) => true, onError: (Object _) => false);
    } catch (_) {
      write = Future.value(false);
    }
    // Every write stores the whole map, so the latest one decides.
    final before = _lastWrite;
    _lastWrite = Future.wait([before, write]).then((r) => r[1]);
  }

  /// Sets the note of each of [keys] (all periods of a merged lesson);
  /// an empty note removes it (leaving a tombstone for sync).
  void set(Iterable<String> keys, LessonNote note) {
    final now = ref.read(lessonNotesClockProvider)().millisecondsSinceEpoch;
    final next = {...state};
    for (final k in keys) {
      final old = next[k];
      // A change always wins over the version it replaces (never stamped
      // at or below it, even if that came from a clock that was ahead;
      // [clampFuture] fixes stamps the server finds too far ahead).
      final at = old == null || now > old.updatedAt ? now : old.updatedAt + 1;
      // The acknowledged version this change replaces.
      final base = old == null ? null : (old.dirty ? old.base : old.updatedAt);
      if (note.isEmpty) {
        if (old != null && !old.deleted) {
          next[k] = LessonNote.tombstone(at, dirty: true, base: base);
        }
      } else {
        next[k] = LessonNote(
          exam: note.exam,
          text: note.text.trim(),
          updatedAt: at,
          dirty: true,
          base: base,
        );
      }
    }
    _commit(next);
  }

  // ---- Sync (lib/sync/sync_engine.dart) ----------------------------------

  /// All notes of [accountId] (including tombstones) by full key.
  Map<String, LessonNote> notesOf(String accountId) {
    final prefix = '$accountId|';
    return {
      for (final e in state.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  /// Whether [accountId] has local changes not yet acknowledged by the sync
  /// server.
  bool hasDirty(String accountId) {
    final prefix = '$accountId|';
    return state.entries.any((e) => e.value.dirty && e.key.startsWith(prefix));
  }

  /// Applies notes from the sync server (by full local key) with
  /// last-write-wins: a remote note replaces the local one if it is newer.
  /// With the same [LessonNote.updatedAt] the server's version wins (it is
  /// what every other device gets): equal content just acknowledges the
  /// local note (clears [LessonNote.dirty]), different content replaces it.
  /// Remote tombstones are stored even for keys never seen here, so a later
  /// upload of an older copy (e.g. after a server reset) loses against
  /// them. Returns the keys whose content changed.
  Set<String> applyRemote(Map<String, LessonNote> remote) {
    final next = {...state};
    final changed = <String>{};
    var touched = false;
    for (final e in remote.entries) {
      final r = e.value;
      final local = next[e.key];
      final n = r.isEmpty
          ? LessonNote.tombstone(r.updatedAt)
          : LessonNote(exam: r.exam, text: r.text, updatedAt: r.updatedAt);
      if (local == null) {
        next[e.key] = n;
        touched = true;
        if (!n.deleted) changed.add(e.key);
        continue;
      }
      if (r.updatedAt < local.updatedAt) continue;
      if (r.updatedAt == local.updatedAt && local == n) {
        if (local.dirty) {
          next[e.key] = _clean(local);
          touched = true;
        }
        continue;
      }
      if (local != n && !(local.isEmpty && n.isEmpty)) changed.add(e.key);
      next[e.key] = n;
      touched = true;
    }
    if (touched) _commit(next);
    return changed;
  }

  /// Stamps notes of [accountId] stored before sync existed (updatedAt 0)
  /// with [at] and marks them for upload, so they don't all tie at 0 with
  /// other devices' copies. Returns how many were stamped.
  int stampLegacy(String accountId, int at) {
    final prefix = '$accountId|';
    final next = {...state};
    var n = 0;
    for (final e in state.entries) {
      if (e.value.updatedAt != 0 || !e.key.startsWith(prefix)) continue;
      next[e.key] = _restamp(e.value, at, dirty: true);
      n++;
    }
    if (n > 0) _commit(next);
    return n;
  }

  /// Lowers [LessonNote.updatedAt] of the unsynced ([LessonNote.dirty])
  /// notes of [accountId] stamped after [max] (derived from the server's
  /// time after a clock-skew rejection) to [max], but never to or below
  /// the version a note replaces ([LessonNote.base] + 1). Acknowledged
  /// notes are never touched (the server has exactly that version).
  /// Returns how many were changed.
  int clampFuture(String accountId, int max) {
    final prefix = '$accountId|';
    final next = {...state};
    var n = 0;
    for (final e in state.entries) {
      final note = e.value;
      if (!note.dirty || note.updatedAt <= max || !e.key.startsWith(prefix)) {
        continue;
      }
      final floor = note.base == null ? null : note.base! + 1;
      final at = floor != null && floor > max ? floor : max;
      if (at >= note.updatedAt) continue;
      next[e.key] = _restamp(note, at);
      n++;
    }
    if (n > 0) _commit(next);
    return n;
  }

  static LessonNote _restamp(LessonNote n, int at, {bool? dirty}) {
    final d = dirty ?? n.dirty;
    final base = d ? n.base : null;
    return n.deleted
        ? LessonNote.tombstone(at, dirty: d, base: base)
        : LessonNote(
            exam: n.exam,
            text: n.text,
            updatedAt: at,
            dirty: d,
            base: base,
          );
  }

  static LessonNote _clean(LessonNote n) => n.deleted
      ? LessonNote.tombstone(n.updatedAt)
      : LessonNote(exam: n.exam, text: n.text, updatedAt: n.updatedAt);

  /// Drops tombstones older than [maxAge] of accounts for which [keep] is
  /// false (accounts that don't sync).
  void pruneTombstones(
    bool Function(String accountId) keep, {
    Duration maxAge = tombstoneMaxAge,
  }) {
    final now = ref.read(lessonNotesClockProvider)();
    final limit = now.subtract(maxAge).millisecondsSinceEpoch;
    final next = {...state};
    next.removeWhere((k, n) {
      if (!n.deleted || n.updatedAt >= limit) return false;
      final i = k.indexOf('|');
      return !keep(i < 0 ? k : k.substring(0, i));
    });
    if (next.length != state.length) _commit(next);
  }
}
