import 'package:better_betteruntis/ui/infocenter/html_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseHtml', () {
    test('decodes named and numeric entities', () {
      expect(
        htmlToPlainText('Gr&uuml;&szlig;e &amp; &lt;Tag&gt; &quot;x&quot; &#39;y&#39; &#x20AC; &#8364; &euro;'),
        'Grüße & <Tag> "x" \'y\' € € €',
      );
      expect(htmlToPlainText('a&nbsp;b'), 'a b');
      expect(htmlToPlainText('&unknown; &#0;'), '&unknown; &#0;');
    });

    test('paragraphs and br; whitespace collapsed', () {
      final blocks = parseHtml('<p>Eins\n   zwei</p><p>drei<br>vier<br/>fünf</p>');
      expect(blocks.map((b) => b.text), ['Eins zwei', 'drei\nvier\nfünf']);
    });

    test('plain text keeps its line breaks', () {
      expect(htmlToPlainText('Zeile 1\nZeile 2 < 3'), 'Zeile 1\nZeile 2 < 3');
    });

    test('unordered, ordered and nested lists', () {
      final blocks = parseHtml(
        '<p>Mitbringen:</p><ul><li>Schuhe</li><li>Jacke<ol><li>rot</li><li>blau</li></ol></li></ul><ol><li>A</li><li>B</li></ol>',
      );
      expect(blocks.map((b) => (b.marker, b.depth, b.text)), [
        (null, 0, 'Mitbringen:'),
        ('•', 1, 'Schuhe'),
        ('•', 1, 'Jacke'),
        ('1.', 2, 'rot'),
        ('2.', 2, 'blau'),
        ('1.', 1, 'A'),
        ('2.', 1, 'B'),
      ]);
    });

    test('bold, italic and links', () {
      final runs = parseHtml(
        '<p>Am <b>Freitag</b> <i>bitte</i> <a href="https://example.org/x?a=1&amp;b=2">hier</a> lesen.</p>',
      ).single.runs;
      final bold = runs.firstWhere((r) => r.text == 'Freitag');
      expect(bold.bold, isTrue);
      expect(runs.firstWhere((r) => r.text == 'bitte').italic, isTrue);
      final link = runs.firstWhere((r) => r.text == 'hier');
      expect(link.href, 'https://example.org/x?a=1&b=2');
      expect(runs.map((r) => r.text).join(), 'Am Freitag bitte hier lesen.');
    });

    test('bare URLs become links; unsafe schemes do not', () {
      final runs = parseHtml('Siehe https://example.org/plan.pdf. Danke').single.runs;
      expect(runs.firstWhere((r) => r.href != null).text, 'https://example.org/plan.pdf');
      final js = parseHtml('<a href="javascript:alert(1)">klick</a>').single.runs.single;
      expect(js.href, isNull);
      expect(parseHtml('<a href=\'mailto:a@b.de\'>Mail</a>').single.runs.single.href, 'mailto:a@b.de');
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

  testWidgets('HtmlBody renders links tappable', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HtmlBody(
            '<p>Infos <a href="https://example.org">hier</a></p><ul><li><b>fett</b></li></ul>',
            onLinkTap: (h) => tapped = h,
          ),
        ),
      ),
    );
    expect(find.textContaining('Infos hier', findRichText: true), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
    final rich = tester.widget<RichText>(
      find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == 'Infos hier'),
    );
    TapGestureRecognizer? rec;
    rich.text.visitChildren((s) {
      if (s is TextSpan && s.recognizer is TapGestureRecognizer) {
        rec = s.recognizer! as TapGestureRecognizer;
      }
      return true;
    });
    rec!.onTap!();
    expect(tapped, 'https://example.org');
  });
}
