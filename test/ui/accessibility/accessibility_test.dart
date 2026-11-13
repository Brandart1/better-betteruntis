import 'package:better_betteruntis/core/accessibility.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/accessibility/accessibility_screen.dart';
import 'package:better_betteruntis/ui/shell/app.dart';
import 'package:better_betteruntis/ui/timetable/day_speech.dart';
import 'package:better_betteruntis/ui/timetable/lesson_layout.dart';
import 'package:better_betteruntis/ui/timetable/lesson_style.dart';
import 'package:better_betteruntis/ui/timetable/timetable_screen.dart';
import 'package:better_betteruntis/ui/timetable/timetable_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSpeaker implements Speaker {
  final spoken = <(String, SpeechLanguage)>[];
  final _speaking = ValueNotifier(false);
  @override
  ValueListenable<bool> get speaking => _speaking;
  @override
  Future<void> speak(String text, SpeechLanguage language) async =>
      spoken.add((text, language));
  @override
  Future<void> stop() async => _speaking.value = false;
}

Period p(
  int id,
  DateTime day,
  int unit, {
  int units = 1,
  int subject = DemoIds.m,
  int teacher = DemoIds.mue,
  int? orgTeacher,
  int room = DemoIds.r101,
  bool cancelled = false,
}) {
  final first = demoTimeGrid.days[1]![unit - 1];
  final last = demoTimeGrid.days[1]![unit + units - 2];
  return Period(
    id: id,
    lessonId: id,
    start: day.add(Duration(minutes: first.start)),
    end: day.add(Duration(minutes: last.end)),
    elements: [
      ElementRef(type: ElementType.subject, id: subject, orgId: subject),
      ElementRef(
        type: ElementType.teacher,
        id: teacher,
        orgId: orgTeacher ?? teacher,
      ),
      ElementRef(type: ElementType.room, id: room, orgId: room),
    ],
    flags: {cancelled ? PeriodFlag.cancelled : PeriodFlag.regular},
  );
}

void main() {
  final monday = DateTime(2026, 11, 9);

  group('settings', () {
    test('json round trip, tolerant', () {
      const a = AccessibilitySettings(
        contrast: ContrastMode.dark,
        dayViewByDefault: true,
        largeDayHeaders: true,
        speakButton: true,
        speechLanguage: SpeechLanguage.de,
        textScale: 1.3,
      );
      expect(AccessibilitySettings.fromJson(a.toJson()), a);
      expect(AccessibilitySettings.fromJson({'textScale': 99}).textScale, 1.0);
      expect(
        AccessibilitySettings.fromJson({'contrast': 'nope', 'speakButton': 1}),
        const AccessibilitySettings(),
      );
      expect(
        AccessibilitySettings.fromJson(null),
        const AccessibilitySettings(),
      );
    });

    test('speech language: device language for "system"', () {
      expect(SpeechLanguage.system.resolve('de'), SpeechLanguage.de);
      expect(SpeechLanguage.system.resolve('fr'), SpeechLanguage.en);
      expect(SpeechLanguage.en.resolve('de'), SpeechLanguage.en);
      expect(SpeechLanguage.de.voiceTag, 'de-DE');
    });

    test('persisted in the settings store', () async {
      final store = MemorySettingsStore();
      final c = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      c
          .read(accessibilityProvider.notifier)
          .update((s) => s.copyWith(contrast: ContrastMode.light));
      await Future<void>.delayed(Duration.zero);
      expect(
        AccessibilitySettings.fromJson(
          store.values[AccessibilityNotifier.storeKey],
        ).contrast,
        ContrastMode.light,
      );
    });
  });

  group('read aloud text', () {
    final names = FakeNameResolver();
    final periods = [
      p(1, monday, 1),
      p(2, monday, 2, units: 2, subject: DemoIds.d, teacher: DemoIds.sch),
      p(3, monday, 4, teacher: DemoIds.web, orgTeacher: DemoIds.mue),
      p(4, monday, 5, subject: DemoIds.e, cancelled: true),
      p(5, monday.add(const Duration(days: 1)), 1),
    ];

    test('English', () {
      expect(
        daySpeech(
          date: monday,
          periods: periods,
          names: names,
          language: SpeechLanguage.en,
        ),
        'Monday, 9 November. '
        'First lesson: Mathematik with Anna Müller in room R101. '
        'Second and third lesson: Deutsch with Peter Schmidt in room R101. '
        'Fourth lesson: Mathematik with Klara Weber in room R101, substitution. '
        'Fifth lesson: Englisch with Anna Müller in room R101, cancelled.',
      );
    });

    test('German, cancelled hidden', () {
      expect(
        daySpeech(
          date: monday,
          periods: periods,
          names: names,
          language: SpeechLanguage.de,
          showCancelled: false,
        ),
        'Montag, 9. November. '
        'Erste Stunde: Mathematik bei Anna Müller in Raum R101. '
        'Zweite und dritte Stunde: Deutsch bei Peter Schmidt in Raum R101. '
        'Vierte Stunde: Mathematik bei Klara Weber in Raum R101, Vertretung.',
      );
    });

    test('empty day and holiday', () {
      final sunday = DateTime(2026, 11, 15);
      expect(
        daySpeech(
          date: sunday,
          periods: periods,
          names: names,
          language: SpeechLanguage.en,
        ),
        'Sunday, 15 November. No lessons.',
      );
      final holidayNames = FakeNameResolver(
        holidays: [
          Holiday(
            id: 1,
            name: 'HB',
            longName: 'Herbstferien',
            start: sunday,
            end: sunday,
          ),
        ],
      );
      expect(
        daySpeech(
          date: sunday,
          periods: const [],
          names: holidayNames,
          language: SpeechLanguage.de,
        ),
        'Sonntag, 15. November. Frei: Herbstferien.',
      );
    });
  });

  group('lesson numbers', () {
    Period at(int id, int h, int m, {int minutes = 45}) {
      final start = monday.add(Duration(hours: h, minutes: m));
      return Period(
        id: id,
        lessonId: id,
        start: start,
        end: start.add(Duration(minutes: minutes)),
        elements: const [
          ElementRef(
            type: ElementType.subject,
            id: DemoIds.m,
            orgId: DemoIds.m,
          ),
        ],
        flags: const {PeriodFlag.regular},
      );
    }

    String speak(List<Period> ps, TimeGrid grid) => daySpeech(
      date: monday,
      periods: ps,
      names: FakeNameResolver(timeGrid: grid),
      language: SpeechLanguage.en,
    );

    test('no school grid (fallback): counted from the day, never times', () {
      final ps = [at(1, 8, 0), at(2, 8, 50), at(3, 9, 50), at(4, 13, 0)];
      final text = speak(ps, TimeGrid.fallback());
      expect(text, contains('First lesson'));
      expect(text, contains('Second lesson'));
      expect(text, contains('Third lesson'));
      expect(text, contains('Fourth lesson'));
      expect(text, isNot(contains(':00')));
    });

    test('grid with letter labels: position in the grid', () {
      const grid = TimeGrid({
        1: [
          TimeUnit(label: 'A', start: 8 * 60, end: 8 * 60 + 45),
          TimeUnit(label: 'B', start: 8 * 60 + 50, end: 9 * 60 + 35),
          TimeUnit(label: 'C', start: 9 * 60 + 50, end: 10 * 60 + 35),
        ],
      });
      expect(speak([at(1, 9, 50)], grid), contains('Third lesson'));
    });

    test('lesson starting a few minutes late still matches its unit', () {
      expect(speak([at(1, 8, 38)], demoTimeGrid), contains('Second lesson'));
    });

    test('one 90-minute period is a double lesson', () {
      expect(
        speak([at(1, 7, 45, minutes: 95)], demoTimeGrid),
        contains('First and second lesson'),
      );
    });

    test('lessons outside the grid: counted from the day', () {
      expect(
        speak([at(1, 16, 0), at(2, 17, 0)], demoTimeGrid),
        allOf(contains('First lesson'), contains('Second lesson')),
      );
    });

    test('lesson sheet numbers hide on the fallback grid', () {
      expect(
        lessonNumbers(
          TimeGrid.fallback(),
          monday.add(const Duration(hours: 8)),
          monday.add(const Duration(hours: 9)),
        ),
        '',
      );
    });
  });

  test('high contrast lesson style is monochrome and outlined', () {
    final cs = monochromeScheme(Brightness.light);
    final s = LessonStyle.of(
      cs,
      LessonBlock([p(1, monday, 1)]),
      const TimetableSettings(regularColor: 0xFFFF0000),
      null,
      true,
    );
    expect(s.background, Colors.white);
    expect(s.foreground, Colors.black);
    expect(s.border, Colors.black);
    final sub = LessonStyle.of(
      cs,
      LessonBlock([
        p(2, monday, 1, teacher: DemoIds.web, orgTeacher: DemoIds.mue),
      ]),
      const TimetableSettings(),
      null,
      true,
    );
    expect(sub.borderWidth, greaterThan(s.borderWidth));
  });

  group('screens', () {
    late FakeSpeaker speaker;
    late MemorySettingsStore store;

    setUp(() {
      speaker = FakeSpeaker();
      store = MemorySettingsStore();
    });

    Future<void> pumpTimetable(WidgetTester t, AccessibilitySettings a) async {
      t.view.physicalSize = const Size(1000, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      store.values[AccessibilityNotifier.storeKey] = a.toJson();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            settingsStoreProvider.overrideWithValue(store),
            speakerProvider.overrideWithValue(speaker),
            timetableRepositoryProvider.overrideWithValue(
              FakeTimetableRepository(),
            ),
            activeAccountProvider.overrideWith(
              (ref) => Stream.value(demoAccount()),
            ),
          ],
          child: const MaterialApp(home: TimetableScreen()),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('defaults: week view, no loudspeaker', (t) async {
      await pumpTimetable(t, const AccessibilitySettings());
      expect(find.byKey(const ValueKey('week-label')), findsOneWidget);
      expect(find.byKey(const ValueKey('speak-day')), findsNothing);
    });

    testWidgets('day view by default with large header', (t) async {
      await pumpTimetable(
        t,
        const AccessibilitySettings(
          dayViewByDefault: true,
          largeDayHeaders: true,
        ),
      );
      expect(find.byKey(const ValueKey('day-label')), findsOneWidget);
      expect(find.byKey(const ValueKey('day-header-large')), findsOneWidget);
      // School day: today, else the next one.
      var d = dateOnly(DateTime.now());
      while (d.weekday > 5) {
        d = addDays(d, 1);
      }
      final large = t.widget<Text>(
        find.byKey(const ValueKey('day-header-large')),
      );
      expect(large.data, contains('${d.day}'));
    });

    testWidgets('loudspeaker reads the shown day in the chosen language', (
      t,
    ) async {
      await pumpTimetable(
        t,
        const AccessibilitySettings(
          dayViewByDefault: true,
          speakButton: true,
          speechLanguage: SpeechLanguage.de,
        ),
      );
      await t.tap(find.byKey(const ValueKey('speak-day')));
      await t.pumpAndSettle();
      expect(speaker.spoken, hasLength(1));
      final (text, lang) = speaker.spoken.single;
      expect(lang, SpeechLanguage.de);
      expect(
        text,
        matches(RegExp(r'^(Montag|Dienstag|Mittwoch|Donnerstag|Freitag), ')),
      );
    });

    testWidgets('accessibility screen changes and themes the app', (t) async {
      t.view.physicalSize = const Size(1000, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            settingsStoreProvider.overrideWithValue(store),
            speakerProvider.overrideWithValue(speaker),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              final c = ref.watch(accessibilityProvider).contrast;
              return MaterialApp(
                theme: c == ContrastMode.off
                    ? ThemeData()
                    : ThemeData(
                        colorScheme: monochromeScheme(Brightness.light),
                      ),
                home: const AccessibilityScreen(),
              );
            },
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('contrast-light')));
      await t.pumpAndSettle();
      final scaffold = t.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold, isNotNull);
      expect(
        Theme.of(t.element(find.text('Accessibility'))).colorScheme.surface,
        Colors.white,
      );
      expect(
        Theme.of(t.element(find.text('Accessibility'))).colorScheme.primary,
        Colors.black,
      );
      // Voice language is only enabled with the loudspeaker.
      expect(find.byKey(const ValueKey('a11y-test-voice')), findsNothing);
      await t.tap(find.byKey(const ValueKey('a11y-speak')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('a11y-test-voice')));
      expect(speaker.spoken, hasLength(1));
      expect(
        AccessibilitySettings.fromJson(
          store.values[AccessibilityNotifier.storeKey],
        ),
        const AccessibilitySettings(
          contrast: ContrastMode.light,
          speakButton: true,
        ),
      );
    });

    testWidgets('text size slider', (t) async {
      t.view.physicalSize = const Size(1000, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            settingsStoreProvider.overrideWithValue(store),
            speakerProvider.overrideWithValue(speaker),
          ],
          child: const MaterialApp(home: AccessibilityScreen()),
        ),
      );
      final slider = find.byKey(const ValueKey('a11y-text-size'));
      await t.tapAt(t.getBottomRight(slider) - const Offset(30, 24));
      await t.pumpAndSettle();
      expect(
        AccessibilitySettings.fromJson(
          store.values[AccessibilityNotifier.storeKey],
        ).textScale,
        AccessibilitySettings.textScales.last,
      );
      expect(find.textContaining('Largest'), findsWidgets);
    });
  });
}
