/// Small Markdown renderer for the subset used in the release notes:
/// headings (`#` … `######`), paragraphs, bullet lists (`-`, `*`, `+`,
/// nested by indentation), numbered lists, `**bold**`, `*italic*` /
/// `_italic_`, `` `code` ``, `[links](https://…)` and bare http(s) URLs.
/// Anything else is shown as plain text.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A run of text with uniform style.
class MdRun {
  const MdRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.href,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final String? href;

  bool sameStyle(MdRun o) =>
      o.bold == bold && o.italic == italic && o.code == code && o.href == href;

  @override
  String toString() =>
      'MdRun(${[if (bold) 'b', if (italic) 'i', if (code) 'c', if (href != null) 'a=$href'].join(',')} "$text")';
}

enum MdBlockKind { heading, paragraph, bullet, ordered }

/// A heading, paragraph or list item.
class MdBlock {
  const MdBlock(this.kind, this.runs, {this.level = 0, this.marker});

  final MdBlockKind kind;
  final List<MdRun> runs;

  /// Heading level (1–6), or list nesting depth (1-based); 0 for paragraphs.
  final int level;

  /// "•" or "1." for list items.
  final String? marker;

  String get text => runs.map((r) => r.text).join();

  @override
  String toString() => 'MdBlock(${kind.name}$level ${marker ?? ''} "$text")';
}

final _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
final _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final _ordered = RegExp(r'^(\s*)(\d{1,9})[.)]\s+(.*)$');
final _rule = RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$');
final _quote = RegExp(r'^\s{0,3}>\s?(.*)$');

/// Parses [markdown] into blocks.
List<MdBlock> parseMarkdown(String markdown) {
  final blocks = <MdBlock>[];
  // Raw text of the block being collected (paragraph or list item).
  MdBlockKind? kind;
  var level = 0;
  String? marker;
  final buf = StringBuffer();
  // Indentation of the open list levels (for nesting).
  final indents = <int>[];

  void flush() {
    if (kind != null) {
      final runs = parseInline(buf.toString().trim());
      if (runs.isNotEmpty || kind != MdBlockKind.paragraph) {
        blocks.add(MdBlock(kind!, runs, level: level, marker: marker));
      }
    }
    kind = null;
    marker = null;
    level = 0;
    buf.clear();
  }

  int depthFor(int indent) {
    while (indents.isNotEmpty && indent < indents.last) {
      indents.removeLast();
    }
    if (indents.isEmpty || indent > indents.last) indents.add(indent);
    return indents.length;
  }

  for (final raw in markdown.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.replaceAll('\t', '    ');
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    final h = _heading.firstMatch(line);
    if (h != null) {
      flush();
      indents.clear();
      blocks.add(
        MdBlock(
          MdBlockKind.heading,
          parseInline(h.group(2)!),
          level: h.group(1)!.length,
        ),
      );
      continue;
    }
    if (_rule.hasMatch(line)) {
      flush();
      indents.clear();
      continue;
    }
    final b = _bullet.firstMatch(line);
    final o = b == null ? _ordered.firstMatch(line) : null;
    if (b != null || o != null) {
      flush();
      final indent = (b ?? o)!.group(1)!.length;
      kind = b != null ? MdBlockKind.bullet : MdBlockKind.ordered;
      level = depthFor(indent);
      marker = b != null ? '•' : '${o!.group(2)}.';
      buf.write(b != null ? b.group(2) : o!.group(3));
      continue;
    }
    final q = _quote.firstMatch(line);
    final text = q != null ? q.group(1)! : line.trim();
    if (kind == null) {
      kind = MdBlockKind.paragraph;
      if (!line.startsWith(' ')) indents.clear();
    } else {
      // Continuation of the paragraph or list item.
      buf.write(' ');
    }
    buf.write(text.trim());
  }
  flush();
  return blocks;
}

final _bareUrl = RegExp(r'''https?://[^\s<>()"']+[^\s<>()"'.,;:!?]''');

/// Inline Markdown → runs (adjacent runs with the same style merged).
List<MdRun> parseInline(String text) {
  final out = <MdRun>[];
  _Inline(text, out).parse(0, text.length, const MdRun(''));
  final merged = <MdRun>[];
  for (final r in out.expand(_autolink)) {
    if (r.text.isEmpty) continue;
    if (merged.isNotEmpty && merged.last.sameStyle(r)) {
      final l = merged.removeLast();
      merged.add(
        MdRun(
          l.text + r.text,
          bold: l.bold,
          italic: l.italic,
          code: l.code,
          href: l.href,
        ),
      );
    } else {
      merged.add(r);
    }
  }
  return merged;
}

Iterable<MdRun> _autolink(MdRun r) sync* {
  if (r.href != null || r.code) {
    yield r;
    return;
  }
  var pos = 0;
  for (final m in _bareUrl.allMatches(r.text)) {
    yield _with(r, r.text.substring(pos, m.start));
    yield _with(r, m.group(0)!, href: m.group(0));
    pos = m.end;
  }
  yield _with(r, r.text.substring(pos));
}

MdRun _with(
  MdRun s,
  String text, {
  bool? bold,
  bool? italic,
  bool? code,
  String? href,
}) => MdRun(
  text,
  bold: bold ?? s.bold,
  italic: italic ?? s.italic,
  code: code ?? s.code,
  href: href ?? s.href,
);

/// Only absolute web and mail links are tappable.
String? _safeHref(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null) return null;
  return const {'http', 'https', 'mailto'}.contains(u.scheme.toLowerCase())
      ? u.toString()
      : null;
}

bool _isWordChar(String c) =>
    RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c);

class _Inline {
  _Inline(this.s, this.out);
  final String s;
  final List<MdRun> out;

  String at(int i) => i >= 0 && i < s.length ? s[i] : '';

  /// Parses s[from, to) with [style].
  void parse(int from, int to, MdRun style) {
    final text = StringBuffer();
    void emit() {
      if (text.isNotEmpty) out.add(_with(style, text.toString()));
      text.clear();
    }

    var i = from;
    while (i < to) {
      final c = s[i];
      // Escapes.
      if (c == r'\' && i + 1 < to && r'\`*_[]()#+-.!'.contains(s[i + 1])) {
        text.write(s[i + 1]);
        i += 2;
        continue;
      }
      // Inline code.
      if (c == '`') {
        final end = s.indexOf('`', i + 1);
        if (end > i + 1 && end < to) {
          emit();
          out.add(_with(style, s.substring(i + 1, end), code: true));
          i = end + 1;
          continue;
        }
      }
      // Links: [text](url).
      if (c == '[') {
        final close = _matching(i, to, '[', ']');
        if (close != -1 && at(close + 1) == '(') {
          final end = s.indexOf(')', close + 2);
          if (end != -1 && end < to) {
            emit();
            final url = s.substring(close + 2, end).trim().split(' ').first;
            final href = _safeHref(url);
            parse(
              i + 1,
              close,
              href == null ? style : _with(style, '', href: href),
            );
            i = end + 1;
            continue;
          }
        }
      }
      // Bold: ** or __.
      if ((c == '*' || c == '_') && i + 1 < to && at(i + 1) == c) {
        final end = _closing(i + 2, to, c * 2);
        if (end != -1 && (c == '*' || !_isWordChar(at(i - 1)))) {
          emit();
          parse(i + 2, end, _with(style, '', bold: true));
          i = end + 2;
          continue;
        }
      }
      // Italic: * or _ (not inside words for _).
      if ((c == '*' || c == '_') &&
          at(i + 1).trim().isNotEmpty &&
          (c == '*' || !_isWordChar(at(i - 1)))) {
        final end = _closing(i + 1, to, c);
        if (end != -1) {
          emit();
          parse(i + 1, end, _with(style, '', italic: true));
          i = end + 1;
          continue;
        }
      }
      text.write(c);
      i++;
    }
    emit();
  }

  /// Index of the `]` matching the `[` at [open], or -1.
  int _matching(int open, int to, String o, String c) {
    var depth = 0;
    for (var j = open; j < to; j++) {
      if (s[j] == r'\') {
        j++;
      } else if (s[j] == o) {
        depth++;
      } else if (s[j] == c && --depth == 0) {
        return j;
      }
    }
    return -1;
  }

  /// Start of the closing [delim] for an opener ending before [from]: not
  /// right after whitespace, not empty, skipping code spans and (for single
  /// delimiters) doubled ones. -1 if there is none.
  int _closing(int from, int to, String delim) {
    var j = from;
    while (j < to) {
      final c = s[j];
      if (c == r'\') {
        j += 2;
        continue;
      }
      if (c == '`') {
        final end = s.indexOf('`', j + 1);
        if (end != -1 && end < to) {
          j = end + 1;
          continue;
        }
      }
      if (s.startsWith(delim, j) && j + delim.length <= to) {
        // `***` closes an inner `*` first: take the last two as `**`.
        while (delim.length == 2 && at(j + 2) == delim[0] && j + 3 <= to) {
          j++;
        }
        if (delim.length == 1 && j + 1 < to && at(j + 1) == delim) {
          // Part of a double delimiter: skip both.
          j += 2;
          continue;
        }
        final ok =
            j > from &&
            at(j - 1).trim().isNotEmpty &&
            (delim[0] == '*' || !_isWordChar(at(j + delim.length)));
        if (ok) return j;
      }
      j++;
    }
    return -1;
  }
}

/// Renders [data] (see the library doc for the supported subset). Links call
/// [onLinkTap].
class MarkdownText extends StatefulWidget {
  const MarkdownText(
    this.data, {
    super.key,
    required this.onLinkTap,
    this.style,
  });

  final String data;
  final void Function(String href) onLinkTap;
  final TextStyle? style;

  @override
  State<MarkdownText> createState() => _MarkdownTextState();
}

class _MarkdownTextState extends State<MarkdownText> {
  late List<MdBlock> _blocks;
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _blocks = parseMarkdown(widget.data);
  }

  @override
  void didUpdateWidget(MarkdownText old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) _blocks = parseMarkdown(widget.data);
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

  TextSpan _span(MdRun r, ThemeData theme) {
    final cs = theme.colorScheme;
    TapGestureRecognizer? rec;
    final href = r.href;
    if (href != null) {
      rec = TapGestureRecognizer()..onTap = () => widget.onLinkTap(href);
      _recognizers.add(rec);
    }
    return TextSpan(
      text: r.text,
      recognizer: rec,
      style: TextStyle(
        fontWeight: r.bold ? FontWeight.bold : null,
        fontStyle: r.italic ? FontStyle.italic : null,
        fontFamily: r.code ? 'monospace' : null,
        backgroundColor: r.code ? cs.surfaceContainerHighest : null,
        color: href != null ? cs.primary : null,
        decoration: href != null ? TextDecoration.underline : null,
        decorationColor: href != null ? cs.primary : null,
      ),
    );
  }

  TextStyle? _headingStyle(int level, TextTheme t) => switch (level) {
    1 => t.titleLarge,
    2 => t.titleMedium,
    _ => t.titleSmall,
  }?.copyWith(fontWeight: FontWeight.bold);

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final theme = Theme.of(context);
    final style = widget.style ?? theme.textTheme.bodyMedium;
    if (_blocks.isEmpty) return const SizedBox.shrink();
    Widget rich(MdBlock b, TextStyle? s) => Text.rich(
      TextSpan(children: [for (final r in b.runs) _span(r, theme)]),
      style: s,
    );
    final isList = {MdBlockKind.bullet, MdBlockKind.ordered};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, b) in _blocks.indexed)
          Padding(
            padding: EdgeInsets.only(
              top: i == 0
                  ? 0
                  : b.kind == MdBlockKind.heading
                  ? 14
                  : isList.contains(b.kind) &&
                        isList.contains(_blocks[i - 1].kind)
                  ? 4
                  : 8,
              left: isList.contains(b.kind) ? 4.0 + 16.0 * (b.level - 1) : 0,
            ),
            child: switch (b.kind) {
              MdBlockKind.heading => Semantics(
                header: true,
                child: rich(b, _headingStyle(b.level, theme.textTheme)),
              ),
              MdBlockKind.paragraph => rich(b, style),
              MdBlockKind.bullet || MdBlockKind.ordered => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 22, child: Text(b.marker!, style: style)),
                  Expanded(child: rich(b, style)),
                ],
              ),
            },
          ),
      ],
    );
  }
}
