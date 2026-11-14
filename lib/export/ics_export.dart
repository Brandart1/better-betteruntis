/// iCalendar (.ics, RFC 5545) export.
///
/// A week export becomes one event per lesson (cancelled lessons with
/// `STATUS:CANCELLED`) plus all-day events for holidays. A regular export
/// becomes weekly repeating events from the reference week until
/// [ExportTimetable.repeatUntil], skipping [ExportTimetable.skipDays]
/// (holidays) with `EXDATE`.
///
/// Times are "floating" local times (no time zone): calendar apps show them
/// at the same wall-clock time as the timetable.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'export_model.dart';

/// RFC 5545 TEXT escaping.
String icsText(String v) => v
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll(RegExp(r'\r\n|\r|\n'), r'\n');

/// Folds [line] into chunks of at most 75 octets (UTF-8), never splitting a
/// character; continuation lines start with a space.
String icsFold(String line) {
  final out = StringBuffer();
  var octets = 0;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final n = utf8.encode(ch).length;
    if (octets + n > 75) {
      out.write('\r\n ');
      octets = 1;
    }
    out.write(ch);
    octets += n;
  }
  return out.toString();
}

String _pad(int v) => v.toString().padLeft(2, '0');

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${_pad(d.month)}${_pad(d.day)}';

String _local(DateTime day, int minutes) =>
    '${_date(day)}T${_pad(minutes ~/ 60)}${_pad(minutes % 60)}00';

String _utc(DateTime t) {
  final u = t.toUtc();
  return '${_date(u)}T${_pad(u.hour)}${_pad(u.minute)}${_pad(u.second)}Z';
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String _slug(String v) => v
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// Event title: subject (long name if known), with the classes when
/// [showClasses] (teacher/room timetables), prefixed for cancelled lessons
/// and exams.
String lessonEventTitle(ExportLesson l, {bool showClasses = false}) {
  var s = l.subjectLong.isNotEmpty
      ? l.subjectLong
      : (l.subject.isNotEmpty ? l.subject : 'Lesson');
  if (showClasses && l.classes.isNotEmpty) s += ' – ${l.classes.join(', ')}';
  return switch (l.status) {
    LessonStatus.cancelled => 'Cancelled: $s',
    LessonStatus.exam => 'Exam: $s',
    _ => s,
  };
}

String icsSummary(ExportTimetable t, ExportLesson l) =>
    lessonEventTitle(l, showClasses: t.showClasses);

/// Event details: lesson numbers, teachers, classes, substitution, notes.
String lessonEventDescription(ExportLesson l) => [
  if (l.lessonNumbers.isNotEmpty) 'Lesson ${l.lessonNumbers}',
  if (l.subject.isNotEmpty && l.subject != l.subjectLong)
    'Subject: ${l.subject}',
  if (l.teachers.isNotEmpty) 'Teachers: ${l.teachers.join(', ')}',
  if (l.classes.isNotEmpty) 'Classes: ${l.classes.join(', ')}',
  if (l.status == LessonStatus.substitution) 'Substitution',
  if (l.replaced.isNotEmpty) 'Instead of: ${l.replaced.join(', ')}',
  if (l.info.isNotEmpty) l.info,
].join('\n');

/// The .ics text (CRLF line endings).
String icsString(ExportTimetable t) {
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//better-betteruntis//Timetable export//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:${icsText(t.title)}',
  ];
  final stamp = _utc(t.exportedAt);
  final name = _slug(t.elementName);
  final until = t.repeatUntil;

  for (final (i, l) in t.lessons.indexed) {
    // Regular: the first occurrence is that weekday of the reference week.
    final day = t.regular
        ? _day(t.weekStart.add(Duration(days: l.weekday - 1)))
        : _day(l.date);
    if (t.regular && until != null && day.isAfter(until)) continue;
    lines
      ..add('BEGIN:VEVENT')
      ..add(
        'UID:${t.regular ? 'regular' : _date(day)}-${l.weekday}-${l.start}-'
        '$i-$name@better-betteruntis',
      )
      ..add('DTSTAMP:$stamp')
      ..add('DTSTART:${_local(day, l.start)}')
      ..add('DTEND:${_local(day, l.end)}')
      ..add('SUMMARY:${icsText(icsSummary(t, l))}');
    if (l.rooms.isNotEmpty) {
      lines.add('LOCATION:${icsText(l.rooms.join(', '))}');
    }
    final desc = lessonEventDescription(l);
    if (desc.isNotEmpty) lines.add('DESCRIPTION:${icsText(desc)}');
    if (l.status == LessonStatus.cancelled) lines.add('STATUS:CANCELLED');
    if (t.regular) {
      lines.add(
        until == null
            ? 'RRULE:FREQ=WEEKLY'
            : 'RRULE:FREQ=WEEKLY;UNTIL=${_date(until)}T235959',
      );
      final skipped = [
        for (final d in t.skipDays)
          if (d.weekday == l.weekday && !d.isBefore(day)) _local(d, l.start),
      ];
      if (skipped.isNotEmpty) lines.add('EXDATE:${skipped.join(',')}');
    }
    lines.add('END:VEVENT');
  }

  // Week export: holidays as all-day events.
  if (!t.regular) {
    for (final MapEntry(key: weekday, value: holiday) in t.holidays.entries) {
      final day = _day(t.weekStart.add(Duration(days: weekday - 1)));
      final next = DateTime(day.year, day.month, day.day + 1);
      lines.addAll([
        'BEGIN:VEVENT',
        'UID:holiday-${_date(day)}-$name@better-betteruntis',
        'DTSTAMP:$stamp',
        'DTSTART;VALUE=DATE:${_date(day)}',
        'DTEND;VALUE=DATE:${_date(next)}',
        'SUMMARY:${icsText(holiday)}',
        'TRANSP:TRANSPARENT',
        'END:VEVENT',
      ]);
    }
  }

  lines.add('END:VCALENDAR');
  return '${lines.map(icsFold).join('\r\n')}\r\n';
}

Uint8List buildIcs(ExportTimetable t) =>
    Uint8List.fromList(utf8.encode(icsString(t)));
