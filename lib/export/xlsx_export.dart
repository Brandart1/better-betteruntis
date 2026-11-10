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

Uint8List buildXlsx(ExportTimetable t, {bool colors = true}) {
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
  CellStyle cellStyle({int? fill, bool strike = false, bool italic = false}) =>
      CellStyle(
        backgroundColorHex: fill == null ? ExcelColor.none : _argb(fill),
        fontColorHex: fill != null && isDarkColor(fill)
            ? ExcelColor.white
            : ExcelColor.black,
        verticalAlign: VerticalAlign.Top,
        horizontalAlign: HorizontalAlign.Left,
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

  final rowLines = List<int>.filled(rows.length, 1);
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
      final text = [
        for (final l in here)
          cellLines(l, showClasses: t.showClasses).join('\n'),
      ].join('\n\n');
      final lines = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
      final first = here.isEmpty ? null : here.first;
      final style = cellStyle(
        fill: colors ? first?.color : null,
        italic: first != null && first.status == LessonStatus.cancelled,
      );
      grid.updateCell(
        at(col, r + 1),
        here.isEmpty ? null : TextCellValue(text),
        cellStyle: style,
      );
      for (var k = r + 1; k <= end; k++) {
        grid.updateCell(at(col, k + 1), null, cellStyle: style);
      }
      if (end > r) grid.merge(at(col, r + 1), at(col, end + 1));
      // Spread the needed height over the merged rows.
      final perRowLines = (lines / (end - r + 1)).ceil();
      for (var k = r; k <= end; k++) {
        rowLines[k] = math.max(rowLines[k], perRowLines);
      }
      r = end + 1;
    }
  }
  grid.setColumnWidth(0, 14);
  for (var c = 0; c < t.weekdays.length; c++) {
    grid.setColumnWidth(c + 1, 24);
  }
  grid.setRowHeight(0, 32);
  for (var r = 0; r < rows.length; r++) {
    grid.setRowHeight(r + 1, math.max(30, rowLines[r] * 15.0));
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

  final bytes = Uint8List.fromList(excel.encode()!);
  return freezeFirstRowAndColumn(bytes);
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
