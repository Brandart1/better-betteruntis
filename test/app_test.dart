import 'package:better_betteruntis/app/routing_api.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/data/data_providers.dart';
import 'package:better_betteruntis/data/db/database.dart';
import 'package:better_betteruntis/data/secret_store.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/ui/shell/app.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('fresh install → demo login → timetable shows teachers', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final fake = FakeUntisApi(latency: Duration.zero);
    final api = RoutingUntisApi(real: fake, demo: fake);
    final db = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          untisApiProvider.overrideWithValue(api),
          ...dataOverrides(database: db, secrets: MemorySecretStore()),
        ],
        child: const BetterUntisApp(),
      ),
    );
    await tester.pumpAndSettle();

    // No accounts → redirected to login.
    expect(find.text('Try the demo'), findsOneWidget);

    await tester.ensureVisible(find.text('Try the demo'));
    await tester.tap(find.text('Try the demo'));
    // Real DB / stream work needs real async time.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('MUE', findRichText: true).evaluate().isNotEmpty) break;
    }
    if (find.textContaining('MUE', findRichText: true).evaluate().isEmpty) {
      debugDumpApp();
    }

    // Home timetable with teacher short names rendered in lesson cards.
    expect(find.byKey(const ValueKey('week-label')), findsOneWidget);
    expect(find.textContaining('MUE', findRichText: true), findsWidgets);

    await db.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
