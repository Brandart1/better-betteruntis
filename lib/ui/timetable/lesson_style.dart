import 'package:flutter/material.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import 'lesson_layout.dart';

/// Visual style of a lesson card derived from its state and the theme.
class LessonStyle {
  const LessonStyle({
    required this.background,
    required this.foreground,
    this.border,
    this.cancelled = false,
    this.exam = false,
  });

  final Color background;
  final Color foreground;
  final Color? border;
  final bool cancelled;
  final bool exam;

  factory LessonStyle.of(ColorScheme cs, LessonBlock block) {
    final p = block.first;
    if (block.isCancelled) {
      return LessonStyle(
        background: cs.surfaceContainerHighest,
        foreground: cs.onSurfaceVariant,
        cancelled: true,
      );
    }
    if (block.isExam) {
      return LessonStyle(
        background: cs.errorContainer,
        foreground: cs.onErrorContainer,
        border: cs.error,
        exam: true,
      );
    }
    final irregular = block.isIrregular;
    if (p.backColor != null) {
      final bg = Color(p.backColor!);
      final fg =
          ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
              ? Colors.white
              : Colors.black87;
      return LessonStyle(
        background: bg,
        foreground: fg,
        border: irregular ? cs.tertiary : null,
      );
    }
    if (irregular) {
      return LessonStyle(
        background: cs.tertiaryContainer,
        foreground: cs.onTertiaryContainer,
        border: cs.tertiary,
      );
    }
    return LessonStyle(
      background: cs.primaryContainer,
      foreground: cs.onPrimaryContainer,
    );
  }
}

const _strike = TextStyle(decoration: TextDecoration.lineThrough);

/// Spans for the elements of [type]: substitutions show the new name followed
/// by the struck-through original; removed elements show only the struck
/// original. Inactive master-data entries are shown like any other.
List<InlineSpan> elementSpans(
  NameResolver names,
  Iterable<ElementRef> refs, {
  bool long = false,
  String separator = ', ',
  TextStyle? oldStyle,
}) {
  String nameOf(ElementRef r, {bool original = false}) => long
      ? names.longName(r, original: original)
      : names.shortName(r, original: original);
  final struck = (oldStyle ?? const TextStyle()).merge(_strike);
  final spans = <InlineSpan>[];
  for (final r in refs) {
    if (spans.isNotEmpty) spans.add(TextSpan(text: separator));
    switch (r.change) {
      case ElementChange.regular:
      case ElementChange.added:
        spans.add(TextSpan(text: nameOf(r)));
      case ElementChange.substituted:
        spans.add(TextSpan(text: nameOf(r)));
        spans.add(const TextSpan(text: ' '));
        spans.add(TextSpan(text: nameOf(r, original: true), style: struck));
      case ElementChange.removed:
        spans.add(TextSpan(text: nameOf(r, original: true), style: struck));
    }
  }
  return spans;
}
