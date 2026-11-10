import 'package:flutter/material.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import 'lesson_layout.dart';

/// Readable text color on an arbitrary [background], chosen by luminance.
Color onColorFor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? Colors.white
    : Colors.black87;

/// Visual style of a lesson card derived from its state, the theme and the
/// user's [TimetableSettings].
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

  /// A custom state color: background, readable foreground and a border that
  /// is a stronger shade of the same color.
  static (Color, Color, Color) _custom(int argb) {
    final bg = Color(argb);
    final fg = onColorFor(bg);
    return (bg, fg, Color.lerp(bg, fg, 0.45)!);
  }

  factory LessonStyle.of(
    ColorScheme cs,
    LessonBlock block, [
    TimetableSettings settings = const TimetableSettings(),
  ]) {
    final p = block.first;
    if (block.isCancelled) {
      if (settings.cancelledColor case final c?) {
        final (bg, fg, _) = _custom(c);
        return LessonStyle(background: bg, foreground: fg, cancelled: true);
      }
      return LessonStyle(
        background: cs.surfaceContainerHighest,
        foreground: cs.onSurfaceVariant,
        cancelled: true,
      );
    }
    if (block.isExam) {
      if (settings.examColor case final c?) {
        final (bg, fg, border) = _custom(c);
        return LessonStyle(
          background: bg,
          foreground: fg,
          border: border,
          exam: true,
        );
      }
      return LessonStyle(
        background: cs.errorContainer,
        foreground: cs.onErrorContainer,
        border: cs.error,
        exam: true,
      );
    }
    final irregular = block.isIrregular;
    if (settings.useSchoolColors && p.backColor != null) {
      final bg = Color(p.backColor!);
      return LessonStyle(
        background: bg,
        foreground: onColorFor(bg),
        border: irregular
            ? (settings.irregularColor != null
                  ? Color(settings.irregularColor!)
                  : cs.tertiary)
            : null,
      );
    }
    if (irregular) {
      if (settings.irregularColor case final c?) {
        final (bg, fg, border) = _custom(c);
        return LessonStyle(background: bg, foreground: fg, border: border);
      }
      return LessonStyle(
        background: cs.tertiaryContainer,
        foreground: cs.onTertiaryContainer,
        border: cs.tertiary,
      );
    }
    if (settings.regularColor case final c?) {
      final (bg, fg, _) = _custom(c);
      return LessonStyle(background: bg, foreground: fg);
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
