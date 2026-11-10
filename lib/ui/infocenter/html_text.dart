/// Minimal HTML → rich text for message bodies.
///
/// Supports paragraphs/divs/headings, `<br>`, ordered/unordered lists, bold,
/// italic, underline and links (http, https, mailto, tel). Bare URLs in text
/// become links too. Entities are decoded; every other tag is dropped, and
/// the contents of script/style/head/title are removed entirely.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A run of text with uniform style.
class HtmlRun {
  const HtmlRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.href,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final String? href;

  bool sameStyle(HtmlRun o) =>
      o.bold == bold &&
      o.italic == italic &&
      o.underline == underline &&
      o.href == href;

  @override
  String toString() =>
      'HtmlRun(${[if (bold) 'b', if (italic) 'i', if (href != null) 'a=$href'].join(',')} "$text")';
}

/// A paragraph or list item.
class HtmlBlock {
  const HtmlBlock(this.runs, {this.marker, this.depth = 0});

  final List<HtmlRun> runs;

  /// "•" or "1." for list items, null for paragraphs.
  final String? marker;

  /// List nesting depth (0 for paragraphs and top-level items... 1-based for
  /// list items).
  final int depth;

  String get text => runs.map((r) => r.text).join();
}

const _dropContent = {'script', 'style', 'head', 'title', 'noscript', 'template'};
const _blockTags = {
  'p', 'div', 'section', 'article', 'header', 'footer', 'blockquote', //
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'table', 'tr', 'pre', 'hr', 'center',
};
const _boldTags = {'b', 'strong', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'th'};
const _italicTags = {'i', 'em', 'cite'};

final _tokenRe = RegExp(
  r'''<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<![^>]*>|<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)((?:[^>"']|"[^"]*"|'[^']*')*)>''',
);
final _hrefRe = RegExp(
  r'''href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
  caseSensitive: false,
);
final _urlRe = RegExp(r'''(https?://[^\s<>"']+[^\s<>"'.,;:!?)\]])''');
final _looksLikeHtml = RegExp(r'<\s*/?\s*[a-zA-Z][^>]*>|&[a-zA-Z#0-9]+;');

/// Parses [html] into blocks. Plain text (no tags) keeps its line breaks.
List<HtmlBlock> parseHtml(String html) {
  if (!_looksLikeHtml.hasMatch(html)) {
    html = html
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('\r\n', '\n')
        .replaceAll('\n', '<br>');
  }
  return _HtmlParser().parse(html);
}

/// Plain-text rendering (for previews and tests).
String htmlToPlainText(String html) => parseHtml(html)
    .map((b) => b.marker == null ? b.text : '${'  ' * (b.depth - 1)}${b.marker} ${b.text}')
    .join('\n');

class _ListState {
  _ListState(this.ordered);
  final bool ordered;
  int counter = 0;
}

class _HtmlParser {
  final _blocks = <HtmlBlock>[];
  var _runs = <HtmlRun>[];
  String? _marker;
  int _depth = 0;
  final _lists = <_ListState>[];
  int _bold = 0, _italic = 0, _underline = 0;
  final _hrefs = <String?>[];
  String? _dropping;

  List<HtmlBlock> parse(String html) {
    var pos = 0;
    for (final m in _tokenRe.allMatches(html)) {
      if (_dropping == null && m.start > pos) {
        _text(html.substring(pos, m.start));
      }
      pos = m.end;
      final name = m.group(2)?.toLowerCase();
      if (name == null) continue; // comment / doctype / CDATA
      final closing = m.group(1) == '/';
      if (_dropping != null) {
        if (closing && name == _dropping) _dropping = null;
        continue;
      }
      final attrs = m.group(3) ?? '';
      final selfClosing = attrs.trimRight().endsWith('/');
      if (closing) {
        _close(name);
      } else {
        _open(name, attrs);
        if (selfClosing) _close(name);
      }
    }
    if (_dropping == null && pos < html.length) _text(html.substring(pos));
    _flush();
    return _blocks;
  }

  void _open(String name, String attrs) {
    if (_dropContent.contains(name)) {
      _dropping = name;
      return;
    }
    if (name == 'br') {
      _append('\n');
      return;
    }
    if (_blockTags.contains(name)) _flush();
    if (name == 'ul' || name == 'ol') {
      _flush();
      _lists.add(_ListState(name == 'ol'));
    } else if (name == 'li') {
      _flush();
      final list = _lists.isEmpty ? null : _lists.last;
      if (list != null) list.counter++;
      _marker = (list?.ordered ?? false) ? '${list!.counter}.' : '•';
      _depth = _lists.isEmpty ? 1 : _lists.length;
    } else if (name == 'td' || name == 'th') {
      if (_runs.isNotEmpty) _append(' ');
    }
    if (_boldTags.contains(name)) _bold++;
    if (_italicTags.contains(name)) _italic++;
    if (name == 'u') _underline++;
    if (name == 'a') {
      final h = _hrefRe.firstMatch(attrs);
      final raw = h == null
          ? null
          : decodeEntities(h.group(1) ?? h.group(2) ?? h.group(3) ?? '').trim();
      _hrefs.add(_safeHref(raw));
    }
  }

  void _close(String name) {
    if (_blockTags.contains(name) || name == 'li') _flush();
    if (name == 'ul' || name == 'ol') {
      _flush();
      if (_lists.isNotEmpty) _lists.removeLast();
    }
    if (_boldTags.contains(name) && _bold > 0) _bold--;
    if (_italicTags.contains(name) && _italic > 0) _italic--;
    if (name == 'u' && _underline > 0) _underline--;
    if (name == 'a' && _hrefs.isNotEmpty) _hrefs.removeLast();
  }

  /// Text node: collapse whitespace, decode entities.
  void _text(String raw) {
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.isEmpty) return;
    _append(decodeEntities(collapsed));
  }

  void _append(String text) {
    final href = _hrefs.lastWhere((h) => h != null, orElse: () => null);
    final pieces = <HtmlRun>[];
    if (href == null) {
      // Auto-link bare URLs.
      var pos = 0;
      for (final m in _urlRe.allMatches(text)) {
        if (m.start > pos) pieces.add(_run(text.substring(pos, m.start), null));
        pieces.add(_run(m.group(0)!, m.group(0)));
        pos = m.end;
      }
      if (pos < text.length) pieces.add(_run(text.substring(pos), null));
    } else {
      pieces.add(_run(text, href));
    }
    for (final p in pieces) {
      if (_runs.isNotEmpty && _runs.last.sameStyle(p)) {
        final last = _runs.removeLast();
        _runs.add(HtmlRun(
          last.text + p.text,
          bold: p.bold,
          italic: p.italic,
          underline: p.underline,
          href: p.href,
        ));
      } else {
        _runs.add(p);
      }
    }
  }

  HtmlRun _run(String text, String? href) => HtmlRun(
    text,
    bold: _bold > 0,
    italic: _italic > 0,
    underline: _underline > 0,
    href: href,
  );

  /// Ends the current block, trimming whitespace at its edges.
  void _flush() {
    final runs = _trimRuns(_runs);
    if (runs.isNotEmpty) {
      _blocks.add(HtmlBlock(runs, marker: _marker, depth: _marker == null ? 0 : _depth));
    }
    _runs = [];
    _marker = null;
    _depth = 0;
  }

  static List<HtmlRun> _trimRuns(List<HtmlRun> runs) {
    final out = <HtmlRun>[];
    for (var i = 0; i < runs.length; i++) {
      var t = runs[i].text;
      // Spaces around explicit line breaks are noise.
      t = t.replaceAll(RegExp(r' *\n *'), '\n');
      if (out.isEmpty) t = t.replaceFirst(RegExp(r'^\s+'), '');
      if (i == runs.length - 1) t = t.replaceFirst(RegExp(r'\s+$'), '');
      if (t.isEmpty) continue;
      final r = runs[i];
      out.add(HtmlRun(t, bold: r.bold, italic: r.italic, underline: r.underline, href: r.href));
    }
    // Trailing whitespace may sit in an earlier run when the last run vanished.
    while (out.isNotEmpty) {
      final last = out.last;
      final t = last.text.replaceFirst(RegExp(r'\s+$'), '');
      if (t == last.text) break;
      out.removeLast();
      if (t.isNotEmpty) {
        out.add(HtmlRun(t, bold: last.bold, italic: last.italic, underline: last.underline, href: last.href));
        break;
      }
    }
    return out;
  }
}

String? _safeHref(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  const allowed = {'http', 'https', 'mailto', 'tel'};
  return allowed.contains(uri.scheme.toLowerCase()) ? raw : null;
}

const _named = <String, String>{
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ',
  'auml': 'ä', 'ouml': 'ö', 'uuml': 'ü', 'Auml': 'Ä', 'Ouml': 'Ö', 'Uuml': 'Ü',
  'szlig': 'ß', 'euro': '€', 'ndash': '–', 'mdash': '—', 'hellip': '…',
  'laquo': '«', 'raquo': '»', 'bdquo': '„', 'ldquo': '“', 'rdquo': '”',
  'lsquo': '‘', 'rsquo': '’', 'sbquo': '‚', 'copy': '©', 'reg': '®',
  'deg': '°', 'middot': '·', 'bull': '•', 'sect': '§', 'times': '×',
  'eacute': 'é', 'egrave': 'è', 'aacute': 'á', 'agrave': 'à', 'shy': '',
};

final _entityRe = RegExp(r'&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);');

String decodeEntities(String s) => s.replaceAllMapped(_entityRe, (m) {
  final e = m.group(1)!;
  if (e.startsWith('#')) {
    final hex = e.length > 1 && (e[1] == 'x' || e[1] == 'X');
    final code = int.tryParse(hex ? e.substring(2) : e.substring(1), radix: hex ? 16 : 10);
    if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
    return String.fromCharCode(code);
  }
  return _named[e] ?? m.group(0)!;
});

/// Renders an HTML message body. Links call [onLinkTap].
class HtmlBody extends StatefulWidget {
  const HtmlBody(this.html, {super.key, required this.onLinkTap, this.style});

  final String html;
  final void Function(String href) onLinkTap;
  final TextStyle? style;

  @override
  State<HtmlBody> createState() => _HtmlBodyState();
}

class _HtmlBodyState extends State<HtmlBody> {
  late List<HtmlBlock> _blocks;
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _blocks = parseHtml(widget.html);
  }

  @override
  void didUpdateWidget(HtmlBody old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html) _blocks = parseHtml(widget.html);
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TextSpan _span(HtmlRun r, ColorScheme cs) {
    TapGestureRecognizer? rec;
    if (r.href != null) {
      final href = r.href!;
      rec = TapGestureRecognizer()..onTap = () => widget.onLinkTap(href);
      _recognizers.add(rec);
    }
    return TextSpan(
      text: r.text,
      recognizer: rec,
      style: TextStyle(
        fontWeight: r.bold ? FontWeight.bold : null,
        fontStyle: r.italic ? FontStyle.italic : null,
        color: r.href != null ? cs.primary : null,
        decoration: r.href != null || r.underline ? TextDecoration.underline : null,
        decorationColor: r.href != null ? cs.primary : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final cs = Theme.of(context).colorScheme;
    final style = widget.style ?? Theme.of(context).textTheme.bodyMedium;
    if (_blocks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, b) in _blocks.indexed)
          Padding(
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : (b.marker != null && _blocks[i - 1].marker != null ? 4 : 10),
              left: b.marker == null ? 0 : 8.0 + 16.0 * (b.depth - 1),
            ),
            child: b.marker == null
                ? Text.rich(TextSpan(children: [for (final r in b.runs) _span(r, cs)]), style: style)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 22, child: Text(b.marker!, style: style)),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [for (final r in b.runs) _span(r, cs)]),
                          style: style,
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}
