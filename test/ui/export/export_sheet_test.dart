import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/export/pdf_fonts.dart';
import 'package:better_betteruntis/ui/export/export_service.dart';
import 'package:better_betteruntis/ui/export/export_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

class _CountingRepo extends FakeTimetableRepository {
  _CountingRepo({super.watchError});
  final watched = <DateTime>[];

  @override
  Stream<List<Period>> watchWeek(
    Account account,
    TimetableTarget target,
    DateTime weekStart,
  ) {
    watched.add(weekStart);
    return super.watchWeek(account, target, weekStart);
  }
}

void main() {
  late _CountingRepo repo;
  late Directory dir;
  late List<ExportedFile> shared;

  // Wednesday; the sheet must start at that week's Monday (9 Nov).
  final shown = DateTime(2026, 11, 11);

  setUp(() {
    repo = _CountingRepo();
    dir = Directory.systemTemp.createTempSync('export_test');
    shared = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  PdfFonts fonts() {
    ByteData load(String p) => ByteData.sublistView(File(p).readAsBytesSync());
    return PdfFonts(
      pw.Font.ttf(load(kPdfFontRegular)),
      pw.Font.ttf(load(kPdfFontBold)),
    );
  }

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final account = demoAccount();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timetableRepositoryProvider.overrideWithValue(repo),
          activeAccountProvider.overrideWith((ref) => Stream.value(account)),
          exportDirectoryProvider.overrideWithValue(() async => dir),
          exportFontsProvider.overrideWithValue(() async => fonts()),
          exportShareProvider.overrideWithValue((
            file, {
            origin,
            subject,
          }) async {
            shared.add(file);
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showExportSheet(
                    context,
                    account: account,
                    target: const TimetableTarget(
                      ElementType.klasse,
                      DemoIds.klasse,
                    ),
                    initialWeek: shown,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Taps Export and lets the real I/O (file write) finish.
  Future<void> export(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Export'));
    await tester.tap(find.text('Export'));
    for (var i = 0; i < 100 && shared.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('defaults and week stepping', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Export timetable'), findsOneWidget);
    // Regular is the default: no week picker.
    expect(find.byKey(const ValueKey('export-week')), findsNothing);
    expect(
      find.textContaining('derived from the next 4 weeks'),
      findsOneWidget,
    );

    await tester.tap(find.text('Specific week'));
    await tester.pumpAndSettle();
    expect(find.text('9 – 13 Nov 2026'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('export-next-week')));
    await tester.pumpAndSettle();
    expect(find.text('16 – 20 Nov 2026'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('export-prev-week')));
    await tester.tap(find.byKey(const ValueKey('export-prev-week')));
    await tester.pumpAndSettle();
    expect(find.text('2 – 6 Nov 2026'), findsOneWidget);

    // Format-specific options.
    expect(find.byKey(const ValueKey('export-landscape')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export-format-csv')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('export-landscape')), findsNothing);
    expect(find.byKey(const ValueKey('export-colors')), findsNothing);
    expect(find.text('Comma ( , )'), findsOneWidget);
  });

  testWidgets('exports a specific week as CSV and shares it', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('Specific week'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('export-next-week')));
    await tester.tap(find.byKey(const ValueKey('export-format-csv')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semicolon ( ; )'));
    await tester.pumpAndSettle();

    await export(tester);

    expect(shared, hasLength(1));
    final f = shared.single;
    expect(f.name, 'timetable_10a_2026-11-16.csv');
    expect(f.mimeType, 'text/csv');
    expect(File(f.path).existsSync(), isTrue);
    expect(f.bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    final text = utf8.decode(f.bytes.sublist(3));
    expect(text, startsWith('Date;Day;Start;'));
    expect(text, contains('2026-11-16;Monday;07:45;09:20;1–2;M;Mathematik'));
    expect(text, contains('Substitution'));
    expect(repo.watched, [DateTime(2026, 11, 16)]);
    // Sheet closed after sharing.
    expect(find.text('Export timetable'), findsNothing);
  });

  testWidgets('exports the regular timetable as PDF from 4 weeks', (
    tester,
  ) async {
    await pumpSheet(tester);
    expect(find.byKey(const ValueKey('export-format-pdf')), findsOneWidget);
    await export(tester);

    expect(shared, hasLength(1));
    final f = shared.single;
    expect(f.name, 'timetable_10a_regular.pdf');
    expect(f.mimeType, 'application/pdf');
    expect(latin1.decode(f.bytes.sublist(0, 5)), '%PDF-');
    expect(repo.watched, [
      DateTime(2026, 11, 9),
      DateTime(2026, 11, 16),
      DateTime(2026, 11, 23),
      DateTime(2026, 11, 30),
    ]);
  });

  testWidgets('xlsx export', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.byKey(const ValueKey('export-format-xlsx')));
    await tester.pumpAndSettle();
    await export(tester);
    expect(shared.single.name, 'timetable_10a_regular.xlsx');
    // ZIP signature.
    expect(shared.single.bytes.sublist(0, 2), [0x50, 0x4B]);
  });

  testWidgets('load errors are shown, nothing is shared', (tester) async {
    repo = _CountingRepo(watchError: Exception('boom'));
    await pumpSheet(tester);
    await tester.tap(find.text('Specific week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(shared, isEmpty);
    expect(find.textContaining('boom'), findsWidgets);
    expect(find.text('Export timetable'), findsOneWidget);
  });
}
