/// In-memory fakes for demo mode, UI development and widget tests.
///
/// * [FakeUntisApi]: a handful of German schools, scripted login outcomes and
///   a generated demo week.
/// * [InMemoryAccountRepository]: accounts + active account kept in memory,
///   exposed as streams that emit the current value on listen.
library;

import 'dart:async';
import 'dart:typed_data';

import '../core/absence_details.dart';
import '../core/absence_summary.dart';
import '../core/class_register.dart';
import '../core/info.dart';
import '../core/interfaces.dart';
import '../core/models.dart';
import '../core/pupil_photos.dart';
import '../core/teacher_tools.dart';
import 'fake_pupil_photos.dart';

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
class FakeUntisApi
    implements FullUntisApi, TeacherToolsApi, PupilPhotoApi, ClassAbsencesApi {
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
      // Teacher demo: the on-call "Aufsichtsstunde".
      MasterElement(
        type: ElementType.subject,
        id: 25,
        name: 'A',
        longName: 'Aufsichtsstunde',
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
      // Not used by the demo week: free for room booking.
      MasterElement(
        type: ElementType.room,
        id: 34,
        name: 'EDV1',
        longName: 'Informatikraum',
      ),
      MasterElement(
        type: ElementType.room,
        id: 35,
        name: 'R110',
        longName: 'Raum 110',
      ),
      MasterElement(
        type: ElementType.room,
        id: 36,
        name: 'TH',
        longName: 'Turnhalle',
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
    const plan = demoPlan;
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
        // A substituted lesson stays in the original teacher's timetable
        // with their entry struck through (orgId = them, id = substitute).
        if (target.type == ElementType.teacher &&
            target.id != (substituted ? 12 : p.$2) &&
            target.id != p.$2) {
          continue;
        }
        final ttId = demoPeriodId(day, unit);
        if (target.type == ElementType.teacher) {
          _issuedTeacherIds.add(ttId);
          if (substituted) _substitutedIds.add(ttId);
        }
        final room = roomChanges[ttId] ?? p.$3;
        final roomRemoved = removedRooms.contains(ttId);
        final added = addedRooms[ttId] ?? const <int>[];
        final exam = _examAt(s, s.add(const Duration(minutes: 45)));
        periods.add(
          Period(
            // Unique per date and unit, like real timetable ids.
            id: ttId,
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
              ElementRef(
                type: ElementType.room,
                id: roomRemoved ? 0 : room,
                orgId: p.$3,
              ),
              for (final r in added)
                ElementRef(type: ElementType.room, id: r, orgId: 0),
            ],
            flags: {
              if (day.weekday == 5 && unit == 4)
                PeriodFlag.cancelled
              else if (substituted ||
                  room != p.$3 ||
                  roomRemoved ||
                  added.isNotEmpty)
                PeriodFlag.irregular
              else
                PeriodFlag.regular,
              if (exam != null) PeriodFlag.exam,
            },
            exam: exam == null
                ? null
                : Exam(
                    id: exam.id,
                    type: exam.examType,
                    name: exam.name,
                    text: exam.text,
                  ),
            substitutionText: substituted ? 'Vertretung' : '',
            infoText: periodInfos[ttId] ?? '',
          ),
        );
      }
      periods.addAll(_demoExtras(day, target));
    }
    // Room bookings without a lesson: in the booking teacher's and the
    // room's timetable, as a period without class.
    for (final b in roomBookings) {
      if (b.start.isBefore(start) ||
          !b.start.isBefore(DateTime(end.year, end.month, end.day + 1))) {
        continue;
      }
      final mine =
          (target.type == ElementType.teacher && target.id == b.teacherId) ||
          (target.type == ElementType.room && target.id == b.roomId);
      if (!mine) continue;
      periods.add(
        Period(
          id: b.id,
          lessonId: 0,
          start: b.start,
          end: b.end,
          elements: [
            if (b.teacherId != null)
              ElementRef(
                type: ElementType.teacher,
                id: b.teacherId!,
                orgId: b.teacherId!,
              ),
            ElementRef(type: ElementType.room, id: b.roomId, orgId: b.roomId),
          ],
          flags: const {PeriodFlag.regular},
          lessonText: b.text.isEmpty ? 'Room booking' : b.text,
        ),
      );
    }
    return TimetableResponse(periods, null);
  }

  /// Subject of the demo "Aufsichtsstunde" (on-call lesson, short "A").
  static const demoOnCallSubjectId = 25;

  /// Teacher demo extras on [day] that [target] sees: a colleague's
  /// maths lesson in class 9b on Thursdays (WEB teaches it; the demo
  /// teacher MUE is assigned to 9b maths, so it shows faded in her
  /// timetable), a Gangaufsicht 07:40–07:50 before the first lesson on
  /// Mondays and Thursdays, a room booking without class (EDV1) on Tuesdays
  /// and an Aufsichtsstunde (no class, no room, a substitution) on Fridays.
  List<Period> _demoExtras(DateTime day, TimetableTarget target) {
    DateTime at(int h, int m) => DateTime(day.year, day.month, day.day, h, m);
    ElementRef el(ElementType t, int id, [int? orgId]) =>
        ElementRef(type: t, id: id, orgId: orgId ?? id);
    final extras = <Period>[
      if (day.weekday == DateTime.thursday)
        Period(
          id: demoPeriodId(day, 5),
          lessonId: 21,
          start: at(12, 10),
          end: at(12, 55),
          elements: [
            el(ElementType.klasse, 1),
            el(ElementType.teacher, 13),
            el(ElementType.subject, 21),
            el(ElementType.room, 31),
          ],
          flags: const {PeriodFlag.regular},
          lessonText: 'Förderunterricht',
        ),
      if (day.weekday == DateTime.monday || day.weekday == DateTime.thursday)
        Period(
          id: demoPeriodId(day, 7),
          lessonId: 0,
          start: at(7, 40),
          end: at(7, 50),
          elements: [el(ElementType.teacher, demoTeacherId)],
          flags: const {PeriodFlag.breakSupervision},
          lessonText: 'Gangaufsicht',
        ),
      if (day.weekday == DateTime.tuesday)
        Period(
          id: demoPeriodId(day, 6),
          lessonId: 0,
          start: at(12, 10),
          end: at(12, 55),
          elements: [
            el(ElementType.teacher, demoTeacherId),
            el(ElementType.room, 34),
          ],
          flags: const {PeriodFlag.regular},
          lessonText: 'Raumreservierung',
        ),
      if (day.weekday == DateTime.friday)
        Period(
          id: demoPeriodId(day, 8),
          lessonId: 0,
          start: at(8, 0),
          end: at(8, 45),
          elements: [
            el(ElementType.teacher, demoTeacherId, 0),
            el(ElementType.subject, demoOnCallSubjectId),
          ],
          flags: const {PeriodFlag.irregular},
          substitutionText: 'Aufsichtsstunde',
        ),
    ];
    bool has(Period p, ElementType t, int id) =>
        p.elements.any((e) => e.type == t && (e.id == id || e.orgId == id));
    return [
      for (final p in extras)
        if (switch (target.type) {
          ElementType.teacher => has(p, ElementType.teacher, target.id),
          ElementType.room => has(p, ElementType.room, target.id),
          _ => p.hasClass,
        })
          p,
    ];
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

  /// Demo accounts can't sync (the sync server checks the token with
  /// WebUntis).
  @override
  Future<String> restAuthToken({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) async =>
      throw const UntisException(0, 'Demo accounts have no WebUntis token.');

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
    items.addAll(
      createdExams.where((e) => e.end.isAfter(start) && e.start.isBefore(end)),
    );
    items.sort((a, b) => a.start.compareTo(b.start));
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

  /// Demo pupils without a photo (shown with initials).
  static const demoStudentsWithoutPhoto = {506};

  /// How often [pupilPhoto] was asked (tests check the session cache).
  int pupilPhotoCalls = 0;

  /// Generated placeholder portraits; [demoStudentsWithoutPhoto] have none.
  @override
  Future<Uint8List?> pupilPhoto({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int studentId,
    String? imageUrl,
  }) async {
    pupilPhotoCalls++;
    await _delay();
    if (demoStudentsWithoutPhoto.contains(studentId)) return null;
    if (!demoStudents.any((s) => s.id == studentId)) return null;
    return placeholderPortrait(studentId);
  }

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
  /// [registerChecked] are open, except that lessons before today start
  /// with a mix (see [_seededChecked] / [_seededTopic]) so the class
  /// register overview shows done, half-done and open lessons.
  final registerTopics = <int, String>{};
  final registerChecked = <int>{};
  final registerAbsences = <int, List<ClassRegAbsence>>{};
  var _nextAbsenceId = 9000;

  /// Lessons before today (ids are yyyymmddN, see [demoPeriodId]):
  /// ttId % 4 == 0 is done, 1 has only the attendance check, 2 only the
  /// topic, 3 nothing.
  bool _seededPast(int ttId) {
    final now = DateTime.now();
    return ttId ~/ 10 < now.year * 10000 + now.month * 100 + now.day;
  }

  bool _seededChecked(int ttId) => _seededPast(ttId) && ttId % 4 <= 1;
  bool _seededTopic(int ttId) =>
      _seededPast(ttId) && (ttId % 4 == 0 || ttId % 4 == 2);

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
            absenceChecked:
                registerChecked.contains(id) ||
                _seededChecked(id) ||
                (_isDemoSubstitution(id) && _seededPast(id)),
            studentIds: [for (final s in demoStudents) s.id],
            absences: [..._absencesOf(id)],
            topic:
                registerTopics[id] ??
                (_isDemoSubstitution(id) && _seededPast(id)
                    ? 'Substitute: worksheet on percentages'
                    : (_seededTopic(id) ? _demoTopic(id) : '')),
            events: _demoEvents(id),
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

  /// Demo lessons on Wednesdays in unit 1 are held by teacher 12 instead of
  /// the planned teacher (see [timetable]); [periodData] seeds what "the
  /// substitute" entered there.
  bool _isDemoSubstitution(int ttId) => _substitutedIds.contains(ttId);

  /// Ids of teacher lessons this fake handed out (only those get seeded
  /// absences / substitute entries, so tests with their own timetables see
  /// a clean register).
  final _issuedTeacherIds = <int>{};
  final _substitutedIds = <int>{};

  /// The day of a [demoPeriodId], null for other ids (e.g. in tests).
  static DateTime? _demoDay(int ttId) {
    final ymd = ttId ~/ 10;
    if (ymd < 20000101 || ymd > 29991231) return null;
    return DateTime(ymd ~/ 10000, (ymd ~/ 100) % 100, ymd % 100);
  }

  /// Absences of a lesson: seeded ones for past demo lessons (a few per
  /// week, some late, a mix of excused / unexcused / open), materialized on
  /// first read so they can be deleted like created ones.
  List<ClassRegAbsence> _absencesOf(int ttId, {bool seed = false}) =>
      registerAbsences.putIfAbsent(
        ttId,
        () => seed || _issuedTeacherIds.contains(ttId)
            ? _seededAbsences(ttId)
            : [],
      );

  List<ClassRegAbsence> _seededAbsences(int ttId) {
    final day = _demoDay(ttId);
    if (day == null || !_seededPast(ttId)) return [];
    final unit = ttId % 10;
    final start = day.add(Duration(minutes: 8 * 60 + unit * 50));
    final end = start.add(const Duration(minutes: 45));
    final ymd = ttId ~/ 10;
    final out = <ClassRegAbsence>[];
    final h = (ymd * 7 + unit * 3) % 11;
    if (h < 3) {
      out.add(
        ClassRegAbsence(
          id: ttId * 10 + 1,
          studentId: demoStudents[(ymd + unit) % demoStudents.length].id,
          start: start,
          end: h == 0 ? start.add(const Duration(minutes: 10)) : end,
          excused: ymd % 3 == 0,
          excuseStatusId: ymd % 3 == 1 ? 2 : null,
          excuseStatus: ymd % 3 == 1 ? 'nicht entschuldigt' : '',
          text: h == 0 ? 'Bus late' : '',
        ),
      );
    }
    // Every ninth day Paul Koch is away all day (excused).
    if (ymd % 9 == 0) {
      out.add(
        ClassRegAbsence(
          id: ttId * 10 + 2,
          studentId: 504,
          start: start,
          end: end,
          excused: true,
          excuseStatusId: 1,
          excuseStatus: 'entschuldigt',
          reasonId: 1,
        ),
      );
    }
    return out;
  }

  /// All-subjects scope of the absence summary: the absences of every demo
  /// lesson of class 1 in the range (all teachers).
  @override
  Future<List<ClassAbsenceRecord>> classAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int klasseId,
    required DateTime start,
    required DateTime end,
  }) async {
    await _delay();
    if (klasseId != 1) return const [];
    final names = {for (final s in demoStudents) s.id: s.displayName};
    final out = <ClassAbsenceRecord>[];
    for (
      var day = DateTime(start.year, start.month, start.day);
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      if (day.weekday > 5) continue;
      for (var unit = 0; unit < 5; unit++) {
        if (day.weekday == 5 && unit == 4) continue; // cancelled
        for (final a in _absencesOf(demoPeriodId(day, unit), seed: true)) {
          out.add(
            ClassAbsenceRecord(
              id: a.id,
              studentId: a.studentId,
              studentName: names[a.studentId] ?? '',
              klasseId: 1,
              start: a.start,
              end: a.end,
              state: a.excused
                  ? ExcuseState.excused
                  : a.excuseStatusId != null
                  ? ExcuseState.unexcused
                  : ExcuseState.open,
              reason: a.reasonId == null
                  ? ''
                  : (demoLookups.reasons[a.reasonId] ?? ''),
              text: a.text,
              late: a.end.difference(a.start).inMinutes < 40,
            ),
          );
        }
      }
    }
    return out;
  }

  /// Class register entries created in the demo, by timetable id.
  final registerEvents = <int, List<ClassRegEvent>>{};
  var _nextEventId = 7000;

  static const demoEventReasons = {
    1: 'Hausübung fehlt',
    2: 'Material vergessen',
    3: 'Störung des Unterrichts',
    4: 'Lob',
  };

  static const _demoTopics = [
    'Revision',
    'Fractions: adding and subtracting',
    'Exercises p. 42, no. 3–7',
    'Linear equations',
    'Test preparation',
    'Word problems',
    'Percentages',
  ];

  /// Seeded topics vary by date so "Previous topics" is worth a look.
  static String _demoTopic(int ttId) =>
      _demoTopics[(ttId ~/ 10) % _demoTopics.length];

  /// Created entries plus a seeded one in about every fifth past lesson
  /// (no date of its own, like the parser may see on a real server).
  List<ClassRegEvent> _demoEvents(int ttId) => [
    if (_seededPast(ttId) && (ttId ~/ 10) % 5 == ttId % 10)
      ClassRegEvent(
        id: ttId,
        ttId: ttId,
        studentId: demoStudents[ttId % demoStudents.length].id,
        reasonId: 1 + ttId % 4,
        text: ttId % 2 == 0 ? 'Second time this month' : '',
      ),
    ...?registerEvents[ttId],
  ];

  @override
  Future<Map<int, String>> eventReasons({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) async {
    await _delay();
    return demoEventReasons;
  }

  @override
  Future<void> createClassRegEvent({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    int? studentId,
    int? eventReasonId,
    required String text,
  }) async {
    await _delay();
    (registerEvents[ttId] ??= []).add(
      ClassRegEvent(
        id: _nextEventId++,
        ttId: ttId,
        studentId: studentId,
        reasonId: eventReasonId,
        text: text,
        date: DateTime.now(),
      ),
    );
  }

  // ---- Room booking and exams demo (teacher login) ----------------------

  /// (subject, teacher, room) per unit of the demo week, cycling through it.
  static const demoPlan = [
    (21, 11, 31),
    (22, 12, 31),
    (23, 13, 32),
    (24, 11, 33),
    (21, 11, 31),
    (23, 13, 32),
  ];

  /// Rooms of the demo school.
  static const demoRoomIds = [31, 32, 33, 34, 35, 36];

  /// Room changes made in the demo: new room by timetable id.
  final roomChanges = <int, int>{};

  /// Rooms added to a lesson in the demo (orgRoomId 0), by timetable id.
  final addedRooms = <int, List<int>>{};

  /// Timetable ids whose planned (or changed) room was removed (roomId 0).
  final removedRooms = <int>{};

  /// Room bookings without a lesson made in the demo.
  final roomBookings =
      <
        ({
          int id,
          int roomId,
          DateTime start,
          DateTime end,
          int? teacherId,
          String text,
        })
      >[];
  var _nextBookingId = 1000000;

  /// Lesson info ("Info zur Stunde") set with submitPeriodInfo, by period.
  final periodInfos = <int, String>{};

  /// Exams created in the demo.
  final createdExams = <ExamItem>[];
  var _nextExamId = 8000;

  /// Every submitRoomChange / createExam call, for test assertions.
  final roomChangeCalls =
      <({List<int> periodIds, int orgRoomId, int roomId})>[];
  final createExamCalls = <NewExam>[];
  final roomBookingCalls = <RoomBookingRequest>[];

  ExamItem? _examAt(DateTime start, DateTime end) {
    for (final e in createdExams) {
      if (e.start.isBefore(end) && e.end.isAfter(start)) return e;
    }
    return null;
  }

  /// Rooms the demo week uses from [start] to [end] (one class, so one
  /// lesson per unit), with room changes applied; [except] are left out.
  Set<int> _busyRooms(
    DateTime start,
    DateTime end, {
    Set<int> except = const {},
  }) {
    final busy = <int>{};
    for (
      var day = DateTime(start.year, start.month, start.day);
      day.isBefore(end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      if (day.weekday > 5) continue;
      for (var unit = 0; unit < 5; unit++) {
        final s = DateTime(day.year, day.month, day.day, 8, unit * 50);
        final e = s.add(const Duration(minutes: 45));
        if (!s.isBefore(end) || !e.isAfter(start)) continue;
        final id = demoPeriodId(day, unit);
        if (except.contains(id)) continue;
        if (day.weekday == 5 && unit == 4) continue; // cancelled
        if (!removedRooms.contains(id)) {
          busy.add(roomChanges[id] ?? demoPlan[(unit + day.weekday) % 6].$3);
        }
        busy.addAll(addedRooms[id] ?? const []);
      }
    }
    for (final b in roomBookings) {
      if (b.start.isBefore(end) && b.end.isAfter(start)) busy.add(b.roomId);
    }
    // The gym is booked on Mondays.
    if (start.weekday == DateTime.monday) busy.add(36);
    return busy;
  }

  static DateTime _demoStart(int ttId) {
    final d = ttId ~/ 10;
    return DateTime(d ~/ 10000, d ~/ 100 % 100, d % 100, 8, (ttId % 10) * 50);
  }

  @override
  Future<FreeRooms> roomChangeData({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> periodIds,
  }) async {
    await _delay();
    if (periodIds.isEmpty) return const FreeRooms();
    final starts = [for (final id in periodIds) _demoStart(id)]..sort();
    final start = starts.first;
    final end = starts.last.add(const Duration(minutes: 45));
    // The lesson's own room counts as busy (it is in use by this lesson).
    final own = {for (final id in periodIds) ..._currentRooms(id)};
    final busy = {..._busyRooms(start, end, except: periodIds.toSet()), ...own};
    return FreeRooms(
      roomIds: [
        for (final r in demoRoomIds)
          if (!busy.contains(r)) r,
      ],
    );
  }

  @override
  Future<FreeRooms> availableRooms({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
  }) async {
    await _delay();
    final busy = _busyRooms(start, end);
    return FreeRooms(
      roomIds: [
        for (final r in demoRoomIds)
          if (!busy.contains(r)) r,
      ],
    );
  }

  @override
  Future<bool> submitPeriodInfo({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int periodId,
    required String text,
  }) async {
    await _delay();
    if (text.isEmpty) {
      periodInfos.remove(periodId);
    } else {
      periodInfos[periodId] = text;
    }
    return true;
  }

  @override
  Future<RoomChangeResult> submitRoomChange({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> periodIds,
    required int orgRoomId,
    required int roomId,
  }) async {
    await _delay();
    roomChangeCalls.add((
      periodIds: periodIds,
      orgRoomId: orgRoomId,
      roomId: roomId,
    ));
    // Like the real server (as far as known): orgRoomId is a room the
    // lesson has now (0: add roomId), roomId 0 removes orgRoomId.
    if (roomId != 0 && !demoRoomIds.contains(roomId)) {
      return const RoomChangeResult(
        errors: [TeacherToolError(code: 'ROOM_UNKNOWN', title: 'Unknown room')],
      );
    }
    if (orgRoomId == 0 && roomId == 0) {
      return const RoomChangeResult(
        errors: [TeacherToolError(code: 'NO_ROOM', title: 'No room given')],
      );
    }
    for (final id in periodIds) {
      if (orgRoomId != 0 && !_currentRooms(id).contains(orgRoomId)) {
        return const RoomChangeResult(
          errors: [
            TeacherToolError(
              code: 'ROOM_NOT_IN_PERIOD',
              title: 'The room to replace is not in this lesson',
            ),
          ],
        );
      }
      if (roomId == 0) continue;
      if (orgRoomId != roomId && _currentRooms(id).contains(roomId)) {
        return const RoomChangeResult(
          errors: [
            TeacherToolError(
              code: 'ROOM_ALREADY_IN_PERIOD',
              title: 'The lesson already has this room',
            ),
          ],
        );
      }
      final busy = _busyRooms(
        _demoStart(id),
        _demoStart(id).add(const Duration(minutes: 45)),
        except: {id},
      );
      if (roomId != orgRoomId && busy.contains(roomId)) {
        return const RoomChangeResult(
          errors: [
            TeacherToolError(
              code: 'ROOM_OCCUPIED',
              title: 'Room is occupied',
              details: 'Another lesson uses this room.',
            ),
          ],
        );
      }
    }
    for (final id in periodIds) {
      final planned = demoPlan[(id % 10 + _demoStart(id).weekday) % 6].$3;
      final main = removedRooms.contains(id) ? 0 : (roomChanges[id] ?? planned);
      final added = addedRooms[id] ?? <int>[];
      void setMain(int r) {
        if (r == 0) {
          removedRooms.add(id);
          roomChanges.remove(id);
          return;
        }
        removedRooms.remove(id);
        if (r == planned) {
          roomChanges.remove(id);
        } else {
          roomChanges[id] = r;
        }
      }

      if (orgRoomId == 0) {
        // Adding the removed planned room back puts it in its slot.
        if (main == 0) {
          setMain(roomId);
        } else {
          added.add(roomId);
        }
      } else if (orgRoomId == main) {
        // The main room goes: an added room moves into its place.
        if (roomId == 0 && added.isNotEmpty) {
          setMain(added.removeAt(0));
        } else {
          setMain(roomId);
        }
      } else {
        final k = added.indexOf(orgRoomId);
        if (roomId == 0) {
          added.removeAt(k);
        } else {
          added[k] = roomId;
        }
      }
      if (added.isEmpty) {
        addedRooms.remove(id);
      } else {
        addedRooms[id] = added;
      }
    }
    return RoomChangeResult(periodCount: periodIds.length);
  }

  /// The rooms period [ttId] has now (changes applied).
  List<int> _currentRooms(int ttId) {
    final planned = demoPlan[(ttId % 10 + _demoStart(ttId).weekday) % 6].$3;
    return [
      if (!removedRooms.contains(ttId)) roomChanges[ttId] ?? planned,
      ...?addedRooms[ttId],
    ];
  }

  @override
  Future<RoomBookingResult> createRoomBooking({
    required String host,
    required String school,
    required UntisCredentials auth,
    required RoomBookingRequest booking,
  }) async {
    await _delay();
    roomBookingCalls.add(booking);
    if (!demoRoomIds.contains(booking.roomId)) {
      return const RoomBookingResult(
        errors: [TeacherToolError(code: 'ROOM_UNKNOWN', title: 'Unknown room')],
      );
    }
    if (_busyRooms(booking.start, booking.end).contains(booking.roomId)) {
      return const RoomBookingResult(
        errors: [
          TeacherToolError(
            code: 'ROOM_OCCUPIED',
            title: 'Room is occupied',
            details: 'The room is in use at that time.',
          ),
        ],
      );
    }
    final id = _nextBookingId++;
    roomBookings.add((
      id: id,
      roomId: booking.roomId,
      start: booking.start,
      end: booking.end,
      teacherId: booking.teacherId,
      text: booking.text,
    ));
    return RoomBookingResult(id: id);
  }

  static const demoExamTypes = [
    ExamType(id: 1, name: 'SA', longName: 'Schularbeit'),
    ExamType(id: 2, name: 'Test', longName: 'Test'),
    ExamType(id: 3, name: 'MÜ', longName: 'Mündliche Prüfung'),
  ];

  @override
  Future<List<ExamType>> examTypes({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) async {
    await _delay();
    return demoExamTypes;
  }

  @override
  Future<int?> createExam({
    required String host,
    required String school,
    required UntisCredentials auth,
    required NewExam exam,
  }) async {
    await _delay();
    createExamCalls.add(exam);
    if (!exam.end.isAfter(exam.start)) {
      throw const UntisException(-1, 'The end must be after the start.');
    }
    final id = _nextExamId++;
    createdExams.add(
      ExamItem(
        id: id,
        start: exam.start,
        end: exam.end,
        examType: exam.examType,
        name: exam.name,
        text: exam.text,
        subjectId: exam.subjectId,
        klassenIds: exam.klasseIds,
        roomIds: exam.roomIds,
        teacherIds: exam.teacherIds,
      ),
    );
    return id;
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
      // Two teachers sent with only their last name.
      at(4, 1, 9, 'Huber', 'R110', ''),
      at(5, 4, 12, 'Huber', 'R215', ''),
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
