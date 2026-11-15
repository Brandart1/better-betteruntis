/// In-memory timetable fakes for demo mode, UI development and widget tests.
///
/// * [demoTimeGrid]: 8 units 07:45–15:10 with breaks.
/// * [demoElements]: German subjects/teachers/rooms, incl. an INACTIVE teacher
///   (BEC) that must still be shown everywhere.
/// * [buildDemoWeek]: a realistic week with a double lesson, substitution,
///   cancelled lesson, exam, overlapping lessons, removed teacher, homework and
///   an online link.
/// * [FakeNameResolver], [FakeTimetableRepository].
library;

import 'dart:async';

import 'package:collection/collection.dart';

import '../core/interfaces.dart';
import '../core/models.dart';

// ---------------------------------------------------------------------------
// Master data

const demoTimeGrid = TimeGrid({
  1: _units,
  2: _units,
  3: _units,
  4: _units,
  5: _units,
});

const _units = [
  TimeUnit(label: '1', start: 7 * 60 + 45, end: 8 * 60 + 30),
  TimeUnit(label: '2', start: 8 * 60 + 35, end: 9 * 60 + 20),
  TimeUnit(label: '3', start: 9 * 60 + 40, end: 10 * 60 + 25),
  TimeUnit(label: '4', start: 10 * 60 + 30, end: 11 * 60 + 15),
  TimeUnit(label: '5', start: 11 * 60 + 30, end: 12 * 60 + 15),
  TimeUnit(label: '6', start: 12 * 60 + 20, end: 13 * 60 + 5),
  TimeUnit(label: '7', start: 13 * 60 + 40, end: 14 * 60 + 25),
  TimeUnit(label: '8', start: 14 * 60 + 25, end: 15 * 60 + 10),
];

/// Ids used by the demo data.
abstract final class DemoIds {
  static const klasse = 40;
  // Teachers
  static const mue = 1, sch = 2, web = 3, fis = 4, bec = 5, hof = 6;
  // Subjects
  static const m = 10,
      d = 11,
      e = 12,
      ph = 13,
      bio = 14,
      sp = 15,
      ge = 16,
      inf = 17,
      ku = 18,
      ch = 19,
      rel = 20,
      eth = 21;
  // Rooms
  static const r101 = 30, r102 = 31, ph1 = 32, th = 33, r204 = 34, inf1 = 35;

  /// Lesson id of the Monday double maths lesson (merged into one card).
  static const doubleMathsLesson = 100;

  /// Teacher id that is NOT in master data; only inline names exist.
  static const inlineOnlyTeacher = 99;
}

const demoElements = <MasterElement>[
  MasterElement(
    type: ElementType.klasse,
    id: DemoIds.klasse,
    name: '10a',
    longName: 'Klasse 10a',
  ),
  MasterElement(
    type: ElementType.teacher,
    id: DemoIds.mue,
    name: 'MUE',
    longName: 'Anna Müller',
  ),
  MasterElement(
    type: ElementType.teacher,
    id: DemoIds.sch,
    name: 'SCH',
    longName: 'Peter Schmidt',
  ),
  MasterElement(
    type: ElementType.teacher,
    id: DemoIds.web,
    name: 'WEB',
    longName: 'Klara Weber',
  ),
  MasterElement(
    type: ElementType.teacher,
    id: DemoIds.fis,
    name: 'FIS',
    longName: 'Jonas Fischer',
  ),
  MasterElement(
    type: ElementType.teacher,
    id: DemoIds.bec,
    name: 'BEC',
    longName: 'Maria Becker',
    active: false, // inactive — must still be displayed
  ),
  MasterElement(
    type: ElementType.teacher,
    id: DemoIds.hof,
    name: 'HOF',
    longName: 'Lena Hoffmann',
  ),
  MasterElement(
    type: ElementType.subject,
    id: DemoIds.m,
    name: 'M',
    longName: 'Mathematik',
    backColor: 0xFFB3D4FC,
  ),
  MasterElement(
    type: ElementType.subject,
    id: DemoIds.d,
    name: 'D',
    longName: 'Deutsch',
  ),
  MasterElement(
    type: ElementType.subject,
    id: DemoIds.e,
    name: 'E',
    longName: 'Englisch',
  ),
  MasterElement(
    type: ElementType.subject,
    id: DemoIds.ph,
    name: 'PH',
    longName: 'Physik',
  ),
  MasterElement(
    type: ElementType.subject,
    id: DemoIds.bio,
    name: 'BIO',
    longName: 'Biologie',
  ),
  MasterElement(
    type: ElementType.subject,
    id: DemoIds.sp,
    name: 'SP',
    longName: 'Sport',
  ),
  MasterElement(
    type: ElementType.subject,
    id: DemoIds.ge,
    name: 'GE',
    longName: 'Geschichte',
  ),
  MasterElement(
    type: ElementType.subject,
    id: DemoIds.inf,
    name: 'INF',
    longName: 'Informatik',
  ),
  MasterElement(
    type: ElementType.subject,
    id: DemoIds.ku,
    name: 'KU',
    longName: 'Kunst',
  ),
  MasterElement(
    type: ElementType.subject,
    id: DemoIds.ch,
    name: 'CH',
    longName: 'Chemie',
  ),
  MasterElement(
    type: ElementType.subject,
    id: DemoIds.rel,
    name: 'REL',
    longName: 'Religion',
  ),
  MasterElement(
    type: ElementType.subject,
    id: DemoIds.eth,
    name: 'ETH',
    longName: 'Ethik',
  ),
  MasterElement(
    type: ElementType.room,
    id: DemoIds.r101,
    name: 'R101',
    longName: 'Raum 101',
  ),
  MasterElement(
    type: ElementType.room,
    id: DemoIds.r102,
    name: 'R102',
    longName: 'Raum 102',
  ),
  MasterElement(
    type: ElementType.room,
    id: DemoIds.ph1,
    name: 'PH1',
    longName: 'Physiksaal 1',
  ),
  MasterElement(
    type: ElementType.room,
    id: DemoIds.th,
    name: 'TH',
    longName: 'Turnhalle',
  ),
  MasterElement(
    type: ElementType.room,
    id: DemoIds.r204,
    name: 'R204',
    longName: 'Raum 204',
  ),
  MasterElement(
    type: ElementType.room,
    id: DemoIds.inf1,
    name: 'INF1',
    longName: 'Informatikraum',
  ),
];

/// A holiday on the Friday of the week starting [weekStart].
Holiday demoHoliday(DateTime weekStart) {
  final fri = DateTime(weekStart.year, weekStart.month, weekStart.day + 4);
  return Holiday(
    id: 1,
    name: 'Studientag',
    longName: 'Pädagogischer Tag',
    start: fri,
    end: fri,
  );
}

DateTime _mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

// ---------------------------------------------------------------------------
// Demo week

/// Builds a realistic week starting at [weekStart] (a Monday). If
/// [holidayFriday] is true no lessons are generated for Friday (pair with
/// [demoHoliday]). Period ids are deterministic per week.
List<Period> buildDemoWeek(DateTime weekStart, {bool holidayFriday = false}) {
  final base =
      (weekStart.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay) * 100;
  var n = 0;
  final out = <Period>[];

  ElementRef el(ElementType t, int id, [int? orgId]) =>
      ElementRef(type: t, id: id, orgId: orgId ?? id);

  void add(
    int weekday,
    int unit, {
    required int lesson,
    required int subject,
    required List<int> teachers,
    required int room,
    int units = 1,
    List<ElementRef> extra = const [],
    List<ElementRef>? teacherRefs,
    ElementRef? roomRef,
    Set<PeriodFlag> flags = const {PeriodFlag.regular},
    String substitutionText = '',
    String lessonText = '',
    String infoText = '',
    Exam? exam,
    List<Homework> homework = const [],
    String? onlineLink,
    int? startMinute,
    int? endMinute,
  }) {
    for (var u = unit; u < unit + units; u++) {
      final tu = _units[u - 1];
      final day = DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day + weekday - 1,
      );
      final s = startMinute ?? tu.start, e = endMinute ?? tu.end;
      out.add(
        Period(
          id: base + n++,
          lessonId: lesson,
          start: DateTime(day.year, day.month, day.day, 0, s),
          end: DateTime(day.year, day.month, day.day, 0, e),
          elements: [
            el(ElementType.klasse, DemoIds.klasse),
            el(ElementType.subject, subject),
            ...?teacherRefs,
            if (teacherRefs == null)
              for (final t in teachers) el(ElementType.teacher, t),
            roomRef ?? el(ElementType.room, room),
            ...extra,
          ],
          flags: flags,
          substitutionText: substitutionText,
          lessonText: lessonText,
          infoText: infoText,
          exam: exam,
          homework: homework,
          isOnline: onlineLink != null,
          onlineLink: onlineLink,
        ),
      );
    }
  }

  final mon = weekStart;
  DateTime dayAt(int weekday) =>
      DateTime(mon.year, mon.month, mon.day + weekday - 1);

  // Monday
  add(
    1,
    1,
    lesson: DemoIds.doubleMathsLesson,
    subject: DemoIds.m,
    teachers: [DemoIds.mue],
    room: DemoIds.r101,
    units: 2,
  );
  add(
    1,
    3,
    lesson: 101,
    subject: DemoIds.d,
    teachers: [DemoIds.sch],
    room: DemoIds.r101,
  );
  add(
    1,
    4,
    lesson: 102,
    subject: DemoIds.e,
    teachers: [DemoIds.web],
    room: DemoIds.r102,
  );
  add(
    1,
    5,
    lesson: 103,
    subject: DemoIds.ph,
    teachers: [DemoIds.fis],
    room: DemoIds.ph1,
    units: 2,
  );
  add(
    1,
    7,
    lesson: 104,
    subject: DemoIds.sp,
    teachers: [DemoIds.hof],
    room: DemoIds.th,
    units: 2,
  );

  // Tuesday: inactive teacher, exam, substitution, cancelled
  add(
    2,
    1,
    lesson: 101,
    subject: DemoIds.d,
    teachers: [DemoIds.sch],
    room: DemoIds.r101,
  );
  add(
    2,
    2,
    lesson: 105,
    subject: DemoIds.ge,
    teachers: [DemoIds.bec],
    room: DemoIds.r204,
  );
  add(
    2,
    3,
    lesson: 106,
    subject: DemoIds.m,
    teachers: [DemoIds.mue],
    room: DemoIds.r101,
    flags: const {PeriodFlag.exam},
    exam: const Exam(
      id: 1,
      type: 'Klassenarbeit',
      name: 'Klassenarbeit Nr. 2',
      text: 'Lineare Funktionen',
    ),
  );
  add(
    2,
    4,
    lesson: 102,
    subject: DemoIds.e,
    teachers: const [],
    room: DemoIds.r102,
    teacherRefs: [el(ElementType.teacher, DemoIds.fis, DemoIds.web)],
    flags: const {PeriodFlag.irregular},
    substitutionText: 'Vertretung',
  );
  add(
    2,
    5,
    lesson: 107,
    subject: DemoIds.ch,
    teachers: [DemoIds.web],
    room: DemoIds.r204,
    flags: const {PeriodFlag.cancelled},
    substitutionText: 'Entfall',
  );
  add(
    2,
    6,
    lesson: 108,
    subject: DemoIds.ku,
    teachers: [DemoIds.hof],
    room: DemoIds.r102,
  );

  // Wednesday: parallel REL/ETH, removed teacher + room change, inline-only teacher
  add(
    3,
    1,
    lesson: 109,
    subject: DemoIds.rel,
    teachers: [DemoIds.bec],
    room: DemoIds.r204,
    units: 2,
  );
  add(
    3,
    1,
    lesson: 110,
    subject: DemoIds.eth,
    teachers: [DemoIds.sch],
    room: DemoIds.r102,
    units: 2,
  );
  add(
    3,
    3,
    lesson: 102,
    subject: DemoIds.e,
    teachers: [DemoIds.web],
    room: DemoIds.r102,
  );
  add(
    3,
    4,
    lesson: 111,
    subject: DemoIds.m,
    teachers: [DemoIds.mue],
    room: DemoIds.r101,
  );
  add(
    3,
    5,
    lesson: 112,
    subject: DemoIds.ge,
    teachers: const [],
    room: DemoIds.r102,
    teacherRefs: [
      el(ElementType.teacher, 0, DemoIds.sch),
      const ElementRef(
        type: ElementType.teacher,
        id: DemoIds.inlineOnlyTeacher,
        orgId: 0,
        inlineName: 'NEU',
        inlineLongName: 'Nina Neumann',
      ),
    ],
    roomRef: el(ElementType.room, DemoIds.r204, DemoIds.r102),
    flags: const {PeriodFlag.irregular},
    substitutionText: 'Raumänderung',
  );
  add(
    3,
    6,
    lesson: 101,
    subject: DemoIds.d,
    teachers: [DemoIds.sch],
    room: DemoIds.r101,
  );

  // Thursday: homework + online link, partially overlapping afternoon
  add(
    4,
    1,
    lesson: 113,
    subject: DemoIds.inf,
    teachers: [DemoIds.fis],
    room: DemoIds.inf1,
    units: 2,
    lessonText: 'Projekt: Sortieralgorithmen',
    onlineLink: 'https://example.org/meet/inf-10a',
    homework: [
      Homework(
        id: 1,
        lessonId: 113,
        startDate: dayAt(4),
        endDate: dayAt(4).add(const Duration(days: 7)),
        text: 'Bubble Sort implementieren',
        remark: 'In Python',
      ),
    ],
  );
  add(
    4,
    3,
    lesson: 114,
    subject: DemoIds.ph,
    teachers: [DemoIds.fis],
    room: DemoIds.ph1,
  );
  add(
    4,
    4,
    lesson: 115,
    subject: DemoIds.bio,
    teachers: [DemoIds.hof],
    room: DemoIds.r204,
    infoText: 'Bitte Laborkittel mitbringen',
  );
  add(
    4,
    5,
    lesson: 104,
    subject: DemoIds.sp,
    teachers: [DemoIds.hof],
    room: DemoIds.th,
    units: 2,
  );
  add(
    4,
    7,
    lesson: 116,
    subject: DemoIds.m,
    teachers: [DemoIds.mue],
    room: DemoIds.r101,
  );
  add(
    4,
    7,
    lesson: 117,
    subject: DemoIds.inf,
    teachers: [DemoIds.fis],
    room: DemoIds.inf1,
    lessonText: 'Förderkurs',
    startMinute: 14 * 60,
    endMinute: 15 * 60 + 10,
  );

  // Friday
  if (!holidayFriday) {
    add(
      5,
      1,
      lesson: 101,
      subject: DemoIds.d,
      teachers: [DemoIds.sch],
      room: DemoIds.r101,
    );
    add(
      5,
      2,
      lesson: 102,
      subject: DemoIds.e,
      teachers: [DemoIds.web],
      room: DemoIds.r102,
    );
    add(
      5,
      3,
      lesson: 118,
      subject: DemoIds.bio,
      teachers: [DemoIds.bec],
      room: DemoIds.r204,
      units: 2,
    );
    add(
      5,
      5,
      lesson: 119,
      subject: DemoIds.m,
      teachers: [DemoIds.mue],
      room: DemoIds.r101,
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// Fakes

/// [NameResolver] over a fixed list of master elements. Looks names up in ALL
/// entries (active or not) and falls back to inline names, then `#id`.
class FakeNameResolver implements NameResolver {
  FakeNameResolver({
    this.elements = demoElements,
    this.holidays = const [],
    this.schoolYears = const [],
    this.timeGrid = demoTimeGrid,
  }) : _byKey = {for (final e in elements) (e.type, e.id): e};

  final List<MasterElement> elements;
  final Map<(ElementType, int), MasterElement> _byKey;

  @override
  final List<Holiday> holidays;
  @override
  final List<SchoolYear> schoolYears;
  @override
  final TimeGrid timeGrid;

  @override
  MasterElement? element(ElementType type, int id) => _byKey[(type, id)];

  @override
  List<MasterElement> elementsOf(ElementType type, {bool onlyActive = true}) =>
      [
        for (final e in elements)
          if (e.type == type && (!onlyActive || e.active)) e,
      ];

  @override
  String shortName(ElementRef ref, {bool original = false}) {
    final id = original ? ref.orgId : ref.id;
    return element(ref.type, id)?.name ??
        (original && ref.orgId != ref.id ? null : ref.inlineName) ??
        '#$id';
  }

  @override
  String longName(ElementRef ref, {bool original = false}) {
    final id = original ? ref.orgId : ref.id;
    final e = element(ref.type, id);
    if (e != null) return e.longName;
    final inline = original && ref.orgId != ref.id
        ? null
        : (ref.inlineLongName ?? ref.inlineName);
    return inline ?? '#$id';
  }
}

/// Cache-free in-memory [TimetableRepository].
///
/// [watchWeek] emits [weekBuilder]'s result immediately and again after each
/// successful [refresh] of that week. Set [refreshError] to make refreshes
/// fail, [watchError] to make the stream fail (no "cached" data).
class FakeTimetableRepository implements TimetableRepository {
  FakeTimetableRepository({
    NameResolver? names,
    List<Period> Function(TimetableTarget target, DateTime weekStart)?
    weekBuilder,
    this.refreshError,
    this.watchError,
    this.latency = Duration.zero,
    DateTime? initialRefreshed,
  }) : names = names ?? demoNames(),
       weekBuilder = weekBuilder ?? _defaultWeek,
       _initialRefreshed =
           initialRefreshed ??
           DateTime.now().subtract(const Duration(minutes: 5));

  final NameResolver names;
  final List<Period> Function(TimetableTarget target, DateTime weekStart)
  weekBuilder;
  Object? refreshError;
  Object? watchError;
  final Duration latency;
  final DateTime _initialRefreshed;

  final _refreshed = <(String, TimetableTarget, DateTime), DateTime>{};
  final _changes =
      StreamController<(String, TimetableTarget, DateTime)>.broadcast();
  int refreshCount = 0;

  static List<Period> _defaultWeek(TimetableTarget _, DateTime weekStart) =>
      buildDemoWeek(
        weekStart,
        holidayFriday: weekStart == _mondayOf(DateTime.now()),
      );

  @override
  Stream<List<Period>> watchWeek(
    Account account,
    TimetableTarget target,
    DateTime weekStart,
  ) async* {
    final key = (account.id, target, weekStart);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (watchError != null) throw watchError!;
    yield weekBuilder(target, weekStart);
    await for (final k in _changes.stream) {
      if (k == key) yield weekBuilder(target, weekStart);
    }
  }

  @override
  Future<void> refresh(
    Account account,
    TimetableTarget target,
    DateTime weekStart,
  ) async {
    refreshCount++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (refreshError != null) throw refreshError!;
    final key = (account.id, target, weekStart);
    _refreshed[key] = DateTime.now();
    _changes.add(key);
  }

  @override
  Stream<NameResolver> watchNames(Account account) => Stream.value(names);

  @override
  DateTime? lastRefreshed(
    Account account,
    TimetableTarget target,
    DateTime weekStart,
  ) => _refreshed[(account.id, target, weekStart)] ?? _initialRefreshed;

  int discoverCount = 0;

  @override
  Future<void> discoverTeachers(
    Account account,
    DateTime weekStart, {
    void Function(int done, int total)? onProgress,
  }) async {
    discoverCount++;
    const total = 3;
    for (var i = 1; i <= total; i++) {
      if (latency > Duration.zero) await Future<void>.delayed(latency);
      onProgress?.call(i, total);
    }
    if (refreshError != null) throw refreshError!;
  }

  void dispose() => _changes.close();
}

/// Resolver with the demo master data and a holiday on Friday of the current
/// week.
FakeNameResolver demoNames({DateTime? now}) =>
    FakeNameResolver(holidays: [demoHoliday(_mondayOf(now ?? DateTime.now()))]);

/// A demo student account in class 10a.
Account demoAccount() => const Account(
  id: 'demo',
  school: School(
    schoolId: 0,
    loginName: 'demo',
    displayName: 'Demo-Gymnasium',
    address: 'Musterstraße 1, 12345 Musterstadt',
    host: 'demo.invalid',
  ),
  username: 'demo',
  anonymous: false,
  displayName: 'Max Mustermann',
  elementType: ElementType.klasse,
  elementId: DemoIds.klasse,
  klassenIds: [DemoIds.klasse],
);

/// Finds the period [id] in [periods] (test helper).
Period? periodById(List<Period> periods, int id) =>
    periods.firstWhereOrNull((p) => p.id == id);
