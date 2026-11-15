import 'dart:async';

import 'package:flutter/material.dart';

import 'lesson_layout.dart';
import 'timetable_utils.dart';

/// Horizontal "now" line across today's column. Must be a direct child of a
/// [Stack]. Ticks once a minute on its own, so the grid never rebuilds for it.
class NowIndicator extends StatefulWidget {
  const NowIndicator({
    super.key,
    required this.scale,
    required this.left,
    required this.width,
  });

  final TimeScale scale;
  final double left;
  final double width;

  @override
  State<NowIndicator> createState() => _NowIndicatorState();
}

class _NowIndicatorState extends State<NowIndicator> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = minuteOfDay(_now);
    final s = widget.scale;
    final visible = m >= s.startMinute && m <= s.endMinute;
    final color = Theme.of(context).colorScheme.error;
    return Positioned(
      left: widget.left - 4,
      width: widget.width + 4,
      top: s.y(m.clamp(s.startMinute, s.endMinute)) - 4,
      height: 8,
      child: IgnorePointer(
        child: visible
            ? CustomPaint(painter: _NowLinePainter(color))
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _NowLinePainter extends CustomPainter {
  const _NowLinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    final y = size.height / 2;
    canvas.drawCircle(Offset(4, y), 4, p);
    canvas.drawLine(Offset(4, y), Offset(size.width, y), p);
  }

  @override
  bool shouldRepaint(_NowLinePainter old) => old.color != color;
}

/// Past tint over the part of today's column that is over (top to now).
/// Must be a direct child of a [Stack], below the lessons. Ticks once a
/// minute on its own, like [NowIndicator].
class TodayPastTint extends StatefulWidget {
  const TodayPastTint({
    super.key,
    required this.scale,
    required this.left,
    required this.width,
    required this.height,
    required this.color,
  });

  final TimeScale scale;
  final double left;
  final double width;

  /// Full canvas height (covered completely once the day's grid is over).
  final double height;
  final Color color;

  @override
  State<TodayPastTint> createState() => _TodayPastTintState();
}

class _TodayPastTintState extends State<TodayPastTint> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final m = minuteOfDay(_now);
    final h = m >= s.endMinute
        ? widget.height
        : s.y(m.clamp(s.startMinute, s.endMinute)).clamp(0.0, widget.height);
    return Positioned(
      key: const ValueKey('today-past-tint'),
      left: widget.left,
      width: widget.width,
      top: 0,
      height: h,
      child: IgnorePointer(child: ColoredBox(color: widget.color)),
    );
  }
}
