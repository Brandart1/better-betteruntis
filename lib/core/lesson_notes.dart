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
class LessonNote {
  const LessonNote({this.exam = false, this.text = ''});

  /// Marked as an exam by the user.
  final bool exam;

  /// Lesson details entered by the user.
  final String text;

  bool get isEmpty => !exam && text.trim().isEmpty;

  LessonNote copyWith({bool? exam, String? text}) =>
      LessonNote(exam: exam ?? this.exam, text: text ?? this.text);

  Map<String, Object?> toJson() => {
    if (exam) 'exam': true,
    if (text.isNotEmpty) 'text': text,
  };

  factory LessonNote.fromJson(Map<String, Object?> j) =>
      LessonNote(exam: j['exam'] == true, text: '${j['text'] ?? ''}');

  @override
  bool operator ==(Object other) =>
      other is LessonNote && other.exam == exam && other.text == text;

  @override
  int get hashCode => Object.hash(exam, text);
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

/// [periods] with the user's notes of [accountId] applied. Every period gets
/// its [Period.noteKey], so the lesson details can add a note later.
List<Period> applyLessonNotes(
  List<Period> periods,
  String accountId,
  Map<String, LessonNote> notes,
) => [
  for (final p in periods)
    () {
      final key = lessonNoteKey(accountId, p);
      final n = notes[key];
      return p.withUserNote(
        noteKey: key,
        userExam: n?.exam ?? false,
        userNote: n?.text.trim() ?? '',
      );
    }(),
];

final lessonNotesProvider =
    NotifierProvider<LessonNotesNotifier, Map<String, LessonNote>>(
      LessonNotesNotifier.new,
    );

class LessonNotesNotifier extends Notifier<Map<String, LessonNote>> {
  static const storeKey = 'lessonNotes';
  bool _changed = false;

  @override
  Map<String, LessonNote> build() {
    final store = ref.watch(settingsStoreProvider);
    final cached = store.peek(storeKey);
    if (cached != null) return _decode(cached);
    unawaited(_load(store));
    return const {};
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
      if (!n.isEmpty) out['${e.key}'] = n;
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

  /// Sets the note of each of [keys] (all periods of a merged lesson);
  /// an empty note removes it.
  void set(Iterable<String> keys, LessonNote note) {
    final next = {...state};
    for (final k in keys) {
      if (note.isEmpty) {
        next.remove(k);
      } else {
        next[k] = LessonNote(exam: note.exam, text: note.text.trim());
      }
    }
    _changed = true;
    state = next;
    unawaited(
      ref
          .read(settingsStoreProvider)
          .write(storeKey, {
            for (final e in next.entries) e.key: e.value.toJson(),
          })
          .catchError((_) {}),
    );
  }
}
