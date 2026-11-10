import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/settings.dart';
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
  ExportPalette palette = const ExportPalette(),
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
      palette: palette,
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

    test('border mode: thick state-colored cell border, base fill', () {
      String styles(ExportPalette palette) => readZipText(
        buildXlsx(demoExport(palette: palette)),
        'xl/styles.xml',
      )!;
      expect(styles(const ExportPalette()), contains('thick'));
      const allFill = ExportPalette(substitutionMode: StateColorMode.fill);
      expect(styles(allFill), isNot(contains('thick')));
      final exam = styles(
        const ExportPalette(
          substitutionMode: StateColorMode.fill,
          examMode: StateColorMode.border,
          exam: 0xFF7B1FA2,
        ),
      );
      expect(exam, contains('thick'));
      expect(exam, contains('FF7B1FA2'));
      // The excel package still reads it.
      expect(
        () => Excel.decodeBytes(buildXlsx(demoExport(palette: allFill))),
        returnsNormally,
      );
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

    group('text style', () {
      String gridXml(Uint8List bytes) =>
          readZipText(bytes, worksheetPath(bytes, kGridSheet)!)!;
      String stylesXml(Uint8List bytes) => readZipText(bytes, 'xl/styles.xml')!;
      String? cellXml(String xml, String ref) => RegExp(
        '<c r="$ref"[^>]*?(/>|>.*?</c>)',
        dotAll: true,
      ).firstMatch(xml)?[0];

      /// The cell format (`<xf>…</xf>`) and font (`<font>…</font>`) of [ref]
      /// in the grid sheet.
      (String, String) styleOf(Uint8List bytes, String ref) {
        final styles = stylesXml(bytes);
        final s = int.parse(
          RegExp(r'\bs="([0-9]+)"')
              .firstMatch(cellXml(gridXml(bytes), ref)!)![1]!,
        );
        String nth(String list, String tag, int n) =>
            RegExp('<$tag\\b[^>]*?(/>|>.*?</$tag>)')
                .allMatches(
                  RegExp('<$list\\b.*?</$list>').firstMatch(styles)![0]!,
                )
                .elementAt(n)[0]!;
        final xf = nth('cellXfs', 'xf', s);
        final font = int.parse(
          RegExp(r'fontId="([0-9]+)"').firstMatch(xf)![1]!,
        );
        return (xf, nth('fonts', 'font', font));
      }

      test('built-in look without a text style', () {
        final bytes = buildXlsx(demoExport());
        final xml = gridXml(bytes);
        expect(xml, isNot(contains('inlineStr')));
        final (xf, font) = styleOf(bytes, 'B2');
        expect(xf, isNot(contains('horizontal=')));
        expect(xf, contains('vertical="top"'));
        expect(font, isNot(contains('<sz')));
      });

      test('centered, sized and bold subject runs', () {
        final t = demoExport();
        final bytes = buildXlsx(
          t,
          text: const ExportTextStyle(
            centered: true,
            subjectSize: 22,
            detailSize: 18,
          ),
        );
        expect(worksheetPath(bytes, kGridSheet), 'xl/worksheets/sheet1.xml');
        final xml = gridXml(bytes);
        final b2 = cellXml(xml, 'B2')!;
        expect(b2, contains('t="inlineStr"'));
        expect(b2, isNot(contains('t="s"')));
        // Subject: 12 pt × 22/15 → 17.5 pt, bold; details 10 × 1.5 = 15 pt.
        expect(
          b2,
          contains(
            '<b/><color rgb="FF000000"/><sz val="17.5"/></rPr>'
            '<t xml:space="preserve">M</t>',
          ),
        );
        expect(
          b2,
          contains(
            '<sz val="15"/></rPr><t xml:space="preserve">\nMUE\nR101</t>',
          ),
        );
        // Header and time cells stay shared strings.
        expect(cellXml(xml, 'A2'), contains('t="s"'));
        // Cell font size and centered alignment end up in styles.xml.
        final (xf, font) = styleOf(bytes, 'B2');
        expect(xf, contains('horizontal="center"'));
        expect(xf, contains('vertical="center"'));
        expect(font, contains('<sz val="15"/>'));
        // Larger text: wider day columns, taller rows.
        expect(xml, contains('<col min="2" max="2" width="36.00"'));
        final plain = gridXml(buildXlsx(t));
        double rowHeight(String x) => double.parse(
          RegExp(r'<row r="2" ht="([0-9.]+)"').firstMatch(x)![1]!,
        );
        expect(rowHeight(xml), greaterThan(rowHeight(plain)));
        // Still a valid workbook; the frozen pane is still added.
        expect(() => Excel.decodeBytes(bytes), returnsNormally);
        expect(xml, contains('state="frozen"'));
      });

      test('left aligned, regular weight, small text', () {
        final bytes = buildXlsx(
          demoExport(),
          text: const ExportTextStyle(
            centered: false,
            subjectSize: 11,
            detailSize: 9,
            boldSubject: false,
          ),
        );
        final b2 = cellXml(gridXml(bytes), 'B2')!;
        expect(b2, isNot(contains('<b/>')));
        // 12 × 11/15 = 8.8 → 9; 10 × 0.75 = 7.5.
        expect(b2, contains('<sz val="9"/>'));
        expect(b2, contains('<sz val="7.5"/>'));
        final (xf, _) = styleOf(bytes, 'B2');
        expect(xf, isNot(contains('horizontal=')));
        expect(xf, contains('vertical="top"'));
      });

      test('cancelled lessons keep italics in rich runs', () {
        final t = demoExport();
        final bytes = buildXlsx(t, text: const ExportTextStyle());
        // C6: Tuesday unit 5, cancelled chemistry (see round trip test).
        final c6 = cellXml(gridXml(bytes), 'C6')!;
        expect(c6, contains('<i/>'));
        expect(c6, contains('Cancelled'));
      });
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

    test('border mode for every state renders', () async {
      final t = demoExport(
        palette: const ExportPalette(
          examMode: StateColorMode.border,
          cancelledMode: StateColorMode.border,
          subjectColors: {'M': 0xFF1976D2},
        ),
      );
      expect(t.lessons.where((l) => l.borderColor != null), isNotEmpty);
      final bytes = await buildPdf(t, fonts: testFonts());
      expect(isPdf(bytes), isTrue);
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

    test('text style: large, centered and small sizes', () async {
      for (final text in const [
        ExportTextStyle(subjectSize: 22, detailSize: 18),
        ExportTextStyle(centered: false, boldSubject: false),
        ExportTextStyle(subjectSize: 1, detailSize: 1000),
        ExportTextStyle(subjectSize: double.nan, detailSize: 0),
      ]) {
        final bytes = await buildPdf(
          demoExport(),
          options: PdfExportOptions(text: text),
          fonts: testFonts(),
        );
        expect(isPdf(bytes), isTrue);
        final pages = RegExp(r'/Type\s*/Page\b')
            .allMatches(latin1.decode(bytes));
        expect(pages, hasLength(1));
      }
      // Dense portrait page with the largest sizes, Latin-1 fallback.
      final bytes = await buildPdf(
        demoExport(kind: ExportKind.regular),
        options: const PdfExportOptions(
          landscape: false,
          text: ExportTextStyle(subjectSize: 22, detailSize: 18),
        ),
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
