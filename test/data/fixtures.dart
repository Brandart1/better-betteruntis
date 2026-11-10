import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/data/db/database.dart';
import 'package:drift/native.dart';

AppDatabase memoryDb() => AppDatabase(NativeDatabase.memory());

const school = School(
  schoolId: 42,
  loginName: 'demo-school',
  displayName: 'Demo School',
  address: 'Somewhere 1',
  host: 'demo.webuntis.com',
);

Account account(String id, {bool anonymous = false, int ts = 0}) => Account(
  id: id,
  school: school,
  username: anonymous ? '#anonymous#' : 'user_$id',
  anonymous: anonymous,
  displayName: 'User $id',
  elementType: ElementType.student,
  elementId: 7,
  klassenIds: const [1, 2],
  rights: const {'R_MY_TIMETABLE'},
  masterDataTimestamp: ts,
);

MasterElement teacher(int id, String name, {bool active = true}) =>
    MasterElement(
      type: ElementType.teacher,
      id: id,
      name: name,
      longName: '$name long',
      active: active,
    );

MasterData masterData({int ts = 100, List<MasterElement>? elements}) =>
    MasterData(
      timestamp: ts,
      elements:
          elements ??
          [
            teacher(1, 'MUE'),
            teacher(2, 'OLD', active: false),
            const MasterElement(
              type: ElementType.klasse,
              id: 1,
              name: '5a',
              longName: 'Class 5a',
            ),
          ],
      holidays: [
        Holiday(
          id: 1,
          name: 'X',
          longName: 'Christmas',
          start: DateTime(2026, 12, 23),
          end: DateTime(2027, 1, 6),
        ),
      ],
      timeGrid: const TimeGrid({
        1: [TimeUnit(label: '1', start: 480, end: 525)],
      }),
    );

Period period(int id, {List<ElementRef> elements = const []}) => Period(
  id: id,
  lessonId: 10 + id,
  start: DateTime(2026, 11, 9, 8),
  end: DateTime(2026, 11, 9, 8, 45),
  elements: elements,
  flags: const {PeriodFlag.regular},
);
