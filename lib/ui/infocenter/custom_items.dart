/// The user's own homework and exams (lesson notes, lib/core/lesson_notes.dart)
/// in the Info center: the "Custom" chip and editing them in place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/info.dart';
import '../../core/lesson_notes.dart';
import '../timetable/lesson_details_sheet.dart';
import 'info_common.dart';

/// Marks an item the user added themselves (not from the school).
class CustomChip extends StatelessWidget {
  const CustomChip({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InfoChip(
      'Custom',
      key: const ValueKey('custom-chip'),
      icon: Icons.edit_outlined,
      // Neutral: the tertiary colours already mark exams that are soon.
      background: cs.surfaceContainerHighest,
      foreground: cs.onSurfaceVariant,
    );
  }
}

/// The current note of [source] (its first period; a merged lesson has the
/// same note on all of them).
LessonNote _noteOf(WidgetRef ref, CustomSource source) =>
    ref.read(lessonNotesProvider)[source.noteKeys.first] ?? const LessonNote();

/// Edits (empty text: removes) the user's own homework of [source].
Future<void> editCustomHomework(
  BuildContext context,
  WidgetRef ref,
  CustomSource source,
) async {
  final note = _noteOf(ref, source);
  final text = await askLessonDetails(
    context,
    title: 'Edit homework',
    initial: note.homework,
    hint: homeworkHint,
  );
  if (text == null || !context.mounted) return;
  saveLessonNote(ref, source.noteKeys, note.copyWith(homework: text));
}

/// Edits the details of the user's own exam of [source] (the exam mark
/// itself is changed in the lesson details).
Future<void> editCustomExam(
  BuildContext context,
  WidgetRef ref,
  CustomSource source,
) async {
  final note = _noteOf(ref, source);
  final text = await askLessonDetails(
    context,
    title: 'Exam details',
    initial: note.text,
  );
  if (text == null || !context.mounted) return;
  saveLessonNote(ref, source.noteKeys, note.copyWith(text: text));
}
