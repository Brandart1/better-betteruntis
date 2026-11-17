/// HTML message bodies: sanitising, rendering and plain-text extraction.
///
/// Rendering is done by `flutter_widget_from_html_core`. Before it sees the
/// markup we parse it with `package:html` and: drop script/style/head/title
/// (and embedded content), replace images with their alt text (no remote
/// loading), remove links whose scheme is not http, https, mailto or tel,
/// strip inline styles, and turn bare URLs in text into links.
library;

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

const _dropContent = {
  'script', 'style', 'head', 'title', 'noscript', 'template', //
  'iframe', 'object', 'embed', 'svg', 'video', 'audio',
};
const _blockTags = {
  'p', 'div', 'section', 'article', 'header', 'footer', 'blockquote', 'h1', //
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'table',
  'tr',
  'pre',
  'hr',
  'center',
  'ul',
  'ol',
};
const _allowedSchemes = {'http', 'https', 'mailto', 'tel'};

final _urlRe = RegExp(r'''(https?://[^\s<>"']+[^\s<>"'.,;:!?)\]])''');
final _looksLikeHtml = RegExp(r'<\s*/?\s*[a-zA-Z][^>]*>|&[a-zA-Z#0-9]+;');

/// True if [href] may be opened (http, https, mailto, tel).
bool isSafeHref(String? href) {
  if (href == null || href.trim().isEmpty) return false;
  final uri = Uri.tryParse(href.trim());
  return uri != null && _allowedSchemes.contains(uri.scheme.toLowerCase());
}

/// Parses [html] into a sanitised body element. Plain text (no tags) keeps
/// its line breaks.
dom.Element _parseBody(String html) {
  if (!_looksLikeHtml.hasMatch(html)) {
    html = html
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('\r\n', '\n')
        .replaceAll('\n', '<br>');
  }
  final body = html_parser.parse(html).body ?? dom.Element.tag('body');
  _sanitize(body);
  return body;
}

void _sanitize(dom.Node node) {
  for (final child in node.nodes.toList()) {
    if (child is dom.Element) {
      final name = child.localName;
      if (_dropContent.contains(name)) {
        child.remove();
        continue;
      }
      if (name == 'img') {
        final alt = child.attributes['alt']?.trim() ?? '';
        if (alt.isEmpty) {
          child.remove();
        } else {
          child.replaceWith(dom.Text(alt));
        }
        continue;
      }
      child.attributes.remove('style');
      if (name == 'a' && !isSafeHref(child.attributes['href'])) {
        child.attributes.remove('href');
      }
      // Links keep their own text; no nested auto-linking.
      if (name == 'a' && child.attributes['href'] != null) continue;
      _sanitize(child);
    } else if (child is dom.Text) {
      _linkify(child);
    } else {
      child.remove(); // comments, CDATA, doctype
    }
  }
}

/// Splits a text node so bare URLs become `<a>` elements.
void _linkify(dom.Text node) {
  final text = node.text;
  final matches = _urlRe.allMatches(text).toList();
  if (matches.isEmpty) return;
  var pos = 0;
  final out = <dom.Node>[];
  for (final m in matches) {
    if (m.start > pos) out.add(dom.Text(text.substring(pos, m.start)));
    out.add(
      dom.Element.tag('a')
        ..attributes['href'] = m.group(0)!
        ..text = m.group(0)!,
    );
    pos = m.end;
  }
  if (pos < text.length) out.add(dom.Text(text.substring(pos)));
  final parent = node.parentNode!;
  for (final n in out) {
    parent.insertBefore(n, node);
  }
  node.remove();
}

/// Plain-text rendering (for previews and reply quotes).
String htmlToPlainText(String html) {
  final out = StringBuffer();
  var lineOpen = false; // text emitted on the current line

  void newline() {
    if (lineOpen) out.write('\n');
    lineOpen = false;
  }

  void walk(dom.Node node, int depth, List<int> counters) {
    if (node is dom.Text) {
      var t = node.text.replaceAll(RegExp(r'\s+'), ' ');
      if (!lineOpen) t = t.trimLeft();
      if (t.isEmpty) return;
      out.write(t);
      lineOpen = true;
      return;
    }
    if (node is! dom.Element) return;
    final name = node.localName;
    if (name == 'br') {
      out.write('\n');
      lineOpen = false;
      return;
    }
    if (name == 'li') {
      newline();
      final ordered = node.parent?.localName == 'ol';
      final marker = ordered ? '${++counters.last}.' : '•';
      out.write('${'  ' * (depth - 1)}$marker ');
      lineOpen = true;
      for (final c in node.nodes) {
        walk(c, depth, counters);
      }
      newline();
      return;
    }
    final block = _blockTags.contains(name);
    final list = name == 'ul' || name == 'ol';
    if (block) newline();
    if (list) counters.add(0);
    for (final c in node.nodes) {
      walk(c, list ? depth + 1 : depth, counters);
    }
    if (list) counters.removeLast();
    if (block) newline();
  }

  walk(_parseBody(html), 0, []);
  return out.toString().split('\n').map((l) => l.trimRight()).join('\n').trim();
}

/// Renders an HTML message body. Links (http, https, mailto, tel only) call
/// [onLinkTap].
class HtmlBody extends StatelessWidget {
  const HtmlBody(this.html, {super.key, required this.onLinkTap, this.style});

  final String html;
  final void Function(String href) onLinkTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final body = _parseBody(html);
    if (body.nodes.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return HtmlWidget(
      body.innerHtml,
      textStyle: style ?? theme.textTheme.bodyMedium,
      customStylesBuilder: (e) => e.localName == 'a'
          ? {'color': _css(theme.colorScheme.primary)}
          : null,
      onTapUrl: (url) {
        if (!isSafeHref(url)) return false;
        onLinkTap(url);
        return true;
      },
    );
  }

  static String _css(Color c) {
    final rgb = c.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }
}
