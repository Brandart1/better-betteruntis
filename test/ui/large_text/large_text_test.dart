// Every screen on a small phone with very large text: nothing may overflow.
// Android allows up to 200 % font size; the app's own text size goes up to
// 150 % on top of that (together capped at 250 %, see AppTextScaler).
import 'dart:io';

import 'package:better_betteruntis/app/routing_api.dart';
import 'package:better_betteruntis/core/accessibility.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/data/data_providers.dart';
import 'package:better_betteruntis/data/db/database.dart';
import 'package:better_betteruntis/data/secret_store.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/ui/shell/app.dart';
import 'package:better_betteruntis/ui/timetable/day_speech.dart';
import 'package:better_betteruntis/ui/timetable/lesson_card.dart';
import 'package:better_betteruntis/ui/timetable/timetable_canvas.dart';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Small Android phone: 360 × 740 dp.
const phone = Size(360, 740);

const routes = [
  '/',
  '/accessibility',
  '/browse',
  '/exams',
  '/info',
  '/accounts',
  '/calendar',
  '/sync',
  '/whats-new',
  '/settings',
  '/login/add',
  '/login/form',
];

/// Real Roboto (from the Flutter SDK) instead of the test font's squares:
/// realistic widths, and readable review screenshots.
Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    if (!files.every((f) => File('$dir/$f').existsSync())) return;
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())),
      );
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(_loadRoboto);

  test('app text size multiplies the system one, capped at 250 %', () {
    const s = AppTextScaler(TextScaler.linear(2), 1.5);
    expect(s.scale(10), 25);
    expect(
      const AppTextScaler(TextScaler.linear(1.2), 1.15).scale(10),
      closeTo(13.8, 1e-9),
    );
    expect(const AppTextScaler(TextScaler.noScaling, 1).scale(14), 14);
  });

  for (final (system, app) in [(2.0, 1.0), (2.0, 1.5)]) {
    testWidgets('font ${system * 100}% × app ${app * 100}%: no overflow', (
      tester,
    ) async {
      tester.view.physicalSize = phone * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = system;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final errors = <String>[];
      var where = 'start';

      final fake = FakeUntisApi(latency: Duration.zero);
      final api = RoutingUntisApi(real: fake, demo: fake);
      final db = AppDatabase(NativeDatabase.memory());
      final store = MemorySettingsStore()
        ..values[AccessibilityNotifier.storeKey] = AccessibilitySettings(
          textScale: app,
          speakButton: true,
        ).toJson();

      Future<void> settle() async {
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 100));
          final e = tester.takeException();
          if (e != null) {
            errors.add('$where: ${e.toString().split('\n').first}');
          }
        }
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            untisApiProvider.overrideWithValue(api),
            ...dataOverrides(database: db, secrets: MemorySecretStore()),
            settingsStoreProvider.overrideWithValue(store),
            speakerProvider.overrideWithValue(_SilentSpeaker()),
          ],
          child: const BetterUntisApp(),
        ),
      );
      await settle();
      where = '/login';
      for (final w in find.byType(Text).evaluate()) {
        debugPrint('TXT ${(w.widget as Text).data}');
      }
      debugPrint('ERRS $errors');
      await tester.scrollUntilVisible(
        find.text('Try the demo'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // The button may sit at the very edge; press it directly.
      tester
          .widget<ButtonStyleButton>(
            find.ancestor(
              of: find.text('Try the demo'),
              matching: find.bySubtype<ButtonStyleButton>(),
            ),
          )
          .onPressed!();
      await settle();

      Future<void> shot(String name) async {
        const dir = String.fromEnvironment('SHOTS');
        if (dir.isEmpty) return;
        final file = name.replaceAll('/', '_');
        await expectLater(
          find.byType(BetterUntisApp),
          matchesGoldenFile(Uri.file('$dir/${system}x$app$file.png')),
        );
      }

      /// Texts narrower than their longest word (broken mid-word or cut).
      void checkSqueezed() {
        // Lesson cards (week grid, day view) clip their text on purpose:
        // the lesson sheet shows everything.
        final skip = <RenderObject>{};
        void collect(RenderObject o) {
          skip.add(o);
          o.visitChildren(collect);
        }

        for (final e in [
          ...find.byType(TimetableCanvas, skipOffstage: false).evaluate(),
          ...find.byType(LessonCard, skipOffstage: false).evaluate(),
        ]) {
          final r = e.renderObject;
          if (r != null) collect(r);
        }
        void visit(RenderObject o) {
          if (skip.contains(o)) return;
          if (o is RenderParagraph && o.attached && o.hasSize) {
            final text = o.text.toPlainText().trim();
            final minWidth = o.getMinIntrinsicWidth(double.infinity);
            // Ending in "…" is fine (previews, long names); broken
            // mid-word, clipped or faded text is not.
            final ellipsis = o.overflow == TextOverflow.ellipsis;
            if (!ellipsis && text.length > 1 && o.size.width + 0.5 < minWidth) {
              errors.add('$where: squeezed "$text"');
            }
          }
          o.visitChildren(visit);
        }

        for (final e in find.byType(Scaffold).hitTestable().evaluate()) {
          visit(e.renderObject!);
        }
      }

      /// Checks the screen, then scrolls its main list page by page.
      Future<void> sweep(String name) async {
        checkSqueezed();
        await shot(name);
        final lists = find
            .byWidgetPredicate(
              (w) =>
                  w is Scrollable &&
                  axisDirectionToAxis(w.axisDirection) == Axis.vertical,
            )
            .hitTestable();
        if (lists.evaluate().isEmpty) return;
        final state = tester.state<ScrollableState>(lists.first);
        for (var page = 1; page < 12; page++) {
          final pos = state.position;
          if (pos.pixels >= pos.maxScrollExtent) break;
          pos.jumpTo(
            (pos.pixels + pos.viewportDimension * 0.8).clamp(
              0,
              pos.maxScrollExtent,
            ),
          );
          await settle();
          checkSqueezed();
          await shot('$name-$page');
        }
      }

      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      for (final r in routes) {
        where = r;
        router.go(r);
        await settle();
        await sweep(r);
      }

      where = 'day view';
      router.go('/');
      await settle();
      await tester.tap(find.byKey(const ValueKey('day-header-2')));
      await settle();
      await shot('day');

      where = 'drawer';
      await tester.tap(find.byTooltip('Open navigation menu'));
      await settle();
      checkSqueezed();
      await shot('drawer');

      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.runAsync(db.close);
      await tester.pump(const Duration(seconds: 1));
      for (final e in errors.toSet()) {
        debugPrint('ERR $e');
      }
      expect(errors.toSet().toList(), isEmpty);
    });
  }
}

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
