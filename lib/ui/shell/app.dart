import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

const _seed = Color(0xFF3F6FD8);

class BetterUntisApp extends ConsumerWidget {
  const BetterUntisApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
      useMaterial3: true,
    );
    return MaterialApp.router(
      title: 'BetterBetterUntis',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('de')],
    );
  }
}
