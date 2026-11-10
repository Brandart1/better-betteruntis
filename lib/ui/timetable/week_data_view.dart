import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'timetable_providers.dart';
import 'timetable_utils.dart';

typedef WeekContentBuilder = Widget Function(
  BuildContext context,
  List<Period> periods,
  NameResolver names,
);

/// Loads one week (cache-first) and handles everything around the content:
/// loading, full error state with retry, pull-to-refresh, an error banner when
/// a refresh fails over cached data, and the "Updated x min ago" label.
///
/// [builder] must return a widget containing a vertical scrollable (for the
/// [RefreshIndicator]).
class WeekDataView extends ConsumerStatefulWidget {
  const WeekDataView({
    super.key,
    required this.account,
    required this.target,
    required this.weekStart,
    required this.builder,
  });

  final Account account;
  final TimetableTarget target;
  final DateTime weekStart;
  final WeekContentBuilder builder;

  @override
  ConsumerState<WeekDataView> createState() => _WeekDataViewState();
}

class _WeekDataViewState extends ConsumerState<WeekDataView> {
  Object? _refreshError;

  WeekRequest get _req =>
      WeekRequest(widget.account, widget.target, widget.weekStart);

  Future<void> _refresh() async {
    try {
      await ref
          .read(timetableRepositoryProvider)
          .refresh(widget.account, widget.target, widget.weekStart);
      if (mounted) setState(() => _refreshError = null);
    } catch (e) {
      if (mounted) setState(() => _refreshError = e);
    }
  }

  void _retry() {
    setState(() => _refreshError = null);
    ref.invalidate(weekPeriodsProvider(_req));
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final periods = ref.watch(weekPeriodsProvider(_req));
    final namesAsync = ref.watch(nameResolverProvider);
    final names = namesAsync.value;

    if (names == null || !periods.hasValue) {
      final error = periods.hasValue ? namesAsync.error : periods.error;
      if (error != null) {
        return TimetableErrorState(error: error, onRetry: _retry);
      }
      return const Center(child: CircularProgressIndicator());
    }

    final bannerError = _refreshError ?? periods.error;
    final updated = ref
        .read(timetableRepositoryProvider)
        .lastRefreshed(widget.account, widget.target, widget.weekStart);
    return Column(
      children: [
        if (bannerError != null)
          _ErrorBanner(
            message: describeError(bannerError),
            onRetry: _refresh,
            onDismiss: () => setState(() => _refreshError = null),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: widget.builder(context, periods.requireValue, names),
          ),
        ),
        UpdatedLabel(at: updated),
      ],
    );
  }
}

/// User-facing text for an error.
String describeError(Object e) {
  if (e is UntisException) {
    if (e.isTimeout) return "Server didn't respond. Showing saved timetable.";
    return e.isNetwork ? 'No connection. Showing saved timetable.' : e.message;
  }
  return 'Something went wrong: $e';
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
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

/// Full-page error with a retry button (no cached data available).
class TimetableErrorState extends StatelessWidget {
  const TimetableErrorState({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final network = error is UntisException && (error as UntisException).isNetwork;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(network ? Icons.cloud_off : Icons.error_outline,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              network ? 'No connection' : 'Could not load the timetable',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              network ? 'Check your internet connection and try again.' : describeError(error),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
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

/// "Updated x min ago", re-evaluated every minute.
class UpdatedLabel extends StatefulWidget {
  const UpdatedLabel({super.key, required this.at});
  final DateTime? at;

  @override
  State<UpdatedLabel> createState() => _UpdatedLabelState();
}

class _UpdatedLabelState extends State<UpdatedLabel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        formatUpdated(context, widget.at, DateTime.now()),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
