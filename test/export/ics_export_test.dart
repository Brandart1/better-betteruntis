import 'dart:convert';

import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/export/export_model.dart';
import 'package:better_betteruntis/export/ics_export.dart';
import 'package:better_betteruntis/ui/export/export_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'export_test_helpers.dart';

/// Unfolds RFC 5545 continuation lines.
List<String> unfold(String ics) =>
    ics.replaceAll('\r\n ', '').split('\r\n')..removeLast();

List<List<String>> events(String ics) {
  final out = <List<String>>[];
  List<String>? cur;
  for (final l in unfold(ics)) {
    if (l == 'BEGIN:VEVENT') {
      cur = [];
    } else if (l == 'END:VEVENT') {
      out.add(cur!);
      cur = null;
    } else {
      cur?.add(l);
    }
  }
  return out;
}

String? prop(List<String> event, String name) {
  for (final l in event) {
    if (l.startsWith('$name:') || l.startsWith('$name;')) {
      return l.substring(l.indexOf(':') + 1);
    }
  }
  return null;
}

void main() {
  const target = TimetableTarget(ElementType.klasse, DemoIds.klasse);

  Future<ExportTimetable> prepare(ExportKind kind, {FakeNameResolver? names}) {
    final n = names ?? FakeNameResolver();
    return prepareExport(
      repo: FakeTimetableRepository(names: n),
      names: n,
      account: demoAccount(),
      target: target,
      elementName: '10a',
      options: ExportOptions(
        kind: kind,
        weekStart: mon,
        format: ExportFormat.ics,
      ),
      now: DateTime.utc(2026, 11, 10, 12),
    );
  }

  test('escaping and folding', () {
    expect(
      icsText(
        r'a,b;c\d'
        '\nx',
      ),
      r'a\,b\;c\\d\nx',
    );
    final long = 'SUMMARY:${'ä' * 60}';
    final folded = icsFold(long);
    for (final line in folded.split('\r\n')) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(75));
    }
    expect(folded.replaceAll('\r\n ', ''), long);
  });

  test('week export: one event per lesson, cancelled marked', () async {
    final t = await prepare(ExportKind.week);
    final ics = icsString(t);
    expect(ics, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    final ev = events(ics);
    expect(ev, hasLength(t.lessons.length));
    final first = t.lessons.first;
    final e0 = ev.first;
    expect(
      prop(e0, 'DTSTART'),
      '20261109T${hhmmOf(first.start).replaceAll(':', '')}00',
    );
    expect(prop(e0, 'DTSTAMP'), '20261110T120000Z');
    expect(prop(e0, 'RRULE'), isNull);
    expect(e0.any((l) => l.startsWith('UID:')), isTrue);
    final uids = {for (final e in ev) prop(e, 'UID')};
    expect(uids, hasLength(ev.length));

    final cancelled = t.lessons.indexWhere(
      (l) => l.status == LessonStatus.cancelled,
    );
    expect(cancelled, isNot(-1));
    expect(prop(ev[cancelled], 'STATUS'), 'CANCELLED');
    expect(prop(ev[cancelled], 'SUMMARY'), startsWith('Cancelled: '));
  });

  test('week export: holidays become all-day events', () async {
    final names = FakeNameResolver(
      holidays: [
        Holiday(
          id: 1,
          name: 'Leopold',
          longName: 'Leopolditag',
          start: DateTime(2026, 11, 13),
          end: DateTime(2026, 11, 13),
        ),
      ],
    );
    final ics = icsString(await prepare(ExportKind.week, names: names));
    final holiday = events(ics)
        .firstWhere((e) => prop(e, 'SUMMARY') == 'Leopolditag');
    expect(prop(holiday, 'DTSTART'), '20261113');
    expect(prop(holiday, 'DTEND'), '20261114');
  });

  test('regular export repeats weekly until the school year ends, '
      'skipping holidays', () async {
    final names = FakeNameResolver(
      schoolYears: [
        SchoolYear(
          id: 1,
          name: '2026/2027',
          start: DateTime(2026, 9, 7),
          end: DateTime(2027, 7, 2),
        ),
      ],
      holidays: [
        Holiday(
          id: 1,
          name: 'Weihnachten',
          longName: 'Weihnachtsferien',
          start: DateTime(2026, 12, 24),
          end: DateTime(2027, 1, 6),
        ),
      ],
    );
    final t = await prepare(ExportKind.regular, names: names);
    expect(t.repeatUntil, DateTime(2027, 7, 2));
    final ev = events(icsString(t));
    expect(ev, hasLength(t.lessons.length));
    for (final e in ev) {
      expect(prop(e, 'RRULE'), 'FREQ=WEEKLY;UNTIL=20270702T235959');
      expect(prop(e, 'STATUS'), isNull);
    }
    // A Thursday lesson skips 24 and 31 Dec.
    final i = t.lessons.indexWhere((l) => l.weekday == 4);
    final start = hhmmOf(t.lessons[i].start).replaceAll(':', '');
    expect(prop(ev[i], 'DTSTART'), '20261112T${start}00');
    expect(prop(ev[i], 'EXDATE'), '20261224T${start}00,20261231T${start}00');
  });

  test('school year end falls back to 31 July', () {
    expect(
      schoolYearEnd(const [], DateTime(2026, 11, 9)),
      DateTime(2027, 7, 31),
    );
    expect(
      schoolYearEnd(const [], DateTime(2027, 3, 1)),
      DateTime(2027, 7, 31),
    );
  });
}
