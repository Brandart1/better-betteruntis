import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accessibility.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import 'lesson_layout.dart';
import 'lesson_style.dart';
import 'timetable_utils.dart';
import 'viewing_target.dart';

/// A rounded lesson card. All text is one [Text.rich] (one paragraph per
/// card) so the grid stays cheap to lay out; overflowing text is clipped.
///
/// Watches [timetableSettingsProvider] itself, so a settings change rebuilds
/// just the cards (no relayout of the grid, no refetch).
class LessonCard extends ConsumerWidget {
  const LessonCard({
    super.key,
    required this.block,
    required this.names,
    this.detailed = false,
    this.past = false,
    this.pastSurface,
    this.onTap,
  });

  final LessonBlock block;
  final NameResolver names;

  /// Larger card with long names and info text (day view).
  final bool detailed;

  /// The lesson is over: drawn muted (see [LessonStyle.dimmed]).
  final bool past;

  /// Background behind past lessons that [past] cards fade towards; defaults
  /// to [pastSurfaceOf] the theme.
  final Color? pastSurface;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(timetableSettingsProvider);
    final cs = Theme.of(context).colorScheme;
    final highContrast = ref.watch(
      accessibilityProvider.select((a) => a.highContrast),
    );
    var style = LessonStyle.of(cs, block, settings, names, highContrast);
    if (past) style = style.dimmed(pastSurface ?? pastSurfaceOf(cs));
    final radius = BorderRadius.circular(detailed ? 10 : 6);
    final fg = style.foreground;
    final centered = settings.centerText;

    final padding = EdgeInsets.symmetric(
      horizontal: detailed ? 10 : 3,
      vertical: detailed ? 6 : 2,
    );
    final text = TextSpan(
      children: _spans(fg, style, settings, ViewingTarget.of(context)),
    );
    final textStyle = TextStyle(
      color: fg,
      fontSize: settings.detailFontSize,
      height: 1.2,
    );
    final align = centered ? TextAlign.center : TextAlign.start;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    Widget content = Padding(
      padding: padding,
      child: Align(
        alignment: centered ? Alignment.center : AlignmentDirectional.topStart,
        // Only whole lines: a line that doesn't fit is left out instead of
        // being cut in half (short lessons, large text).
        child: LayoutBuilder(
          builder: (context, constraints) => Text.rich(
            text,
            style: textStyle,
            textAlign: align,
            overflow: TextOverflow.clip,
            textScaler: scaler,
            maxLines: _fittingLines(
              TextSpan(
                style: DefaultTextStyle.of(context).style.merge(textStyle),
                children: [text],
              ),
              align,
              scaler,
              Directionality.of(context),
              constraints,
              settings.subjectFontSize,
            ),
          ),
        ),
      ),
    );
    if (style.cancelled) {
      content = CustomPaint(
        foregroundPainter: CancelledHatchPainter(fg.withValues(alpha: 0.18)),
        child: content,
      );
    }

    return Material(
      color: style.background,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: style.border == null
            ? BorderSide.none
            : BorderSide(color: style.border!, width: style.borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.expand(child: content),
      ),
    );
  }

  /// How many lines of [text] fit completely into [constraints] (at least
  /// one); null when all of them do.
  static int? _fittingLines(
    InlineSpan text,
    TextAlign align,
    TextScaler scaler,
    TextDirection direction,
    BoxConstraints constraints,
    double iconSize,
  ) {
    if (!constraints.hasBoundedHeight || !constraints.hasBoundedWidth) {
      return null;
    }
    final painter = TextPainter(
      text: text,
      textAlign: align,
      textDirection: direction,
      textScaler: scaler,
    );
    // The exam icon (a WidgetSpan) needs a size to measure the text.
    var placeholders = 0;
    text.visitChildren((span) {
      if (span is PlaceholderSpan) placeholders++;
      return true;
    });
    if (placeholders > 0) {
      painter.setPlaceholderDimensions([
        for (var i = 0; i < placeholders; i++)
          PlaceholderDimensions(
            size: Size(iconSize + 2, iconSize),
            alignment: PlaceholderAlignment.middle,
          ),
      ]);
    }
    painter.layout(maxWidth: constraints.maxWidth);
    try {
      if (painter.height <= constraints.maxHeight + 0.5) return null;
      final lines = painter.computeLineMetrics();
      var fit = 0;
      var bottom = 0.0;
      for (final l in lines) {
        bottom += l.height;
        if (bottom > constraints.maxHeight + 0.5) break;
        fit++;
      }
      return fit < 1 ? 1 : fit;
    } finally {
      painter.dispose();
    }
  }

  List<InlineSpan> _spans(
    Color fg,
    LessonStyle style,
    TimetableSettings settings,
    TimetableTarget? viewing,
  ) {
    final p = block.first;
    final subjects = p.ofType(ElementType.subject).toList();
    final teachers = p.ofType(ElementType.teacher).toList();
    final rooms = p.ofType(ElementType.room).toList();
    final oldStyle = TextStyle(color: fg.withValues(alpha: 0.65));

    final title = <InlineSpan>[
      if (style.exam)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(
              Icons.assignment_outlined,
              size: settings.subjectFontSize,
              color: fg,
            ),
          ),
        ),
      if (subjects.isEmpty)
        TextSpan(text: p.customTitle.isNotEmpty ? p.customTitle : '—')
      else
        ...elementSpans(names, subjects, long: detailed, oldStyle: oldStyle),
    ];

    final spans = <InlineSpan>[
      TextSpan(
        children: title,
        style: TextStyle(
          fontSize: settings.subjectFontSize,
          fontWeight: settings.boldSubject ? FontWeight.bold : FontWeight.w500,
          decoration: style.cancelled ? TextDecoration.lineThrough : null,
        ),
      ),
    ];
    void line(List<InlineSpan> s, {TextStyle? st}) {
      if (s.isEmpty) return;
      spans.add(const TextSpan(text: '\n'));
      spans.add(TextSpan(children: s, style: st));
    }

    if (detailed) {
      spans.add(
        TextSpan(
          text:
              '  ${hhmm(minuteOfDay(block.start))}–${hhmm(minuteOfDay(block.end))}',
          style: TextStyle(color: fg.withValues(alpha: 0.75)),
        ),
      );
    }
    final classes = p.ofType(ElementType.klasse).toList();
    final classLine = elementSpans(names, classes, oldStyle: oldStyle);
    final viewType = viewing?.type;
    if (viewType == ElementType.room) {
      // Room timetable: who is there. No class if the room is struck through.
      line(elementSpans(names, teachers, long: detailed, oldStyle: oldStyle));
      if (!roomVacated(p, viewing!.id)) line(classLine);
    } else if (viewType == ElementType.teacher) {
      // Teacher timetable: where and with whom.
      line(classLine);
      line(elementSpans(names, rooms, long: detailed, oldStyle: oldStyle));
    } else {
      // Teachers first: they must never be clipped away (BetterUntis bug).
      line(elementSpans(names, teachers, long: detailed, oldStyle: oldStyle));
      line(elementSpans(names, rooms, long: detailed, oldStyle: oldStyle));
      if (detailed) {
        line(classLine, st: TextStyle(color: fg.withValues(alpha: 0.75)));
      }
    }
    if (detailed) {
      final texts = {
        for (final q in block.periods) ...[
          q.substitutionText,
          q.lessonText,
          q.infoText,
          q.userNote,
        ],
      }.where((t) => t.trim().isNotEmpty);
      for (final t in texts) {
        line([
          TextSpan(text: t),
        ], st: const TextStyle(fontStyle: FontStyle.italic));
      }
    } else if (p.substitutionText.isNotEmpty) {
      line([
        TextSpan(text: p.substitutionText),
      ], st: const TextStyle(fontStyle: FontStyle.italic));
    }
    return spans;
  }
}

/// Tint painted over the grid background of past days and of the part of
/// today that is over.
Color pastTintOf(ColorScheme cs) => cs.onSurface.withValues(alpha: 0.10);

/// The grid background behind past lessons ([pastTintOf] over the surface).
Color pastSurfaceOf(ColorScheme cs) =>
    Color.alphaBlend(pastTintOf(cs), cs.surface);

/// Diagonal cross-hatch drawn over cancelled lessons.
class CancelledHatchPainter extends CustomPainter {
  const CancelledHatchPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 8.0;
    for (var x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CancelledHatchPainter old) => old.color != color;
}
