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
    expect(notes.keys, unorderedEquals(['k1', 'k2']));
    expect(notes['k1'], const LessonNote(exam: true, text: 'Topics 1-3'));
    c.dispose();
  });
}
