import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'lesson_layout.dart';

/// Paints unit lines, day dividers, past-day tint and today's tint in a single
/// pass (instead of dozens of decorated containers).
class GridBackgroundPainter extends CustomPainter {
  const GridBackgroundPainter({
    required this.scale,
    required this.units,
    required this.left,
    required this.columnWidth,
    required this.columns,
    required this.pastColumns,
    required this.todayColumn,
    required this.lineColor,
    required this.pastTint,
    required this.todayTint,
  });

  final TimeScale scale;
  final List<TimeUnit> units;
  final double left;
  final double columnWidth;
  final int columns;

  /// Columns [0, pastColumns) are in the past.
  final int pastColumns;

  /// -1 if today is not displayed.
  final int todayColumn;
  final Color lineColor;
  final Color pastTint;
  final Color todayTint;

  @override
  void paint(Canvas canvas, Size size) {
    if (pastColumns > 0) {
      canvas.drawRect(
        Rect.fromLTWH(left, 0, columnWidth * pastColumns, size.height),
        Paint()..color = pastTint,
      );
    }
    if (todayColumn >= 0) {
      canvas.drawRect(
        Rect.fromLTWH(left + columnWidth * todayColumn, 0, columnWidth, size.height),
        Paint()..color = todayTint,
      );
    }
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (final u in units) {
      final y = scale.y(u.start).roundToDouble() + 0.5;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), line);
    }
    for (var c = 0; c <= columns; c++) {
      final x = (left + columnWidth * c).roundToDouble() + 0.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  @override
  bool shouldRepaint(GridBackgroundPainter old) =>
      old.scale.pxPerMinute != scale.pxPerMinute ||
      old.scale.startMinute != scale.startMinute ||
      old.units != units ||
      old.left != left ||
      old.columnWidth != columnWidth ||
      old.columns != columns ||
      old.pastColumns != pastColumns ||
      old.todayColumn != todayColumn ||
      old.lineColor != lineColor ||
      old.pastTint != pastTint ||
      old.todayTint != todayTint;
}
