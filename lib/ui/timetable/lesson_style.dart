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

/// Short name of the lesson's subject (for [TimetableSettings.subjectColors]):
/// the current subject, else the removed original one; null if the period
/// has no subject or the name can't be resolved.
String? lessonSubjectName(Period p, NameResolver? names) {
  final subjects = p.ofType(ElementType.subject).toList();
  if (subjects.isEmpty) return null;
  final r = subjects.firstWhere(
    (r) => r.change != ElementChange.removed,
    orElse: () => subjects.first,
  );
  final original = r.change == ElementChange.removed;
  final name = names != null
      ? names.shortName(r, original: original)
      : (original ? r.orgInlineName : r.inlineName);
  if (name == null) return null;
  final t = name.trim();
  return t.isEmpty || t == '?' || RegExp(r'^#-?\d+$').hasMatch(t) ? null : t;
}

/// Visual style of a lesson card derived from its state, the theme and the
/// user's [TimetableSettings].
class LessonStyle {
  const LessonStyle({
    required this.background,
    required this.foreground,
    this.border,
    this.borderWidth = defaultBorderWidth,
    this.cancelled = false,
    this.exam = false,
  });

  /// Width of the accent border of filled state colors (exam, substitution).
  static const defaultBorderWidth = 2.0;

  /// Width of the border in [StateColorMode.border]: clearly visible even on
  /// small week-grid cards.
  static const stateBorderWidth = 3.0;

  final Color background;
  final Color foreground;
  final Color? border;
  final double borderWidth;
  final bool cancelled;
  final bool exam;

  /// A custom state color: background, readable foreground and a border that
  /// is a stronger shade of the same color.
  static (Color, Color, Color) _custom(int argb) {
    final bg = Color(argb);
    final fg = onColorFor(bg);
    return (bg, fg, Color.lerp(bg, fg, 0.45)!);
  }

  /// The lesson's normal color, ignoring its state. Priority: custom subject
  /// color > school color (if enabled) > custom regular color > theme.
  static (Color, Color) base(
    ColorScheme cs,
    Period p,
    TimetableSettings settings, [
    NameResolver? names,
  ]) {
    final subject = settings.subjectColorFor(lessonSubjectName(p, names));
    final argb =
        subject ??
        (settings.useSchoolColors ? p.backColor : null) ??
        settings.regularColor;
    if (argb == null) return (cs.primaryContainer, cs.onPrimaryContainer);
    final bg = Color(argb);
    return (bg, onColorFor(bg));
  }

  /// [names] resolves the subject for custom subject colors; without it only
  /// inline subject names are matched.
  ///
  /// [highContrast]: monochrome cards (background and text from [cs], always
  /// outlined); exams and substitutions get a thicker border, cancelled
  /// lessons keep their hatching and strike-through.
  factory LessonStyle.of(
    ColorScheme cs,
    LessonBlock block, [
    TimetableSettings settings = const TimetableSettings(),
    NameResolver? names,
    bool highContrast = false,
  ]) {
    final p = block.first;
    final cancelled = block.isCancelled;
    final exam = !cancelled && block.isExam;
    final irregular = !cancelled && !exam && block.isIrregular;

    if (highContrast) {
      return LessonStyle(
        background: cs.surface,
        foreground: cs.onSurface,
        border: cs.onSurface,
        borderWidth: exam || irregular ? 4 : 1.5,
        cancelled: cancelled,
        exam: exam,
      );
    }

    // State color as a border around the normal lesson color.
    LessonStyle bordered(Color border) {
      final (bg, fg) = base(cs, p, settings, names);
      return LessonStyle(
        background: bg,
        foreground: fg,
        border: border,
        borderWidth: stateBorderWidth,
        cancelled: cancelled,
        exam: exam,
      );
    }

    if (cancelled) {
      final custom = settings.cancelledColor;
      if (settings.cancelledMode == StateColorMode.border) {
        return bordered(custom != null ? Color(custom) : cs.outline);
      }
      if (custom != null) {
        final (bg, fg, _) = _custom(custom);
        return LessonStyle(background: bg, foreground: fg, cancelled: true);
      }
      return LessonStyle(
        background: cs.surfaceContainerHighest,
        foreground: cs.onSurfaceVariant,
        cancelled: true,
      );
    }
    if (exam) {
      final custom = settings.examColor;
      if (settings.examMode == StateColorMode.border) {
        return bordered(custom != null ? Color(custom) : cs.error);
      }
      if (custom != null) {
        final (bg, fg, border) = _custom(custom);
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
    if (irregular) {
      final custom = settings.irregularColor;
      if (settings.irregularMode == StateColorMode.border) {
        return bordered(custom != null ? Color(custom) : cs.tertiary);
      }
      if (custom != null) {
        final (bg, fg, border) = _custom(custom);
        return LessonStyle(background: bg, foreground: fg, border: border);
      }
      return LessonStyle(
        background: cs.tertiaryContainer,
        foreground: cs.onTertiaryContainer,
        border: cs.tertiary,
      );
    }
    final (bg, fg) = base(cs, p, settings, names);
    return LessonStyle(background: bg, foreground: fg);
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
