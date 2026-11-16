import 'package:better_betteruntis/core/lesson_notes.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Period _p({
  int lessonId = 7,
  int subject = 3,
  int hour = 8,
  String text = '',
  Set<PeriodFlag> flags = const {},
}) => Period(
  id: 1,
  lessonId: lessonId,
  start: DateTime(2026, 11, 16, hour),
  end: DateTime(2026, 11, 16, hour, 50),
  elements: [
    if (subject != 0)
      ElementRef(type: ElementType.subject, id: subject, orgId: 0),
    const ElementRef(type: ElementType.room, id: 9, orgId: 0),
  ],
  flags: flags,
  lessonText: text,
);

void main() {
  test('key: per account, date, time, lesson and subject', () {
    final k = lessonNoteKey('acc', _p());
    expect(k, 'acc|2026-11-16|0800|7|3');
    expect(lessonNoteKey('other', _p()), isNot(k));
    expect(lessonNoteKey('acc', _p(hour: 9)), isNot(k));
    expect(lessonNoteKey('acc', _p(subject: 4)), isNot(k));
    // No subject: the lesson title tells events apart.
    expect(
      lessonNoteKey('acc', _p(subject: 0, text: 'E-Theater')),
      endsWith('|E-Theater'),
    );
  });

  test('apply: custom exam and details; every period gets its key', () {
    final a = _p();
    final b = _p(hour: 9);
    final out = applyLessonNotes(
      [a, b],
      'acc',
      {
        lessonNoteKey('acc', a): const LessonNote(
          exam: true,
          text: ' mündliche Wiederholung ',
        ),
      },
    );
    expect(out[0].isExam, isTrue);
    expect(out[0].isSchoolExam, isFalse);
    expect(out[0].userNote, 'mündliche Wiederholung');
    expect(out[1].isExam, isFalse);
    expect(out[1].userNote, '');
    expect(out[1].noteKey, lessonNoteKey('acc', b));
    // Kept through other copies.
    expect(out[0].copyWithElements(out[0].elements).userExam, isTrue);
  });

  test('notifier stores, removes and reloads notes', () async {
    final store = MemorySettingsStore();
    var c = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
    );
    final n = c.read(lessonNotesProvider.notifier);
    n.set(['k1', 'k2'], const LessonNote(exam: true, text: 'Topics 1-3'));
    n.set(['k3'], const LessonNote(text: 'Bring calculator'));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(lessonNotesProvider).length, 3);
    n.set(['k3'], const LessonNote());
    await Future<void>.delayed(Duration.zero);
    c.dispose();

    c = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
    );
    final notes = c.read(lessonNotesProvider);
    // k3 stays as a tombstone so the deletion can be synced.
    expect(notes.keys, unorderedEquals(['k1', 'k2', 'k3']));
    expect([
      for (final e in notes.entries)
        if (!e.value.isEmpty) e.key,
    ], unorderedEquals(['k1', 'k2']));
    expect(notes['k3']!.deleted, isTrue);
    expect(notes['k3']!.dirty, isTrue);
    expect(notes['k1'], const LessonNote(exam: true, text: 'Topics 1-3'));
    c.dispose();
  });

  test('old entries without updatedAt load with updatedAt 0', () {
    final store = MemorySettingsStore({
      LessonNotesNotifier.storeKey: {
        'a|k': {'exam': true, 'text': 'x'},
        'a|empty': <String, Object?>{},
      },
    });
    final c = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    final notes = c.read(lessonNotesProvider);
    expect(notes.keys, ['a|k']);
    expect(notes['a|k']!.updatedAt, 0);
    expect(notes['a|k']!.dirty, isFalse);
  });

  test('set stamps updatedAt; tombstones are ignored when applied', () {
    var now = DateTime.utc(2026, 11, 16, 10);
    final c = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
        lessonNotesClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    final n = c.read(lessonNotesProvider.notifier);
    final key = lessonNoteKey('acc', _p());
    n.set([key], const LessonNote(exam: true));
    expect(
      c.read(lessonNotesProvider)[key]!.updatedAt,
      now.millisecondsSinceEpoch,
    );
    // Same millisecond: the change still gets a newer stamp.
    n.set([key], const LessonNote());
    final t = c.read(lessonNotesProvider)[key]!;
    expect(t.deleted, isTrue);
    expect(t.updatedAt, now.millisecondsSinceEpoch + 1);
    final out = applyLessonNotes([_p()], 'acc', c.read(lessonNotesProvider));
    expect(out.single.userExam, isFalse);
    expect(n.notesOf('acc').keys, [key]);
    expect(n.notesOf('other'), isEmpty);
    expect(n.hasDirty('acc'), isTrue);
  });

  test('applyRemote: last write wins, equal stamp acknowledges', () {
    final c = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
        lessonNotesClockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      ],
    );
    addTearDown(c.dispose);
    final n = c.read(lessonNotesProvider.notifier);
    n.set(['a|k'], const LessonNote(text: 'local'));
    // Older remote: ignored.
    expect(
      n.applyRemote({'a|k': const LessonNote(text: 'old', updatedAt: 500)}),
      isEmpty,
    );
    expect(c.read(lessonNotesProvider)['a|k']!.text, 'local');
    // Same stamp: acknowledged (no longer dirty).
    n.applyRemote({'a|k': const LessonNote(text: 'local', updatedAt: 1000)});
    expect(c.read(lessonNotesProvider)['a|k']!.dirty, isFalse);
    // Newer remote: replaces, also as a tombstone.
    expect(n.applyRemote({'a|k': const LessonNote.tombstone(2000)}), {'a|k'});
    expect(c.read(lessonNotesProvider)['a|k']!.deleted, isTrue);
    // A remote tombstone for an unknown key is kept (H1), so an older copy
    // uploaded later loses against it; it changes no visible content.
    expect(n.applyRemote({'a|x': const LessonNote.tombstone(3000)}), isEmpty);
    expect(c.read(lessonNotesProvider)['a|x']!.deleted, isTrue);
    expect(c.read(lessonNotesProvider)['a|x']!.dirty, isFalse);
  });

  test(
    'applyRemote: a tie with other content takes the server version (H3)',
    () {
      final c = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
          lessonNotesClockProvider.overrideWithValue(
            () => DateTime.fromMillisecondsSinceEpoch(1000),
          ),
        ],
      );
      addTearDown(c.dispose);
      final n = c.read(lessonNotesProvider.notifier);
      n.set(['a|k'], const LessonNote(text: 'mine'));
      expect(
        n.applyRemote({
          'a|k': const LessonNote(text: 'theirs', updatedAt: 1000),
        }),
        {'a|k'},
      );
      final k = c.read(lessonNotesProvider)['a|k']!;
      expect(k.text, 'theirs');
      expect(k.dirty, isFalse);
    },
  );

  test('set stamps above the replaced version; clampFuture only lowers '
      'unsynced notes, never below the replaced version; stampLegacy '
      '(H2/M4/H3)', () {
    final now = DateTime.utc(2026, 11, 16, 10);
    final c = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
        lessonNotesClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    final n = c.read(lessonNotesProvider.notifier);
    final ms = now.millisecondsSinceEpoch;
    // A version from a device whose clock was an hour ahead.
    n.applyRemote({
      'a|k': LessonNote(text: 'future', updatedAt: ms + 3600 * 1000),
    });
    final future = ms + 3600 * 1000;
    for (var i = 0; i < 3; i++) {
      n.set(['a|k'], LessonNote(text: 'edit $i'));
      // Never at or below the version it replaces.
      expect(c.read(lessonNotesProvider)['a|k']!.updatedAt, future + i + 1);
    }
    expect(c.read(lessonNotesProvider)['a|k']!.base, future);
    // Clamping can't go below the replaced version + 1.
    expect(n.clampFuture('a', ms), 1);
    expect(c.read(lessonNotesProvider)['a|k']!.updatedAt, future + 1);
    expect(c.read(lessonNotesProvider)['a|k']!.dirty, isTrue);
    // A new note (no replaced version) is clamped to the limit.
    n.applyRemote({'a|j': LessonNote(text: 'synced', updatedAt: ms - 10)});
    n.set(['a|n'], const LessonNote(text: 'new'));
    n.set(['a|j'], const LessonNote(text: 'changed'));
    expect(c.read(lessonNotesProvider)['a|j']!.base, ms - 10);
    expect(n.clampFuture('a', ms - 100), 2);
    expect(c.read(lessonNotesProvider)['a|n']!.updatedAt, ms - 100);
    // a|j stays above the version it replaces.
    expect(c.read(lessonNotesProvider)['a|j']!.updatedAt, ms - 9);
    // Acknowledged notes are never clamped.
    n.applyRemote({'a|s': LessonNote(text: 'server', updatedAt: ms + 999)});
    expect(n.clampFuture('a', ms - 100), 0);
    expect(c.read(lessonNotesProvider)['a|s']!.updatedAt, ms + 999);
    expect(c.read(lessonNotesProvider)['a|s']!.dirty, isFalse);

    n.applyRemote({'a|old': const LessonNote(text: 'legacy')});
    expect(c.read(lessonNotesProvider)['a|old']!.updatedAt, 0);
    expect(n.stampLegacy('a', 5), 1);
    expect(c.read(lessonNotesProvider)['a|old']!.updatedAt, 5);
    expect(c.read(lessonNotesProvider)['a|old']!.dirty, isTrue);
  });

  test('old tombstones are pruned only for accounts that do not sync', () {
    var now = DateTime.utc(2026, 1, 1);
    final c = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
        lessonNotesClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    final n = c.read(lessonNotesProvider.notifier);
    n.set(['a|k', 'b|k'], const LessonNote(text: 'x'));
    n.set(['a|k', 'b|k'], const LessonNote());
    now = now.add(const Duration(days: 200));
    n.pruneTombstones((id) => id == 'b');
    expect(c.read(lessonNotesProvider).keys, ['b|k']);
  });

  test('saved reports whether the latest change was stored (M8)', () async {
    final store = _FailingStore();
    final c = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    final n = c.read(lessonNotesProvider.notifier);
    n.set(['k'], const LessonNote(text: 'x'));
    expect(await n.saved, isTrue);
    store.fail = true;
    n.set(['k'], const LessonNote(text: 'y'));
    expect(await n.saved, isFalse);
    store.fail = false;
    n.set(['k'], const LessonNote(text: 'z'));
    expect(await n.saved, isTrue);
  });
}

class _FailingStore extends MemorySettingsStore {
  bool fail = false;
  @override
  Future<void> write(String key, Object? value) async {
    if (fail) throw StateError('disk full');
    await super.write(key, value);
  }
}
