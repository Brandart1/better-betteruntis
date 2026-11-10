import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Future<void> search(WidgetTester tester, String q) async {
  await tester.enterText(find.byKey(const ValueKey('schoolSearchField')), q);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows welcome and idle hint', (tester) async {
    await Harness().pump(tester);
    expect(find.text('BetterBetterUntis'), findsOneWidget);
    expect(find.text('Find your school'), findsOneWidget);
    expect(find.text('Scan QR code'), findsOneWidget);
    expect(find.text('Enter details manually'), findsOneWidget);
    expect(find.text('Try the demo'), findsOneWidget);
  });

  testWidgets('debounces and shows results', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('schoolSearchField')),
      'goe',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const ValueKey('schoolSearchField')),
      'goethe',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(h.api.searchCalls, ['goethe']);
    expect(find.text('Goethe-Gymnasium'), findsOneWidget);
    expect(find.text('Gasteiner Str. 23, 10717 Berlin'), findsOneWidget);

    await tester.tap(find.text('Goethe-Gymnasium'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('usernameField')), findsOneWidget);
    expect(find.text('Goethe-Gymnasium'), findsOneWidget);
  });

  testWidgets('too many results asks to be more specific', (tester) async {
    await Harness().pump(tester);
    await search(tester, 'gy');
    expect(find.text('Too many results — be more specific'), findsOneWidget);
  });

  testWidgets('no results state', (tester) async {
    await Harness().pump(tester);
    await search(tester, 'zzzzz');
    expect(find.text('No schools found'), findsOneWidget);
  });

  testWidgets('network error offers retry', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await search(tester, 'offline');
    expect(find.text("Couldn't search"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(h.api.searchCalls, ['offline', 'offline']);
  });

  testWidgets('add-account mode shows title and close button', (tester) async {
    await Harness().pump(tester, initial: '/login/add');
    expect(find.text('Add account'), findsOneWidget);
    expect(find.byType(CloseButton), findsOneWidget);
    expect(find.text('BetterBetterUntis'), findsNothing);
  });

  testWidgets('try the demo logs in and goes home', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await tester.tap(find.text('Try the demo'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(h.repo.accounts.single.username, 'demo');
    expect(h.repo.active?.label, 'Demo');
  });

  for (final size in const [Size(320, 568), Size(1024, 1366)]) {
    testWidgets('lays out without overflow at $size', (tester) async {
      final h = Harness();
      await h.pump(tester, size: size);
      await search(tester, 'gymnasium');
      expect(tester.takeException(), isNull);
      h.router.push('/login/form');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      h.router.push('/accounts');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
