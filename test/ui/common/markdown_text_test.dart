import 'dart:io';

import 'package:better_betteruntis/ui/common/markdown_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String runs(String md) => parseInline(md).join(' ');

void main() {
  group('blocks', () {
    test('headings, paragraphs and lists', () {
      final b = parseMarkdown('''
## New in this release

### New
- **Custom exams:** first line
  continued here
  - nested item
- second
1. one
2) two

Plain paragraph
on two lines.
---
# Title #
''');
      expect(
        [for (final x in b) (x.kind, x.level, x.marker, x.text)],
        [
          (MdBlockKind.heading, 2, null, 'New in this release'),
          (MdBlockKind.heading, 3, null, 'New'),
          (
            MdBlockKind.bullet,
            1,
            '•',
            'Custom exams: first line continued here',
          ),
          (MdBlockKind.bullet, 2, '•', 'nested item'),
          (MdBlockKind.bullet, 1, '•', 'second'),
          (MdBlockKind.ordered, 1, '1.', 'one'),
          (MdBlockKind.ordered, 1, '2.', 'two'),
          (MdBlockKind.paragraph, 0, null, 'Plain paragraph on two lines.'),
          (MdBlockKind.heading, 1, null, 'Title'),
        ],
      );
    });

    test('CRLF, tabs, quotes and empty input', () {
      expect(parseMarkdown(''), isEmpty);
      expect(parseMarkdown('\n\n  \n'), isEmpty);
      final b = parseMarkdown('- a\r\n\t- b\r\n> quoted');
      expect(
        [for (final x in b) (x.level, x.text)],
        [(1, 'a'), (2, 'b quoted')],
      );
      expect(parseMarkdown('> quoted').single.text, 'quoted');
    });

    test('#hashtag without a space is text', () {
      expect(parseMarkdown('#notaheading').single.kind, MdBlockKind.paragraph);
    });
  });

  group('inline', () {
    test('bold, italic, code', () {
      expect(
        runs('**Bold** and *it* and _it2_ and `co*de*`'),
        'MdRun(b "Bold") MdRun( " and ") MdRun(i "it") MdRun( " and ") '
        'MdRun(i "it2") MdRun( " and ") MdRun(c "co*de*")',
      );
      expect(runs('**bold *both***'), 'MdRun(b "bold ") MdRun(b,i "both")');
      expect(runs('__bold__'), 'MdRun(b "bold")');
    });

    test('unmatched or spaced delimiters stay literal', () {
      expect(runs('5 * 3 = 15'), 'MdRun( "5 * 3 = 15")');
      expect(runs('a ** b'), 'MdRun( "a ** b")');
      expect(runs('*open'), 'MdRun( "*open")');
      expect(runs('snake_case_name'), 'MdRun( "snake_case_name")');
      expect(runs(r'\*not italic\*'), 'MdRun( "*not italic*")');
    });

    test('links and bare URLs', () {
      expect(
        runs('Use [AltStore](https://altstore.io) or [**Side**](https://s.io)'),
        'MdRun( "Use ") MdRun(a=https://altstore.io "AltStore") '
        'MdRun( " or ") MdRun(b,a=https://s.io "Side")',
      );
      expect(
        runs('See https://example.com/x, then go.'),
        'MdRun( "See ") MdRun(a=https://example.com/x "https://example.com/x") '
        'MdRun( ", then go.")',
      );
      // Relative and script links are not tappable.
      expect(runs('[docs](WEB.md)'), 'MdRun( "docs")');
      expect(runs('[x](javascript:alert(1))'), 'MdRun( "x)")');
      expect(runs('[no target]'), 'MdRun( "[no target]")');
    });
  });

  test('every bundled release note parses without leftover markup', () {
    final dir = Directory('assets/release_notes');
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.md')) continue;
      for (final b in parseMarkdown(f.readAsStringSync())) {
        for (final r in b.runs.where((r) => !r.code)) {
          expect(r.text, isNot(contains('**')), reason: '${f.path}: $b');
          expect(r.text, isNot(contains('](')), reason: '${f.path}: $b');
        }
      }
    }
  });

  testWidgets('renders styles and opens links on tap', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownText(
            '### Fixed\n- **Bold** item with [a link](https://example.com)\n',
            onLinkTap: tapped.add,
          ),
        ),
      ),
    );
    expect(find.text('Fixed'), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text as TextSpan)
        .firstWhere((s) => s.toPlainText().contains('a link'));
    final spans = <TextSpan>[];
    rich.visitChildren((s) {
      if (s is TextSpan && s.text != null) spans.add(s);
      return true;
    });
    final bold = spans.firstWhere((s) => s.text == 'Bold');
    expect(bold.style?.fontWeight, FontWeight.bold);
    final link = spans.firstWhere((s) => s.text == 'a link');
    (link.recognizer! as TapGestureRecognizer).onTap!();
    expect(tapped, ['https://example.com']);
  });
}
