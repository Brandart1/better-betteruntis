import 'package:better_betteruntis/api/parsers.dart';
import 'package:better_betteruntis/core/absence_details.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('homework', () {
    final raw = {
      'homeWorks': [
        {
          'id': 1,
          'lessonId': 55,
          'startDate': '2026-11-09',
          'endDate': '2026-11-12',
          'text': 'Read chapter 4',
          'remark': 'pages 30-41',
          'completed': false,
          'attachments': [
            {'id': 9, 'name': 'sheet.pdf', 'url': 'https://x.invalid/s.pdf'},
            {'name': 'link only', 'src': 'https://x.invalid/l'},
            {'id': 3},
          ],
        },
        // yyyyMMdd ints, unknown lesson, completed as 1.
        {
          'id': 2,
          'lessonId': 77,
          'startDate': 20261102,
          'endDate': 20261105,
          'text': 'Vocab',
          'completed': 1,
        },
        {'id': 3, 'text': 'no dates -> skipped'},
        'garbage',
      ],
      'lessonsById': {
        '55': {
          'id': 55,
          'subjectId': 21,
          'klassenIds': [1, '2'],
          'teacherIds': [11],
        },
        'oops': 'not a map',
      },
    };

    test('joins lessonsById and parses tolerantly', () {
      final items = parseHomeworkItems(raw);
      expect(items.map((h) => h.id), [2, 1]); // sorted by due date
      final h = items[1];
      expect(h.assignedOn, DateTime(2026, 11, 9));
      expect(h.dueOn, DateTime(2026, 11, 12));
      expect(h.subjectId, 21);
      expect(h.klassenIds, [1, 2]);
      expect(h.teacherIds, [11]);
      expect(h.remark, 'pages 30-41');
      expect(h.attachments.map((a) => a.url), [
        'https://x.invalid/s.pdf',
        'https://x.invalid/l',
      ]);
      final v = items[0];
      expect(v.subjectId, isNull);
      expect(v.teacherIds, isEmpty);
      expect(v.completed, isTrue);
      expect(v.dueOn, DateTime(2026, 11, 5));
    });

    test('garbage input gives empty list', () {
      expect(parseHomeworkItems(null), isEmpty);
      expect(parseHomeworkItems({'homeWorks': 'x', 'lessonsById': 5}), isEmpty);
    });
  });

  test('exams', () {
    final items = parseExamItems({
      'exams': [
        {
          'id': 7,
          'examType': 'Klassenarbeit',
          'startDateTime': '2026-11-20T08:00Z',
          'endDateTime': '2026-11-20T09:30Z',
          'subjectId': 21,
          'klasseIds': [1],
          'roomIds': [31],
          'teacherIds': [11, 'x'],
          'name': 'Fractions',
          'text': 'Calculator allowed',
        },
        {'id': 8, 'startDateTime': '2026-11-18T10:00', 'subjectId': 0},
        {'id': 9, 'startDateTime': 'never'},
      ],
    });
    expect(items.map((e) => e.id), [8, 7]);
    final e = items[1];
    expect(e.start, DateTime(2026, 11, 20, 8));
    expect(e.end, DateTime(2026, 11, 20, 9, 30));
    expect(e.examType, 'Klassenarbeit');
    expect(e.klassenIds, [1]);
    expect(e.roomIds, [31]);
    expect(e.teacherIds, [11]);
    expect(items[0].subjectId, isNull);
    expect(items[0].end, items[0].start);
  });

  group('absences', () {
    const lookups = AbsenceLookups(
      reasons: {1: 'Illness', 2: 'Doctor'},
      statuses: {5: 'excused', 6: 'open'},
    );

    final raw = {
      'absences': [
        {
          'id': 1,
          'startDateTime': '2026-10-01T08:00',
          'endDateTime': '2026-10-01T13:00',
          'excused': true,
          'absenceReasonId': 1,
          'absenceReason': '',
          'text': 'fever',
          'excuse': {'id': 3, 'excuseStatusId': 5},
        },
        {
          'id': 2,
          'startDateTime': '2026-10-05T09:00',
          'endDateTime': '2026-10-05T10:00',
          'excused': false,
          'absenceReasonId': 2,
          'absenceReason': 'Dentist (inline)',
        },
        // Old-style date + time ints.
        {
          'id': 3,
          'startDate': 20260910,
          'startTime': 800,
          'endDate': 20260910,
          'endTime': 945,
          'absenceReasonId': 99,
          'excuse': {'excuseStatusId': 6},
        },
        {'id': 4},
      ],
    };

    test('parse with ids, newest first', () {
      final a = parseRawAbsences(raw);
      expect(a.map((x) => x.id), [2, 1, 3]);
      expect(a[2].start, DateTime(2026, 9, 10, 8));
      expect(a[2].end, DateTime(2026, 9, 10, 9, 45));
      expect(a[1].reasonId, 1);
      expect(a[1].excuseStatusId, 5);
      expect(a[1].inlineReason, '');
    });

    test('resolve: inline name first, then lookups, else empty', () {
      final items = [for (final a in parseRawAbsences(raw)) a.resolve(lookups)];
      expect(items[0].reason, 'Dentist (inline)');
      expect(items[0].excuseStatus, '');
      expect(items[1].reason, 'Illness');
      expect(items[1].excuseStatus, 'excused');
      expect(items[1].text, 'fever');
      expect(items[1].excused, isTrue);
      expect(items[2].reason, ''); // unknown id 99
      expect(items[2].excuseStatus, 'open');
    });

    test('needsLookup', () {
      final a = parseRawAbsences(raw);
      expect(a[0].needsLookup(const AbsenceLookups()), isFalse); // inline
      expect(a[1].needsLookup(const AbsenceLookups()), isTrue);
      expect(a[1].needsLookup(lookups), isFalse);
    });

    test('master-data lookups keep inactive entries, longName first', () {
      final md = parseMasterData({
        'timeStamp': 5,
        'absenceReasons': [
          {'id': 1, 'name': 'K', 'longName': 'Illness', 'active': true},
          {'id': 2, 'name': 'A', 'longName': '', 'active': false},
          {'name': 'no id'},
        ],
        'excuseStatuses': [
          {
            'id': 5,
            'name': 'ent',
            'longName': 'excused',
            'excused': true,
            'active': true,
          },
        ],
      });
      expect(md, isA<MasterDataWithLookups>());
      final l = (md as MasterDataWithLookups).lookups;
      expect(l.reasons, {1: 'Illness', 2: 'A'});
      expect(l.statuses, {5: 'excused'});
    });
  });

  test('office hours', () {
    final items = parseOfficeHourItems({
      'officeHours': [
        {
          'id': 4,
          'startDateTime': '2026-11-11T10:00',
          'endDateTime': '2026-11-11T10:45',
          'displayNameTeacher': 'Erika Beispiel',
          'displayNameRooms': 'R12, R13',
          'email': 'e.beispiel@example.invalid',
          'phone': null,
          'registrationPossible': true,
          'registered': 'false',
        },
        {'id': 5, 'displayNameTeacher': 'No time'},
      ],
    });
    expect(items, hasLength(1));
    final o = items.single;
    expect(o.teacherName, 'Erika Beispiel');
    expect(o.rooms, 'R12, R13');
    expect(o.phone, '');
    expect(o.registrationPossible, isTrue);
    expect(o.registered, isFalse);
    expect(o.end, DateTime(2026, 11, 11, 10, 45));
  });

  group('inbox', () {
    test('merges both lists, de-duplicates, newest first', () {
      final items = parseInbox({
        'incomingMessages': [
          {
            'id': 10,
            'subject': 'Trip',
            'contentPreview': 'Bring shoes',
            'sender': {'displayName': 'Max Muster'},
            'sentDateTime': '2026-11-01T08:00:00',
            'isMessageRead': true,
            'hasAttachments': false,
          },
          {
            'id': 12,
            'subject': 'Newest',
            'sentDateTime': '2026-11-09T10:00:00',
          },
          {'subject': 'no id -> skipped'},
        ],
        'readConfirmationMessages': [
          {
            'id': 11,
            'subject': 'Please confirm',
            'sender': 'Office',
            'sentDateTime': '2026-11-05T12:00:00',
            'attachments': [{}],
          },
          {'id': 10, 'subject': 'duplicate'},
          {'id': 13, 'subject': 'no date'},
        ],
      });
      expect(items.map((m) => m.id), [12, 11, 10, 13]);
      expect(items[2].sender, 'Max Muster');
      expect(items[2].preview, 'Bring shoes');
      expect(items[2].isRead, isTrue);
      expect(items[2].subject, 'Trip');
      expect(items[1].sender, 'Office');
      expect(items[1].hasAttachments, isTrue);
      expect(items[0].sender, '');
      expect(items[3].sentAt, isNull);
    });

    test('zoned timestamps are converted to local time', () {
      final m = parseInbox({
        'incomingMessages': [
          {'id': 1, 'sentDateTime': '2026-11-01T08:00:00Z'},
        ],
      }).single;
      expect(m.sentAt, DateTime.utc(2026, 11, 1, 8).toLocal());
    });

    test('tolerates garbage', () {
      expect(parseInbox(null), isEmpty);
      expect(parseInbox({'incomingMessages': 'x'}), isEmpty);
    });

    test('message detail with attachment url fallbacks', () {
      final d = parseInboxMessageDetail({
        'id': 10,
        'subject': 'Trip',
        'content': '<p>Bring <b>shoes</b></p>',
        'sender': {'displayName': 'Max Muster'},
        'sentDateTime': '2026-11-01T08:00:00',
        'attachments': [
          {'name': 'a.pdf', 'src': 'https://x.invalid/a'},
          {'name': 'b.pdf', 'downloadUrl': 'https://x.invalid/b'},
          {'name': 'c.pdf', 'url': 'https://x.invalid/c'},
        ],
      }, 99);
      expect(d.id, 10);
      expect(d.bodyHtml, contains('<b>shoes</b>'));
      expect(d.sender, 'Max Muster');
      expect(d.attachments.map((a) => a.url), [
        'https://x.invalid/a',
        'https://x.invalid/b',
        'https://x.invalid/c',
      ]);
      expect(parseInboxMessageDetail('junk', 99).id, 99);
    });

    test('REST error messages', () {
      expect(
        parseRestErrorMessage({'errorCode': 'FORBIDDEN', 'errorMessage': 'No'}),
        'No',
      );
      expect(
        parseRestErrorMessage({
          'errorCode': 'NOT_FOUND',
          'requestId': 'r1',
          'validationErrors': [],
        }),
        'NOT_FOUND',
      );
      expect(parseRestErrorMessage(null), isNull);
    });
  });
}
