import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_update.dart';
import '../infocenter/info_providers.dart';

/// Checks once per app start whether a newer release exists on GitHub and,
/// if so, shows a dialog with the link. Wraps the app (below MaterialApp);
/// dialogs open on [navigatorKey].
class UpdateChecker extends ConsumerStatefulWidget {
  const UpdateChecker({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends ConsumerState<UpdateChecker> {
  @override
  void initState() {
    super.initState();
    if (ref.read(updateCheckEnabledProvider)) unawaited(_check());
  }

  Future<void> _check() async {
    final current = await ref.read(appVersionProvider.future);
    if (current == null) return;
    final latest = await ref.read(latestReleaseFetcherProvider)();
    if (latest == null || !isNewerVersion(latest.tag, current.version)) return;
    if (!mounted) return;
    // The navigator may not exist yet on the very first frame.
    var context = widget.navigatorKey.currentContext;
    for (var i = 0; context == null && i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      context = widget.navigatorKey.currentContext;
    }
    if (context == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => UpdateDialog(current: current.version, latest: latest),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class UpdateDialog extends ConsumerWidget {
  const UpdateDialog({super.key, required this.current, required this.latest});

  final String current;
  final ReleaseInfo latest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('update-dialog'),
      icon: const Icon(Icons.system_update_outlined),
      title: const Text('Update available'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Version ${latest.version} is available. You have $current.'),
          const SizedBox(height: 12),
          SelectableText(
            latest.url.toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        FilledButton.icon(
          key: const ValueKey('update-open'),
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(ref.read(urlOpenerProvider)(latest.url));
          },
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open GitHub'),
        ),
      ],
    );
  }
}
