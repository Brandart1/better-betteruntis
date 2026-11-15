import '../../calendar/calendar_sync_service.dart' show kAppSeedColor;
import '../calendar/calendar_auto_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accessibility.dart';
import 'router.dart';
import 'update_check.dart';

const _seed = kAppSeedColor;

/// Pure black/white scheme for high-contrast mode: every foreground role is
/// [fg], every background role [bg].
ColorScheme monochromeScheme(Brightness b) {
  final light = b == Brightness.light;
  final fg = light ? Colors.black : Colors.white;
  final bg = light ? Colors.white : Colors.black;
  return ColorScheme(
    brightness: b,
    primary: fg,
    onPrimary: bg,
    primaryContainer: bg,
    onPrimaryContainer: fg,
    secondary: fg,
    onSecondary: bg,
    secondaryContainer: bg,
    onSecondaryContainer: fg,
    tertiary: fg,
    onTertiary: bg,
    tertiaryContainer: bg,
    onTertiaryContainer: fg,
    error: fg,
    onError: bg,
    errorContainer: bg,
    onErrorContainer: fg,
    surface: bg,
    onSurface: fg,
    onSurfaceVariant: fg,
    surfaceDim: bg,
    surfaceBright: bg,
    surfaceContainerLowest: bg,
    surfaceContainerLow: bg,
    surfaceContainer: bg,
    surfaceContainerHigh: bg,
    surfaceContainerHighest: bg,
    outline: fg,
    outlineVariant: fg,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: fg,
    onInverseSurface: bg,
    inversePrimary: bg,
    surfaceTint: Colors.transparent,
  );
}

/// Turns everything still drawn in color (school colors, avatars, …) gray.
const _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

const _identity = ColorFilter.matrix(<double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
]);

class BetterUntisApp extends ConsumerWidget {
  const BetterUntisApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textScale = ref.watch(
      accessibilityProvider.select((a) => a.textScale),
    );
    final contrast = ref.watch(accessibilityProvider.select((a) => a.contrast));
    ThemeData theme(Brightness b) {
      if (contrast == ContrastMode.off) {
        return ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
          useMaterial3: true,
        );
      }
      final cs = monochromeScheme(b);
      return ThemeData(
        colorScheme: cs,
        useMaterial3: true,
        dividerColor: cs.onSurface,
        // Filled fields and chips would vanish on a same-colored background.
        inputDecorationTheme: InputDecorationTheme(
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: cs.onSurface),
          ),
        ),
      );
    }

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'BetterBetterUntis',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: switch (contrast) {
        ContrastMode.off => ThemeMode.system,
        ContrastMode.light => ThemeMode.light,
        ContrastMode.dark => ThemeMode.dark,
      },
      routerConfig: router,
      builder: (context, child) {
        // Accessibility text size multiplies the system's.
        final mq = MediaQuery.of(context);
        // Always wrapped (identity when off), so toggling the mode keeps
        // the widget tree and the open screens.
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(mq.textScaler.scale(1) * textScale),
          ),
          child: ColorFiltered(
            colorFilter: contrast == ContrastMode.off ? _identity : _grayscale,
            child: UpdateChecker(
              navigatorKey: router.routerDelegate.navigatorKey,
              child: CalendarAutoSync(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
      },
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('de')],
    );
  }
}
