// Renders the README screenshots from the real screens with demo data
// (made-up school and names). Not part of `flutter test` (lives in tool/);
// regenerate with tool/screenshots/update.sh.
import 'dart:io';

import 'package:better_betteruntis/core/accessibility.dart';
import 'package:better_betteruntis/core/info.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_info.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/infocenter/info_center_screen.dart';
import 'package:better_betteruntis/ui/settings/timetable_settings_screen.dart';
import 'package:better_betteruntis/ui/shell/app.dart';
import 'package:better_betteruntis/ui/timetable/day_speech.dart';
import 'package:better_betteruntis/ui/timetable/lesson_card.dart';
import 'package:better_betteruntis/ui/timetable/timetable_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone size: 1080 × 2340 px.
const _size = Size(1080, 2340);
const _dpr = 2.75;

class _SilentSpeaker implements Speaker {
  final _speaking = ValueNotifier(false);
  @override
  ValueListenable<bool> get speaking => _speaking;
  @override
  Future<void> speak(
    String text,
    SpeechLanguage language, {
    double rate = 1,
  }) async {}
  @override
  Future<void> stop() async {}
}

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  final dir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Italic.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  // Roboto lacks some symbols (e.g. "→"); phones fall back to other fonts,
  // the test renderer only to what is loaded here.
  const dejavu = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
  if (File(dejavu).existsSync()) {
    final loader = FontLoader('Fallback')
      ..addFont(
        Future.value(ByteData.sublistView(File(dejavu).readAsBytesSync())),
      );
    await loader.load();
  }
}

ThemeData _theme(Brightness b, ContrastMode contrast) => ThemeData(
  colorScheme: contrast == ContrastMode.off
      ? ColorScheme.fromSeed(seedColor: const Color(0xFF3F6FD8), brightness: b)
      : monochromeScheme(b),
  useMaterial3: true,
  fontFamilyFallback: const ['Fallback'],
);

/// Custom subject colors, to show them off (keys are subject short names).
const _colors = TimetableSettings(
  subjectColors: {
    'M': 0xFF90CAF9, // blue
    'D': 0xFFFFCC80, // orange
    'E': 0xFFA5D6A7, // green
    'PH': 0xFFB39DDB, // purple
    'CH': 0xFF80CBC4, // teal
    'BIO': 0xFFC5E1A5, // light green
    'GE': 0xFFBCAAA4, // brown
    'SP': 0xFFFFAB91, // coral
    'INF': 0xFF81D4FA, // light blue
    'KU': 0xFFF48FB1, // pink
    'REL': 0xFFFFF59D, // yellow
    'ETH': 0xFFE6EE9C, // lime
  },
);

void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(
    WidgetTester t,
    String name,
    Widget home, {
    Brightness brightness = Brightness.light,
    AccessibilitySettings a11y = const AccessibilitySettings(),
    Future<void> Function(WidgetTester t)? before,
  }) async {
    t.view.physicalSize = _size;
    t.view.devicePixelRatio = _dpr;
    addTearDown(t.view.reset);
    final store = MemorySettingsStore({
      AccessibilityNotifier.storeKey: a11y.toJson(),
      TimetableSettingsNotifier.storeKey: _colors.toJson(),
    });
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          speakerProvider.overrideWithValue(_SilentSpeaker()),
          timetableRepositoryProvider.overrideWithValue(
            FakeTimetableRepository(),
          ),
          infoCenterRepositoryProvider.overrideWithValue(
            FakeInfoCenterRepository(),
          ),
          activeAccountProvider.overrideWith(
            (ref) => Stream.value(demoAccount()),
          ),
          nameResolverProvider.overrideWith(
            (ref) => Stream<NameResolver>.value(demoNames()),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light, a11y.contrast),
          darkTheme: _theme(Brightness.dark, a11y.contrast),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en')],
          home: home,
        ),
      ),
    );
    await t.pumpAndSettle();
    if (before != null) {
      await before(t);
      await t.pumpAndSettle();
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../docs/screenshots/$name.png'),
    );
  }

  testWidgets('week', (t) => shoot(t, 'week', const TimetableScreen()));

  testWidgets(
    'lesson details',
    (t) => shoot(
      t,
      'lesson',
      const TimetableScreen(),
      before: (t) async {
        // A substitution shows the most (old → new teacher).
        final cards = find.byType(LessonCard);
        final i = List.generate(cards.evaluate().length, (i) => i).firstWhere(
          (i) => t.widget<LessonCard>(cards.at(i)).block.isIrregular,
          orElse: () => 0,
        );
        await t.tap(cards.at(i));
      },
    ),
  );

  testWidgets(
    'day view',
    (t) => shoot(
      t,
      'day',
      const TimetableScreen(),
      a11y: const AccessibilitySettings(
        largeDayHeaders: true,
        speakButton: true,
      ),
      // Tuesday of the demo week has an exam, a substitution and a
      // cancelled lesson (Friday is a holiday).
      before: (t) => t.tap(find.byKey(const ValueKey('day-header-2'))),
    ),
  );

  testWidgets(
    'info center',
    (t) => shoot(
      t,
      'info',
      const InfoCenterScreen(),
      before: (t) => t.tap(find.text('Homework').first),
    ),
  );

  testWidgets(
    'high contrast',
    (t) => shoot(
      t,
      'contrast',
      const TimetableScreen(),
      a11y: const AccessibilitySettings(contrast: ContrastMode.light),
    ),
  );

  testWidgets(
    'settings',
    (t) => shoot(t, 'settings', const TimetableSettingsScreen()),
  );

  testWidgets(
    'week dark',
    (t) => shoot(
      t,
      'week-dark',
      const TimetableScreen(),
      brightness: Brightness.dark,
    ),
  );
}
