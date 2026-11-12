import 'package:better_betteruntis/core/info.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/dev/fake_info.dart';
import 'package:better_betteruntis/ui/infocenter/absences_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'absence_report_test.dart' show parentAccount;

final now = DateTime(2026, 11, 12, 17);
final absence = AbsenceItem(
  id: 264305,
  start: DateTime(2026, 11, 13, 7, 55),
  end: DateTime(2026, 11, 13, 17, 55),
  excused: true,
  reason: 'krank (EZB)',
  excuseStatus: 'entschuldigt',
);

AbsenceRecord record({bool canEdit = true, String by = 'parent'}) =>
    AbsenceRecord(
      id: absence.id,
      start: absence.start,
      end: absence.end,
      canEdit: canEdit,
      createdUser: by,
      updatedUser: by,
      created: DateTime(2026, 11, 12, 16, 1),
    );

void main() {
  late FakeInfoCenterRepository repo;
  late bool? result;

  setUp(() {
    repo = FakeInfoCenterRepository();
    repo.absenceItems = [absence];
    result = null;
  });

  Future<void> open(WidgetTester tester, Account account) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [infoCenterRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showAbsenceDetails(
                  context,
                  account,
                  absence,
                  now,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  test('describeAbsenceUser: you, another parent, a teacher', () {
    final a = parentAccount();
    expect(describeAbsenceUser('Parent', a), 'You');
    expect(
      describeAbsenceUser('mum@example.com', a),
      'Parent (mum@example.com)',
    );
    expect(describeAbsenceUser('Fch', a), 'Teacher (Fch)');
    expect(describeAbsenceUser(' ', a), isNull);
  });

  testWidgets('parent: shows who entered it and deletes after confirming', (
    tester,
  ) async {
    repo.records = {absence.id: record()};
    await open(tester, parentAccount());
    expect(find.text('krank (EZB)'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.textContaining('You · 12 Nov 2026'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('absence-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this absence?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('absence-delete-confirm')));
    await tester.pumpAndSettle();
    expect(repo.deleted, [absence.id]);
    expect(result, isTrue);
    expect(find.byKey(const ValueKey('absence-details')), findsNothing);
  });

  testWidgets('cancel keeps the absence', (tester) async {
    repo.records = {absence.id: record()};
    await open(tester, parentAccount());
    await tester.tap(find.byKey(const ValueKey('absence-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);
    expect(find.byKey(const ValueKey('absence-details')), findsOneWidget);
  });

  testWidgets('teacher entry: no delete, says why', (tester) async {
    repo.records = {absence.id: record(canEdit: false, by: 'Fch')};
    await open(tester, parentAccount());
    expect(find.textContaining('Teacher (Fch)'), findsOneWidget);
    expect(find.byKey(const ValueKey('absence-delete')), findsNothing);
    expect(find.textContaining("doesn't let you change"), findsOneWidget);
  });

  testWidgets('delete failure is shown in the sheet', (tester) async {
    repo.records = {absence.id: record()};
    repo.deleteError = const UntisException(-1, 'Too late');
    await open(tester, parentAccount());
    await tester.tap(find.byKey(const ValueKey('absence-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('absence-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't delete: Too late"), findsOneWidget);
    expect(find.byKey(const ValueKey('absence-details')), findsOneWidget);
  });

  testWidgets('record lookup failing still shows the details', (tester) async {
    repo.recordError = const UntisException(0, 'offline');
    await open(tester, parentAccount());
    expect(find.text('krank (EZB)'), findsOneWidget);
    expect(find.textContaining("Couldn't load who entered"), findsOneWidget);
  });
}
