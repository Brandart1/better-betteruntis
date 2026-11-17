import 'dart:io';

import 'package:better_betteruntis/ui/common/markdown_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<String>> pump(
  WidgetTester tester,
  String md, {
  double textScale = 1,
  double width = 400,
}) async {
  final tapped = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: MarkdownText(md, onLinkTap: tapped.add),
            ),
          ),
        ),
      ),
    ),
  );
  return tapped;
}

/// All styled spans of the rendered rich text.
List<TextSpan> spans(WidgetTester tester) {
  final out = <TextSpan>[];
  for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
    r.text.visitChildren((s) {
      if (s is TextSpan && s.text != null) out.add(s);
      return true;
    });
  }
  return out;
}

void main() {
  testWidgets('headings, bullets, bold, code', (tester) async {
    await pump(
      tester,
      '## New\n\n- **Bold** item with `code`\n- second\n\nPlain paragraph.\n',
    );
    final h = spans(tester).firstWhere((s) => s.text == 'New');
    expect(h.style?.fontWeight, FontWeight.bold);
    expect(find.text('•'), findsNWidgets(2));
    expect(find.text('Plain paragraph.'), findsOneWidget);
    final all = spans(tester);
    expect(
      all.firstWhere((s) => s.text == 'Bold').style?.fontWeight,
      FontWeight.bold,
    );
    expect(
      all.firstWhere((s) => s.text == 'code').style?.fontFamily,
      'monospace',
    );
  });

  testWidgets('links are tappable, only http, https and mailto', (
    tester,
  ) async {
    final tapped = await pump(
      tester,
      '[a](https://example.com) [m](mailto:x@y.z) [d](WEB.md) '
      '[j](javascript:alert) https://bare.example/x',
    );
    for (final label in ['a', 'm', 'd', 'j', 'https://bare.example/x']) {
      final s = spans(tester).firstWhere((s) => s.text == label);
      (s.recognizer! as TapGestureRecognizer).onTap!();
    }
    expect(tapped, [
      'https://example.com',
      'mailto:x@y.z',
      'https://bare.example/x',
    ]);
  });

  testWidgets('empty input renders nothing', (tester) async {
    await pump(tester, '');
    expect(find.byType(RichText), findsNothing);
  });

  testWidgets('large text and narrow width do not overflow', (tester) async {
    await pump(
      tester,
      '# Title\n\n### Fixed\n- A long bullet with **bold** and '
      '[a link](https://example.com/very/long/path) that must wrap properly\n'
      '  - nested item `some_long_identifier_name_here`\n',
      textScale: 3,
      width: 200,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every bundled release note renders without raw markers', (
    tester,
  ) async {
    final dir = Directory('assets/release_notes');
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.md')) continue;
      await pump(tester, f.readAsStringSync());
      for (final s in spans(tester)) {
        if (s.style?.fontFamily == 'monospace') continue;
        expect(s.text, isNot(contains('**')), reason: f.path);
        expect(s.text, isNot(contains('](')), reason: f.path);
      }
    }
  });
}
