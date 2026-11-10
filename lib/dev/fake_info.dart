/// In-memory [InfoCenterRepository] with made-up German school data, for demo
/// mode, UI development and widget tests.
///
/// All dates are relative to [FakeInfoCenterRepository.now] (default: the
/// time of construction). Each stream emits a "cached" value first (when
/// [FakeInfoCenterRepository.hasCache]), then — after [latency] — either the
/// fresh data or, when the kind is failing, the cached data with an error.
library;

import 'dart:async';

import '../core/info.dart';
import '../core/interfaces.dart';
import '../core/models.dart';
import 'fake_timetable.dart' show DemoIds;

enum FakeInfoKind { messagesOfDay, inbox, homework, exams, absences, officeHours }

/// Teacher id that no resolver knows (schools hiding teachers from students).
const fakeHiddenTeacherId = 77;

class FakeInfoCenterRepository implements InfoCenterRepository {
  FakeInfoCenterRepository({
    DateTime? now,
    this.latency = Duration.zero,
    this.error,
    this.failing,
    this.hasCache = true,
    this.cacheAge = const Duration(minutes: 5),
    List<Message> Function(DateTime day)? messagesOfDay,
    List<InboxMessage>? inbox,
    Map<int, InboxMessageDetail>? inboxDetails,
    List<HomeworkItem>? homework,
    List<ExamItem>? exams,
    List<AbsenceItem>? absences,
    List<OfficeHourItem>? officeHours,
  }) : now = now ?? DateTime.now() {
    final today = DateTime(this.now.year, this.now.month, this.now.day);
    messagesOfDayFor = messagesOfDay ?? (day) => demoMessagesOfDay(today, day);
    inboxItems = inbox ?? demoInbox(this.now);
    this.inboxDetails = inboxDetails ?? demoInboxDetails(this.now);
    homeworkItems = homework ?? demoHomework(today);
    examItems = exams ?? demoExams(today);
    absenceItems = absences ?? demoAbsences(today);
    officeHourItems = officeHours ?? demoOfficeHours(today);
  }

  final DateTime now;
  Duration latency;

  /// Refresh failure; applies to [failing] kinds (all kinds when null).
  UntisException? error;
  Set<FakeInfoKind>? failing;

  /// Whether a cached value is emitted first. Without cache, a failing kind
  /// has no data at all (full error state).
  bool hasCache;
  Duration cacheAge;

  late List<Message> Function(DateTime day) messagesOfDayFor;
  late List<InboxMessage> inboxItems;
  late Map<int, InboxMessageDetail> inboxDetails;
  late List<HomeworkItem> homeworkItems;
  late List<ExamItem> examItems;
  late List<AbsenceItem> absenceItems;
  late List<OfficeHourItem> officeHourItems;

  /// Every subscription: kind and whether it was forced.
  final calls = <({FakeInfoKind kind, bool force})>[];

  bool _fails(FakeInfoKind k) => error != null && (failing == null || failing!.contains(k));

  Stream<Cached<T>> _stream<T>(FakeInfoKind kind, bool force, T Function() data) async* {
    calls.add((kind: kind, force: force));
    final cachedAt = DateTime.now().subtract(cacheAge);
    final cached = hasCache ? data() : null;
    yield Cached(data: cached, fetchedAt: hasCache ? cachedAt : null, refreshing: true);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (_fails(kind)) {
      yield Cached(data: cached, fetchedAt: hasCache ? cachedAt : null, error: error);
    } else {
      yield Cached(data: data(), fetchedAt: DateTime.now());
    }
  }

  static bool _inRange(DateTime d, DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day + 1);
    return !d.isBefore(s) && d.isBefore(e);
  }

  @override
  Stream<Cached<List<Message>>> messagesOfDay(Account a, DateTime day, {bool force = false}) =>
      _stream(FakeInfoKind.messagesOfDay, force, () => messagesOfDayFor(day));

  @override
  Stream<Cached<List<InboxMessage>>> inbox(Account a, {bool force = false}) =>
      _stream(FakeInfoKind.inbox, force, () => inboxItems);

  @override
  Future<InboxMessageDetail> inboxMessage(Account a, int id) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (_fails(FakeInfoKind.inbox)) throw error!;
    final d = inboxDetails[id];
    if (d == null) throw const UntisException(404, 'Message not found');
    return d;
  }

  @override
  Stream<Cached<List<HomeworkItem>>> homework(Account a, DateTime start, DateTime end, {bool force = false}) =>
      _stream(FakeInfoKind.homework, force, () => [
        for (final h in homeworkItems)
          if (_inRange(h.dueOn, start, end) || _inRange(h.assignedOn, start, end)) h,
      ]);

  @override
  Stream<Cached<List<ExamItem>>> exams(Account a, DateTime start, DateTime end, {bool force = false}) =>
      _stream(FakeInfoKind.exams, force, () => [
        for (final e in examItems)
          if (_inRange(e.start, start, end)) e,
      ]);

  @override
  Stream<Cached<List<AbsenceItem>>> absences(Account a, DateTime start, DateTime end, {bool force = false}) =>
      _stream(FakeInfoKind.absences, force, () => [
        for (final x in absenceItems)
          if (_inRange(x.start, start, end)) x,
      ]);

  @override
  Stream<Cached<List<OfficeHourItem>>> officeHours(
    Account a,
    DateTime start, {
    bool force = false,
    bool onlyMyClass = false,
  }) {
    lastOfficeHoursOnlyMyClass = onlyMyClass;
    return _stream(FakeInfoKind.officeHours, force, () => [
        for (final o in officeHourItems)
          if (!o.start.isBefore(DateTime(start.year, start.month, start.day))) o,
      ]);
  }

  /// `onlyMyClass` of the most recent [officeHours] call.
  bool? lastOfficeHoursOnlyMyClass;
}

// ---------------------------------------------------------------------------
// Demo data (made up)

DateTime _at(DateTime day, int h, int m) => DateTime(day.year, day.month, day.day, h, m);
DateTime _d(DateTime today, int days) => DateTime(today.year, today.month, today.day + days);

List<Message> demoMessagesOfDay(DateTime today, DateTime day) {
  final offset = DateTime(day.year, day.month, day.day).difference(today).inHours ~/ 24;
  return switch (offset) {
    0 => const [
      Message(
        id: 501,
        subject: 'Wandertag am Freitag',
        bodyHtml:
            '<p>Liebe Schülerinnen und Schüler,</p><p>am <b>Freitag</b> findet der '
            'Wandertag statt. Treffpunkt ist um 08:00 Uhr am Haupteingang.</p>'
            '<ul><li>festes Schuhwerk</li><li>Regenjacke</li><li>Verpflegung &amp; Getränke</li></ul>'
            '<p>Weitere Infos: <a href="https://example.org/wandertag">Elternbrief</a></p>',
        attachments: [(name: 'Elternbrief_Wandertag.pdf', url: 'https://example.org/wandertag.pdf')],
      ),
      Message(
        id: 502,
        subject: 'Heizungsausfall in Haus B',
        bodyHtml:
            'Wegen eines Heizungsausfalls finden die Stunden in Haus B heute in der Aula statt.<br>'
            'Bitte warme Kleidung mitbringen.',
      ),
    ],
    -1 => const [
      Message(
        id: 500,
        subject: 'Fundsachen',
        bodyHtml: '<p>Die Fundsachen werden am Monatsende gespendet. Bitte im Sekretariat nachsehen.</p>',
      ),
    ],
    _ => const [],
  };
}

List<InboxMessage> demoInbox(DateTime now) => [
  InboxMessage(
    id: 1,
    subject: 'Elternsprechtag am 27.11.',
    preview: 'Liebe Eltern, der diesjährige Elternsprechtag findet am …',
    sender: 'Sekretariat',
    sentAt: now.subtract(const Duration(hours: 2)),
    hasAttachments: true,
  ),
  InboxMessage(
    id: 2,
    subject: 'Klassenfahrt: Zahlungserinnerung',
    preview: 'Bitte denken Sie an die zweite Rate für die Klassenfahrt nach …',
    sender: 'Anna Müller',
    sentAt: now.subtract(const Duration(days: 1, hours: 3)),
  ),
  InboxMessage(
    id: 3,
    subject: 'AG-Angebote im zweiten Halbjahr',
    preview: 'Ab Februar starten neue Arbeitsgemeinschaften: Robotik, Theater, …',
    sender: 'Peter Schmidt',
    sentAt: now.subtract(const Duration(days: 4)),
    isRead: true,
  ),
  InboxMessage(
    id: 4,
    subject: 'Schulbuchausleihe',
    preview: 'Die Rückgabe der ausgeliehenen Bücher erfolgt in der letzten Schulwoche.',
    sender: 'Bibliothek',
    sentAt: now.subtract(const Duration(days: 12)),
    isRead: true,
  ),
];

Map<int, InboxMessageDetail> demoInboxDetails(DateTime now) {
  final list = demoInbox(now);
  InboxMessageDetail detail(int i, String html, [List<({String name, String url})> att = const []]) =>
      InboxMessageDetail(
        id: list[i].id,
        subject: list[i].subject,
        bodyHtml: html,
        sender: list[i].sender,
        sentAt: list[i].sentAt,
        attachments: att,
      );
  return {
    1: detail(
      0,
      '<p>Liebe Eltern,</p>'
      '<p>der diesj&auml;hrige <strong>Elternsprechtag</strong> findet am 27.11. von 15:00 bis 19:00 Uhr statt.</p>'
      '<ol><li>Termine bitte &uuml;ber das Portal buchen</li><li>Pro Lehrkraft 10 Minuten</li></ol>'
      '<p>Anmeldung: <a href="https://example.org/sprechtag">example.org/sprechtag</a><br>'
      'Fragen gerne an <a href="mailto:sekretariat@example.org">das Sekretariat</a>.</p>'
      '<script>alert("x")</script><p><em>Mit freundlichen Gr&uuml;&szlig;en</em><br>Ihre Schulleitung</p>',
      [(name: 'Raumplan_Sprechtag.pdf', url: 'https://example.org/raumplan.pdf')],
    ),
    2: detail(
      1,
      '<p>Liebe Klasse 10a,</p><p>bitte denkt an die zweite Rate (120&nbsp;&euro;) bis zum Monatsende.</p>'
      '<p>Viele Gr&uuml;&szlig;e<br>A. M&uuml;ller</p>',
    ),
    3: detail(
      2,
      '<p>Ab Februar starten neue AGs:</p><ul><li><b>Robotik</b> (Di, 7./8. Stunde)</li>'
      '<li><b>Theater</b> (Do, Aula)</li><li>Schulgarten</li></ul>',
    ),
    4: detail(3, 'Die Rückgabe der ausgeliehenen Bücher erfolgt in der letzten Schulwoche.\nDanke!'),
  };
}

List<HomeworkItem> demoHomework(DateTime today) => [
  HomeworkItem(
    id: 1,
    lessonId: 100,
    assignedOn: _d(today, -1),
    dueOn: _d(today, 1),
    text: 'Buch S. 84, Nr. 3a–d und 5',
    subjectId: DemoIds.m,
    teacherIds: const [DemoIds.mue],
  ),
  HomeworkItem(
    id: 2,
    lessonId: 101,
    assignedOn: _d(today, -2),
    dueOn: _d(today, 3),
    text: 'Gedichtanalyse „Der Panther“ fertigstellen',
    remark: 'Mindestens eine Seite',
    subjectId: DemoIds.d,
    teacherIds: const [fakeHiddenTeacherId],
  ),
  HomeworkItem(
    id: 3,
    lessonId: 102,
    assignedOn: _d(today, -3),
    dueOn: _d(today, 3),
    text: 'Vocabulary Unit 4 lernen',
    completed: true,
    subjectId: DemoIds.e,
    teacherIds: const [DemoIds.sch],
  ),
  HomeworkItem(
    id: 4,
    lessonId: 103,
    assignedOn: _d(today, -6),
    dueOn: _d(today, -2),
    text: 'Versuchsprotokoll „Freier Fall“ abgeben',
    subjectId: DemoIds.ph,
    teacherIds: const [DemoIds.fis],
    attachments: const [(name: 'Vorlage_Protokoll.pdf', url: 'https://example.org/protokoll.pdf')],
  ),
  HomeworkItem(
    id: 5,
    lessonId: 104,
    assignedOn: _d(today, -9),
    dueOn: _d(today, -5),
    text: 'Referat zur Zellteilung vorbereiten',
    completed: true,
    subjectId: DemoIds.bio,
    teacherIds: const [DemoIds.web],
  ),
  HomeworkItem(
    id: 6,
    lessonId: 105,
    assignedOn: _d(today, 0),
    dueOn: _d(today, 9),
    text: 'Quellenarbeit: Weimarer Verfassung, Art. 48',
    subjectId: DemoIds.ge,
    teacherIds: const [DemoIds.hof],
  ),
];

List<ExamItem> demoExams(DateTime today) => [
  ExamItem(
    id: 1,
    start: _at(_d(today, 3), 8, 35),
    end: _at(_d(today, 3), 10, 25),
    examType: 'Klassenarbeit',
    name: 'Lineare Funktionen',
    subjectId: DemoIds.m,
    klassenIds: const [DemoIds.klasse],
    roomIds: const [DemoIds.r101],
    teacherIds: const [DemoIds.mue, fakeHiddenTeacherId],
    text: 'Taschenrechner und Geodreieck mitbringen.',
  ),
  ExamItem(
    id: 2,
    start: _at(_d(today, 10), 9, 40),
    end: _at(_d(today, 10), 10, 25),
    examType: 'Test',
    name: 'Vocabulary Test Unit 4',
    subjectId: DemoIds.e,
    klassenIds: const [DemoIds.klasse],
    roomIds: const [DemoIds.r102],
    teacherIds: const [DemoIds.sch],
  ),
  ExamItem(
    id: 3,
    start: _at(_d(today, 24), 7, 45),
    end: _at(_d(today, 24), 9, 20),
    examType: 'Klausur',
    name: 'Mechanik',
    subjectId: DemoIds.ph,
    roomIds: const [DemoIds.ph1],
    teacherIds: const [DemoIds.fis],
  ),
  ExamItem(
    id: 4,
    start: _at(_d(today, -7), 8, 35),
    end: _at(_d(today, -7), 10, 25),
    examType: 'Klassenarbeit',
    name: 'Erörterung',
    subjectId: DemoIds.d,
    roomIds: const [DemoIds.r101],
  ),
  ExamItem(
    id: 5,
    start: _at(_d(today, -21), 11, 30),
    end: _at(_d(today, -21), 12, 15),
    examType: 'Test',
    name: 'Zellbiologie',
    subjectId: DemoIds.bio,
    roomIds: const [DemoIds.r204],
    teacherIds: const [DemoIds.web],
  ),
];

List<AbsenceItem> demoAbsences(DateTime today) => [
  AbsenceItem(
    id: 1,
    start: _at(_d(today, -2), 7, 45),
    end: _at(_d(today, -2), 9, 20),
    excused: false,
    reason: 'Verspätung',
    text: 'Bus ausgefallen',
  ),
  AbsenceItem(
    id: 2,
    start: _at(_d(today, -9), 7, 45),
    end: _at(_d(today, -8), 13, 5),
    excused: true,
    reason: 'Krankheit',
    excuseStatus: 'entschuldigt',
    text: 'Attest liegt vor',
  ),
  AbsenceItem(
    id: 3,
    start: _at(_d(today, -20), 11, 30),
    end: _at(_d(today, -20), 13, 5),
    excused: true,
    reason: 'Arzttermin',
    excuseStatus: 'entschuldigt',
  ),
  AbsenceItem(
    id: 4,
    start: _at(_d(today, -45), 13, 40),
    end: _at(_d(today, -45), 15, 10),
    excused: false,
    reason: 'Unentschuldigt',
    excuseStatus: 'offen',
  ),
  AbsenceItem(
    id: 5,
    start: _at(_d(today, -60), 7, 45),
    end: _at(_d(today, -60), 13, 5),
    excused: true,
    reason: 'Familiäre Gründe',
    excuseStatus: 'entschuldigt',
  ),
];

List<OfficeHourItem> demoOfficeHours(DateTime today) => [
  OfficeHourItem(
    id: 1,
    start: _at(_d(today, 1), 9, 40),
    end: _at(_d(today, 1), 10, 25),
    teacherName: 'Anna Müller',
    rooms: 'Lehrerzimmer',
    email: 'a.mueller@example.org',
    registrationPossible: true,
  ),
  OfficeHourItem(
    id: 2,
    start: _at(_d(today, 2), 11, 30),
    end: _at(_d(today, 2), 12, 15),
    teacherName: 'Peter Schmidt',
    rooms: 'R204',
    phone: '+49 123 456789-12',
    registered: true,
  ),
  OfficeHourItem(
    id: 3,
    start: _at(_d(today, 8), 13, 40),
    end: _at(_d(today, 8), 14, 25),
    teacherName: 'Klara Weber',
    rooms: 'Besprechungsraum 1',
    email: 'k.weber@example.org',
    phone: '+49 123 456789-30',
  ),
  OfficeHourItem(
    id: 4,
    start: _at(_d(today, 20), 9, 40),
    end: _at(_d(today, 20), 10, 25),
    teacherName: 'Jonas Fischer',
    rooms: 'PH1',
  ),
];
