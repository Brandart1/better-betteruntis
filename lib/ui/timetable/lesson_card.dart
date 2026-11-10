import 'package:flutter/material.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import 'lesson_layout.dart';
import 'lesson_style.dart';
import 'timetable_utils.dart';

/// A rounded lesson card. All text is one [Text.rich] (one paragraph per
/// card) so the grid stays cheap to lay out; overflowing text is clipped.
class LessonCard extends StatelessWidget {
  const LessonCard({
    super.key,
    required this.block,
    required this.names,
    this.detailed = false,
    this.onTap,
  });

  final LessonBlock block;
  final NameResolver names;

  /// Larger card with long names and info text (day view).
  final bool detailed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = LessonStyle.of(cs, block);
    final radius = BorderRadius.circular(detailed ? 10 : 6);
    final fg = style.foreground;

    Widget content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: detailed ? 10 : 3,
        vertical: detailed ? 6 : 2,
      ),
      child: Text.rich(
        TextSpan(children: _spans(fg, style)),
        style: TextStyle(
          color: fg,
          fontSize: detailed ? 14 : 11,
          height: 1.2,
        ),
        overflow: TextOverflow.clip,
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
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
            : BorderSide(color: style.border!, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: SizedBox.expand(child: content)),
    );
  }

  List<InlineSpan> _spans(Color fg, LessonStyle style) {
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
            child: Icon(Icons.assignment_outlined, size: detailed ? 16 : 11, color: fg),
          ),
        ),
      if (subjects.isEmpty)
        TextSpan(text: p.lessonText.isNotEmpty ? p.lessonText : '—')
      else
        ...elementSpans(names, subjects, long: detailed, oldStyle: oldStyle),
    ];

    final spans = <InlineSpan>[
      TextSpan(
        children: title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
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
      spans.add(TextSpan(
        text: '  ${hhmm(minuteOfDay(block.start))}–${hhmm(minuteOfDay(block.end))}',
        style: TextStyle(color: fg.withValues(alpha: 0.75)),
      ));
    }
    // Teachers first: they must never be clipped away (BetterUntis bug).
    line(elementSpans(names, teachers, long: detailed, oldStyle: oldStyle));
    line(elementSpans(names, rooms, long: detailed, oldStyle: oldStyle));
    if (detailed) {
      final classes = p.ofType(ElementType.klasse);
      line(elementSpans(names, classes, oldStyle: oldStyle),
          st: TextStyle(color: fg.withValues(alpha: 0.75)));
      final texts = {
        for (final q in block.periods) ...[q.substitutionText, q.lessonText, q.infoText],
      }.where((t) => t.trim().isNotEmpty);
      for (final t in texts) {
        line([TextSpan(text: t)], st: const TextStyle(fontStyle: FontStyle.italic));
      }
    } else if (p.substitutionText.isNotEmpty) {
      line([TextSpan(text: p.substitutionText)],
          st: const TextStyle(fontStyle: FontStyle.italic));
    }
    return spans;
  }
}

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
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(CancelledHatchPainter old) => old.color != color;
}
