import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/export/csv_export.dart';
import 'package:better_betteruntis/export/export_model.dart';
import 'package:better_betteruntis/export/pdf_export.dart';
import 'package:better_betteruntis/export/pdf_fonts.dart';
import 'package:better_betteruntis/export/xlsx_export.dart';
import 'package:better_betteruntis/export/zip_patch.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'export_test_helpers.dart';

ExportTimetable demoExport({
  ExportKind kind = ExportKind.week,
  List<Period>? periods,
  Map<int, String> holidays = const {},
}) {
  final names = FakeNameResolver();
  return ExportTimetable(
    kind: kind,
    elementName: '10a',
    schoolName: 'Demo-Gymnasium Süd',
    periodLabel: kind == ExportKind.regular
        ? 'Regular timetable'
        : '9 – 13 Nov 2026',
    weekStart: mon,
    grid: demoTimeGrid,
    weekdays: const [1, 2, 3, 4, 5],
    lessons: buildExportLessons(
      periods ?? buildDemoWeek(mon),
      names,
      regular: kind == ExportKind.regular,
    ),
    exportedAt: DateTime(2026, 11, 10, 12),
    holidays: holidays,
  );
}

PdfFonts testFonts() {
  ByteData load(String p) => ByteData.sublistView(File(p).readAsBytesSync());
  return PdfFonts(
    pw.Font.ttf(load(kPdfFontRegular)),
    pw.Font.ttf(load(kPdfFontBold)),
  );
}

void main() {
  group('CSV', () {
    test('field quoting (RFC 4180)', () {
      expect(csvField('plain', ','), 'plain');
      expect(csvField('a,b', ','), '"a,b"');
      expect(csvField('a,b', ';'), 'a,b');
      expect(csvField('a;b', ';'), '"a;b"');
      expect(csvField('say "hi"', ','), '"say ""hi"""');
      expect(csvField('two\nlines', ','), '"two\nlines"');
      expect(
        csvString([
          ['a', 'b'],
          ['1', 'x,y'],
        ]),
        'a,b\r\n1,"x,y"\r\n',
      );
    });

    test('BOM, UTF-8, header and rows', () {
      final bytes = buildCsv(demoExport(), separator: ';');
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      final text = utf8.decode(bytes.sublist(3));
      final lines = text.split('\r\n');
      expect(
        lines.first,
        'Date;Day;Start;End;Lesson;Subject;Subject (long);Teachers;Rooms;'
        'Classes;Status;Info',
      );
      expect(
        lines[1],
        '2026-11-09;Monday;07:45;09:20;1–2;M;Mathematik;MUE (Anna Müller);'
        'R101;10a;Regular;',
      );
      expect(text, contains('Cancelled;Entfall'));
      expect(text, contains('Substitution;Vertretung'));
      expect(text, contains('Exam;'));
    });

    test('regular export has no date/status columns', () {
      final text = utf8.decode(
        buildCsv(demoExport(kind: ExportKind.regular)).sublist(3),
      );
      expect(
        text.split('\r\n').first,
        'Day,Start,End,Lesson,Subject,Subject (long),Teachers,Rooms,Classes,'
        'Info',
      );
      // "MUE (Anna Müller)" has no comma -> unquoted; info with comma quoted.
      expect(text, contains('Monday,07:45,09:20,1–2,M,Mathematik,'));
    });

    test('default separator follows the decimal separator', () {
      expect(defaultCsvSeparator('de-DE'), ';');
      expect(defaultCsvSeparator('de_AT'), ';');
      expect(defaultCsvSeparator('en-US'), ',');
      expect(defaultCsvSeparator(null), ',');
      expect(defaultCsvSeparator('xx-invalid'), ',');
    });
  });

  group('XLSX', () {
    test('round trip: grid cells and lessons sheet', () {
      final t = demoExport(holidays: const {});
      final bytes = buildXlsx(t);
      final excel = Excel.decodeBytes(bytes);
      expect(excel.tables.keys, containsAll([kGridSheet, kLessonsSheet]));
      expect(excel.tables.keys, hasLength(2));

      final grid = excel.tables[kGridSheet]!;
      String cell(int c, int r) =>
          grid
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
              .value
              ?.toString() ??
          '';
      expect(cell(1, 0), startsWith('Monday'));
      expect(cell(0, 1), '1\n07:45–08:30');
      expect(cell(1, 1), 'M\nMUE\nR101');
      // Double lesson merged over rows 1-2.
      expect(grid.spannedItems, contains('B2:B3'));
      expect(cell(2, 5), contains('Cancelled'));
      expect(cell(2, 4), 'E\nFIS\nR102\nSubstitution (was WEB)');

      final lessons = excel.tables[kLessonsSheet]!;
      final rows = lessons.rows
          .map((r) => r.map((c) => c?.value?.toString() ?? '').toList())
          .toList();
      expect(rows.first.first, 'Date');
      expect(rows.length, t.lessons.length + 1);
      expect(rows[1].take(6), [
        '2026-11-09',
        'Monday',
        '07:45',
        '09:20',
        '1–2',
        'M',
      ]);
    });

    test('header row/column are frozen', () {
      final bytes = buildXlsx(demoExport());
      // Still a readable workbook after patching.
      expect(() => Excel.decodeBytes(bytes), returnsNormally);
      final sheets = <String>[];
      patchZipText(bytes, (n) => n.startsWith('xl/worksheets/sheet'), (n, x) {
        sheets.add(x);
        return x;
      });
      expect(sheets, hasLength(2));
      for (final x in sheets) {
        expect(x, contains('<pane xSplit="1" ySplit="1"'));
        expect(x, contains('state="frozen"'));
      }
    });

    test('holiday column', () {
      final t = demoExport(
        periods: buildDemoWeek(mon, holidayFriday: true),
        holidays: const {5: 'Pädagogischer Tag'},
      );
      final excel = Excel.decodeBytes(buildXlsx(t));
      final grid = excel.tables[kGridSheet]!;
      expect(
        grid
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 1))
            .value
            .toString(),
        'Pädagogischer Tag',
      );
    });
  });

  group('PDF', () {
    bool isPdf(Uint8List b) =>
        b.length > 1000 && latin1.decode(b.sublist(0, 5)) == '%PDF-';

    test('dense week with the bundled font (umlauts, en dash)', () async {
      // Dense: the demo week plus parallel lessons in every slot.
      final dense = [
        ...buildDemoWeek(mon),
        for (var d = 1; d <= 5; d++)
          for (var u in demoTimeGrid.days[1]!)
            period(
              mon,
              d,
              h: u.start ~/ 60,
              m: u.start % 60,
              minutes: u.end - u.start,
              lesson: 500 + d * 10 + u.start,
              subject: DemoIds.rel,
              teachers: [el(ElementType.teacher, DemoIds.bec)],
            ),
      ];
      final t = demoExport(periods: dense, holidays: const {});
      final bytes = await buildPdf(t, fonts: testFonts());
      expect(isPdf(bytes), isTrue);
      final text = latin1.decode(bytes);
      expect(RegExp(r'/Type\s*/Page\b').allMatches(text), hasLength(1));
    });

    test('grayscale, portrait, holiday', () async {
      final t = demoExport(
        periods: buildDemoWeek(mon, holidayFriday: true),
        holidays: const {5: 'Pädagogischer Tag'},
      );
      final bytes = await buildPdf(
        t,
        options: const PdfExportOptions(colors: false, landscape: false),
        fonts: testFonts(),
      );
      expect(isPdf(bytes), isTrue);
    });

    test('Latin-1 fallback without fonts', () async {
      expect(latin1Safe('9 – 13 Nov · Müller'), '9 - 13 Nov · Müller');
      expect(latin1Safe('… ✓'), '... ?');
      final bytes = await buildPdf(demoExport(kind: ExportKind.regular));
      expect(isPdf(bytes), isTrue);
    });
  });
}
