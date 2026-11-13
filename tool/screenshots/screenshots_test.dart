// Renders the README screenshots from the real screens with demo data
// (made-up school and names). Not part of `flutter test` (lives in tool/);
// regenerate with tool/screenshots/update.sh.
import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone screen is rendered at 1080 × 2340 px, then placed in a frame
/// (title on top, light/dark split) of 1080 × 1920 px, like store images.
const _phone = Size(1080, 2340);
const _dpr = 2.75;
const _out = Size(1080, 1920);

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

/// Right part of the frame, cut diagonally (dark half).
class _DarkHalf extends CustomClipper<Path> {
  const _DarkHalf(this.visibleHeight);
  final double visibleHeight;

  @override
  Path getClip(Size size) {
    // Line from 62 % (top) to 30 % (bottom of the visible part) of the width.
    final top = size.width * 0.62;
    final slope = (size.width * 0.30 - top) / visibleHeight;
    return Path()
      ..moveTo(top, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(top + slope * size.height, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_DarkHalf old) => old.visibleHeight != visibleHeight;
}

/// The store-style image: [title] above a phone showing [light] with the
/// right part replaced by [dark] (if given).
Widget _frame(String title, ui.Image light, ui.Image? dark) {
  const titleHeight = 400.0;
  const width = 756.0; // 70 % of the image
  final height = width * _phone.height / _phone.width;
  const left = (1080 - width) / 2;
  const radius = Radius.circular(48);
  Widget shot(ui.Image i) => RawImage(
    image: i,
    width: width,
    height: height,
    fit: BoxFit.fill,
    filterQuality: FilterQuality.high,
  );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: Colors.white,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: titleHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 64,
                    height: 1.3,
                    color: Color(0xFF1B1B1F),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: titleHeight,
            left: left,
            width: width,
            height: height,
            child: Container(
              // Outline, so a white screen still stands out from the page.
              foregroundDecoration: BoxDecoration(
                borderRadius: const BorderRadius.all(radius),
                border: Border.all(color: const Color(0x22000000), width: 2),
              ),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(radius),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 60,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(radius),
                child: Stack(
                  children: [
                    shot(light),
                    if (dark != null)
                      ClipPath(
                        clipper: _DarkHalf(_out.height - titleHeight),
                        child: shot(dark),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUpAll(_loadFonts);

  const phoneKey = ValueKey('phone');

  /// Renders [home] as a phone screen and returns the image.
  Future<ui.Image> render(
    WidgetTester t,
    Widget home,
    Brightness brightness,
    AccessibilitySettings a11y,
    Future<void> Function(WidgetTester t)? before,
  ) async {
    t.view.physicalSize = _phone;
    t.view.devicePixelRatio = _dpr;
    // A fresh tree, so no state leaks between the light and dark render.
    await t.pumpWidget(const SizedBox());
    final store = MemorySettingsStore({
      AccessibilityNotifier.storeKey: a11y.toJson(),
      TimetableSettingsNotifier.storeKey: _colors.toJson(),
    });
    await t.pumpWidget(
      RepaintBoundary(
        key: phoneKey,
        child: ProviderScope(
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
      ),
    );
    await t.pumpAndSettle();
    if (before != null) {
      await before(t);
      await t.pumpAndSettle();
    }
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.byKey(phoneKey),
    );
    return (await t.runAsync(() => boundary.toImage(pixelRatio: _dpr)))!;
  }

  Future<void> shoot(
    WidgetTester t,
    String name,
    String title,
    Widget home, {
    AccessibilitySettings Function(Brightness b) a11y = _noA11y,
    Future<void> Function(WidgetTester t)? before,
    bool split = true,
  }) async {
    addTearDown(t.view.reset);
    final light = await render(
      t,
      home,
      Brightness.light,
      a11y(Brightness.light),
      before,
    );
    final dark = split
        ? await render(t, home, Brightness.dark, a11y(Brightness.dark), before)
        : null;
    t.view.physicalSize = _out;
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_frame(title, light, dark));
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('../../docs/screenshots/$name.png'),
    );
    light.dispose();
    dark?.dispose();
  }

  testWidgets(
    'week',
    (t) => shoot(
      t,
      'week',
      'Your whole week\nat a glance',
      const TimetableScreen(),
    ),
  );

  testWidgets(
    'lesson details',
    (t) => shoot(
      t,
      'lesson',
      'Every detail\nof every lesson',
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
      split: false,
    ),
  );

  testWidgets(
    'day view',
    (t) => shoot(
      t,
      'day',
      'A day view that\nreads itself aloud',
      const TimetableScreen(),
      a11y: (_) =>
          const AccessibilitySettings(largeDayHeaders: true, speakButton: true),
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
      'Homework with\ndue dates and files',
      const InfoCenterScreen(),
      before: (t) => t.tap(find.text('Homework').first),
      split: false,
    ),
  );

  testWidgets(
    'absences',
    (t) => shoot(
      t,
      'absences',
      'All absences,\nexcused or not',
      const InfoCenterScreen(),
      before: (t) => t.tap(find.text('Absences').first),
      split: false,
    ),
  );

  testWidgets(
    'high contrast',
    (t) => shoot(
      t,
      'contrast',
      'High contrast\nfor easier reading',
      const TimetableScreen(),
      a11y: (b) => AccessibilitySettings(
        contrast: b == Brightness.dark ? ContrastMode.dark : ContrastMode.light,
      ),
    ),
  );

  testWidgets(
    'exams',
    (t) => shoot(
      t,
      'exams',
      'Every exam\nin one place',
      const InfoCenterScreen(),
      before: (t) => t.tap(find.text('Exams').first),
      split: false,
    ),
  );

  testWidgets(
    'settings',
    (t) => shoot(
      t,
      'settings',
      'Make it look\nthe way you like',
      const TimetableSettingsScreen(),
    ),
  );
}

AccessibilitySettings _noA11y(Brightness _) => const AccessibilitySettings();
