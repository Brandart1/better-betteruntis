/// Loads weeks, derives the exported timetable, generates the file and hands
/// it to the share sheet.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Rect;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../export/csv_export.dart';
import '../../export/export_model.dart';
import '../../export/pdf_export.dart';
import '../../export/pdf_fonts.dart';
import '../../export/regular_timetable.dart';
import '../../export/xlsx_export.dart';

/// Number of weeks sampled for the regular timetable.
const kRegularSampleWeeks = 4;

class ExportOptions {
  const ExportOptions({
    required this.kind,
    required this.weekStart,
    required this.format,
    this.colors = true,
    this.landscape = true,
    this.separator = ',',
  });

  final ExportKind kind;

  /// Monday of the specific week, or the first sampled week (regular).
  final DateTime weekStart;
  final ExportFormat format;
  final bool colors;
  final bool landscape;
  final String separator;
}

class ExportedFile {
  const ExportedFile(this.path, this.name, this.mimeType, this.bytes);
  final String path;
  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// Shares a written file. Injected so tests don't call the platform.
typedef ShareExportedFile = Future<void> Function(
  ExportedFile file, {
  Rect? origin,
  String? subject,
});

Future<void> shareWithSystem(
  ExportedFile file, {
  Rect? origin,
  String? subject,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: file.mimeType, name: file.name)],
      fileNameOverrides: [file.name],
      subject: subject,
      title: file.name,
      sharePositionOrigin: origin,
    ),
  );
}

final exportShareProvider = Provider<ShareExportedFile>((_) => shareWithSystem);

/// Directory the export is written to before sharing. Resolves to null where
/// there is no file system (web): the file is then only kept in memory.
final exportDirectoryProvider = Provider<Future<Directory?> Function()>(
  (_) => () async {
    final tmp = await getTemporaryDirectory();
    return Directory('${tmp.path}/exports').create(recursive: true);
  },
);

/// PDF font loader (bundled Noto Sans). Overridable for tests.
final exportFontsProvider = Provider<Future<PdfFonts?> Function()>(
  (_) => loadPdfFonts,
);

class ExportException implements Exception {
  const ExportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Loads one week cache-first: the first emission of [TimetableRepository.watchWeek]
/// (cached data, or fresh data once fetched).
Future<List<Period>> loadWeek(
  TimetableRepository repo,
  Account account,
  TimetableTarget target,
  DateTime weekStart, {
  Duration timeout = const Duration(seconds: 90),
}) => repo.watchWeek(account, target, weekStart).first.timeout(timeout);

DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Builds the [ExportTimetable] (loading weeks as needed).
Future<ExportTimetable> prepareExport({
  required TimetableRepository repo,
  required NameResolver names,
  required Account account,
  required TimetableTarget target,
  required String elementName,
  required ExportOptions options,
  ExportPalette palette = const ExportPalette(),
  bool includeCancelled = true,
  String? locale,
  DateTime? now,
  void Function(String message)? onProgress,
}) async {
  final grid = names.timeGrid;
  final ws = options.weekStart;
  final palOrNull = palette;

  final List<Period> periods;
  final Map<int, String> holidays = {};
  if (options.kind == ExportKind.week) {
    onProgress?.call('Loading week…');
    periods = await loadWeek(repo, account, target, ws);
    for (var d = 1; d <= 7; d++) {
      final day = _addDays(ws, d - 1);
      for (final h in names.holidays) {
        final s = DateTime(h.start.year, h.start.month, h.start.day);
        final e = DateTime(h.end.year, h.end.month, h.end.day);
        if (!day.isBefore(s) && !day.isAfter(e)) {
          holidays[d] = h.longName.isNotEmpty ? h.longName : h.name;
          break;
        }
      }
    }
  } else {
    final samples = <SampleWeek>[];
    Object? lastError;
    for (var i = 0; i < kRegularSampleWeeks; i++) {
      final w = _addDays(ws, 7 * i);
      onProgress?.call('Loading week ${i + 1} of $kRegularSampleWeeks…');
      try {
        samples.add(SampleWeek(w, await loadWeek(repo, account, target, w)));
      } catch (e) {
        lastError = e;
      }
    }
    if (samples.isEmpty) {
      throw lastError ?? const ExportException('Could not load the timetable');
    }
    onProgress?.call('Building regular timetable…');
    periods = deriveRegularTimetable(samples, holidays: names.holidays);
  }

  final regular = options.kind == ExportKind.regular;
  final lessons = buildExportLessons(
    periods,
    names,
    regular: regular,
    grid: grid,
    palette: palOrNull,
    includeCancelled: regular || includeCancelled,
  );
  if (lessons.isEmpty && holidays.isEmpty) {
    throw const ExportException('No lessons to export');
  }
  final weekdays = {1, 2, 3, 4, 5};
  for (final d in [6, 7]) {
    if ((grid.days[d]?.isNotEmpty ?? false) ||
        lessons.any((l) => l.weekday == d)) {
      weekdays.add(d);
    }
  }
  final days = weekdays.toList()..sort();
  holidays.removeWhere((d, _) => !weekdays.contains(d));
  final label = regular
      ? 'Regular timetable'
      : exportWeekRange(
          _addDays(ws, days.first - 1),
          _addDays(ws, days.last - 1),
          locale,
        );
  return ExportTimetable(
    kind: options.kind,
    elementName: elementName,
    schoolName: account.school.displayName,
    periodLabel: label,
    weekStart: ws,
    grid: grid,
    weekdays: days,
    lessons: lessons,
    exportedAt: now ?? DateTime.now(),
    holidays: holidays,
    locale: locale,
    targetType: target.type,
  );
}

/// Generates the file bytes for [t].
Future<Uint8List> generateExport(
  ExportTimetable t,
  ExportOptions options, {
  Future<PdfFonts?> Function()? fonts,
}) async => switch (options.format) {
  ExportFormat.csv => buildCsv(t, separator: options.separator),
  ExportFormat.xlsx => buildXlsx(t, colors: options.colors),
  ExportFormat.pdf => buildPdf(
    t,
    options: PdfExportOptions(
      colors: options.colors,
      landscape: options.landscape,
    ),
    fonts: await (fonts ?? loadPdfFonts)(),
  ),
};

Future<ExportedFile> writeExport(
  Directory? dir,
  ExportTimetable t,
  ExportOptions options,
  Uint8List bytes,
) async {
  final name = exportFileName(
    t.elementName,
    options.kind,
    options.weekStart,
    options.format,
  );
  if (dir == null) return ExportedFile('', name, options.format.mimeType, bytes);
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return ExportedFile(file.path, name, options.format.mimeType, bytes);
}
