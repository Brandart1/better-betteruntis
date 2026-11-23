import 'package:better_betteruntis/api/class_register_parsers.dart';
import 'package:better_betteruntis/ui/classreg/pupil_badges.dart';
import 'package:better_betteruntis/api/parsers.dart';
import 'package:better_betteruntis/core/class_register.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/data/class_register_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/classreg/class_register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'class_register_test.dart' show lesson, teacherAccount, week;

ClassRegStudent pupil(int id, [DateTime? born]) => ClassRegStudent(
  id: id,
  firstName: 'P$id',
  lastName: 'L$id',
  birthDate: born,
);

PeriodRegister reg(
  int ttId, {
  List<ClassRole> roles = const [],
  List<ClassRegExemption> exemptions = const [],
}) => PeriodRegister(ttId: ttId, classRoles: roles, exemptions: exemptions);

void main() {
  group('parseExemption', () {
    test('all fields', () {
      final e = parseExemption({
        'id': 4,
        'studentId': 504,
        'subjectId': 12,
        'subjectGroup': ' A ',
        'exemptionReason': 'Medical',
        'text': 'note',
        'startDate': '2026-11-02',
        'endDate': '2026-11-30',
        'startTime': 'T08:00',
        'endTime': 'T09:30',
        'weekDay': 'WED',
      })!;
      expect(e.id, 4);
      expect(e.studentId, 504);
      expect(e.subjectId, 12);
      expect(e.subjectGroup, 'A');
      expect(e.reason, 'Medical');
      expect(e.text, 'note');
      expect(e.startDate, DateTime(2026, 11, 2));
      expect(e.endDate, DateTime(2026, 11, 30));
      expect(e.startMinute, 480);
      expect(e.endMinute, 570);
      expect(e.weekday, DateTime.wednesday);
      expect(e.label, 'Exempt: Medical · note');
    });

    test('0 subject id is none, no pupil is null', () {
      final e = parseExemption({'studentId': 5, 'subjectId': 0})!;
      expect(e.subjectId, isNull);
      expect(e.startDate, isNull);
      expect(e.weekday, isNull);
      expect(e.label, 'Exempt');
      expect(parseExemption({'studentId': 0}), isNull);
      expect(parseExemption({'text': 'x'}), isNull);
    });

    test('appliesOn: dates and weekday', () {
      final e = parseExemption({
        'studentId': 5,
        'startDate': '2026-11-02',
        'endDate': '2026-11-30',
        'weekDay': 'WED',
      })!;
      expect(e.appliesOn(DateTime(2026, 11, 11, 8)), isTrue);
      expect(e.appliesOn(DateTime(2026, 11, 10)), isFalse); // Tuesday
      expect(e.appliesOn(DateTime(2026, 12, 2)), isFalse); // after end
      expect(e.appliesOn(DateTime(2026, 10, 28)), isFalse); // before start
    });
  });

  group('parseClassRole', () {
    test('fields', () {
      final c = parseClassRole({
        'studentId': 505,
        'klasseId': 3,
        'dutyId': 1,
        'startDate': '2026-09-01',
        'endDate': '2027-06-30',
        'text': 'x',
      })!;
      expect(c.studentId, 505);
      expect(c.dutyId, 1);
      expect(c.text, 'x');
      expect(c.startDate, DateTime(2026, 9, 1));
      expect(c.endDate, DateTime(2027, 6, 30));
      expect(c.label, 'x');
      expect(c.withName('Speaker').label, 'Speaker');
      expect(c.withName('Speaker').dutyId, 1);
    });

    test('0 duty id, no pupil, label fallback', () {
      final c = parseClassRole({'studentId': 5, 'dutyId': 0})!;
      expect(c.dutyId, isNull);
      expect(c.label, 'Class duty');
      expect(parseClassRole({'studentId': 0, 'dutyId': 1}), isNull);
    });

    test('appliesOn', () {
      final c = parseClassRole({
        'studentId': 5,
        'startDate': '2026-11-02',
        'endDate': '2026-11-10',
      })!;
      expect(c.appliesOn(DateTime(2026, 11, 10, 15)), isTrue);
      expect(c.appliesOn(DateTime(2026, 11, 11)), isFalse);
    });
  });

  group('parseSeatingPlan', () {
    test('seats', () {
      final p = parseSeatingPlan({
        'id': 2,
        'name': ' Room ',
        'numberOfRows': 2,
        'numberOfColumns': 3,
        'students': [
          {'studentId': 1, 'rowIndex': 0, 'colIndex': 0},
          {'studentId': 2, 'rowIndex': 1, 'colIndex': 2},
          {'studentId': 3, 'rowIndex': -1, 'colIndex': 0},
          {'studentId': 4},
        ],
      })!;
      expect(p.id, 2);
      expect(p.name, 'Room');
      expect(p.rows, 2);
      expect(p.columns, 3);
      expect(p.seats, {(0, 0): 1, (1, 2): 2});
    });

    test('grid grows to fit seats', () {
      final p = parseSeatingPlan({
        'students': [
          {'studentId': 1, 'rowIndex': 3, 'colIndex': 4},
        ],
      })!;
      expect((p.rows, p.columns), (4, 5));
    });

    test('empty or missing plan is null', () {
      expect(
        parseSeatingPlan({
          'numberOfRows': 3,
          'numberOfColumns': 3,
          'students': [],
        }),
        isNull,
      );
      expect(parseSeatingPlan(null), isNull);
      expect(parseSeatingPlan('x'), isNull);
    });
  });

  group('parsing the lesson and master data', () {
    test('birthDate on students', () {
      expect(
        parseClassRegStudent({
          'id': 1,
          'firstName': 'A',
          'lastName': 'B',
          'birthDate': '2011-11-23',
        })!.birthDate,
        DateTime(2011, 11, 23),
      );
      expect(
        parseClassRegStudent({'id': 1, 'firstName': 'A', 'lastName': 'B'})!
            .birthDate,
        isNull,
      );
    });

    test('withBirthDate only fills a missing one', () {
      final a = pupil(1);
      final b = a.withBirthDate(DateTime(2010, 1, 2));
      expect(b.birthDate, DateTime(2010, 1, 2));
      expect(b.firstName, 'P1');
      expect(b.withBirthDate(DateTime(2000, 1, 1)).birthDate, b.birthDate);
      expect(identical(a.withBirthDate(null), a), isTrue);
    });

    test('period register carries exemptions, roles and plan', () {
      final r = parsePeriodRegister(7, {
        'exemptions': [
          {'studentId': 504},
        ],
        'classRoles': [
          {'studentId': 505, 'dutyId': 1},
        ],
        'seatingPlan': {
          'numberOfRows': 1,
          'numberOfColumns': 1,
          'students': [
            {'studentId': 505, 'rowIndex': 0, 'colIndex': 0},
          ],
        },
      });
      expect(r.exemptions.single.studentId, 504);
      expect(r.classRoles.single.dutyId, 1);
      expect(r.seatingPlan!.seats, {(0, 0): 505});
      expect(parsePeriodRegister(7, {}).seatingPlan, isNull);
      final c = r.copyWith(classRoles: [r.classRoles.single.withName('S')]);
      expect(c.classRoles.single.name, 'S');
      expect(c.exemptions, r.exemptions);
      expect(c.seatingPlan, r.seatingPlan);
    });

    test('duties and birth dates in master data', () {
      final l = parseAbsenceLookups({
        'duties': [
          {'id': 1, 'name': 'KS', 'longName': 'Class speaker'},
          {'id': 2, 'name': 'Board'},
          {'name': 'no id'},
        ],
        'students': [
          {'id': 501, 'birthDate': '2011-11-23'},
          {'id': 502, 'birthDate': 'nonsense'},
          {'id': 503},
        ],
      });
      expect(l.duties, {1: 'Class speaker', 2: 'Board'});
      expect(l.birthDates, {501: DateTime(2011, 11, 23)});
      expect(l.isEmpty, isFalse);
      final m = l.merge(
        parseAbsenceLookups({
          'duties': [
            {'id': 2, 'name': 'Window'},
          ],
        }),
      );
      expect(m.duties[2], 'Window');
      expect(m.birthDates, l.birthDates);
    });
  });

  group('isBirthday / ageOn', () {
    test('same month and day, any year', () {
      final born = DateTime(2011, 11, 23);
      expect(isBirthday(born, DateTime(2026, 11, 23, 8)), isTrue);
      expect(isBirthday(born, DateTime(2026, 11, 24)), isFalse);
      expect(isBirthday(null, DateTime(2026, 11, 23)), isFalse);
    });

    test('29 February counts on 28 February in non-leap years', () {
      final born = DateTime(2012, 2, 29);
      expect(isBirthday(born, DateTime(2027, 2, 28)), isTrue);
      expect(isBirthday(born, DateTime(2027, 3, 1)), isFalse);
      // Leap year: the real day.
      expect(isBirthday(born, DateTime(2028, 2, 29)), isTrue);
      expect(isBirthday(born, DateTime(2028, 2, 28)), isFalse);
    });

    test('ageOn', () {
      final born = DateTime(2011, 11, 23);
      expect(ageOn(born, DateTime(2026, 11, 23)), 15);
      expect(ageOn(born, DateTime(2026, 11, 22)), 14);
    });
  });

  group('PupilNotes.of', () {
    final day = DateTime(2026, 11, 11, 8);

    test('filters by date and leaves out pupils without notes', () {
      final notes = PupilNotes.of(
        [
          reg(
            1,
            roles: [
              const ClassRole(studentId: 1, dutyId: 1, name: 'Speaker'),
              ClassRole(
                studentId: 2,
                dutyId: 2,
                name: 'Old',
                endDate: DateTime(2026, 11, 1),
              ),
            ],
            exemptions: [
              ClassRegExemption(
                studentId: 3,
                reason: 'Cert',
                startDate: DateTime(2026, 11, 1),
                endDate: DateTime(2026, 11, 30),
              ),
              ClassRegExemption(studentId: 4, startDate: DateTime(2026, 12, 1)),
            ],
          ),
        ],
        [
          pupil(1),
          pupil(2),
          pupil(3),
          pupil(4),
          pupil(5, DateTime(2011, 11, 11)),
        ],
        day,
      );
      expect(notes.keys.toSet(), {1, 3, 5});
      expect(notes[1]!.roles.single.label, 'Speaker');
      expect(notes[3]!.exemptions.single.reason, 'Cert');
      expect(notes[5]!.birthday, isTrue);
      expect(notes[1]!.birthday, isFalse);
    });

    test('a double lesson does not repeat roles and exemptions', () {
      const role = ClassRole(studentId: 1, dutyId: 1, name: 'Speaker');
      const ex = ClassRegExemption(id: 9, studentId: 1, reason: 'Cert');
      final notes = PupilNotes.of(
        [
          reg(1, roles: [role], exemptions: [ex]),
          reg(2, roles: [role], exemptions: [ex]),
        ],
        [pupil(1)],
        day,
      );
      expect(notes[1]!.roles, hasLength(1));
      expect(notes[1]!.exemptions, hasLength(1));
    });

    test('different duties of one pupil all stay', () {
      final notes = PupilNotes.of(
        [
          reg(
            1,
            roles: [
              const ClassRole(studentId: 1, dutyId: 1, name: 'A'),
              const ClassRole(studentId: 1, dutyId: 2, name: 'B'),
            ],
          ),
        ],
        [pupil(1)],
        day,
      );
      expect(notes[1]!.roles.map((r) => r.name), ['A', 'B']);
    });
  });

  group('screen (demo teacher)', () {
    testWidgets('badges, seating plan toggle, tapping a seat', (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = FakeUntisApi(latency: Duration.zero);
      final accounts = InMemoryAccountRepository(initial: [teacherAccount()]);
      accounts.secrets['teacher'] = 'S';
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day, 8);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            accountRepositoryProvider.overrideWithValue(accounts),
            settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
            classRegisterRepositoryProvider.overrideWithValue(
              ClassRegisterRepositoryImpl(
                api: api,
                accounts: accounts,
                timetables: FakeTimetableRepository(weekBuilder: week),
                clock: () => start.add(const Duration(hours: 4)),
              ),
            ),
          ],
          child: MaterialApp(
            home: ClassRegisterScreen(
              account: teacherAccount(),
              periods: [lesson(11, start)],
              title: 'Maths',
              subtitle: 'today',
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pupil-birthday-501')), findsOneWidget);
      expect(find.text('Class speaker'), findsOneWidget);
      expect(find.text('Board duty'), findsOneWidget);
      expect(find.byKey(const ValueKey('pupil-exempt-504')), findsOneWidget);
      expect(find.byKey(const ValueKey('classreg-seating-plan')), findsNothing);

      await t.tap(find.byKey(const ValueKey('classreg-seating-toggle')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('classreg-seating-plan')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('classreg-student-501')), findsNothing);
      expect(find.byKey(const ValueKey('classreg-seat-501')), findsOneWidget);
      // Ben has no seat but is still shown.
      expect(find.byKey(const ValueKey('classreg-seat-506')), findsOneWidget);
      expect(find.text('List'), findsOneWidget);

      Finder summary(String s) => find.textContaining(s);
      expect(summary('6 present'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('classreg-seat-502')));
      await t.pumpAndSettle();
      expect(summary('5 present · 1 absent'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('classreg-seat-502')));
      await t.pumpAndSettle();
      expect(summary('6 present'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('classreg-seating-toggle')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('classreg-seating-plan')), findsNothing);
      expect(
        find.byKey(const ValueKey('classreg-student-501')),
        findsOneWidget,
      );
    });
  });
}
