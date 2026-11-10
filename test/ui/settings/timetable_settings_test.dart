import 'dart:io';

import 'package:better_betteruntis/app/settings_store.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/settings/timetable_settings_screen.dart';
import 'package:better_betteruntis/ui/timetable/lesson_card.dart';
import 'package:better_betteruntis/ui/timetable/timetable_screen.dart';
import 'package:better_betteruntis/ui/timetable/timetable_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimetableSettings', () {
    test('defaults: centered, bold, school colors, show cancelled', () {
      const s = TimetableSettings();
      expect(s.centerText, isTrue);
      expect(s.subjectFontSize, 15);
      expect(s.detailFontSize, 12);
      expect(s.boldSubject, isTrue);
      expect(s.useSchoolColors, isTrue);
      expect(s.showCancelled, isTrue);
      expect(s.regularColor, isNull);
    });

    test('JSON round-trip', () {
      const s = TimetableSettings(
        centerText: false,
        subjectFontSize: 18,
        detailFontSize: 10,
        boldSubject: false,
        useSchoolColors: false,
        regularColor: 0xFF1976D2,
        irregularColor: 0xFFF57C00,
        cancelledColor: 0xFF90A4AE,
        examColor: 0xFFD32F2F,
        showCancelled: false,
      );
      expect(TimetableSettings.fromJson(s.toJson()), s);
      expect(
        TimetableSettings.fromJson(const TimetableSettings().toJson()),
        const TimetableSettings(),
      );
    });

    test('tolerant parse', () {
      expect(TimetableSettings.fromJson(null), const TimetableSettings());
      expect(TimetableSettings.fromJson('garbage'), const TimetableSettings());
      final s = TimetableSettings.fromJson({
        'centerText': 'nope',
        'subjectFontSize': 99,
        'detailFontSize': '10',
        'boldSubject': 0,
        'regularColor': '#336699',
        'examColor': 'zzz',
        'cancelledColor': 1.5,
        'unknownField': [1, 2],
      });
      expect(s.centerText, isTrue);
      expect(s.subjectFontSize, TimetableSettings.maxSubjectFontSize);
      expect(s.detailFontSize, 10);
      expect(s.boldSubject, isFalse);
      expect(s.regularColor, 0xFF336699);
      expect(s.examColor, isNull);
      expect(s.cancelledColor, isNull);
    });

    test('copyWith keeps colors unless passed, null resets', () {
      const s = TimetableSettings(
        regularColor: 0xFF00FF00,
        examColor: 0xFF0000FF,
      );
      final kept = s.copyWith(boldSubject: false);
      expect(kept.regularColor, 0xFF00FF00);
      final reset = s.copyWith(regularColor: null);
      expect(reset.regularColor, isNull);
      expect(reset.examColor, 0xFF0000FF);
    });
  });

  group('FileSettingsStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('settings_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('persists across instances', () async {
      final a = FileSettingsStore(directory: () async => dir);
      expect(await a.read('timetable'), isNull);
      await a.write('timetable', {'centerText': false});
      // Rapid writes are coalesced; the last one wins.
      final f1 = a.write(
        'timetable',
        const TimetableSettings(subjectFontSize: 20).toJson(),
      );
      final f2 = a.write(
        'timetable',
        const TimetableSettings(subjectFontSize: 21).toJson(),
      );
      await Future.wait([f1, f2]);

      final b = await FileSettingsStore.open(directory: () async => dir);
      expect(
        TimetableSettings.fromJson(b.peek('timetable')).subjectFontSize,
        21,
      );
    });

    test('corrupt file falls back to empty', () async {
      File('${dir.path}/${FileSettingsStore.fileName}')
          .writeAsStringSync('{not json');
      final s = FileSettingsStore(directory: () async => dir);
      expect(await s.read('timetable'), isNull);
      await s.write('timetable', {'boldSubject': false});
      final again = await FileSettingsStore.open(directory: () async => dir);
      expect(
        TimetableSettings.fromJson(again.peek('timetable')).boldSubject,
        isFalse,
      );
    });

    test('notifier loads from and saves to the store', () async {
      final store = FileSettingsStore(directory: () async => dir);
      await store.write(
        'timetable',
        const TimetableSettings(showCancelled: false).toJson(),
      );
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(
            FileSettingsStore(directory: () async => dir),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(timetableSettingsProvider, (_, _) {});
      expect(container.read(timetableSettingsProvider).showCancelled, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(timetableSettingsProvider).showCancelled, isFalse);

      container
          .read(timetableSettingsProvider.notifier)
          .update((s) => s.copyWith(examColor: 0xFF123456));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final reread = await FileSettingsStore.open(directory: () async => dir);
      expect(
        TimetableSettings.fromJson(reread.peek('timetable')).examColor,
        0xFF123456,
      );
    });
  });

  group('settings screen', () {
    late MemorySettingsStore store;
    setUp(() => store = MemorySettingsStore());

    Future<void> pump(
      WidgetTester tester, {
      Brightness brightness = Brightness.light,
    }) async {
      tester.view.physicalSize = const Size(400 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const TimetableSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder preview(String kind) => find.byKey(ValueKey('preview-$kind'));

    Color cardColor(WidgetTester tester, String kind) => tester
        .widget<Material>(
          find
              .descendant(of: preview(kind), matching: find.byType(Material))
              .first,
        )
        .color!;

    RichText cardText(WidgetTester tester, String kind) =>
        tester.widget<RichText>(
          find
              .descendant(of: preview(kind), matching: find.byType(RichText))
              .first,
        );

    double? subjectSize(WidgetTester tester) {
      final root = cardText(tester, 'regular').text as TextSpan;
      final spans = root.children!.first as TextSpan; // Text.rich wrapper
      final title = spans.children!.first as TextSpan;
      return title.style?.fontSize;
    }

    testWidgets('text is centered by default (horizontally and vertically)', (
      tester,
    ) async {
      await pump(tester);
      expect(cardText(tester, 'regular').textAlign, TextAlign.center);
      final align = tester.widget<Align>(
        find
            .descendant(of: preview('regular'), matching: find.byType(Align))
            .first,
      );
      expect(align.alignment, Alignment.center);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('center-text')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('center-text')));
      await tester.pumpAndSettle();
      expect(cardText(tester, 'regular').textAlign, TextAlign.start);
    });

    testWidgets('picking a color updates the preview card, reset restores it', (
      tester,
    ) async {
      await pump(tester);
      final before = cardColor(tester, 'regular');
      await tester.tap(find.byKey(const ValueKey('color-regular')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preset-ffd32f2f')));
      await tester.pumpAndSettle();
      expect(cardColor(tester, 'regular'), const Color(0xFFD32F2F));
      // White text on the dark red background.
      final root = cardText(tester, 'regular').text as TextSpan;
      expect(root.style?.color, Colors.white);

      // Hue slider changes the color live.
      await tester.tap(find.byKey(const ValueKey('hue-slider')));
      await tester.pumpAndSettle();
      expect(cardColor(tester, 'regular'), isNot(const Color(0xFFD32F2F)));

      await tester.tap(find.text('Reset to default'));
      await tester.pumpAndSettle();
      expect(cardColor(tester, 'regular'), before);
      expect((store.values['timetable'] as Map)['regularColor'], isNull);
    });

    testWidgets('subject size slider changes the preview text size', (
      tester,
    ) async {
      await pump(tester);
      expect(subjectSize(tester), 15);
      final slider = find.descendant(
        of: find.byKey(const ValueKey('subject-size-slider')),
        matching: find.byType(Slider),
      );
      await tester.tap(slider);
      await tester.pumpAndSettle();
      final mid = subjectSize(tester)!;
      expect(mid, inInclusiveRange(16, 17));
      await tester.drag(slider, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(subjectSize(tester), TimetableSettings.minSubjectFontSize);
    });

    testWidgets('school colors switch and reset all', (tester) async {
      await pump(tester);
      expect(cardColor(tester, 'school'), const Color(0xFF81C784));
      await tester.tap(find.byKey(const ValueKey('school-colors')));
      await tester.pumpAndSettle();
      expect(cardColor(tester, 'school'), cardColor(tester, 'regular'));
      await tester.tap(find.byKey(const ValueKey('reset-all')));
      await tester.pumpAndSettle();
      expect(cardColor(tester, 'school'), const Color(0xFF81C784));
    });

    testWidgets('dark mode renders without errors', (tester) async {
      await pump(tester, brightness: Brightness.dark);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('color-exam')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('timetable applies settings', () {
    late FakeTimetableRepository repo;
    setUp(() => repo = FakeTimetableRepository());
    final week = buildDemoWeek(mondayOf(DateTime.now()), holidayFriday: true);

    testWidgets(
      'hide cancelled hides the cancelled card; colors rebuild without refetch',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final container = ProviderContainer(
          overrides: [
            timetableRepositoryProvider.overrideWithValue(repo),
            activeAccountProvider.overrideWith(
              (ref) => Stream.value(demoAccount()),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: TimetableScreen()),
          ),
        );
        await tester.pumpAndSettle();
        final cancelled = week.firstWhere((p) => p.isCancelled);
        final regular = week.firstWhere(
          (p) =>
              !p.isCancelled &&
              !p.isIrregular &&
              !p.isExam &&
              p.backColor == null,
        );
        expect(find.byKey(ValueKey('lesson-${cancelled.id}')), findsOneWidget);

        final notifier = container.read(timetableSettingsProvider.notifier);
        notifier.update((s) => s.copyWith(regularColor: 0xFF00796B));
        await tester.pumpAndSettle();
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.descendant(
                  of: find.byKey(ValueKey('lesson-${regular.id}')),
                  matching: find.byType(LessonCard),
                ),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, const Color(0xFF00796B));

        notifier.update((s) => s.copyWith(showCancelled: false));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('lesson-${cancelled.id}')), findsNothing);
        expect(repo.refreshCount, 0, reason: 'settings never refetch');
      },
    );
  });
}
