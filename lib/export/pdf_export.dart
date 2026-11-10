/// PDF export: a one-page grid like the app (time column, weekday columns,
/// lesson boxes placed by time).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'export_grid.dart';
import 'export_model.dart';
import 'pdf_fonts.dart';
import 'xlsx_export.dart' show isDarkColor;

class PdfExportOptions {
  const PdfExportOptions({
    this.colors = true,
    this.landscape = true,
    this.pageFormat = PdfPageFormat.a4,
  });

  final bool colors;
  final bool landscape;
  final PdfPageFormat pageFormat;
}

/// Text for the built-in Helvetica (WinAnsi/Latin-1 only).
String latin1Safe(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r <= 0xFF) {
      b.writeCharCode(r);
    } else {
      b.write(switch (r) {
        0x2013 || 0x2014 || 0x2212 => '-',
        0x2018 || 0x2019 => "'",
        0x201C || 0x201D || 0x201E => '"',
        0x2026 => '...',
        0x2022 => '·',
        _ => '?',
      });
    }
  }
  return b.toString();
}

PdfColor _c(int argb) => PdfColor.fromInt(0xFF000000 | (argb & 0xFFFFFF));

class _Placed {
  _Placed(this.lesson);
  final ExportLesson lesson;
  int column = 0;
  int columns = 1;
}

/// Side-by-side sub-columns for overlapping lessons of one day.
List<_Placed> _placeDay(List<ExportLesson> lessons) {
  final sorted = [...lessons]
    ..sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.end.compareTo(b.end);
    });
  final out = <_Placed>[];
  var cluster = <_Placed>[];
  var clusterEnd = -1;
  final ends = <int>[];
  void close() {
    for (final p in cluster) {
      p.columns = ends.length;
    }
    cluster = [];
    ends.clear();
  }

  for (final l in sorted) {
    if (cluster.isNotEmpty && l.start >= clusterEnd) close();
    final p = _Placed(l);
    var col = ends.indexWhere((e) => e <= l.start);
    if (col == -1) {
      col = ends.length;
      ends.add(l.end);
    } else {
      ends[col] = l.end;
    }
    p.column = col;
    cluster.add(p);
    out.add(p);
    clusterEnd = math.max(clusterEnd, l.end);
  }
  close();
  return out;
}

Future<Uint8List> buildPdf(
  ExportTimetable t, {
  PdfExportOptions options = const PdfExportOptions(),
  PdfFonts? fonts,
}) async {
  final unicode = fonts != null;
  String tx(String s) => unicode ? s : latin1Safe(s);

  final doc = pw.Document(
    title: tx(t.title),
    creator: 'better-betteruntis',
    theme: fonts == null
        ? pw.ThemeData.base()
        : pw.ThemeData.withFont(
            base: fonts.regular,
            bold: fonts.bold,
            italic: fonts.regular,
            boldItalic: fonts.bold,
          ),
  );
  final format = options.landscape
      ? options.pageFormat.landscape
      : options.pageFormat.portrait;
  const margin = 22.0;
  final width = format.width - 2 * margin;
  final height = format.height - 2 * margin;

  const headerH = 34.0;
  const footerH = 14.0;
  const dayHeaderH = 18.0;
  const timeColW = 42.0;
  final gridH = height - headerH - footerH - dayHeaderH;
  final dayW = (width - timeColW) / math.max(1, t.weekdays.length);

  final rows = gridRows(t.grid, t.weekdays, t.lessons);
  var startMin = rows.isEmpty
      ? 8 * 60
      : rows.map((r) => r.start).reduce(math.min);
  var endMin = rows.isEmpty ? 16 * 60 : rows.map((r) => r.end).reduce(math.max);
  for (final l in t.lessons) {
    startMin = math.min(startMin, l.start);
    endMin = math.max(endMin, l.end);
  }
  if (endMin <= startMin) endMin = startMin + 60;
  final ppm = gridH / (endMin - startMin);
  double y(int minute) => dayHeaderH + (minute - startMin) * ppm;

  // Font sizes: shrink for short units and crowded days.
  final unitH = rows.isEmpty
      ? 40.0
      : rows.map((r) => (r.end - r.start) * ppm).reduce(math.min);
  var maxCols = 1;
  final placedByDay = <int, List<_Placed>>{};
  for (final d in t.weekdays) {
    final placed = _placeDay([
      for (final l in t.lessons)
        if (l.weekday == d) l,
    ]);
    placedByDay[d] = placed;
    for (final p in placed) {
      maxCols = math.max(maxCols, p.columns);
    }
  }
  final colW = dayW / maxCols;
  final subjectSize = math
      .min(unitH * 0.32, math.min(9.5, colW / 5))
      .clamp(4.5, 9.5)
      .toDouble();
  final detailSize = math.max(4.0, subjectSize * 0.82);

  final grey = PdfColor.fromInt(0xFF9E9E9E);
  final lightGrey = PdfColor.fromInt(0xFFE0E0E0);
  final children = <pw.Widget>[];

  // Day headers.
  for (var i = 0; i < t.weekdays.length; i++) {
    final d = t.weekdays[i];
    final date = DateTime(
      t.weekStart.year,
      t.weekStart.month,
      t.weekStart.day + d - 1,
    );
    final label = t.regular
        ? weekdayName(d, t.locale)
        : '${weekdayName(d, t.locale, short: true)} ${exportDateFormat('d MMM', t.locale).format(date)}';
    children.add(
      pw.Positioned(
        left: timeColW + i * dayW,
        top: 0,
        child: pw.SizedBox(
          width: dayW,
          height: dayHeaderH,
          child: pw.Center(
            child: pw.Text(
              tx(label),
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  // Unit bands and labels.
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    final top = y(row.start), h = (row.end - row.start) * ppm;
    if (r.isOdd) {
      children.add(
        pw.Positioned(
          left: 0,
          top: top,
          child: pw.Container(
            width: width,
            height: h,
            color: PdfColor.fromInt(0xFFF6F6F6),
          ),
        ),
      );
    }
    final labelSize = math.min(8.0, math.max(4.5, h * 0.3));
    children.add(
      pw.Positioned(
        left: 0,
        top: top,
        child: pw.SizedBox(
          width: timeColW - 2,
          height: h,
          child: pw.ClipRect(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                if (row.label.isNotEmpty)
                  pw.Text(
                    tx(row.label),
                    style: pw.TextStyle(
                      fontSize: labelSize,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                pw.Text(
                  tx('${hhmmOf(row.start)}–${hhmmOf(row.end)}'),
                  style: pw.TextStyle(fontSize: labelSize * 0.8, color: grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Grid lines.
  children.add(
    pw.Positioned(
      left: 0,
      top: 0,
      child: pw.CustomPaint(
        size: PdfPoint(width, dayHeaderH + gridH),
        painter: (canvas, size) {
          // PDF origin is bottom-left.
          double py(double top) => size.y - top;
          canvas
            ..setStrokeColor(lightGrey)
            ..setLineWidth(0.4);
          for (final row in rows) {
            canvas
              ..moveTo(0, py(y(row.start)))
              ..lineTo(size.x, py(y(row.start)));
          }
          canvas
            ..moveTo(0, py(dayHeaderH + gridH))
            ..lineTo(size.x, py(dayHeaderH + gridH));
          for (var i = 0; i <= t.weekdays.length; i++) {
            final x = timeColW + i * dayW;
            canvas
              ..moveTo(x, py(0))
              ..lineTo(x, py(dayHeaderH + gridH));
          }
          canvas.strokePath();
        },
      ),
    ),
  );

  // Holidays.
  for (var i = 0; i < t.weekdays.length; i++) {
    final name = t.holidays[t.weekdays[i]];
    if (name == null) continue;
    children.add(
      pw.Positioned(
        left: timeColW + i * dayW + 1,
        top: dayHeaderH + 1,
        child: pw.Container(
          width: dayW - 2,
          height: gridH - 2,
          color: PdfColor.fromInt(0xFFEFEFEF),
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(
            tx(name),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColor.fromInt(0xFF616161),
            ),
          ),
        ),
      ),
    );
  }

  // Lessons.
  for (var i = 0; i < t.weekdays.length; i++) {
    for (final p in placedByDay[t.weekdays[i]]!) {
      final l = p.lesson;
      final w = dayW / p.columns;
      final left = timeColW + i * dayW + p.column * w + 1;
      final top = y(l.start) + 1;
      final boxW = w - 2;
      final boxH = math.max(4.0, (l.end - l.start) * ppm - 2);
      children.add(
        pw.Positioned(
          left: left,
          top: top,
          child: _lessonBox(
            l,
            boxW,
            boxH,
            options.colors,
            subjectSize,
            detailSize,
            t.showClasses,
            tx,
          ),
        ),
      );
    }
  }

  final exported = exportDateFormat(
    'd MMM yyyy, HH:mm',
    t.locale,
  ).format(t.exportedAt);
  doc.addPage(
    pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(margin),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            height: headerH,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  tx(t.elementName),
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  maxLines: 1,
                ),
                pw.Text(
                  tx(
                    [
                      t.periodLabel,
                      if (t.schoolName.isNotEmpty) t.schoolName,
                    ].join(' · '),
                  ),
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColor.fromInt(0xFF616161),
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
          pw.SizedBox(
            width: width,
            height: dayHeaderH + gridH,
            child: pw.Stack(children: children),
          ),
          pw.SizedBox(
            height: footerH,
            child: pw.Align(
              alignment: pw.Alignment.bottomRight,
              child: pw.Text(
                tx('Exported with better-betteruntis · $exported'),
                style: pw.TextStyle(fontSize: 6.5, color: grey),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

pw.Widget _lessonBox(
  ExportLesson l,
  double w,
  double h,
  bool colors,
  double subjectSize,
  double detailSize,
  bool showClasses,
  String Function(String) tx,
) {
  final cancelled = l.status == LessonStatus.cancelled;
  final exam = l.status == LessonStatus.exam;
  final subst = l.status == LessonStatus.substitution;

  final int bgArgb;
  if (colors) {
    bgArgb = l.color ?? ExportPalette.defaultRegular;
  } else {
    bgArgb = cancelled ? 0xFFEEEEEE : 0xFFFFFFFF;
  }
  final bg = _c(bgArgb);
  final fg = isDarkColor(bgArgb)
      ? PdfColors.white
      : PdfColor.fromInt(0xFF1C1B1F);
  final fgMuted = isDarkColor(bgArgb)
      ? PdfColor.fromInt(0xFFE0E0E0)
      : PdfColor.fromInt(0xFF424242);

  final PdfColor borderColor;
  final double borderW;
  if (exam) {
    borderColor = colors ? PdfColor.fromInt(0xFFBA1A1A) : PdfColors.black;
    borderW = 1.4;
  } else if (subst) {
    borderColor = colors ? PdfColor.fromInt(0xFFE65100) : PdfColors.black;
    borderW = 1.2;
  } else {
    borderColor = colors ? _c(_darken(bgArgb)) : PdfColor.fromInt(0xFF9E9E9E);
    borderW = 0.5;
  }

  final strike = cancelled ? pw.TextDecoration.lineThrough : null;
  final detail = pw.TextStyle(
    fontSize: detailSize,
    color: fgMuted,
    decoration: strike,
  );
  pw.Widget names(List<String> current, List<String> struck) => pw.RichText(
    maxLines: 1,
    overflow: pw.TextOverflow.clip,
    text: pw.TextSpan(
      style: detail,
      children: [
        pw.TextSpan(text: tx(current.join(', '))),
        if (struck.isNotEmpty) ...[
          if (current.isNotEmpty) const pw.TextSpan(text: ' '),
          pw.TextSpan(
            text: tx(struck.join(', ')),
            style: const pw.TextStyle(
              decoration: pw.TextDecoration.lineThrough,
            ),
          ),
        ],
      ],
    ),
  );

  final lines = <pw.Widget>[
    pw.RichText(
      maxLines: 1,
      overflow: pw.TextOverflow.clip,
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: tx(l.subjectLabel),
            style: pw.TextStyle(
              fontSize: subjectSize,
              fontWeight: pw.FontWeight.bold,
              color: fg,
              decoration: strike,
            ),
          ),
          if (exam || cancelled || subst)
            pw.TextSpan(
              text: tx('  ${l.status.label}'),
              style: pw.TextStyle(
                fontSize: detailSize,
                fontStyle: pw.FontStyle.italic,
                color: fgMuted,
              ),
            ),
        ],
      ),
    ),
    if (l.teachersShort.isNotEmpty || l.replacedTeachers.isNotEmpty)
      names(l.teachersShort, l.replacedTeachers),
    if (l.rooms.isNotEmpty || l.replacedRooms.isNotEmpty)
      names(l.rooms, l.replacedRooms),
    if (showClasses && l.classes.isNotEmpty) names(l.classes, const []),
  ];

  return pw.Container(
    width: w,
    height: h,
    decoration: pw.BoxDecoration(
      color: bg,
      border: pw.Border.all(color: borderColor, width: borderW),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
    ),
    child: pw.ClipRect(
      child: pw.Stack(
        children: [
          if (cancelled)
            pw.CustomPaint(
              size: PdfPoint(w, h),
              painter: (canvas, size) {
                canvas
                  ..setStrokeColor(PdfColor.fromInt(0x55000000 | 0x9E9E9E))
                  ..setLineWidth(0.4);
                for (var x = -size.y; x < size.x; x += 5) {
                  canvas
                    ..moveTo(x, 0)
                    ..lineTo(x + size.y, size.y);
                }
                canvas.strokePath();
              },
            ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 1.5,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: lines,
            ),
          ),
        ],
      ),
    ),
  );
}

int _darken(int argb) {
  int ch(int shift) => (((argb >> shift) & 0xFF) * 0.7).round();
  return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}
