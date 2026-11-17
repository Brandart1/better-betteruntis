import 'package:better_betteruntis/ui/infocenter/html_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps an [HtmlBody] and returns the tapped hrefs list.
Future<List<String>> _pump(WidgetTester tester, String html) async {
  final tapped = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HtmlBody(html, onLinkTap: tapped.add),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tapped;
}

/// All text spans of the rendered body.
List<TextSpan> _spans(WidgetTester tester) {
  final out = <TextSpan>[];
  for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
    r.text.visitChildren((s) {
      if (s is TextSpan) out.add(s);
      return true;
    });
  }
  return out;
}

TextSpan _span(WidgetTester tester, String text) =>
    _spans(tester).firstWhere((s) => s.text == text);

String _allText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => r.text.toPlainText())
    .join('|');

void main() {
  group('htmlToPlainText', () {
    test('decodes named and numeric entities', () {
      expect(
        htmlToPlainText(
          'Gr&uuml;&szlig;e &amp; &lt;Tag&gt; &quot;x&quot; &#39;y&#39; &#x20AC; &#8364; &euro;',
        ),
        'Grüße & <Tag> "x" \'y\' € € €',
      );
      expect(htmlToPlainText('a&nbsp;b').replaceAll(' ', ' '), 'a b');
    });

    test('paragraphs and br; whitespace collapsed', () {
      expect(
        htmlToPlainText('<p>Eins\n   zwei</p><p>drei<br>vier<br/>fünf</p>'),
        'Eins zwei\ndrei\nvier\nfünf',
      );
    });

    test('plain text keeps its line breaks', () {
      expect(htmlToPlainText('Zeile 1\nZeile 2 < 3'), 'Zeile 1\nZeile 2 < 3');
    });

    test('unordered, ordered and nested lists', () {
      expect(
        htmlToPlainText(
          '<p>Mitbringen:</p><ul><li>Schuhe</li><li>Jacke<ol><li>rot</li><li>blau</li></ol></li></ul><ol><li>A</li><li>B</li></ol>',
        ),
        'Mitbringen:\n• Schuhe\n• Jacke\n  1. rot\n  2. blau\n1. A\n2. B',
      );
    });

    test('script, style and comments are stripped, unknown tags dropped', () {
      expect(
        htmlToPlainText(
          '<html><head><title>T</title><style>p{color:red}</style></head><body>'
          '<!-- hidden --><script type="text/javascript">alert("x<p>")</script>'
          '<span style="color:red">Hallo</span> <font>Welt</font><img src="x.png"></body></html>',
        ),
        'Hallo Welt',
      );
    });
  });

  group('isSafeHref', () {
    test('only http, https, mailto, tel', () {
      for (final ok in [
        'https://a.b/c',
        'http://a.b',
        'mailto:a@b.de',
        'tel:+43123',
        'HTTPS://A.B',
      ]) {
        expect(isSafeHref(ok), isTrue, reason: ok);
      }
      for (final bad in [
        'javascript:alert(1)',
        ' javascript:alert(1)',
        'data:text/html,x',
        'file:///etc/passwd',
        'intent://x',
        '/relative',
        '',
      ]) {
        expect(isSafeHref(bad), isFalse, reason: bad);
      }
      expect(isSafeHref(null), isFalse);
    });
  });

  group('HtmlBody', () {
    testWidgets('bold, italic and tappable links', (tester) async {
      final tapped = await _pump(
        tester,
        '<p>Am <b>Freitag</b> <i>bitte</i> <a href="https://example.org/x?a=1&amp;b=2">hier</a> lesen.</p>',
      );
      expect(_allText(tester), contains('Am Freitag bitte hier lesen.'));
      expect(_span(tester, 'Freitag').style?.fontWeight, FontWeight.bold);
      expect(_span(tester, 'bitte').style?.fontStyle, FontStyle.italic);
      final rec = _span(tester, 'hier').recognizer! as TapGestureRecognizer;
      rec.onTap!();
      expect(tapped, ['https://example.org/x?a=1&b=2']);
    });

    testWidgets('mailto and tel links are tappable', (tester) async {
      final tapped = await _pump(
        tester,
        '<a href="mailto:a@b.de">Mail</a> <a href="tel:+4312345">Tel</a>',
      );
      (_span(tester, 'Mail').recognizer! as TapGestureRecognizer).onTap!();
      (_span(tester, 'Tel').recognizer! as TapGestureRecognizer).onTap!();
      expect(tapped, ['mailto:a@b.de', 'tel:+4312345']);
    });

    testWidgets('unsafe link schemes are not tappable', (tester) async {
      final tapped = await _pump(
        tester,
        '<a href="javascript:alert(1)">js</a> <a href="data:text/html,x">data</a> '
        '<a href="file:///etc/passwd">file</a> <a href=" JavaScript:alert(2)">js2</a>',
      );
      expect(_allText(tester), contains('js'));
      for (final t in ['js', 'data', 'file', 'js2']) {
        expect(_span(tester, t).recognizer, isNull, reason: t);
      }
      expect(tapped, isEmpty);
    });

    testWidgets('lists render with markers', (tester) async {
      await _pump(
        tester,
        '<p>Mitbringen:</p><ul><li>Schuhe</li><li><b>Jacke</b></li></ul><ol><li>A</li><li>B</li></ol>',
      );
      final text = _allText(tester);
      expect(text, contains('Schuhe'));
      expect(text, contains('Jacke'));
      expect(text, contains('1.'));
      expect(text, contains('2.'));
    });

    testWidgets('script, style and head content are not rendered', (
      tester,
    ) async {
      await _pump(
        tester,
        '<html><head><title>TITEL</title><style>p{color:red}</style></head><body>'
        '<script>alert("BÖSE")</script><p>Hallo</p></body></html>',
      );
      final text = _allText(tester);
      expect(text, contains('Hallo'));
      expect(text, isNot(contains('BÖSE')));
      expect(text, isNot(contains('TITEL')));
      expect(text, isNot(contains('color')));
    });

    testWidgets('bare URLs become links, trailing punctuation excluded', (
      tester,
    ) async {
      final tapped = await _pump(
        tester,
        'Siehe https://example.org/plan.pdf. Danke',
      );
      (_span(tester, 'https://example.org/plan.pdf').recognizer!
              as TapGestureRecognizer)
          .onTap!();
      expect(tapped, ['https://example.org/plan.pdf']);
    });

    testWidgets('images are not loaded; alt text is shown', (tester) async {
      await _pump(
        tester,
        '<p>A <img src="https://tracker.example/x.png" alt="Logo"> B</p><img src="y.png">',
      );
      expect(find.byType(Image), findsNothing);
      expect(_allText(tester), contains('Logo'));
    });

    testWidgets('plain text with line breaks', (tester) async {
      await _pump(tester, 'Zeile 1\nZeile 2');
      expect(_allText(tester), contains('Zeile 1'));
      expect(_allText(tester), contains('Zeile 2'));
    });

    testWidgets('empty body renders nothing', (tester) async {
      await _pump(tester, '<p> </p><!-- nur Kommentar -->');
      expect(find.byType(RichText), findsNothing);
    });
  });
}
