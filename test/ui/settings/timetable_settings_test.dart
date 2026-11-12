import 'dart:io';

import 'package:better_betteruntis/app/settings_store.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/settings/subject_colors_screen.dart';
import 'package:better_betteruntis/ui/settings/timetable_settings_screen.dart';
import 'package:better_betteruntis/ui/timetable/lesson_card.dart';
import 'package:better_betteruntis/ui/timetable/lesson_style.dart';
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

    test('subject colors and state modes: defaults, round-trip', () {
      const d = TimetableSettings();
      expect(d.subjectColors, isEmpty);
      expect(d.examMode, StateColorMode.fill);
      expect(d.cancelledMode, StateColorMode.fill);
      expect(d.irregularMode, StateColorMode.fill);

      const s = TimetableSettings(
        subjectColors: {'M': 0xFF1976D2, 'PH': 0xFF388E3C},
        examMode: StateColorMode.border,
        irregularMode: StateColorMode.fill,
        cancelledMode: StateColorMode.border,
      );
      final back = TimetableSettings.fromJson(s.toJson());
      expect(back, s);
      expect(back.hashCode, s.hashCode);
      expect(back.subjectColors, {'M': 0xFF1976D2, 'PH': 0xFF388E3C});
      expect(back.examMode, StateColorMode.border);
      expect(s == s.copyWith(subjectColors: {'M': 0xFF1976D2}), isFalse);
    });

    test('subject colors and modes parse tolerantly', () {
      final s = TimetableSettings.fromJson({
        'subjectColors': {
          ' m ': '#1976D2',
          'ph': 0xFF388E3C,
          'bad': 'zzz',
          '': 0xFF000000,
          'x': [1],
        },
        'examMode': 'border',
        'irregularMode': 'sparkles',
        'cancelledMode': 3,
      });
      expect(s.subjectColors, {'M': 0xFF1976D2, 'PH': 0xFF388E3C});
      expect(s.examMode, StateColorMode.border);
      expect(s.irregularMode, StateColorMode.fill);
      expect(s.cancelledMode, StateColorMode.fill);
      expect(
        TimetableSettings.fromJson({'subjectColors': 'nope'}).subjectColors,
        isEmpty,
      );
    });

    test('withSubjectColor sets, normalizes and removes', () {
      final s = const TimetableSettings().withSubjectColor('bio ', 0xFF81C784);
      expect(s.subjectColorFor('BIO'), 0xFF81C784);
      expect(s.subjectColorFor(' Bio'), 0xFF81C784);
      expect(s.subjectColorFor('M'), isNull);
      expect(s.withSubjectColor('BIO', null).subjectColors, isEmpty);
      expect(s.withSubjectColor('  ', 0xFF000000), s);
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
      // File I/O timing varies (slow CI runners): poll instead of a fixed
      // delay, for up to 5 s.
      Future<void> eventually(Future<bool> Function() ok) async {
        final until = DateTime.now().add(const Duration(seconds: 5));
        while (!await ok() && DateTime.now().isBefore(until)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      container.listen(timetableSettingsProvider, (_, _) {});
      expect(container.read(timetableSettingsProvider).showCancelled, isTrue);
      await eventually(
        () async => !container.read(timetableSettingsProvider).showCancelled,
      );
      expect(container.read(timetableSettingsProvider).showCancelled, isFalse);

      container
          .read(timetableSettingsProvider.notifier)
          .update((s) => s.copyWith(examColor: 0xFF123456));
      Future<int?> savedExamColor() async {
        final reread = await FileSettingsStore.open(directory: () async => dir);
        return TimetableSettings.fromJson(reread.peek('timetable')).examColor;
      }

      await eventually(() async => await savedExamColor() == 0xFF123456);
      expect(await savedExamColor(), 0xFF123456);
    });
  });

  group('settings screen', () {
    late MemorySettingsStore store;
    setUp(() => store = MemorySettingsStore());

    Future<void> pump(
      WidgetTester tester, {
      Brightness brightness = Brightness.light,
      NameResolver? names,
    }) async {
      tester.view.physicalSize = const Size(400 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsStoreProvider.overrideWithValue(store),
            if (names != null)
              nameResolverProvider.overrideWith((ref) => Stream.value(names)),
          ],
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
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('detail-size-slider')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
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
      // The undo snackbar times out on its own.
      expect(find.text('Settings reset'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Settings reset'), findsNothing);
    });

    BorderSide cardBorder(WidgetTester tester, String kind) {
      final m = tester.widget<Material>(
        find
            .descendant(of: preview(kind), matching: find.byType(Material))
            .first,
      );
      return (m.shape! as RoundedRectangleBorder).side;
    }

    testWidgets('fill/border toggle per state updates preview and store', (
      tester,
    ) async {
      await pump(tester);
      final cs = Theme.of(tester.element(find.byType(TimetableSettingsScreen)))
          .colorScheme;
      // Defaults: everything filled.
      expect(cardColor(tester, 'exam'), cs.errorContainer);
      expect(cardColor(tester, 'substitution'), cs.tertiaryContainer);
      expect(find.byKey(const ValueKey('mode-regular')), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('mode-exam')),
          matching: find.text('Border'),
        ),
      );
      await tester.pumpAndSettle();
      expect(cardColor(tester, 'exam'), cardColor(tester, 'regular'));
      expect(cardBorder(tester, 'exam').color, cs.error);
      expect(cardBorder(tester, 'exam').width, LessonStyle.stateBorderWidth);
      expect((store.values['timetable'] as Map)['examMode'], 'border');

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('mode-irregular')),
          matching: find.text('Fill'),
        ),
      );
      await tester.pumpAndSettle();
      expect(cardColor(tester, 'substitution'), cs.tertiaryContainer);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('mode-cancelled')),
          matching: find.text('Border'),
        ),
      );
      await tester.pumpAndSettle();
      expect(cardColor(tester, 'cancelled'), cardColor(tester, 'regular'));
      expect(cardBorder(tester, 'cancelled').color, cs.outline);
      expect(tester.takeException(), isNull);
    });

    testWidgets('subject colors: pick, reset one, reset all', (tester) async {
      await pump(tester, names: FakeNameResolver());
      await tester.tap(find.byKey(const ValueKey('subject-colors')));
      await tester.pumpAndSettle();
      expect(find.byType(SubjectColorsScreen), findsOneWidget);
      // Active demo subjects, sorted by name.
      expect(find.byKey(const ValueKey('subject-M')), findsOneWidget);
      expect(find.text('Mathematik · Default'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('subject-M')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preset-ff1976d2')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 40)); // close the sheet
      await tester.pumpAndSettle();
      final saved = (store.values['timetable'] as Map)['subjectColors'] as Map;
      expect(saved, {'M': 0xFF1976D2});
      final swatch = tester.widget<Container>(
        find.byKey(const ValueKey('subject-swatch-M')),
      );
      expect(
        (swatch.decoration! as BoxDecoration).color,
        const Color(0xFF1976D2),
      );

      await tester.tap(find.byKey(const ValueKey('subject-reset-M')));
      await tester.pumpAndSettle();
      expect(
        (store.values['timetable'] as Map)['subjectColors'] as Map,
        isEmpty,
      );

      // Colors from another account (unknown here) are listed too.
      final notifier = ProviderScope.containerOf(
        tester.element(find.byType(SubjectColorsScreen)),
      ).read(timetableSettingsProvider.notifier);
      notifier.update(
        (s) => s
            .withSubjectColor('D', 0xFFD32F2F)
            .withSubjectColor('LAT', 0xFF388E3C),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('subject-LAT')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reset-subject-colors')));
      await tester.pumpAndSettle();
      expect(
        ProviderScope.containerOf(
          tester.element(find.byType(SubjectColorsScreen)),
        ).read(timetableSettingsProvider).subjectColors,
        isEmpty,
      );
      expect(find.byKey(const ValueKey('subject-LAT')), findsNothing);
      // Undo brings them back.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('subject-LAT')), findsOneWidget);

      // Without Undo, the snackbar times out on its own.
      await tester.tap(find.byKey(const ValueKey('reset-subject-colors')));
      await tester.pumpAndSettle();
      expect(find.text('Subject colors reset'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Subject colors reset'), findsNothing);
    });

    testWidgets('subject color shows in the preview', (tester) async {
      store.values['timetable'] = const TimetableSettings(
        subjectColors: {'M': 0xFF1976D2},
      ).toJson();
      await pump(tester);
      expect(cardColor(tester, 'regular'), const Color(0xFF1976D2));
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
