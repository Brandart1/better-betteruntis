import 'package:better_betteruntis/ui/infocenter/info_providers.dart';
import 'package:better_betteruntis/ui/login/id_austria_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Widget _scanner(ValueChanged<String> onCode) =>
    const ColoredBox(color: Colors.black);

void main() {
  testWidgets('login page opens the ID Austria instructions', (tester) async {
    await Harness().pump(tester, qrScanner: _scanner);
    final help = find.byKey(const ValueKey('id-austria-help'));
    await tester.ensureVisible(help);
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(find.text('Log in with ID Austria'), findsOneWidget);
    expect(
      find.text('Log in to bildung.gv.at with ID Austria'),
      findsOneWidget,
    );
    expect(find.textContaining('Zugriff über Untis Mobile'), findsOneWidget);
  });

  testWidgets('scan button opens the QR scanner directly', (tester) async {
    await Harness().pump(
      tester,
      initial: '/login/idaustria',
      qrScanner: _scanner,
    );
    final scan = find.byKey(const ValueKey('id-austria-scan'));
    await tester.ensureVisible(scan);
    await tester.tap(scan);
    await tester.pumpAndSettle();
    expect(find.text('Paste link instead'), findsOneWidget);
  });

  testWidgets('opens bildung.gv.at', (tester) async {
    final opened = <Uri>[];
    await Harness().pump(
      tester,
      initial: '/login/idaustria',
      overrides: [
        urlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('open-bildungsportal')));
    await tester.pump();
    expect(opened, [bildungsportal]);
  });

  testWidgets('lays out without overflow on a small phone', (tester) async {
    await Harness().pump(
      tester,
      initial: '/login/idaustria',
      size: const Size(320, 568),
    );
    expect(tester.takeException(), isNull);
  });
}
