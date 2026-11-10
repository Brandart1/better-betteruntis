/// CSV export: one row per lesson, RFC 4180 quoting, UTF-8 with BOM.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import 'export_model.dart';

/// `;` for locales that write decimals with a comma (de, at, fr, …) — Excel
/// there expects it — otherwise `,`.
String defaultCsvSeparator(String? localeTag) {
  if (localeTag == null || localeTag.isEmpty) return ',';
  try {
    final f = NumberFormat.decimalPattern(localeTag.replaceAll('-', '_'));
    return f.symbols.DECIMAL_SEP == ',' ? ';' : ',';
  } catch (_) {
    return ',';
  }
}

/// Header + rows shared by the CSV and the XLSX "Lessons" sheet.
List<List<String>> lessonTable(ExportTimetable t) {
  final regular = t.regular;
  final header = [
    if (!regular) 'Date',
    'Day',
    'Start',
    'End',
    'Lesson',
    'Subject',
    'Subject (long)',
    'Teachers',
    'Rooms',
    'Classes',
    if (!regular) 'Status',
    'Info',
  ];
  final date = DateFormat('yyyy-MM-dd');
  final rows = [
    for (final l in t.lessons)
      [
        if (!regular) date.format(l.date),
        weekdayName(l.weekday, t.locale),
        hhmmOf(l.start),
        hhmmOf(l.end),
        l.lessonNumbers,
        l.subject,
        l.subjectLong,
        l.teachers.join(', '),
        l.rooms.join(', '),
        l.classes.join(', '),
        if (!regular) l.status.label,
        l.info,
      ],
  ];
  return [header, ...rows];
}

/// RFC 4180 field quoting.
String csvField(String v, String separator) {
  final needs =
      v.contains(separator) ||
      v.contains('"') ||
      v.contains('\n') ||
      v.contains('\r') ||
      v.startsWith(' ') ||
      v.endsWith(' ');
  return needs ? '"${v.replaceAll('"', '""')}"' : v;
}

String csvString(List<List<String>> rows, {String separator = ','}) {
  final b = StringBuffer();
  for (final r in rows) {
    b
      ..write(r.map((f) => csvField(f, separator)).join(separator))
      ..write('\r\n');
  }
  return b.toString();
}

/// UTF-8 bytes with BOM, CRLF line endings.
Uint8List buildCsv(ExportTimetable t, {String separator = ','}) {
  final body = utf8.encode(csvString(lessonTable(t), separator: separator));
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...body]);
}
