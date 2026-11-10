/// XLSX export: sheet "Timetable" as a grid (units × weekdays) and sheet
/// "Lessons" with the same table as the CSV.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'csv_export.dart';
import 'export_grid.dart';
import 'export_model.dart';
import 'zip_patch.dart';

const kGridSheet = 'Timetable';
const kLessonsSheet = 'Lessons';

/// Workbook font (what the excel package writes as the default font).
const kXlsxFontName = 'Arial';

/// Grid font sizes (pt) at the app's default text sizes.
const kXlsxDetailPt = 10.0;
const kXlsxSubjectPt = 12.0;

/// Rounds to half points (Excel's font size steps).
double _halfPt(double v) => (v * 2).round() / 2;

ExcelColor _argb(int argb) => ExcelColor.fromHexString(
  (0xFF000000 | (argb & 0xFFFFFF))
      .toRadixString(16)
      .padLeft(8, '0')
      .toUpperCase(),
);

/// Readable text on [argb]: black on light, white on dark backgrounds.
bool isDarkColor(int argb) {
  double ch(int v) {
    final c = v / 255;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4) as double;
  }

  final l =
      0.2126 * ch((argb >> 16) & 0xFF) +
      0.7152 * ch((argb >> 8) & 0xFF) +
      0.0722 * ch(argb & 0xFF);
  return l < 0.4;
}

/// One formatted piece of a grid cell (subject line or detail lines).
class _Run {
  const _Run(this.text, {required this.subject});
  final String text;
  final bool subject;
}

class _RichCell {
  const _RichCell(this.runs, {required this.fill, required this.italic});
  final List<_Run> runs;
  final int? fill;
  final bool italic;
}

/// [text] null keeps the built-in look (left/top aligned, one font size).
/// Otherwise lesson cells follow it: alignment, detail size as the cell font,
/// and the subject line as a rich-text run (own size, bold).
Uint8List buildXlsx(
  ExportTimetable t, {
  bool colors = true,
  ExportTextStyle? text,
}) {
  final excel = Excel.createExcel();
  final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
  final grid = excel[kGridSheet];
  final lessons = excel[kLessonsSheet];
  excel.setDefaultSheet(kGridSheet);
  if (defaultName != kGridSheet && defaultName != kLessonsSheet) {
    excel.delete(defaultName);
  }

  final thin = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.fromHexString('FFBDBDBD'),
  );
  final headerStyle = CellStyle(
    bold: true,
    backgroundColorHex: ExcelColor.fromHexString('FFEEEEEE'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
    leftBorder: thin,
    rightBorder: thin,
    topBorder: thin,
    bottomBorder: thin,
  );
  final centered = text?.centered ?? false;
  final detailPt = text == null
      ? kXlsxDetailPt
      : _halfPt(kXlsxDetailPt * text.detailScale);
  final subjectPt = text == null
      ? kXlsxDetailPt
      : _halfPt(kXlsxSubjectPt * text.subjectScale);
  CellStyle cellStyle({int? fill, bool strike = false, bool italic = false}) =>
      CellStyle(
        backgroundColorHex: fill == null ? ExcelColor.none : _argb(fill),
        fontColorHex: fill != null && isDarkColor(fill)
            ? ExcelColor.white
            : ExcelColor.black,
        fontSize: text == null ? null : detailPt.round(),
        verticalAlign: centered ? VerticalAlign.Center : VerticalAlign.Top,
        horizontalAlign: centered
            ? HorizontalAlign.Center
            : HorizontalAlign.Left,
        textWrapping: TextWrapping.WrapText,
        italic: italic,
        leftBorder: thin,
        rightBorder: thin,
        topBorder: thin,
        bottomBorder: thin,
      );

  // ---- Grid sheet
  final rows = gridRows(t.grid, t.weekdays, t.lessons);
  CellIndex at(int col, int row) =>
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);

  grid.updateCell(at(0, 0), TextCellValue(t.title), cellStyle: headerStyle);
  for (var c = 0; c < t.weekdays.length; c++) {
    final d = t.weekdays[c];
    final label = t.regular
        ? weekdayName(d, t.locale)
        : '${weekdayName(d, t.locale)}\n${exportDateFormat('d MMM', t.locale).format(DateTime(t.weekStart.year, t.weekStart.month, t.weekStart.day + d - 1))}';
    grid.updateCell(at(c + 1, 0), TextCellValue(label), cellStyle: headerStyle);
  }
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    final label = [
      if (row.label.isNotEmpty) row.label,
      '${hhmmOf(row.start)}–${hhmmOf(row.end)}',
    ].join('\n');
    grid.updateCell(at(0, r + 1), TextCellValue(label), cellStyle: headerStyle);
  }

  // Needed height (pt) per grid row; a text line takes 1.5 × its font size.
  final rowHeights = List<double>.filled(rows.length, 0);
  final rich = <String, _RichCell>{};
  for (var c = 0; c < t.weekdays.length; c++) {
    final d = t.weekdays[c];
    final col = c + 1;
    final holiday = t.holidays[d];
    if (holiday != null && rows.isNotEmpty) {
      grid.updateCell(
        at(col, 1),
        TextCellValue(holiday),
        cellStyle: cellStyle(fill: colors ? 0xFFF0F0F0 : null, italic: true),
      );
      for (var r = 2; r <= rows.length; r++) {
        grid.updateCell(
          at(col, r),
          null,
          cellStyle: cellStyle(fill: colors ? 0xFFF0F0F0 : null),
        );
      }
      if (rows.length > 1) grid.merge(at(col, 1), at(col, rows.length));
      continue;
    }
    final dayLessons = [
      for (final l in t.lessons)
        if (l.weekday == d) l,
    ];
    // Lessons per row, then merge runs of rows holding the same lessons.
    final perRow = [
      for (final row in rows)
        [
          for (final l in dayLessons)
            if (row.overlaps(l.start, l.end)) l,
        ],
    ];
    var r = 0;
    while (r < rows.length) {
      final here = perRow[r];
      var end = r;
      while (here.isNotEmpty &&
          end + 1 < rows.length &&
          _sameLessons(perRow[end + 1], here)) {
        end++;
      }
      final runs = <_Run>[];
      var needed = 0.0;
      for (final l in here) {
        final lines = cellLines(l, showClasses: t.showClasses);
        if (runs.isNotEmpty) {
          runs.add(const _Run('\n\n', subject: false));
          needed += detailPt * 1.5; // the blank line
        }
        runs.add(_Run(lines.first, subject: true));
        needed += subjectPt * 1.5;
        if (lines.length > 1) {
          runs.add(_Run('\n${lines.skip(1).join('\n')}', subject: false));
          needed += (lines.length - 1) * detailPt * 1.5;
        }
      }
      final value = runs.map((r) => r.text).join();
      final first = here.isEmpty ? null : here.first;
      final fill = colors ? first?.color : null;
      final italic = first != null && first.status == LessonStatus.cancelled;
      final style = cellStyle(fill: fill, italic: italic);
      grid.updateCell(
        at(col, r + 1),
        here.isEmpty ? null : TextCellValue(value),
        cellStyle: style,
      );
      if (text != null && here.isNotEmpty) {
        rich[at(col, r + 1).cellId] = _RichCell(
          runs,
          fill: fill,
          italic: italic,
        );
      }
      for (var k = r + 1; k <= end; k++) {
        grid.updateCell(at(col, k + 1), null, cellStyle: style);
      }
      if (end > r) grid.merge(at(col, r + 1), at(col, end + 1));
      // Spread the needed height over the merged rows.
      final share = needed / (end - r + 1);
      for (var k = r; k <= end; k++) {
        rowHeights[k] = math.max(rowHeights[k], share);
      }
      r = end + 1;
    }
  }
  // Wider columns for larger text, so lines wrap about as often as usual.
  final widen = text == null
      ? 1.0
      : math.max(
          1.0,
          math.max(subjectPt / kXlsxSubjectPt, detailPt / kXlsxDetailPt),
        );
  grid.setColumnWidth(0, 14);
  for (var c = 0; c < t.weekdays.length; c++) {
    grid.setColumnWidth(c + 1, (24 * widen).roundToDouble());
  }
  grid.setRowHeight(0, 32);
  for (var r = 0; r < rows.length; r++) {
    // Ceil to whole legacy lines (15 pt) to keep the old row heights.
    grid.setRowHeight(
      r + 1,
      math.max(30, (rowHeights[r] / 15 - 1e-9).ceil() * 15.0),
    );
  }

  // ---- Lessons sheet
  final table = lessonTable(t);
  for (var r = 0; r < table.length; r++) {
    for (var c = 0; c < table[r].length; c++) {
      lessons.updateCell(
        at(c, r),
        TextCellValue(table[r][c]),
        cellStyle: r == 0 ? headerStyle : null,
      );
    }
  }
  final widths = <int, int>{};
  for (final row in table) {
    for (var c = 0; c < row.length; c++) {
      widths[c] = math.max(widths[c] ?? 0, row[c].length);
    }
  }
  widths.forEach(
    (c, w) => lessons.setColumnWidth(c, (w + 2).clamp(6, 50).toDouble()),
  );

  var bytes = Uint8List.fromList(excel.encode()!);
  if (rich.isNotEmpty) {
    bytes = _richGridCells(
      bytes,
      rich,
      subjectPt: subjectPt,
      detailPt: detailPt,
      boldSubject: text!.boldSubject,
    );
  }
  return freezeFirstRowAndColumn(bytes);
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _ptVal(double pt) =>
    pt == pt.roundToDouble() ? pt.toInt().toString() : pt.toString();

/// Path of the worksheet XML of [sheet] (via workbook.xml and its rels).
String? worksheetPath(Uint8List xlsx, String sheet) {
  final wb = readZipText(xlsx, 'xl/workbook.xml');
  final rels = readZipText(xlsx, 'xl/_rels/workbook.xml.rels');
  if (wb == null || rels == null) return null;
  String? attr(String tag, String name) =>
      RegExp('\\b$name="([^"]*)"').firstMatch(tag)?.group(1);
  String? rid;
  for (final m in RegExp(r'<sheet\b[^>]*>').allMatches(wb)) {
    if (attr(m[0]!, 'name') == _xmlEscape(sheet)) rid = attr(m[0]!, 'r:id');
  }
  if (rid == null) return null;
  for (final m in RegExp(r'<Relationship\b[^>]*>').allMatches(rels)) {
    if (attr(m[0]!, 'Id') != rid) continue;
    final target = attr(m[0]!, 'Target');
    if (target == null) return null;
    return target.startsWith('/') ? target.substring(1) : 'xl/$target';
  }
  return null;
}

/// Replaces the shared-string lesson cells of the grid sheet with inline
/// rich text (the excel package can't write rich text): the subject run gets
/// its own size and weight. Font color and italics are repeated per run,
/// since run properties replace the cell font.
Uint8List _richGridCells(
  Uint8List xlsx,
  Map<String, _RichCell> cells, {
  required double subjectPt,
  required double detailPt,
  required bool boldSubject,
}) {
  final path = worksheetPath(xlsx, kGridSheet);
  if (path == null) return xlsx;
  String runs(_RichCell cell) {
    final color = cell.fill != null && isDarkColor(cell.fill!)
        ? 'FFFFFFFF'
        : 'FF000000';
    final b = StringBuffer();
    for (final r in cell.runs) {
      if (r.text.isEmpty) continue;
      b
        ..write('<r><rPr><rFont val="$kXlsxFontName"/>')
        ..write(r.subject && boldSubject ? '<b/>' : '')
        ..write(cell.italic ? '<i/>' : '')
        ..write('<color rgb="$color"/>')
        ..write('<sz val="${_ptVal(r.subject ? subjectPt : detailPt)}"/>')
        ..write('</rPr><t xml:space="preserve">${_xmlEscape(r.text)}</t></r>');
    }
    return b.toString();
  }

  final cellRe = RegExp(
    r'<c r="([A-Z]+[0-9]+)"([^>]*?)(/>|>.*?</c>)',
    dotAll: true,
  );
  return patchZipText(xlsx, (n) => n == path, (_, xml) {
    return xml.replaceAllMapped(cellRe, (m) {
      final cell = cells[m[1]];
      if (cell == null) return m[0]!;
      final attrs = m[2]!.replaceAll(RegExp(r'\s+t="[^"]*"'), '');
      return '<c r="${m[1]}"$attrs t="inlineStr"><is>${runs(cell)}</is></c>';
    });
  });
}

bool _sameLessons(List<ExportLesson> a, List<ExportLesson> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) identical(a[i], b[i])].every((x) => x);

/// Freezes the header row and first column of every worksheet.
Uint8List freezeFirstRowAndColumn(Uint8List xlsx) => patchZipText(
  xlsx,
  (name) => name.startsWith('xl/worksheets/') && name.endsWith('.xml'),
  (_, xml) {
    if (xml.contains('<pane ')) return xml;
    const pane =
        '<pane xSplit="1" ySplit="1" topLeftCell="B2" activePane="bottomRight" state="frozen"/>'
        '<selection pane="topRight"/><selection pane="bottomLeft"/>'
        '<selection pane="bottomRight" activeCell="B2" sqref="B2"/>';
    final selfClosing = RegExp(r'<sheetView\b([^>]*?)/>');
    if (selfClosing.hasMatch(xml)) {
      return xml.replaceFirstMapped(
        selfClosing,
        (m) => '<sheetView${m[1]}>$pane</sheetView>',
      );
    }
    final open = RegExp(r'<sheetView\b([^>]*)>');
    return xml.replaceFirstMapped(open, (m) => '${m[0]}$pane');
  },
);
