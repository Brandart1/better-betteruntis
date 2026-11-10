import 'dart:async';

import 'package:better_betteruntis/core/info.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/dev/fake_info.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/infocenter/absence_report_screen.dart';
import 'package:better_betteruntis/ui/infocenter/info_center_screen.dart';
import 'package:better_betteruntis/ui/infocenter/info_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const children = [
  AccountChild(id: 1001, displayName: 'Demo Child One', klasseId: 1),
  AccountChild(id: 1002, displayName: 'Demo Child Two', klasseId: 1),
];

Account parentAccount({List<AccountChild> kids = children, int? selected}) {
  final d = demoAccount();
  return Account(
    id: 'parent',
    school: d.school,
    username: 'parent',
    anonymous: false,
    displayName: 'Demo Parent',
    elementType: ElementType.unknown,
    elementId: 2001,
    children: kids,
    selectedChildId: selected,
  );
}

void main() {
  group('logic', () {
    test('canReportAbsences: parents with children only', () {
      expect(canReportAbsences(parentAccount()), isTrue);
      expect(canReportAbsences(parentAccount(kids: const [])), isFalse);
      expect(canReportAbsences(demoAccount()), isFalse);
    });

    test('school day from the time grid, else server defaults, else 8–16', () {
      final monday = DateTime(2026, 11, 9);
      expect(schoolDayMinutes(demoTimeGrid, monday), (
        start: 7 * 60 + 45,
        end: 15 * 60 + 10,
      ));
      // Saturday has no units: the first school day's units are used.
      expect(
        schoolDayMinutes(demoTimeGrid, DateTime(2026, 11, 14)).start,
        7 * 60 + 45,
      );
      const opts = AbsenceReportOptions(
        defaultStartMinutes: 7 * 60,
        defaultEndMinutes: 12 * 60,
      );
      expect(schoolDayMinutes(const TimeGrid({}), monday, opts), (
        start: 7 * 60,
        end: 12 * 60,
      ));
      expect(schoolDayMinutes(null, monday), kDefaultSchoolDay);
    });

    test('draft validation', () {
      const reasons = [AbsenceReason(id: 1, name: 'Krankheit')];
      final day = DateTime(2026, 11, 10);
      AbsenceReportDraft d({
        int? student = 1001,
        DateTime? endDay,
        int startM = 480,
        int endM = 600,
        int? reason = 1,
        String text = '',
      }) => AbsenceReportDraft(
        studentId: student,
        startDay: day,
        endDay: endDay ?? day,
        startMinutes: startM,
        endMinutes: endM,
        reasonId: reason,
        text: text,
      );
      expect(d().validate(reasons), isNull);
      expect(d(student: null).validate(reasons), 'Choose a child.');
      expect(d(endM: 480).validate(reasons), contains('after the start'));
      expect(d(startM: 700).validate(reasons), contains('after the start'));
      // A later end day makes an earlier end time fine.
      expect(
        d(startM: 700, endDay: DateTime(2026, 11, 11)).validate(reasons),
        isNull,
      );
      expect(d(reason: null).validate(reasons), 'Choose a reason.');
      expect(d(reason: 9).validate(reasons), 'Choose a reason.');
      expect(d(reason: null).validate(const []), isNull);
      expect(d(text: 'x' * 501).validate(reasons), contains('too long'));
      expect(
        d(endDay: DateTime(2027, 12, 1)).validate(reasons),
        contains('at most a year'),
      );
      final r = d(text: '  Fieber  ').toReport();
      expect(r.start, DateTime(2026, 11, 10, 8));
      expect(r.end, DateTime(2026, 11, 10, 10));
      expect(r.text, 'Fieber');
    });

    test('error texts', () {
      expect(
        describeReportError(const UntisException(-8509, 'HTTP 403')),
        contains("doesn't allow"),
      );
      expect(
        describeReportError(const UntisException(0, 'x')),
        contains('No connection'),
      );
      expect(
        describeReportError(const UntisException(-1, 'Overlaps')),
        'Overlaps',
      );
    });
  });

  group('widgets', () {
    late FakeInfoCenterRepository repo;

    setUp(() => repo = FakeInfoCenterRepository(absences: const []));

    Future<void> pump(WidgetTester tester, Account acct) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/info',
        routes: [
          GoRoute(path: '/info', builder: (_, _) => const InfoCenterScreen()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            infoCenterRepositoryProvider.overrideWithValue(repo),
            activeAccountProvider.overrideWith((ref) => Stream.value(acct)),
            nameResolverProvider.overrideWith(
              (ref) => Stream<NameResolver>.value(FakeNameResolver()),
            ),
            infoTabProvider.overrideWith(() => SessionValue(InfoTab.absences)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    final fab = find.byKey(const ValueKey('absences-report'));
    final send = find.byKey(const ValueKey('absence-report-submit'));

    testWidgets('students get no report button', (tester) async {
      await pump(tester, demoAccount());
      expect(find.text('Absences'), findsWidgets);
      expect(fab, findsNothing);
    });

    testWidgets('parent: defaults, submit, list refreshes', (tester) async {
      await pump(tester, parentAccount(selected: 1002));
      expect(fab, findsOneWidget);
      await tester.tap(fab);
      await tester.pumpAndSettle();

      expect(find.text('Report absence'), findsOneWidget);
      // The selected child is preselected; times are the whole school day.
      expect(find.text('Demo Child Two'), findsOneWidget);
      expect(find.text('07:45 – 15:10'), findsOneWidget);
      expect(find.text('Krankheit'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('absence-report-text')),
        'Fieber',
      );
      await tester.tap(send);
      await tester.pumpAndSettle();

      final today = DateTime.now();
      final r = repo.reports.single;
      expect(r.studentId, 1002);
      expect(r.start, DateTime(today.year, today.month, today.day, 7, 45));
      expect(r.end, DateTime(today.year, today.month, today.day, 15, 10));
      expect(r.reasonId, 1);
      expect(r.text, 'Fieber');

      expect(find.text('Report absence'), findsOneWidget); // FAB label again
      expect(find.text('Absence reported'), findsOneWidget);
      expect(find.byKey(const ValueKey('absence-9001')), findsOneWidget);
    });

    testWidgets('changing the child and the reason', (tester) async {
      await pump(tester, parentAccount());
      await tester.tap(fab);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('absence-report-child')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Demo Child Two').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Krankheit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arzttermin').last);
      await tester.pumpAndSettle();
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(repo.reports.single.studentId, 1002);
      expect(repo.reports.single.reasonId, 2);
    });

    testWidgets('progress while sending, error keeps the form open', (
      tester,
    ) async {
      repo.reportGate = Completer<void>();
      repo.reportError = const UntisException(
        -1,
        'Not saved: it overlaps an existing absence or entry.',
      );
      await pump(tester, parentAccount());
      await tester.tap(fab);
      await tester.pumpAndSettle();
      await tester.tap(send);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('absence-report-progress')),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(send).onPressed, isNull);

      repo.reportGate!.complete();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('absence-report-error')),
        findsOneWidget,
      );
      expect(find.textContaining('overlaps'), findsOneWidget);
      expect(repo.reports, isEmpty);
      // Still on the form; sending is possible again.
      expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
    });

    testWidgets('school does not allow it: explained, send disabled', (
      tester,
    ) async {
      repo.reportOptions = const AbsenceReportOptions(
        reasons: [AbsenceReason(id: 1, name: 'Krankheit')],
        allowed: false,
      );
      await pump(tester, parentAccount());
      await tester.tap(fab);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('absence-report-blocked')),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
    });

    testWidgets(
      'reasons that fail to load are explained; sending still works',
      (tester) async {
        repo.reportOptionsError = const UntisException(-1, 'HTTP 500');
        await pump(tester, parentAccount());
        await tester.tap(fab);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('absence-report-options-error')),
          findsOneWidget,
        );
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(repo.reports.single.reasonId, isNull);
      },
    );

    testWidgets('validation: end before start is not sent', (tester) async {
      await pump(tester, parentAccount());
      await tester.tap(fab);
      await tester.pumpAndSettle();
      // Switch to manual times and make the end earlier than the start.
      await tester.tap(find.byKey(const ValueKey('absence-report-whole-day')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('absence-report-end-time')));
      await tester.pumpAndSettle();
      // Time picker in input mode: type 7:00 AM.
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final inputs = find.byType(TextFormField);
      await tester.enterText(inputs.at(0), '7');
      await tester.enterText(inputs.at(1), '00');
      await tester.tap(find.text('AM'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('07:45 – 07:00'), findsOneWidget);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('absence-report-problem')),
        findsOneWidget,
      );
      expect(find.text('The end must be after the start.'), findsOneWidget);
      expect(repo.reports, isEmpty);
    });
  });
}
