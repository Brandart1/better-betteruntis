/// Shared building blocks of the Info center tabs: loading / error / empty
/// states, the refresh frame, attachment tiles, name and date helpers.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/info.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../timetable/timetable_utils.dart';
import '../timetable/week_data_view.dart' show UpdatedLabel;
import 'info_providers.dart';

/// Max content width on tablets.
const kInfoMaxWidth = 720.0;

// ---------------------------------------------------------------------------
// Status of one cached stream

class InfoStatus {
  const InfoStatus({
    required this.hasData,
    required this.refreshing,
    required this.error,
    required this.fetchedAt,
  });

  factory InfoStatus.of(AsyncValue<Cached<Object?>> v) {
    final c = v.value;
    return InfoStatus(
      hasData: c?.data != null,
      refreshing: (c?.refreshing ?? false) || v.isLoading,
      error: v.hasError ? v.error : c?.error,
      fetchedAt: c?.fetchedAt,
    );
  }

  final bool hasData;
  final bool refreshing;
  final Object? error;
  final DateTime? fetchedAt;

  /// Nothing to show and nothing coming: full error state.
  bool get failed => !hasData && error != null && !refreshing;
}

// ---------------------------------------------------------------------------
// Frame

/// Progress bar, error banners, pull-to-refresh scroll view and the "Updated"
/// label around a tab's slivers. The content is centered and constrained to
/// [kInfoMaxWidth].
class InfoFrame extends StatefulWidget {
  const InfoFrame({
    super.key,
    required this.statuses,
    required this.onRefresh,
    required this.slivers,
    this.header,
  });

  final List<InfoStatus> statuses;
  final Future<void> Function() onRefresh;
  final List<Widget> slivers;

  /// Non-scrolling widget above the content (filters, range chips).
  final Widget? header;

  @override
  State<InfoFrame> createState() => _InfoFrameState();
}

class _InfoFrameState extends State<InfoFrame> {
  final _dismissed = <Object>{};

  @override
  Widget build(BuildContext context) {
    final refreshing = widget.statuses.any((s) => s.refreshing);
    final errors = {
      for (final s in widget.statuses)
        if (s.hasData && s.error != null && !_dismissed.contains(s.error)) s.error!,
    };
    final times = [for (final s in widget.statuses) if (s.fetchedAt != null) s.fetchedAt!];
    final oldest = times.isEmpty ? null : times.reduce((a, b) => a.isBefore(b) ? a : b);
    return Column(
      children: [
        ?widget.header,
        SizedBox(
          height: 2,
          child: refreshing ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        for (final e in errors)
          InfoErrorBanner(
            message: '${describeInfoError(e)} Showing saved data.',
            onRetry: widget.onRefresh,
            onDismiss: () => setState(() => _dismissed.add(e)),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: CenteredScrollView(slivers: widget.slivers),
          ),
        ),
        if (oldest != null) UpdatedLabel(at: oldest),
      ],
    );
  }
}

/// Always-scrollable [CustomScrollView] whose slivers are centered with a max
/// width of [kInfoMaxWidth].
class CenteredScrollView extends StatelessWidget {
  const CenteredScrollView({super.key, required this.slivers});
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final side = math.max(0.0, (c.maxWidth - kInfoMaxWidth) / 2);
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side + 12, 8, side + 12, 24),
              sliver: SliverMainAxisGroup(slivers: slivers),
            ),
          ],
        );
      },
    );
  }
}

/// Single-stream tab body: skeleton on first load, full error with retry when
/// nothing is cached, empty state, or [builder]'s slivers inside an
/// [InfoFrame].
class CachedListView<T> extends StatelessWidget {
  const CachedListView({
    super.key,
    required this.value,
    required this.onRefresh,
    required this.isEmpty,
    required this.empty,
    required this.builder,
    required this.errorTitle,
    this.header,
    this.extraStatuses = const [],
  });

  final AsyncValue<Cached<T>> value;
  final Future<void> Function() onRefresh;
  final bool Function(T data) isEmpty;
  final Widget empty;
  final List<Widget> Function(BuildContext context, T data) builder;
  final String errorTitle;
  final Widget? header;
  final List<InfoStatus> extraStatuses;

  @override
  Widget build(BuildContext context) {
    final status = InfoStatus.of(value);
    final data = value.value?.data;
    if (data == null) {
      return Column(
        children: [
          ?header,
          Expanded(
            child: status.failed
                ? InfoErrorState(
                    title: errorTitle,
                    error: status.error!,
                    onRetry: onRefresh,
                  )
                : const InfoSkeleton(),
          ),
        ],
      );
    }
    return InfoFrame(
      header: header,
      statuses: [status, ...extraStatuses],
      onRefresh: onRefresh,
      slivers: isEmpty(data)
          ? [SliverFillRemaining(hasScrollBody: false, child: empty)]
          : builder(context, data),
    );
  }
}

// ---------------------------------------------------------------------------
// States

class InfoSkeleton extends StatelessWidget {
  const InfoSkeleton({super.key, this.count = 5, this.shrinkWrap = false});
  final int count;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
    );
    final items = [
      for (var i = 0; i < count; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              bar(40, 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(160, 14),
                    const SizedBox(height: 8),
                    FractionallySizedBox(
                      widthFactor: i.isEven ? 0.9 : 0.7,
                      child: bar(double.infinity, 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ];
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: Center(
          key: const ValueKey('info-skeleton'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kInfoMaxWidth),
            child: shrinkWrap
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(children: items),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    physics: const NeverScrollableScrollPhysics(),
                    children: items,
                  ),
          ),
        ),
      ),
    );
  }
}

class InfoErrorState extends StatelessWidget {
  const InfoErrorState({
    super.key,
    required this.title,
    required this.error,
    required this.onRetry,
  });

  final String title;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final network = error is UntisException && (error as UntisException).isNetwork;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              network ? Icons.cloud_off : Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              network
                  ? 'Check your internet connection and try again.'
                  : describeInfoError(error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class InfoErrorBanner extends StatelessWidget {
  const InfoErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('info-error-banner'),
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: cs.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: Icon(Icons.close, size: 18, color: cs.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class InfoEmptyState extends StatelessWidget {
  const InfoEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section title inside a tab.
class InfoSectionHeader extends StatelessWidget {
  const InfoSectionHeader(this.title, {super.key, this.trailing, this.color});
  final String title;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: color ?? theme.colorScheme.primary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Small status chip ("Excused", "in 3 days"…).
class InfoChip extends StatelessWidget {
  const InfoChip(
    this.label, {
    super.key,
    this.icon,
    this.background,
    this.foreground,
  });

  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = foreground ?? cs.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// Success colors (green) that work in light and dark themes.
({Color bg, Color fg}) successColors(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark
      ? (bg: const Color(0xFF1E4D2B), fg: const Color(0xFFB7F1C4))
      : (bg: const Color(0xFFD3F5DC), fg: const Color(0xFF0F5223));
}

/// Tappable attachment list tiles.
class AttachmentList extends ConsumerWidget {
  const AttachmentList(this.attachments, {super.key, this.dense = true});
  final List<({String name, String url})> attachments;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final a in attachments)
          ListTile(
            dense: dense,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            leading: Icon(_iconFor(a.name)),
            title: Text(a.name.isEmpty ? 'Attachment' : a.name),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openLink(context, ref, a.url),
          ),
      ],
    );
  }

  static IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (RegExp(r'\.(png|jpe?g|gif|webp|heic)$').hasMatch(n)) {
      return Icons.image_outlined;
    }
    return Icons.attach_file;
  }
}

/// Opens [url] via [urlOpenerProvider]; shows a snackbar when that fails.
Future<void> openLink(BuildContext context, WidgetRef ref, String url) async {
  final uri = Uri.tryParse(url.trim());
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = uri != null && await ref.read(urlOpenerProvider)(uri);
  if (!ok) {
    messenger?.showSnackBar(const SnackBar(content: Text("Couldn't open the link")));
  }
}

// ---------------------------------------------------------------------------
// Names

/// Resolved display name, or null when the server hides it ('?', empty,
/// unknown id).
String? resolveName(
  NameResolver? names,
  ElementType type,
  int id, {
  bool long = true,
}) {
  if (names == null) return null;
  final ref = ElementRef(type: type, id: id, orgId: id);
  final e = names.element(type, id);
  final n = (e == null
          ? (long ? names.longName(ref) : names.shortName(ref))
          : (long ? e.longName : e.name))
      .trim();
  if (n.isEmpty || n == '?' || n == '#$id' || n == '---') return null;
  return n;
}

List<String> resolveNames(
  NameResolver? names,
  ElementType type,
  Iterable<int> ids, {
  bool long = true,
}) => [
  for (final id in ids) ?resolveName(names, type, id, long: long),
];

// ---------------------------------------------------------------------------
// Dates

String formatTimeRange(BuildContext context, DateTime start, DateTime end) {
  final t = dateFormat(context, 'HH:mm');
  return '${t.format(start)}–${t.format(end)}';
}

/// "Today", "Tomorrow", "Yesterday" or "Fri, 14 Nov" (with year when not this
/// year).
String formatDay(BuildContext context, DateTime day, DateTime now) {
  final diff = dateOnly(day).difference(dateOnly(now)).inHours / 24;
  switch (diff.round()) {
    case 0:
      return 'Today';
    case 1:
      return 'Tomorrow';
    case -1:
      return 'Yesterday';
  }
  return dateFormat(context, day.year == now.year ? 'EEE, d MMM' : 'EEE, d MMM yyyy')
      .format(day);
}

/// Whole calendar days from [now] to [day].
int daysUntil(DateTime day, DateTime now) =>
    (dateOnly(day).difference(dateOnly(now)).inHours / 24).round();

/// Inbox-style relative date: time today, "Yesterday", weekday within a week,
/// otherwise the date.
String formatRelativeDate(BuildContext context, DateTime? at, DateTime now) {
  if (at == null) return '';
  final d = daysUntil(at, now);
  if (d == 0) return dateFormat(context, 'HH:mm').format(at);
  if (d == -1) return 'Yesterday';
  if (d > -7 && d < 0) return dateFormat(context, 'EEE').format(at);
  return dateFormat(context, at.year == now.year ? 'd MMM' : 'd MMM yyyy').format(at);
}
