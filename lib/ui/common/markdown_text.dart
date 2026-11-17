/// Renders Markdown (the release notes: headings, lists, bold, inline code,
/// links) with `flutter_markdown_plus`, styled from the app theme.
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Only absolute web and mail links are tappable.
String? _safeHref(String? url) {
  final u = Uri.tryParse((url ?? '').trim());
  if (u == null) return null;
  return const {'http', 'https', 'mailto'}.contains(u.scheme.toLowerCase())
      ? u.toString()
      : null;
}

/// Renders [data] as Markdown without scrolling (place it in your own scroll
/// view). Links with an http, https or mailto target call [onLinkTap].
class MarkdownText extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = theme.textTheme;
    final body = style ?? t.bodyMedium;
    TextStyle? heading(TextStyle? s) =>
        s?.copyWith(fontWeight: FontWeight.bold);
    const headingPadding = EdgeInsets.only(top: 14);
    return MarkdownBody(
      data: data,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      onTapLink: (text, href, title) {
        final safe = _safeHref(href);
        if (safe != null) onLinkTap(safe);
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: body,
        listBullet: body,
        a: TextStyle(
          color: cs.primary,
          decoration: TextDecoration.underline,
          decorationColor: cs.primary,
        ),
        strong: const TextStyle(fontWeight: FontWeight.bold),
        em: const TextStyle(fontStyle: FontStyle.italic),
        code: TextStyle(
          fontFamily: 'monospace',
          backgroundColor: cs.surfaceContainerHighest,
        ),
        h1: heading(t.titleLarge),
        h2: heading(t.titleMedium),
        h3: heading(t.titleSmall),
        h4: heading(t.titleSmall),
        h5: heading(t.titleSmall),
        h6: heading(t.titleSmall),
        h1Padding: headingPadding,
        h2Padding: headingPadding,
        h3Padding: headingPadding,
        h4Padding: headingPadding,
        h5Padding: headingPadding,
        h6Padding: headingPadding,
        pPadding: const EdgeInsets.only(top: 8),
        listIndent: 16,
        listBulletPadding: const EdgeInsets.only(right: 6),
        blockSpacing: 4,
      ),
    );
  }
}
