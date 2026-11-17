import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/apk_update.dart';
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
    // An APK left over from the last in-app update is no longer needed.
    if (ref.read(inAppUpdateSupportedProvider)) {
      await ref.read(apkUpdaterProvider).cleanup();
    }
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
      barrierDismissible: false,
      builder: (_) => UpdateDialog(current: current.version, latest: latest),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _Phase { idle, downloading, installing, needsPermission, error }

/// "Update available". On Android with an APK attached it can download and
/// install the update itself ("Update now"); elsewhere it links to GitHub.
class UpdateDialog extends ConsumerStatefulWidget {
  const UpdateDialog({super.key, required this.current, required this.latest});

  final String current;
  final ReleaseInfo latest;

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  var _phase = _Phase.idle;
  String? _error;
  double? _progress;
  StreamSubscription<ApkUpdateEvent>? _sub;
  late final ApkUpdater _updater = ref.read(apkUpdaterProvider);

  ReleaseAsset? get _apk =>
      ref.read(inAppUpdateSupportedProvider) ? widget.latest.apk : null;

  @override
  void dispose() {
    if (_phase == _Phase.downloading) unawaited(_updater.cancel());
    _sub?.cancel();
    super.dispose();
  }

  void _set(_Phase phase, {String? error}) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _error = error;
    });
  }

  void _update() {
    final apk = _apk;
    if (apk == null) return;
    setState(() {
      _phase = _Phase.downloading;
      _progress = null;
      _error = null;
    });
    _sub?.cancel();
    _sub = _updater
        .start(apk)
        .listen(
          _onEvent,
          onError: (_) => _fail(),
          onDone: () {
            // The stream ends after its last event; one that just stops
            // while downloading is a failure.
            if (_phase == _Phase.downloading) _fail();
          },
        );
  }

  void _fail() => _set(_Phase.error, error: 'Update failed.');

  void _onEvent(ApkUpdateEvent e) {
    if (!mounted) return;
    switch (e.stage) {
      case ApkUpdateStage.downloading:
        setState(() => _progress = e.progress);
      case ApkUpdateStage.installing:
        _set(_Phase.installing);
      case ApkUpdateStage.needsPermission:
        _set(_Phase.needsPermission);
      case ApkUpdateStage.failed:
        _set(_Phase.error, error: e.message);
      case ApkUpdateStage.canceled:
        _set(_Phase.idle);
      case ApkUpdateStage.done:
        Navigator.of(context).pop();
    }
  }

  void _openGitHub() {
    Navigator.of(context).pop();
    unawaited(ref.read(urlOpenerProvider)(widget.latest.url));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apk = _apk;
    final busy = _phase == _Phase.downloading || _phase == _Phase.installing;
    return PopScope(
      canPop: _phase != _Phase.downloading,
      child: AlertDialog(
        key: const ValueKey('update-dialog'),
        icon: const Icon(Icons.system_update_outlined),
        title: const Text('Update available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${widget.latest.version} is available. '
              'You have ${widget.current}.',
            ),
            const SizedBox(height: 12),
            if (apk == null || _phase == _Phase.idle)
              SelectableText(
                widget.latest.url.toString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            if (_phase == _Phase.downloading) ...[
              Text(
                _progress == null
                    ? 'Downloading…'
                    : 'Downloading… ${(_progress! * 100).round()} %',
                key: const ValueKey('update-progress-text'),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                key: const ValueKey('update-progress'),
                value: _progress,
              ),
            ],
            if (_phase == _Phase.installing)
              const Text(
                'Installing… Confirm in the system dialog. If Android says '
                'this app may not install unknown apps, allow it in the '
                'settings it offers, then tap Update now again.',
                key: ValueKey('update-installing'),
              ),
            if (_phase == _Phase.needsPermission)
              const Text(
                'Allow BetterBetterUntis to install apps ("Install unknown '
                'apps" in the settings), then come back and tap Update now '
                'again.',
                key: ValueKey('update-needs-permission'),
              ),
            if (_phase == _Phase.error)
              Text(
                '${_error ?? 'Update failed.'} You can also download it from '
                'GitHub.',
                key: const ValueKey('update-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ],
        ),
        actions: [
          if (_phase == _Phase.downloading)
            TextButton(
              key: const ValueKey('update-cancel'),
              onPressed: () => unawaited(_updater.cancel()),
              child: const Text('Cancel'),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_phase == _Phase.installing ? 'Close' : 'Later'),
            ),
          if (apk == null)
            FilledButton.icon(
              key: const ValueKey('update-open'),
              onPressed: _openGitHub,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open GitHub'),
            )
          else if (!busy) ...[
            TextButton(
              key: const ValueKey('update-open'),
              onPressed: _openGitHub,
              child: const Text('Open GitHub'),
            ),
            FilledButton.icon(
              key: const ValueKey('update-now'),
              onPressed: _update,
              icon: const Icon(Icons.download),
              label: Text(_phase == _Phase.idle ? 'Update now' : 'Try again'),
            ),
          ],
        ],
      ),
    );
  }
}
