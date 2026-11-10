import 'dart:convert';

import 'package:better_betteruntis/api/parsers.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

const masterDataJson = '''
{
  "timeStamp": 1731230000000,
  "klassen": [
    {"id": 10, "name": "5a", "longName": "Klasse 5a", "active": true},
    {"id": 11, "longName": "Only long"},
    {"id": 12}
  ],
  "teachers": [
    {"id": 1, "name": "MUE", "firstName": "Anna", "lastName": "Müller",
     "foreColor": "#000000", "backColor": "#ff8800"},
    {"id": 2, "name": "SCH"},
    {"id": 3, "lastName": "Schmidt", "active": false, "displayAllowed": false},
    {"id": 4},
    {"name": "no id"},
    "garbage"
  ],
  "rooms": [{"id": 100, "name": "R101", "longName": "Raum 101", "active": "yes"}],
  "subjects": [{"id": 200, "name": "M", "longName": "Mathe", "backColor": "nope"}],
  "holidays": [
    {"id": 5, "name": "HF", "longName": "Herbstferien",
     "startDate": "2025-10-27", "endDate": "2025-10-31"},
    {"id": 6, "name": "broken"}
  ],
  "schoolyears": [
    {"id": 7, "name": "2025/2026", "startDate": "2025-09-01", "endDate": "2026-07-31"}
  ],
  "timeGrid": {"days": [
    {"day": "MON", "units": [
      {"label": "2", "startTime": "T08:50", "endTime": "T09:35"},
      {"label": "1", "startTime": "T08:00", "endTime": "T08:45"}
    ]},
    {"day": "FRI", "units": [{"label": "1", "startTime": "T08:00", "endTime": "T08:45"}]},
    {"day": 1, "units": []},
    {"day": "XYZ", "units": []}
  ]}
}
''';

const timetableJson = '''
{
  "timetable": {"periods": [
    {
      "id": 501, "lessonId": 42,
      "startDateTime": "2025-09-15T08:00Z", "endDateTime": "2025-09-15T08:45:00",
      "foreColor": "#000000", "backColor": "#a0b0c0",
      "text": {"lesson": "L", "substitution": "S", "info": "I"},
      "elements": [
        {"type": "CLASS", "id": 10, "orgId": 10},
        {"type": "TEACHER", "id": 999, "orgId": 999, "name": "XYZ", "longName": "Xaver Yz"},
        {"type": "SUBJECT", "id": 200},
        {"type": "ROOM", "id": 101, "orgId": 100},
        {"type": "TEACHER", "id": 0, "orgId": 1},
        {"type": "BUILDING", "id": 3, "orgId": 3},
        {"type": "TEACHER", "id": 77, "displayName": "Frau Inline"}
      ],
      "can": ["SOMETHING_NEW"],
      "is": ["REGULAR", "SUPER_NEW_FLAG"],
      "homeWorks": [{"id": 9, "lessonId": 42, "startDate": "2025-09-15",
                     "endDate": "2025-09-17", "text": "Page 4", "completed": "x"}],
      "exam": {"id": 3, "examType": "TEST", "name": "Klausur"},
      "isOnlinePeriod": false
    },
    {"id": 502, "startDateTime": "garbage", "endDateTime": "2025-09-15T09:00"},
    {"id": 503, "startDateTime": "2025-09-15T07:00", "endDateTime": "2025-09-15T07:45",
     "is": "CANCELLED", "elements": "nope", "text": null}
  ]}
}
''';

Map<String, Object?> decode(String s) => jsonDecode(s) as Map<String, Object?>;

void main() {
  group('formats', () {
    test('date, datetime local wall clock, time, color', () {
      expect(parseDate('2025-09-15'), DateTime(2025, 9, 15));
      final dt = parseDateTime('2025-09-15T08:00Z')!;
      expect(dt, DateTime(2025, 9, 15, 8));
      expect(dt.isUtc, isFalse);
      expect(
        parseDateTime('2025-09-15T08:00:30'),
        DateTime(2025, 9, 15, 8, 0, 30),
      );
      expect(parseTime('T08:05'), 485);
      expect(parseColor('#ff8800'), 0xFFFF8800);
      expect(parseColor('zzz'), isNull);
      expect(parseColor(null), isNull);
      expect(formatDate(DateTime(2025, 1, 5)), '2025-01-05');
    });
  });

  group('master data', () {
    final md = parseMasterData(decode(masterDataJson));
    MasterElement el(ElementType t, int id) =>
        md.elements.firstWhere((e) => e.type == t && e.id == id);

    test('timestamp', () => expect(md.timestamp, 1731230000000));

    test('teacher without active field is active', () {
      final t = el(ElementType.teacher, 1);
      expect(t.active, isTrue);
      expect(t.displayAllowed, isTrue);
      expect(t.name, 'MUE');
      expect(t.longName, 'Anna Müller');
      expect(t.backColor, 0xFFFF8800);
    });

    test('teacher with only name: longName falls back to name', () {
      final t = el(ElementType.teacher, 2);
      expect(t.name, 'SCH');
      expect(t.longName, 'SCH');
    });

    test('teacher with lastName only, inactive is kept', () {
      final t = el(ElementType.teacher, 3);
      expect(t.name, 'Schmidt');
      expect(t.longName, 'Schmidt');
      expect(t.active, isFalse);
      expect(t.displayAllowed, isFalse);
    });

    test('teacher with nothing gets #id; invalid entries skipped', () {
      expect(el(ElementType.teacher, 4).name, '#4');
      expect(el(ElementType.teacher, 4).longName, '#4');
      expect(md.elements.where((e) => e.type == ElementType.teacher).length, 4);
    });

    test('klassen/rooms/subjects name fallbacks', () {
      expect(el(ElementType.klasse, 10).longName, 'Klasse 5a');
      expect(el(ElementType.klasse, 11).name, 'Only long');
      expect(el(ElementType.klasse, 12).name, '#12');
      expect(el(ElementType.klasse, 12).longName, '#12');
      expect(el(ElementType.room, 100).active, isTrue); // wrong type -> default
      expect(el(ElementType.subject, 200).backColor, isNull);
    });

    test('holidays, schoolyears', () {
      expect(md.holidays, hasLength(1));
      expect(md.holidays.single.end, DateTime(2025, 10, 31));
      expect(md.holidays.single.longName, 'Herbstferien');
      expect(md.schoolYears.single.start, DateTime(2025, 9, 1));
    });

    test('timeGrid days mapped to DateTime.weekday, units sorted', () {
      final g = md.timeGrid!;
      expect(g.days.keys, containsAll([1, 5, 7]));
      expect(g.days[1]!.first.label, '1');
      expect(g.days[1]!.first.start, 480);
      expect(g.days[1]![1].end, 575);
    });

    test('missing timeGrid -> null, empty/garbage master data ok', () {
      expect(parseMasterData({'timeStamp': 1}).timeGrid, isNull);
      final empty = parseMasterData('nope');
      expect(empty.timestamp, 0);
      expect(empty.elements, isEmpty);
      expect(
        parseMasterData({'timeGrid': 'x', 'teachers': 5}).timeGrid,
        isNull,
      );
    });
  });

  group('timetable', () {
    final tt = parseTimetableResponse(decode(timetableJson));

    test('invalid periods are skipped, rest sorted', () {
      expect(tt.periods.map((p) => p.id), [503, 501]);
      expect(tt.masterDataDelta, isNull);
    });

    final p = tt.periods.last;

    test('basic fields', () {
      expect(p.start, DateTime(2025, 9, 15, 8));
      expect(p.end, DateTime(2025, 9, 15, 8, 45));
      expect(p.lessonId, 42);
      expect(p.lessonText, 'L');
      expect(p.substitutionText, 'S');
      expect(p.infoText, 'I');
      expect(p.backColor, 0xFFA0B0C0);
      expect(p.homework.single.endDate, DateTime(2025, 9, 17));
      expect(p.exam?.name, 'Klausur');
      expect(p.isExam, isTrue);
    });

    test('unknown is value kept as unknown, period not dropped', () {
      expect(p.flags, {PeriodFlag.regular, PeriodFlag.unknown});
    });

    test('teacher referenced via inline name only', () {
      final t = p.elements.firstWhere((e) => e.id == 999);
      expect(t.type, ElementType.teacher);
      expect(t.inlineName, 'XYZ');
      expect(t.inlineLongName, 'Xaver Yz');
      final d = p.elements.firstWhere((e) => e.id == 77);
      expect(d.inlineName, 'Frau Inline');
      expect(d.inlineLongName, 'Frau Inline');
      expect(d.orgId, 77);
    });

    test('orgId defaults to id', () {
      final s = p.elements.firstWhere((e) => e.type == ElementType.subject);
      expect(s.orgId, 200);
      expect(s.change, ElementChange.regular);
    });

    test('substitution and removal', () {
      final room = p.elements.firstWhere((e) => e.type == ElementType.room);
      expect(room.change, ElementChange.substituted);
      expect(room.orgId, 100);
      final removed = p.elements.firstWhere((e) => e.id == 0);
      expect(removed.change, ElementChange.removed);
      expect(removed.orgId, 1);
      expect(p.isIrregular, isTrue);
    });

    test('unknown element type kept as unknown', () {
      final u = p.elements.firstWhere((e) => e.id == 3);
      expect(u.type, ElementType.unknown);
      expect(p.elements, hasLength(7));
    });

    test('wrong-typed fields fall back', () {
      final q = tt.periods.first;
      expect(q.elements, isEmpty);
      expect(q.flags, isEmpty);
      expect(q.lessonText, '');
    });

    test('master data delta parsed when present', () {
      final r = parseTimetableResponse({
        'timetable': {'periods': []},
        'masterData': {
          'timeStamp': 5,
          'teachers': [
            {'id': 1, 'name': 'A'},
          ],
        },
      });
      expect(r.masterDataDelta!.timestamp, 5);
      expect(r.masterDataDelta!.elements.single.name, 'A');
    });
  });

  group('schools', () {
    const base = {
      'loginName': 'demo',
      'schoolId': 123,
      'displayName': 'Demo School',
      'address': 'Street 1',
      'serverUrl': 'https://demo.webuntis.com/WebUntis/?school=demo',
      'mobileServiceUrl': 'https://mobile.webuntis.com/ms/app',
      'useMobileServiceUrlAndroid': true,
      'useMobileServiceUrlIos': false,
    };

    test('mobileServiceUrl used per platform flag', () {
      expect(parseSchool(base)!.host, 'mobile.webuntis.com');
      expect(parseSchool(base, isIos: true)!.host, 'demo.webuntis.com');
    });

    test('blank mobile url falls back to serverUrl', () {
      expect(
        parseSchool({...base, 'mobileServiceUrl': '  '})!.host,
        'demo.webuntis.com',
      );
    });

    test('custom url wins', () {
      expect(
        parseSchool(base, customUrl: 'https://my.host:8443/x')!.host,
        'my.host',
      );
      expect(parseSchool(base, customUrl: 'bare.host')!.host, 'bare.host');
    });

    test('school list parse', () {
      final list = parseSchools({
        'schools': [
          base,
          {'schoolId': 1},
          'x',
        ],
      });
      expect(list, hasLength(1));
      expect(list.single.schoolId, 123);
      expect(list.single.loginName, 'demo');
    });
  });

  test('login result mapping', () {
    final r = parseLoginResult({
      'masterData': {'timeStamp': 9},
      'userData': {
        'elemId': 55,
        'elemType': 'STUDENT',
        'displayName': 'Max',
        'klassenIds': [10, '11', 'x'],
        'rights': ['R_MY_ABSENCES', 3, ''],
      },
    }, secret: 'S');
    expect(r.secret, 'S');
    expect(r.elementType, ElementType.student);
    expect(r.elementId, 55);
    expect(r.klassenIds, [10, 11]);
    expect(r.rights, {'R_MY_ABSENCES', '3'});
    expect(r.masterData.timestamp, 9);
  });

  test('messages', () {
    final m = parseMessages({
      'messages': [
        {
          'id': 1,
          'subject': 'Hi',
          'body': '<b>x</b>',
          'attachments': [
            {'name': 'a.pdf', 'url': 'https://x/a.pdf'},
          ],
        },
      ],
    });
    expect(m.single.bodyHtml, '<b>x</b>');
    expect(m.single.attachments.single.name, 'a.pdf');
  });
}
