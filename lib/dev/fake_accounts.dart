/// In-memory fakes for demo mode, UI development and widget tests.
///
/// * [FakeUntisApi]: a handful of German schools, scripted login outcomes and
///   a generated demo week.
/// * [InMemoryAccountRepository]: accounts + active account kept in memory,
///   exposed as streams that emit the current value on listen.
library;

import 'dart:async';

import '../core/absence_details.dart';
import '../core/class_register.dart';
import '../core/info.dart';
import '../core/interfaces.dart';
import '../core/models.dart';

/// Scripted [UntisApi].
///
/// Login rules (checked in order):
/// * password `wrong` -> [UntisException.invalidPassword]
/// * username `locked` -> [UntisException.locked]
/// * username `clock` -> [UntisException.invalidClientTime]
/// * username `offline` -> network error (code 0)
/// * username `2fa` without token `123456` -> [UntisException.twoFactorRequired]
/// * anonymous login at a school whose loginName contains `private` ->
///   [UntisException.noPublicAccess]
/// * username `parent` -> a parent account (no own timetable) with the two
///   [demoChildren]; `parent-nochild` -> a parent account without children;
///   `parent-noreport` -> like `parent`, but the school doesn't allow
///   reporting absences
/// * username `teacher` -> a teacher account (teacher 11, "Anna Müller" in
///   the demo master data) with a demo class register
/// * anything else (e.g. `demo`/`demo`) succeeds.
///
/// Search rules: queries shorter than 3 chars or matching more than
/// [maxResults] schools -> [UntisException.tooManyResults]; query `offline`
/// -> network error.
class FakeUntisApi implements FullUntisApi {
  FakeUntisApi({this.latency = const Duration(milliseconds: 400)});

  /// Artificial delay for every call. Use [Duration.zero] in widget tests.
  final Duration latency;

  static const maxResults = 6;
  static const twoFactorCode = '123456';

  static const schools = <School>[
    School(
      schoolId: 4201,
      loginName: 'goethe-gym-berlin',
      displayName: 'Goethe-Gymnasium',
      address: 'Gasteiner Str. 23, 10717 Berlin',
      host: 'neilo.webuntis.com',
    ),
    School(
      schoolId: 4202,
      loginName: 'humboldt-koeln',
      displayName: 'Humboldt-Gymnasium Köln',
      address: 'Kartäuserwall 40, 50678 Köln',
      host: 'ajax.webuntis.com',
    ),
    School(
      schoolId: 4203,
      loginName: 'einstein-muenchen',
      displayName: 'Albert-Einstein-Gymnasium',
      address: 'Simmernstr. 1, 80804 München',
      host: 'arche.webuntis.com',
    ),
    School(
      schoolId: 4204,
      loginName: 'max-planck-goettingen',
      displayName: 'Max-Planck-Gymnasium',
      address: 'Theaterplatz 10, 37073 Göttingen',
      host: 'herakles.webuntis.com',
    ),
    School(
      schoolId: 4205,
      loginName: 'stadtpark-hamburg',
      displayName: 'Realschule am Stadtpark',
      address: 'Otto-Wels-Str. 2, 22303 Hamburg',
      host: 'kephiso.webuntis.com',
    ),
    School(
      schoolId: 4206,
      loginName: 'bbs-private-hannover',
      displayName: 'Private Berufsschule Hannover',
      address: 'Lavesallee 12, 30169 Hannover',
      host: 'mese.webuntis.com',
    ),
    School(
      schoolId: 4207,
      loginName: 'geschwister-scholl-leipzig',
      displayName: 'Geschwister-Scholl-Gymnasium',
      address: 'Hans-Driesch-Str. 1, 04179 Leipzig',
      host: 'thalia.webuntis.com',
    ),
    School(
      schoolId: 4208,
      loginName: 'gesamtschule-musterstadt',
      displayName: 'Gesamtschule Musterstadt',
      address: 'Schulweg 1, 12345 Musterstadt',
      host: 'demo.webuntis.com',
    ),
  ];

  /// Every login attempt, for test assertions.
  final List<({String school, String username, String? token, bool anonymous})>
  loginCalls = [];

  /// Every search query, for test assertions.
  final List<String> searchCalls = [];

  Future<void> _delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  @override
  Future<List<School>> searchSchools(String query) async {
    searchCalls.add(query);
    await _delay();
    final q = query.trim().toLowerCase();
    if (q == 'offline') {
      throw const UntisException(0, 'Network unreachable');
    }
    if (q.length < 3) {
      throw const UntisException(
        UntisException.tooManyResults,
        'too many results',
      );
    }
    final id = int.tryParse(q);
    final hits = schools.where((s) {
      if (id != null) return s.schoolId == id;
      final hay = '${s.displayName} ${s.address} ${s.loginName}'.toLowerCase();
      return q.split(RegExp(r'\s+')).every(hay.contains);
    }).toList();
    if (hits.length > maxResults) {
      throw const UntisException(
        UntisException.tooManyResults,
        'too many results',
      );
    }
    return hits;
  }

  @override
  Future<LoginResult> login({
    required School school,
    required String username,
    required String passwordOrKey,
    bool anonymous = false,
    String? twoFactorToken,
    bool skipAppSecret = false,
    String? hostOverride,
  }) async {
    loginCalls.add((
      school: school.loginName,
      username: username,
      token: twoFactorToken,
      anonymous: anonymous,
    ));
    await _delay();
    if (anonymous) {
      if (school.loginName.contains('private')) {
        throw const UntisException(
          UntisException.noPublicAccess,
          'no public access',
        );
      }
    } else {
      if (passwordOrKey == 'wrong') {
        throw const UntisException(
          UntisException.invalidPassword,
          'bad credentials',
        );
      }
      switch (username.toLowerCase()) {
        case 'locked':
          throw const UntisException(UntisException.locked, 'locked');
        case 'clock':
          throw const UntisException(
            UntisException.invalidClientTime,
            'invalid client time',
          );
        case 'offline':
          throw const UntisException(0, 'Network unreachable');
        case '2fa' when twoFactorToken != twoFactorCode:
          throw const UntisException(
            UntisException.twoFactorRequired,
            'two factor required',
          );
      }
    }
    final parent = !anonymous && username.toLowerCase().startsWith('parent');
    if (parent) {
      return LoginResult(
        secret: 'FAKESECRET${username.toUpperCase()}',
        displayName: 'Demo Parent',
        elementType: ElementType.unknown,
        elementId: 2001,
        klassenIds: const [],
        rights: const {},
        masterData: demoMasterData,
        children: username.toLowerCase() == 'parent-nochild'
            ? const []
            : demoChildren,
      );
    }
    if (!anonymous && username.toLowerCase() == 'teacher') {
      return LoginResult(
        secret: 'FAKESECRETTEACHER',
        displayName: 'Demo Teacher',
        elementType: ElementType.teacher,
        elementId: demoTeacherId,
        klassenIds: const [],
        rights: const {'R_MY_TIMETABLE'},
        masterData: demoMasterData,
      );
    }
    return LoginResult(
      secret: anonymous ? '' : 'FAKESECRET${username.toUpperCase()}',
      displayName: anonymous ? 'Public timetable' : _displayName(username),
      elementType: anonymous ? ElementType.klasse : ElementType.student,
      elementId: anonymous ? 1 : 1001,
      klassenIds: const [1],
      rights: const {'R_MY_TIMETABLE'},
      masterData: demoMasterData,
    );
  }

  /// The teacher of the demo `teacher` login.
  static const demoTeacherId = 11;

  /// Timetable id of the demo lesson in [unit] (0-based) on [day].
  static int demoPeriodId(DateTime day, int unit) =>
      (day.year * 10000 + day.month * 100 + day.day) * 10 + unit;

  /// Children of the demo `parent` login (made-up names).
  static const demoChildren = [
    AccountChild(id: 1001, displayName: 'Demo Child One', klasseId: 1),
    AccountChild(id: 1002, displayName: 'Demo Child Two', klasseId: 1),
  ];

  static String _displayName(String username) {
    if (username.toLowerCase() == 'demo') return 'Demo Student';
    final parts = username
        .split(RegExp(r'[._\s-]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1));
    return parts.isEmpty ? username : parts.join(' ');
  }

  static final demoMasterData = MasterDataWithLookups(
    lookups: demoLookups,
    timestamp: 1700000000000,
    elements: const [
      MasterElement(
        type: ElementType.klasse,
        id: 1,
        name: '9b',
        longName: 'Klasse 9b',
      ),
      MasterElement(
        type: ElementType.teacher,
        id: 11,
        name: 'MUE',
        longName: 'Anna Müller',
      ),
      MasterElement(
        type: ElementType.teacher,
        id: 12,
        name: 'SCH',
        longName: 'Jonas Schmidt',
      ),
      // Inactive on purpose: names must still be shown.
      MasterElement(
        type: ElementType.teacher,
        id: 13,
        name: 'WEB',
        longName: 'Lea Weber',
        active: false,
      ),
      MasterElement(
        type: ElementType.subject,
        id: 21,
        name: 'M',
        longName: 'Mathematik',
        backColor: 0xFF90CAF9,
      ),
      MasterElement(
        type: ElementType.subject,
        id: 22,
        name: 'D',
        longName: 'Deutsch',
        backColor: 0xFFFFCC80,
      ),
      MasterElement(
        type: ElementType.subject,
        id: 23,
        name: 'E',
        longName: 'Englisch',
        backColor: 0xFFA5D6A7,
      ),
      MasterElement(
        type: ElementType.subject,
        id: 24,
        name: 'PH',
        longName: 'Physik',
        backColor: 0xFFCE93D8,
      ),
      MasterElement(
        type: ElementType.room,
        id: 31,
        name: 'R101',
        longName: 'Raum 101',
      ),
      MasterElement(
        type: ElementType.room,
        id: 32,
        name: 'R204',
        longName: 'Raum 204',
      ),
      MasterElement(
        type: ElementType.room,
        id: 33,
        name: 'PH1',
        longName: 'Physiksaal',
      ),
    ],
    timeGrid: TimeGrid({
      for (var d = 1; d <= 5; d++)
        d: [
          for (var i = 0; i < 6; i++)
            TimeUnit(
              label: '${i + 1}',
              start: 8 * 60 + i * 50,
              end: 8 * 60 + i * 50 + 45,
            ),
        ],
    }),
  );

  @override
  Future<TimetableResponse> timetable({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
    required int masterDataTimestamp,
  }) async {
    await _delay();
    const plan = [
      // (subject, teacher, room) per unit, cycling through the week.
      (21, 11, 31), (22, 12, 31), (23, 13, 32), (24, 11, 33), (21, 11, 31),
      (23, 13, 32),
    ];
    final periods = <Period>[];
    for (
      var day = DateTime(start.year, start.month, start.day);
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      if (day.weekday > 5) continue;
      for (var unit = 0; unit < 5; unit++) {
        final p = plan[(unit + day.weekday) % plan.length];
        final s = day.add(Duration(minutes: 8 * 60 + unit * 50));
        final substituted = day.weekday == 3 && unit == 1;
        // Teachers only see their own lessons.
        if (target.type == ElementType.teacher &&
            target.id != (substituted ? 12 : p.$2)) {
          continue;
        }
        periods.add(
          Period(
            // Unique per date and unit, like real timetable ids.
            id: demoPeriodId(day, unit),
            lessonId: p.$1,
            start: s,
            end: s.add(const Duration(minutes: 45)),
            elements: [
              const ElementRef(type: ElementType.klasse, id: 1, orgId: 1),
              ElementRef(
                type: ElementType.teacher,
                id: substituted ? 12 : p.$2,
                orgId: p.$2,
              ),
              ElementRef(type: ElementType.subject, id: p.$1, orgId: p.$1),
              ElementRef(type: ElementType.room, id: p.$3, orgId: p.$3),
            ],
            flags: {
              if (day.weekday == 5 && unit == 4)
                PeriodFlag.cancelled
              else if (substituted)
                PeriodFlag.irregular
              else
                PeriodFlag.regular,
            },
            substitutionText: substituted ? 'Vertretung' : '',
          ),
        );
      }
    }
    return TimetableResponse(periods, null);
  }

  @override
  Future<List<Message>> messagesOfDay({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime date,
  }) async {
    await _delay();
    return const [
      Message(
        id: 1,
        subject: 'Welcome to the demo',
        bodyHtml: '<p>This is sample data. Add your real school anytime.</p>',
      ),
    ];
  }

  @override
  List<({String method, DateTime at, String json})> get debugLog => const [];

  @override
  Future<void> probeTeacherSources({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime weekStart,
  }) async {}

  // ---- Info center demo data --------------------------------------------

  static const demoLookups = AbsenceLookups(
    reasons: {1: 'Krankheit', 2: 'Arzttermin', 3: 'Familiäre Gründe'},
    statuses: {1: 'entschuldigt', 2: 'nicht entschuldigt', 3: 'offen'},
  );

  static DateTime _day(DateTime d, int plus) =>
      DateTime(d.year, d.month, d.day + plus);

  @override
  Future<List<HomeworkItem>> homework({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
  }) async {
    await _delay();
    const plan = [
      (21, 11, 'Arbeitsblatt Bruchrechnung, Aufgaben 1–6'),
      (22, 12, 'Kapitel 3 lesen und zusammenfassen'),
      (23, 13, 'Vocabulary unit 4, p. 58'),
      (24, 11, 'Versuchsprotokoll fertigstellen'),
    ];
    final items = <HomeworkItem>[];
    for (var i = 0, off = 0; _day(start, off + 2).compareTo(end) <= 0; i++) {
      final p = plan[i % plan.length];
      items.add(
        HomeworkItem(
          id: 500 + i,
          lessonId: p.$1,
          assignedOn: _day(start, off),
          dueOn: _day(start, off + 2),
          text: p.$3,
          remark: i == 1 ? 'Mit Quellenangabe' : '',
          completed: i == 0,
          subjectId: p.$1,
          teacherIds: [p.$2],
          klassenIds: const [1],
        ),
      );
      off += 3;
    }
    return items;
  }

  @override
  Future<List<ExamItem>> exams({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
  }) async {
    await _delay();
    const plan = [
      (21, 'Klassenarbeit', 'Bruchrechnung', 31),
      (23, 'Test', 'Unit 3 & 4', 32),
      (24, 'Klassenarbeit', 'Mechanik', 33),
    ];
    final items = <ExamItem>[];
    for (var i = 0, off = 4; _day(start, off).compareTo(end) <= 0; i++) {
      final p = plan[i % plan.length];
      final s = _day(start, off).add(const Duration(hours: 8));
      items.add(
        ExamItem(
          id: 700 + i,
          start: s,
          end: s.add(const Duration(minutes: 90)),
          examType: p.$2,
          name: p.$3,
          text: i == 0 ? 'Taschenrechner erlaubt' : '',
          subjectId: p.$1,
          klassenIds: const [1],
          roomIds: [p.$4],
          teacherIds: const [11],
        ),
      );
      off += 9;
    }
    return items;
  }

  @override
  Future<List<RawAbsence>> rawAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
    int? studentId,
  }) async {
    await _delay();
    final items = <RawAbsence>[];
    for (var i = 0, off = 2; _day(start, off).compareTo(end) <= 0; i++) {
      final s = _day(
        start,
        off,
      ).add(Duration(hours: 8, minutes: i.isEven ? 0 : 50));
      items.add(
        RawAbsence(
          id: 900 + i,
          start: s,
          end: s.add(Duration(minutes: i.isEven ? 45 * 6 : 45)),
          excused: i != 1,
          reasonId: 1 + i % 3,
          text: i == 2 ? 'Bescheinigung liegt vor' : '',
          excuseStatusId: i == 1 ? 3 : 1,
        ),
      );
      off += 11;
    }
    for (final r in reported) {
      if (studentId != null && r.studentId != studentId) continue;
      if (r.absence.start.isBefore(start) ||
          !r.absence.start.isBefore(_day(end, 1))) {
        continue;
      }
      items.add(r.absence);
    }
    items.sort((a, b) => a.start.compareTo(b.start));
    return items.reversed.toList();
  }

  var _reportedIds = 0;

  /// Absences reported via [reportAbsence] (demo mode keeps them in memory).
  final reported = <({int studentId, RawAbsence absence})>[];

  /// When set, [reportAbsence] throws it (tests).
  UntisException? reportError;

  static bool _mayReport(UntisCredentials auth) =>
      auth.username.toLowerCase() != 'parent-noreport';

  @override
  Future<AbsenceReportOptions> absenceReportOptions({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int studentId,
  }) async {
    await _delay();
    return AbsenceReportOptions(
      reasons: [
        for (final e in demoLookups.reasons.entries)
          AbsenceReason(id: e.key, name: e.value),
      ],
      defaultReasonId: 1,
      allowed: _mayReport(auth),
    );
  }

  @override
  Future<void> reportAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required AbsenceReport report,
  }) async {
    await _delay();
    if (reportError case final e?) throw e;
    if (!_mayReport(auth)) {
      throw const UntisException(
        UntisException.noRight,
        "Your school doesn't allow reporting absences for this account.",
      );
    }
    if (!report.end.isAfter(report.start)) {
      throw const UntisException(-1, 'The end must be after the start.');
    }
    final clash = reported.any(
      (r) =>
          r.studentId == report.studentId &&
          r.absence.start.isBefore(report.end) &&
          report.start.isBefore(r.absence.end),
    );
    if (clash) {
      throw const UntisException(
        -1,
        'Not saved: it overlaps an existing absence or entry.',
      );
    }
    reported.add((
      studentId: report.studentId,
      absence: RawAbsence(
        id: 5000 + _reportedIds++,
        start: report.start,
        end: report.end,
        excused: false,
        reasonId: report.reasonId,
        text: report.text,
        excuseStatusId: 3,
      ),
    ));
  }

  /// Demo: absences reported in this session can be deleted; the generated
  /// ones have no classreg record.
  @override
  Future<List<AbsenceRecord>> absenceRecords({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int studentId,
    required DateTime start,
    required DateTime end,
  }) async {
    await _delay();
    final to = DateTime(end.year, end.month, end.day + 1);
    return [
      for (final r in reported)
        if (r.studentId == studentId &&
            r.absence.start.isBefore(to) &&
            !r.absence.end.isBefore(
              DateTime(start.year, start.month, start.day),
            ))
          AbsenceRecord(
            id: r.absence.id,
            start: r.absence.start,
            end: r.absence.end,
            canEdit: true,
            createdUser: auth.username,
            updatedUser: auth.username,
          ),
    ];
  }

  @override
  Future<void> deleteAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> ids,
  }) async {
    await _delay();
    reported.removeWhere((r) => ids.contains(r.absence.id));
  }

  // ---- Class register demo (teacher login) ------------------------------

  /// Made-up pupils of demo class 1.
  static const demoStudents = [
    ClassRegStudent(id: 501, firstName: 'Lena', lastName: 'Bauer', klasseId: 1),
    ClassRegStudent(
      id: 502,
      firstName: 'Jonas',
      lastName: 'Fischer',
      klasseId: 1,
    ),
    ClassRegStudent(
      id: 503,
      firstName: 'Mia',
      lastName: 'Hofmann',
      klasseId: 1,
    ),
    ClassRegStudent(id: 504, firstName: 'Paul', lastName: 'Koch', klasseId: 1),
    ClassRegStudent(
      id: 505,
      firstName: 'Emma',
      lastName: 'Richter',
      klasseId: 1,
    ),
    ClassRegStudent(id: 506, firstName: 'Ben', lastName: 'Wagner', klasseId: 1),
  ];

  /// Demo register state by timetable id. Lessons not in [registerTopics] /
  /// [registerChecked] are open, except every other one, which starts filled
  /// in so the "open lessons" list is not all of them.
  final registerTopics = <int, String>{};
  final registerChecked = <int>{};
  final registerAbsences = <int, List<ClassRegAbsence>>{};
  var _nextAbsenceId = 9000;

  bool _seededDone(int ttId) => ttId % 3 == 0;

  @override
  Future<PeriodRegisterData> periodData({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> ttIds,
  }) async {
    await _delay();
    return PeriodRegisterData(
      periods: {
        for (final id in ttIds)
          id: PeriodRegister(
            ttId: id,
            absenceChecked: registerChecked.contains(id) || _seededDone(id),
            studentIds: [for (final s in demoStudents) s.id],
            absences: [...?registerAbsences[id]],
            topic: registerTopics[id] ?? (_seededDone(id) ? 'Revision' : ''),
          ),
      },
      students: {for (final s in demoStudents) s.id: s},
    );
  }

  @override
  Future<void> submitLessonTopic({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    required String topic,
  }) async {
    await _delay();
    registerTopics[ttId] = topic;
  }

  @override
  Future<void> createAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    required int studentId,
    required DateTime start,
    required DateTime end,
  }) async {
    await _delay();
    (registerAbsences[ttId] ??= []).add(
      ClassRegAbsence(
        id: _nextAbsenceId++,
        studentId: studentId,
        start: start,
        end: end,
      ),
    );
  }

  @override
  Future<void> deleteAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int absenceId,
  }) async {
    await _delay();
    for (final list in registerAbsences.values) {
      list.removeWhere((a) => a.id == absenceId);
    }
  }

  @override
  Future<void> submitAbsencesChecked({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> ttIds,
  }) async {
    await _delay();
    registerChecked.addAll(ttIds);
  }

  @override
  Future<AbsenceLookups> absenceLookups({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) async {
    await _delay();
    return demoLookups;
  }

  @override
  Future<List<AbsenceItem>> absences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
    int? studentId,
  }) async => [
    for (final a in await rawAbsences(
      host: host,
      school: school,
      auth: auth,
      start: start,
      end: end,
      studentId: studentId,
    ))
      a.resolve(demoLookups),
  ];

  @override
  Future<List<OfficeHourItem>> officeHours({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int klasseId,
    required DateTime start,
  }) async {
    await _delay();
    final monday = _day(start, -(start.weekday - 1));
    OfficeHourItem at(int id, int day, int h, String t, String r, String mail) {
      final s = _day(monday, day).add(Duration(hours: h));
      return OfficeHourItem(
        id: id,
        start: s,
        end: s.add(const Duration(minutes: 45)),
        teacherName: t,
        rooms: r,
        email: mail,
        registrationPossible: id != 3,
        registered: id == 2,
      );
    }

    return [
      at(1, 0, 10, 'Anna Müller', 'R101', 'a.mueller@example.invalid'),
      at(2, 2, 11, 'Jonas Schmidt', 'R204', 'j.schmidt@example.invalid'),
      at(3, 3, 13, 'Lea Weber', 'Lehrerzimmer', ''),
    ];
  }

  @override
  Future<List<InboxMessage>> inbox({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) async {
    await _delay();
    final now = DateTime.now();
    return [
      for (final m in _demoMessages)
        InboxMessage(
          id: m.id,
          subject: m.subject,
          preview: m.preview,
          sender: m.sender,
          sentAt: now.subtract(m.ago),
          isRead: m.id != 1,
          hasAttachments: m.id == 2,
        ),
    ];
  }

  @override
  Future<InboxMessageDetail> inboxMessage({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int id,
  }) async {
    await _delay();
    final m = _demoMessages.where((m) => m.id == id).firstOrNull;
    if (m == null) {
      throw const UntisException(-1, 'NOT_FOUND');
    }
    return InboxMessageDetail(
      id: m.id,
      subject: m.subject,
      bodyHtml: '<p>${m.preview}</p><p>Viele Grüße<br>${m.sender}</p>',
      sender: m.sender,
      sentAt: DateTime.now().subtract(m.ago),
      attachments: m.id == 2
          ? const [
              (
                name: 'Elternbrief.pdf',
                url: 'https://example.invalid/elternbrief.pdf',
              ),
            ]
          : const [],
    );
  }

  static const _demoMessages = [
    (
      id: 1,
      subject: 'Wandertag am Freitag',
      preview: 'Bitte denkt an festes Schuhwerk und Verpflegung.',
      sender: 'Anna Müller',
      ago: Duration(hours: 3),
    ),
    (
      id: 2,
      subject: 'Elternabend',
      preview: 'Die Einladung zum Elternabend findet ihr im Anhang.',
      sender: 'Sekretariat',
      ago: Duration(days: 2),
    ),
    (
      id: 3,
      subject: 'Physik-AG',
      preview: 'Die AG beginnt ab nächster Woche um 14:00 Uhr.',
      sender: 'Jonas Schmidt',
      ago: Duration(days: 9),
    ),
  ];
}

/// [AccountRepository] kept in memory. Streams are broadcast and emit the
/// current value to every new listener.
class InMemoryAccountRepository implements AccountRepository {
  InMemoryAccountRepository({
    List<Account> initial = const [],
    String? activeId,
  }) : _accounts = [...initial],
       _activeId = activeId ?? (initial.isEmpty ? null : initial.first.id);

  final List<Account> _accounts;
  String? _activeId;
  final Map<String, String> secrets = {};
  final Map<String, MasterData> masterData = {};

  final _accountsCtrl = StreamController<List<Account>>.broadcast();
  final _activeCtrl = StreamController<Account?>.broadcast();

  List<Account> get accounts => List.unmodifiable(_accounts);
  Account? get active => _accounts.where((a) => a.id == _activeId).firstOrNull;

  void _emit() {
    _accountsCtrl.add(accounts);
    _activeCtrl.add(active);
  }

  @override
  Stream<List<Account>> watchAccounts() async* {
    yield accounts;
    yield* _accountsCtrl.stream;
  }

  @override
  Stream<Account?> watchActive() async* {
    yield active;
    yield* _activeCtrl.stream;
  }

  @override
  Future<void> setActive(String accountId) async {
    if (_accounts.any((a) => a.id == accountId)) {
      _activeId = accountId;
      _emit();
    }
  }

  @override
  Future<Account> add(Account account, String secret, MasterData data) async {
    _accounts.removeWhere((a) => a.id == account.id);
    _accounts.add(account);
    secrets[account.id] = secret;
    masterData[account.id] = data;
    _activeId = account.id;
    _emit();
    return account;
  }

  @override
  Future<void> update(Account account) async {
    final i = _accounts.indexWhere((a) => a.id == account.id);
    if (i < 0) return;
    _accounts[i] = account;
    _emit();
  }

  @override
  Future<void> delete(String accountId) async {
    _accounts.removeWhere((a) => a.id == accountId);
    secrets.remove(accountId);
    masterData.remove(accountId);
    if (_activeId == accountId) {
      _activeId = _accounts.isEmpty ? null : _accounts.first.id;
    }
    _emit();
  }

  @override
  Future<UntisCredentials> credentials(String accountId) async {
    final account = _accounts.firstWhere((a) => a.id == accountId);
    if (account.anonymous) return const UntisCredentials.anonymous();
    return UntisCredentials.user(account.username, secrets[accountId] ?? '');
  }

  Future<void> dispose() async {
    await _accountsCtrl.close();
    await _activeCtrl.close();
  }
}
