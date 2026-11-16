import 'package:better_betteruntis/core/info.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/lesson_notes.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/dev/fake_info.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/infocenter/absences_tab.dart';
import 'package:better_betteruntis/ui/infocenter/info_center_screen.dart';
import 'package:better_betteruntis/ui/infocenter/info_common.dart';
import 'package:better_betteruntis/ui/infocenter/info_providers.dart';
import 'package:better_betteruntis/ui/infocenter/messages_tab.dart';
import 'package:better_betteruntis/ui/infocenter/office_hours_tab.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

Account account({Set<String> rights = const {}, bool anonymous = false}) {
  final d = demoAccount();
  return Account(
    id: d.id,
    school: d.school,
    username: anonymous ? '#anonymous#' : d.username,
    anonymous: anonymous,
    displayName: d.displayName,
    elementType: d.elementType,
    elementId: d.elementId,
    klassenIds: d.klassenIds,
    rights: rights,
  );
}

void main() {
  late FakeInfoCenterRepository repo;
  late List<Uri> opened;

  setUp(() {
    repo = FakeInfoCenterRepository();
    opened = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    Account? acct,
    Size size = const Size(420, 1800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/info',
      routes: [
        GoRoute(
          path: '/info',
          builder: (_, _) => const InfoCenterScreen(),
          routes: [
            GoRoute(
              path: 'message/:id',
              builder: (_, s) => MessageDetailScreen(
                messageId: int.parse(s.pathParameters['id']!),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          infoCenterRepositoryProvider.overrideWithValue(repo),
          activeAccountProvider.overrideWith(
            (ref) => Stream.value(acct ?? account()),
          ),
          nameResolverProvider.overrideWith(
            (ref) => Stream<NameResolver>.value(FakeNameResolver()),
          ),
          urlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder rich(String text) => find.textContaining(text, findRichText: true);
  final today = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  String dayLabel(DateTime d) =>
      DateFormat(d.year == today.year ? 'EEE, d MMM' : 'EEE, d MMM yyyy')
          .format(d);

  testWidgets('tabs render and switch; last tab remembered', (tester) async {
    await pump(tester);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Wandertag am Freitag'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Elternsprechtag am 27.11.'), findsOneWidget);
    expect(find.textContaining('Updated'), findsOneWidget);

    await openTab(tester, 'Homework');
    expect(find.text('Buch S. 84, Nr. 3a–d und 5'), findsOneWidget);
    await openTab(tester, 'Exams');
    expect(find.text('Mathematik · Lineare Funktionen'), findsOneWidget);
    await openTab(tester, 'Office hours');
    expect(find.text('Anna Müller'), findsOneWidget);
  });

  testWidgets('wide screens use a navigation rail', (tester) async {
    await pump(tester, size: const Size(1000, 900));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('known rights hide absences / office hours', (tester) async {
    await pump(tester, acct: account(rights: {'R_MY_ABSENCES', 'R_OTHER'}));
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('Absences'), findsOneWidget);
    expect(find.text('Office hours'), findsNothing);
  });

  test('empty rights = unknown → all tabs; anonymous → messages only', () {
    expect(visibleInfoTabs(account()), InfoTab.values);
    expect(
      visibleInfoTabs(account(rights: {'R_OFFICEHOURS'})),
      isNot(contains(InfoTab.absences)),
    );
    expect(visibleInfoTabs(account(anonymous: true)), [InfoTab.messages]);
  });

  testWidgets('anonymous: messages of the day only', (tester) async {
    await pump(tester, acct: account(anonymous: true));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Messages of the day'), findsOneWidget);
    expect(find.text('Wandertag am Freitag'), findsOneWidget);
    expect(find.text('Inbox'), findsNothing);
    expect(repo.calls.map((c) => c.kind), isNot(contains(FakeInfoKind.inbox)));
  });

  testWidgets('message of the day expands; day stepping', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Wandertag am Freitag'));
    await tester.pumpAndSettle();
    expect(find.text('Elternbrief_Wandertag.pdf'), findsOneWidget);
    expect(find.text('festes Schuhwerk', findRichText: true), findsOneWidget);

    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(InfoSectionHeader),
        matching: find.text('Yesterday'),
      ),
      findsOneWidget,
    );
    expect(find.text('Fundsachen'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
    expect(find.text('No messages on this day'), findsOneWidget);
  });

  testWidgets('inbox: unread marked; detail renders HTML and links', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('unread-dot')), findsNWidgets(2));
    final unreadTitle = tester.widget<Text>(find.text('Sekretariat'));
    expect(unreadTitle.style?.fontWeight, FontWeight.bold);

    await tester.tap(find.text('Elternsprechtag am 27.11.'));
    await tester.pumpAndSettle();
    expect(find.text('Message'), findsOneWidget);
    expect(rich('der diesjährige Elternsprechtag'), findsOneWidget);
    expect(rich('Termine bitte über das Portal buchen'), findsOneWidget);
    expect(rich('alert'), findsNothing);
    expect(find.text('Raumplan_Sprechtag.pdf'), findsOneWidget);

    final linkText = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText().contains('Anmeldung: example.org/sprechtag'),
      ),
    );
    final hrefs = <String>[];
    linkText.text.visitChildren((s) {
      if (s is TextSpan && s.recognizer is TapGestureRecognizer) {
        hrefs.add(s.text!);
        if (s.text == 'example.org/sprechtag') {
          (s.recognizer! as TapGestureRecognizer).onTap!();
        }
      }
      return true;
    });
    expect(hrefs, ['example.org/sprechtag', 'das Sekretariat']);
    await tester.pump();
    expect(opened, [Uri.parse('https://example.org/sprechtag')]);

    await tester.tap(find.text('Raumplan_Sprechtag.pdf'));
    await tester.pump();
    expect(opened.last, Uri.parse('https://example.org/raumplan.pdf'));
  });

  testWidgets(
    'homework: grouped by due date, overdue highlighted, hidden teachers',
    (tester) async {
      await pump(tester);
      await openTab(tester, 'Homework');
      await tester.tap(find.text('Next 2 weeks'));
      await tester.pumpAndSettle();
      expect(find.text('Due tomorrow'), findsOneWidget);
      expect(
        find.text('Due ${dayLabel(today.add(const Duration(days: 3)))}'),
        findsOneWidget,
      );
      expect(
        find.text('Gedichtanalyse „Der Panther“ fertigstellen'),
        findsOneWidget,
      );
      expect(find.text('Vocabulary Unit 4 lernen'), findsOneWidget);
      expect(find.text('Deutsch'), findsOneWidget);
      expect(
        find.text('Anna Müller'),
        findsOneWidget,
        reason: 'resolved teacher',
      );
      expect(
        find.textContaining('#77'),
        findsNothing,
        reason: 'unresolved teacher hidden',
      );
      expect(find.text('Overdue'), findsNothing);

      await tester.tap(find.text('Past 4 weeks'));
      await tester.pumpAndSettle();
      final overdue = find.byKey(const ValueKey('homework-4'));
      expect(overdue, findsOneWidget);
      expect(
        find.descendant(of: overdue, matching: find.text('Overdue')),
        findsOneWidget,
      );
      final done = find.byKey(const ValueKey('homework-5'));
      expect(
        find.descendant(of: done, matching: find.text('Overdue')),
        findsNothing,
      );
      expect(
        find.descendant(of: done, matching: find.text('Done')),
        findsOneWidget,
      );
      final card = tester.widget<Card>(overdue);
      expect(
        card.color,
        Theme.of(tester.element(overdue)).colorScheme.errorContainer,
      );
    },
  );

  testWidgets('exams: upcoming with countdown, past collapsed', (tester) async {
    await pump(tester);
    await openTab(tester, 'Exams');
    expect(find.text('Mathematik · Lineare Funktionen'), findsOneWidget);
    expect(find.text('in 3 days'), findsOneWidget);
    expect(find.text('R101'), findsOneWidget);
    expect(find.text('Anna Müller'), findsOneWidget);
    expect(find.textContaining('#77'), findsNothing);
    expect(find.text('Deutsch · Erörterung'), findsNothing);
    expect(find.text('Past (2)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('exams-past-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Deutsch · Erörterung'), findsOneWidget);
    expect(find.text('Biologie · Zellbiologie'), findsOneWidget);
  });

  testWidgets('absences: summary and only-unexcused filter', (tester) async {
    final items = demoAbsences(today);
    final inYear = [
      for (final a in items)
        if (!a.start.isBefore(schoolYearStart(DateTime.now()))) a,
    ];
    final summary = absenceSummary(inYear);
    await pump(tester);
    await openTab(tester, 'Absences');
    Text stat(String k) =>
        tester.widget<Text>(find.byKey(ValueKey('absences-summary-$k')));
    expect(stat('total').data, '${summary.total}');
    expect(stat('unexcused').data, '${summary.unexcused}');
    expect(stat('hours').data, formatHours(summary.hours));
    expect(find.text('Excused'), findsWidgets);
    expect(find.byKey(const ValueKey('absence-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('absence-2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('absences-only-unexcused')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('absence-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('absence-2')), findsNothing);
    expect(find.text('Excused'), findsNothing);
    expect(
      stat('total').data,
      '${summary.total}',
      reason: 'summary covers the range',
    );
  });

  testWidgets('absences: tapping one shows its details', (tester) async {
    await pump(tester);
    await openTab(tester, 'Absences');
    await tester.tap(find.byKey(const ValueKey('absence-2')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('absence-details'));
    expect(sheet, findsOneWidget);
    for (final t in ['Krankheit', 'entschuldigt', 'Attest liegt vor', 'Yes']) {
      expect(
        find.descendant(of: sheet, matching: find.text(t)),
        findsOneWidget,
        reason: t,
      );
    }
  });

  test('absence range reaches the end of the school year', () {
    final now = DateTime(2026, 11, 12, 17);
    final (start, end) = const AbsenceFilter(range: AbsenceRange.days7)
        .dates(now);
    expect(start, DateTime(2026, 11, 5));
    expect(end, DateTime(2027, 8, 31));
    expect(schoolYearEnd(DateTime(2027, 3, 1)), DateTime(2027, 8, 31));
  });

  test('absence summary counts', () {
    final s = absenceSummary([
      AbsenceItem(
        id: 1,
        start: DateTime(2026, 1, 1, 8),
        end: DateTime(2026, 1, 1, 9, 30),
        excused: false,
      ),
      AbsenceItem(
        id: 2,
        start: DateTime(2026, 1, 2, 8),
        end: DateTime(2026, 1, 2, 9),
        excused: true,
      ),
    ]);
    expect((s.total, s.unexcused, s.hours), (2, 1, 2.5));
    expect(formatHours(2.5), '2.5 h');
    expect(schoolYearStart(DateTime(2026, 11, 10)), DateTime(2026, 9, 1));
    expect(schoolYearStart(DateTime(2027, 3, 1)), DateTime(2026, 9, 1));
  });

  testWidgets('office hours: next 2 weeks with mailto/tel actions', (
    tester,
  ) async {
    await pump(tester);
    await openTab(tester, 'Office hours');
    expect(find.text('Registration possible'), findsOneWidget);
    expect(find.text('Registered'), findsOneWidget);
    expect(find.text('Jonas Fischer'), findsNothing, reason: 'beyond 2 weeks');
    await tester.tap(find.byKey(const ValueKey('officehour-1-email')));
    await tester.pump();
    expect(opened.single, Uri.parse('mailto:a.mueller@example.org'));
    await tester.tap(find.byKey(const ValueKey('officehour-2-phone')));
    await tester.pump();
    expect(opened.last, Uri.parse('tel:+4912345678912'));
  });

  testWidgets(
    'office hours: all teachers by default, chip narrows to my class',
    (tester) async {
      await pump(tester);
      await openTab(tester, 'Office hours');
      expect(repo.lastOfficeHoursOnlyMyClass, isFalse);
      await tester.tap(find.byKey(const ValueKey('officehours-only-mine')));
      await tester.pumpAndSettle();
      expect(repo.lastOfficeHoursOnlyMyClass, isTrue);
      expect(
        find.byKey(const ValueKey('officehours-only-mine')),
        findsOneWidget,
      );
    },
  );

  test('office hours are grouped by teacher A–Z, then by time', () {
    OfficeHourItem oh(int id, String t, int day) => OfficeHourItem(
      id: id,
      start: DateTime(2026, 11, day, 10),
      end: DateTime(2026, 11, day, 11),
      teacherName: t,
    );
    final g = groupByTeacher([
      oh(1, 'Zimmer', 10),
      oh(2, 'Özdemir', 12),
      oh(3, 'anders', 11),
      oh(4, 'Özdemir', 9),
      oh(5, '', 9),
      oh(6, 'Otto', 9),
    ]);
    expect(g.map((e) => e.name), ['anders', 'Otto', 'Özdemir', 'Zimmer', '']);
    expect(g[2].items.map((o) => o.id), [4, 2]);
    expect(g.last.title, 'Teacher');
  });

  test('teachers with the same last name only are not merged', () {
    OfficeHourItem oh(
      int id,
      String t, {
      int teacherId = 0,
      String rooms = '',
      String email = '',
    }) => OfficeHourItem(
      id: id,
      start: DateTime(2026, 11, 10, 8 + id),
      end: DateTime(2026, 11, 10, 9 + id),
      teacherName: t,
      teacherId: teacherId,
      rooms: rooms,
      email: email,
    );
    // By teacher id.
    var g = groupByTeacher([
      oh(1, 'Huber', teacherId: 7, rooms: 'R1'),
      oh(2, 'Huber', teacherId: 8, rooms: 'R1'),
      oh(3, 'Huber', teacherId: 7, rooms: 'R2'),
    ]);
    expect(g.map((e) => e.items.map((o) => o.id).toList()), [
      [2],
      [1, 3],
    ]);
    expect(g.map((e) => e.title), ['Huber · R1', 'Huber · R1, R2']);
    // By email.
    g = groupByTeacher([
      oh(1, 'Huber', email: 'a@x.org'),
      oh(2, 'Huber', email: 'b@x.org'),
      oh(3, 'Huber', email: 'a@x.org'),
    ]);
    expect(g.length, 2);
    expect(g.map((e) => e.title), ['Huber · a@x.org', 'Huber · b@x.org']);
    // Bare last name, nothing else: the room tells them apart.
    g = groupByTeacher([
      oh(1, 'Huber', rooms: 'R110'),
      oh(2, 'Huber', rooms: 'R215'),
      oh(3, 'Huber', rooms: 'R110'),
    ]);
    expect(g.map((e) => e.title), ['Huber · R110', 'Huber · R215']);
    expect(g.first.items.map((o) => o.id), [1, 3]);
    // A full name stays one teacher even across rooms.
    g = groupByTeacher([
      oh(1, 'Anna Huber', rooms: 'R110'),
      oh(2, 'Anna Huber', rooms: 'R215'),
    ]);
    expect(g.single.title, 'Anna Huber');
  });

  test('office hour search matches teacher, room and email', () {
    final o = OfficeHourItem(
      id: 1,
      start: DateTime(2026, 11, 10, 9),
      end: DateTime(2026, 11, 10, 10),
      teacherName: 'Anna Müller',
      rooms: 'Lehrerzimmer',
      email: 'a.mueller@example.org',
    );
    expect(officeHourMatches(o, ''), isTrue);
    expect(officeHourMatches(o, 'müll'), isTrue);
    expect(officeHourMatches(o, 'lehrer'), isTrue);
    expect(officeHourMatches(o, 'mueller'), isTrue);
    expect(officeHourMatches(o, 'weber'), isFalse);
  });

  testWidgets('office hours: same last names stay apart; search filters', (
    tester,
  ) async {
    await pump(tester);
    await openTab(tester, 'Office hours');
    expect(find.text('Huber · R110'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('officehours-search')),
      'HUB',
    );
    await tester.pumpAndSettle();
    expect(find.text('Anna Müller'), findsNothing);
    expect(find.text('Huber · R110'), findsOneWidget);
    expect(find.text('Huber · R215'), findsOneWidget);
    expect(find.byKey(const ValueKey('officehour-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('officehour-6')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('officehours-search')),
      'r215',
    );
    await tester.pumpAndSettle();
    expect(find.text('Huber · R110'), findsNothing);
    expect(find.byKey(const ValueKey('officehour-5')), findsNothing);
    expect(find.byKey(const ValueKey('officehour-6')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('officehours-search')),
      'nobody',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('officehours-search')),
      '',
    );
    await tester.pumpAndSettle();
    expect(find.text('Anna Müller'), findsOneWidget);
  });

  testWidgets('refresh failure keeps cached data and shows a banner', (
    tester,
  ) async {
    repo.error = const UntisException(0, 'offline');
    repo.failing = {FakeInfoKind.homework};
    await pump(tester);
    expect(find.byKey(const ValueKey('info-error-banner')), findsNothing);
    await openTab(tester, 'Homework');
    expect(find.byKey(const ValueKey('info-error-banner')), findsOneWidget);
    expect(find.text('No connection. Showing saved data.'), findsOneWidget);
    expect(find.text('Buch S. 84, Nr. 3a–d und 5'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('info-error-banner')), findsNothing);
  });

  testWidgets('no cache + failure: full error state, retry recovers', (
    tester,
  ) async {
    repo
      ..hasCache = false
      ..error = const UntisException(-8509, 'no right');
    await pump(tester);
    await openTab(tester, 'Homework');
    expect(find.text('Could not load homework'), findsOneWidget);
    repo.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Buch S. 84, Nr. 3a–d und 5'), findsOneWidget);
    expect(repo.calls.last.force, isTrue);
  });

  testWidgets('pull-to-refresh forces a refresh', (tester) async {
    await pump(tester);
    await openTab(tester, 'Exams');
    final before = repo.calls.length;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
    await tester.pumpAndSettle();
    final forced = repo.calls
        .skip(before)
        .where((c) => c.force && c.kind == FakeInfoKind.exams);
    expect(forced.length, 2, reason: 'upcoming + past');
  });

  testWidgets('first load shows a skeleton', (tester) async {
    repo
      ..hasCache = false
      ..latency = const Duration(seconds: 1);
    await pump(tester); // settles while the fetch is still pending
    await openTab(tester, 'Homework');
    expect(find.byKey(const ValueKey('info-skeleton')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('info-skeleton')), findsNothing);
    expect(find.text('Buch S. 84, Nr. 3a–d und 5'), findsOneWidget);
  });

  testWidgets('empty states', (tester) async {
    repo = FakeInfoCenterRepository(
      inbox: const [],
      homework: const [],
      messagesOfDay: (_) => const [],
    );
    await pump(tester);
    expect(find.text('No messages today'), findsOneWidget);
    expect(find.text('Your inbox is empty'), findsOneWidget);
    await openTab(tester, 'Homework');
    expect(find.text('No homework 🎉'), findsOneWidget);
  });

  group('custom items (lesson notes)', () {
    String two(int v) => v.toString().padLeft(2, '0');
    String key(
      DateTime d,
      String hhmm,
      int lesson,
      String what, {
      String? acc,
    }) =>
        '${acc ?? account().id}|${d.year}-${two(d.month)}-${two(d.day)}|'
        '$hhmm|$lesson|$what';
    ProviderContainer container(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(InfoCenterScreen)),
        );

    testWidgets('homework tab: custom homework among the school\'s, with a '
        '"Custom" chip; tapping edits it', (tester) async {
      await pump(tester);
      final notes = container(tester).read(lessonNotesProvider.notifier);
      final ph = '${DemoIds.ph}';
      // A double lesson: one item.
      notes.set([
        key(today, '0745', 501, ph),
        key(today, '0835', 501, ph),
      ], const LessonNote(homework: 'Arbeitsblatt 2'));
      // A lesson without a subject: its title.
      notes.set([
        key(today, '0940', 502, 'Projekttag'),
      ], const LessonNote(text: 'details only', homework: 'Plakat'));
      // Not shown: details only, another account, a removed one.
      notes.set([key(today, '1030', 503, ph)], const LessonNote(text: 'x'));
      notes.set([
        key(today, '1130', 504, ph, acc: 'other'),
      ], const LessonNote(homework: 'Not mine'));
      notes.set([key(today, '1220', 505, ph)], const LessonNote(homework: 'y'));
      notes.set([key(today, '1220', 505, ph)], const LessonNote());
      await openTab(tester, 'Homework');

      final card = find.byKey(
        ValueKey('homework-custom-${key(today, '0745', 501, ph)}'),
      );
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Physik')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Arbeitsblatt 2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Custom')),
        findsOneWidget,
      );
      final other = find.byKey(
        ValueKey('homework-custom-${key(today, '0940', 502, 'Projekttag')}'),
      );
      expect(
        find.descendant(of: other, matching: find.text('Projekttag')),
        findsOneWidget,
      );
      expect(find.text('Custom'), findsNWidgets(2));
      expect(find.text('Not mine'), findsNothing);
      expect(find.text('y'), findsNothing);
      expect(find.text('details only'), findsNothing);
      // The school's homework is still there.
      expect(find.text('Buch S. 84, Nr. 3a–d und 5'), findsOneWidget);

      await tester.tap(find.text('Arbeitsblatt 2'));
      await tester.pumpAndSettle();
      expect(find.text('Edit homework'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('lesson-details-field')),
        'Arbeitsblatt 3',
      );
      await tester.tap(find.byKey(const ValueKey('lesson-details-save')));
      await tester.pumpAndSettle();
      expect(find.text('Arbeitsblatt 3'), findsOneWidget);
      final all = container(tester).read(lessonNotesProvider);
      expect(all[key(today, '0745', 501, ph)]!.homework, 'Arbeitsblatt 3');
      expect(all[key(today, '0835', 501, ph)]!.homework, 'Arbeitsblatt 3');
    });

    testWidgets('homework tab: custom homework alone is not "empty", and '
        'past custom homework is never overdue', (tester) async {
      repo = FakeInfoCenterRepository(homework: const []);
      await pump(tester);
      await openTab(tester, 'Homework');
      expect(find.text('Nothing is due this week.'), findsOneWidget);
      final notes = container(tester).read(lessonNotesProvider.notifier);
      final ph = '${DemoIds.ph}';
      notes.set([
        key(today.subtract(const Duration(days: 7)), '0745', 501, ph),
      ], const LessonNote(homework: 'Old one'));
      notes.set([
        key(today, '0745', 501, ph),
      ], const LessonNote(homework: 'New'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing is due this week.'), findsNothing);
      expect(find.text('New'), findsOneWidget);
      await tester.tap(find.text('Past 4 weeks'));
      await tester.pumpAndSettle();
      expect(find.text('Old one'), findsOneWidget);
      expect(find.text('Overdue'), findsNothing);
    });

    testWidgets('exams tab: custom exams upcoming and past, with a "Custom" '
        'chip, their details and the period\'s time', (tester) async {
      await pump(tester);
      final notes = container(tester).read(lessonNotesProvider.notifier);
      final ph = '${DemoIds.ph}';
      final tomorrow = today.add(const Duration(days: 1));
      notes.set([
        key(tomorrow, '0745', 601, ph),
        key(tomorrow, '0835', 601, ph),
      ], const LessonNote(exam: true, text: 'Kapitel 4'));
      notes.set([
        key(today.subtract(const Duration(days: 20)), '0940', 602, ph),
      ], const LessonNote(exam: true));
      // Homework only is no exam.
      notes.set([
        key(tomorrow, '1030', 603, ph),
      ], const LessonNote(homework: 'Not an exam'));
      await openTab(tester, 'Exams');

      final card = find.byKey(
        ValueKey('exam-custom-${key(tomorrow, '0745', 601, ph)}'),
      );
      expect(card, findsOneWidget);
      for (final t in ['Physik', 'Custom', 'Kapitel 4', 'Tomorrow']) {
        expect(
          find.descendant(of: card, matching: find.text(t)),
          findsOneWidget,
        );
      }
      // Start of the first, end of the last period (time grid).
      expect(
        find.descendant(of: card, matching: find.textContaining('07:45–09:20')),
        findsOneWidget,
      );
      expect(find.text('Not an exam'), findsNothing);
      // School exams stay; the past one counts in the past section.
      expect(find.text('Mathematik · Lineare Funktionen'), findsOneWidget);
      expect(find.text('Past (3)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('exams-past-toggle')));
      await tester.pumpAndSettle();
      final past = find.byKey(
        ValueKey(
          'exam-custom-'
          '${key(today.subtract(const Duration(days: 20)), '0940', 602, ph)}',
        ),
      );
      expect(
        find.descendant(of: past, matching: find.text('Custom')),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Kapitel 4'));
      await tester.tap(find.text('Kapitel 4'));
      await tester.pumpAndSettle();
      expect(find.text('Exam details'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('lesson-details-field')),
        'Kapitel 4 und 5',
      );
      await tester.tap(find.byKey(const ValueKey('lesson-details-save')));
      await tester.pumpAndSettle();
      final n = container(tester)
          .read(lessonNotesProvider)[key(tomorrow, '0835', 601, ph)]!;
      expect((n.exam, n.text), (true, 'Kapitel 4 und 5'));
    });
  });
}
