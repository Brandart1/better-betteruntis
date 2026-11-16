import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../sync/sync_controller.dart';
import 'sync_dialogs.dart';

/// Drawer → "Sync": optional sync of the user's lesson notes (custom exams,
/// lesson details) through the BetterBetterUntis server, per account.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: switch (accounts) {
        AsyncData(value: final list) when list.isEmpty => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Log in first to sync your notes.'),
          ),
        ),
        AsyncData(value: final list) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Keep your custom exams, lesson details and settings '
                '(colours, text, accessibility) the same on all your devices '
                '(also the web version).',
              ),
            ),
            for (final a in list)
              SyncAccountSection(
                key: ValueKey('sync-account-${a.id}'),
                account: a,
                showHeader: list.length > 1,
              ),
          ],
        ),
        AsyncError(:final error) => Center(child: Text('$error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Sync status and actions for one account.
class SyncAccountSection extends ConsumerStatefulWidget {
  const SyncAccountSection({
    super.key,
    required this.account,
    this.showHeader = false,
  });

  final Account account;

  /// Shows the account's name (only when there are several accounts).
  final bool showHeader;

  @override
  ConsumerState<SyncAccountSection> createState() => _SyncAccountSectionState();
}

class _SyncAccountSectionState extends ConsumerState<SyncAccountSection> {
  /// "Sync now" is running (in addition to the engine's own flag).
  var _syncing = false;

  String get _id => widget.account.id;
  SyncController get _sync => ref.read(syncControllerProvider.notifier);

  Future<void> _syncNow() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _syncing = true);
    try {
      await _sync.syncNow(_id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(syncErrorText(e))));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _turnOff() async {
    final ok = await confirmSync(
      context,
      title: 'Turn off sync?',
      body:
          'Everything stored about you on the BetterBetterUntis server is '
          'deleted: your synced notes, the encryption data and the sessions '
          'of all your devices. Other devices stop syncing.\n\n'
          'The notes on this device (and on your other devices) stay.',
      confirmLabel: 'Turn off and delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final done = await runSyncAction(
      context,
      title: 'Turning off sync',
      action: () => _sync.disable(_id),
    );
    if (done != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync is off. The data on the server was deleted.'),
        ),
      );
    }
  }

  Future<void> _turnOnE2e() async {
    final root = Navigator.of(context, rootNavigator: true);
    // Kept: this section may be gone when the code is confirmed.
    final sync = _sync;
    final id = _id;
    final done = await showDialog<SyncDone<SyncEnableResult>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PassphraseDialog<SyncEnableResult>(
        title: 'Turn on encryption',
        intro:
            'Your notes on the server are replaced by an encrypted copy. '
            'Your other devices then need this passphrase once.',
        confirmLabel: 'Turn on',
        offerRecoveryCode: true,
        offerWebKeyRetention: _sync.webKeyChoice,
        action: (pass, recovery, retention) => _sync.enableE2e(
          _id,
          pass,
          withRecoveryCode: recovery,
          webKeyRetention: _sync.webKeyChoice ? retention : null,
        ),
      ),
    );
    final code = done?.value.recoveryCode;
    if (code != null && root.mounted) {
      await showRecoveryCode(
        root.context,
        code,
        onSaved: () => sync.acknowledgeRecoveryCode(id),
      );
    }
  }

  Future<void> _changePassphrase() => showDialog<SyncDone<void>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PassphraseDialog<void>(
      title: 'Change passphrase',
      intro:
          'Your other devices stay unlocked. Use the new passphrase on new '
          'devices.',
      confirmLabel: 'Change',
      action: (pass, _, _) => _sync.changePassphrase(_id, pass),
    ),
  );

  Future<void> _newRecoveryCode() async {
    // Only replacing an existing code needs a confirmation.
    if (ref
        .read(syncControllerProvider.notifier)
        .stateOf(_id)
        .hasRecoveryCode) {
      final ok = await confirmSync(
        context,
        title: 'Create a new recovery code?',
        body: 'Your old recovery code stops working.',
        confirmLabel: 'Create',
      );
      if (!ok || !mounted) return;
    }
    final root = Navigator.of(context, rootNavigator: true);
    final sync = _sync;
    final id = _id;
    final done = await runSyncAction(
      context,
      title: 'Creating a recovery code',
      action: () => _sync.regenerateRecoveryCode(_id),
    );
    if (done != null && root.mounted) {
      await showRecoveryCode(
        root.context,
        done.value,
        onSaved: () => sync.acknowledgeRecoveryCode(id),
      );
    }
  }

  Future<void> _forget() async {
    final ok = await confirmSync(
      context,
      title: 'Forget sync on this device?',
      body:
          'This device forgets its sync session and encryption key. Your '
          'notes on this device stay, and nothing on the server is deleted '
          '(turn sync on again and then off to delete it there).',
      confirmLabel: 'Forget',
    );
    if (!ok || !mounted) return;
    await runSyncAction(
      context,
      title: 'Forgetting sync',
      action: () => _sync.signOutDevice(_id),
    );
  }

  /// Web: changes how long the browser remembers the key.
  /// Bumped when changing the retention fails, so the dropdown (which only
  /// reads its initial value) shows the stored choice again.
  var _retentionReset = 0;

  Future<void> _setRetention(WebKeyRetention r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _sync.setWebKeyRetention(_id, r);
    } catch (e) {
      if (mounted) setState(() => _retentionReset++);
      messenger.showSnackBar(SnackBar(content: Text(syncErrorText(e))));
    }
  }

  Future<void> _turnOffE2e() async {
    final ok = await confirmSync(
      context,
      title: 'Turn off encryption?',
      body:
          'Your notes on the server are replaced by an unencrypted copy that '
          'the server can read. Your other devices stay signed in and '
          'switch to unencrypted sync by themselves (also devices that are '
          'still locked).',
      confirmLabel: 'Turn off encryption',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await runSyncAction(
      context,
      title: 'Turning off encryption',
      action: () => _sync.disableE2e(_id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(
      syncControllerProvider.select(
        (m) => m[_id] ?? SyncAccountState(accountId: _id),
      ),
    );
    final theme = Theme.of(context);
    final a = widget.account;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeader)
            Semantics(
              header: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${a.label} · ${a.school.displayName}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
          Card.outlined(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: switch (s.phase) {
                  _ when a.anonymous => _anonymous(),
                  SyncPhase.off when !_sync.available => _unavailable(),
                  SyncPhase.off when _otherAccountSyncs() =>
                    _webSecondAccount(),
                  SyncPhase.off => _off(),
                  SyncPhase.on => _on(s),
                  SyncPhase.locked => _locked(s),
                  SyncPhase.signedOut => _signedOut(s),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _status(IconData icon, String title, {Color? color}) => Row(
    children: [
      Icon(icon, color: color),
      const SizedBox(width: 12),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
    ],
  );

  Widget _buttons(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Wrap(spacing: 8, runSpacing: 8, children: children),
  );

  Widget _turnOffButton() {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      key: const ValueKey('sync-turn-off'),
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.error,
        side: BorderSide(color: scheme.error),
      ),
      icon: const Icon(Icons.cloud_off),
      label: const Text('Turn off sync'),
      onPressed: _turnOff,
    );
  }

  Widget? _errorText(SyncAccountState s) => s.error == null
      ? null
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            s.error!,
            key: const ValueKey('sync-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );

  List<Widget> _unavailable() => [
    _status(Icons.cloud_off, "Sync isn't available in this build"),
    const SizedBox(height: 8),
    const Text(
      'This version of the app was built without a sync server. Your notes '
      'are only stored on this device.',
      key: ValueKey('sync-unavailable'),
    ),
  ];

  /// Anonymous (public timetable) accounts never sync.
  List<Widget> _anonymous() => [
    _status(Icons.cloud_off, "Sync isn't available"),
    const SizedBox(height: 8),
    const Text(
      "Public timetable logins can't sync: sync needs a personal WebUntis "
      'login. Your notes for this account are only stored on this device.',
      key: ValueKey('sync-anonymous'),
    ),
  ];

  /// Web version: another account already syncs (one browser cookie).
  /// Leftover state of an anonymous account doesn't count (it never syncs).
  bool _otherAccountSyncs() {
    if (!_sync.singleAccountOnly) return false;
    final anonymous = {
      for (final a in ref.watch(accountsProvider).value ?? const <Account>[])
        if (a.anonymous) a.id,
    };
    return ref
        .watch(syncControllerProvider)
        .values
        .any(
          (o) =>
              o.accountId != _id &&
              o.enabled &&
              !anonymous.contains(o.accountId),
        );
  }

  List<Widget> _webSecondAccount() => [
    _status(Icons.cloud_off, 'Sync is off'),
    const SizedBox(height: 8),
    const Text(
      'The web version of BetterBetterUntis only supports one synced '
      'account. To sync more accounts, use the Android or iOS app.',
      key: ValueKey('sync-web-single-account'),
    ),
    _buttons([
      OutlinedButton.icon(
        key: const ValueKey('sync-get-apps'),
        icon: const Icon(Icons.open_in_new),
        label: const Text('Get the Android / iOS app'),
        onPressed: () => launchUrl(
          Uri.parse(kLatestReleaseUrl),
          mode: LaunchMode.externalApplication,
        ),
      ),
    ]),
  ];

  List<Widget> _off() => [
    _status(Icons.cloud_outlined, 'Sync is off'),
    const SizedBox(height: 8),
    const Text(
      'Your notes are only stored on this device. With sync, they and your '
      'settings (colours, text, accessibility) are also stored on the '
      'BetterBetterUntis server, optionally end-to-end encrypted.',
    ),
    _buttons([
      FilledButton.icon(
        key: const ValueKey('sync-turn-on'),
        icon: const Icon(Icons.cloud_upload_outlined),
        label: const Text('Turn on sync'),
        onPressed: () => turnOnSync(context, _sync, _id),
      ),
    ]),
  ];

  List<Widget> _on(SyncAccountState s) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final busy = _syncing || s.syncing;
    final last = s.lastSync;
    return [
      _status(Icons.cloud_done_outlined, 'Sync is on'),
      const SizedBox(height: 12),
      if (s.identity case final id?) ...[
        Text('Sync account', style: theme.textTheme.labelLarge),
        SelectableText(id.toString(), key: const ValueKey('sync-identity')),
        Text(
          'This identifies you if you ask for your data to be deleted.',
          style: small,
        ),
        const SizedBox(height: 12),
      ],
      if (busy)
        Semantics(
          liveRegion: true,
          child: const Row(
            key: ValueKey('sync-progress-inline'),
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Expanded(child: Text('Syncing…')),
            ],
          ),
        )
      else
        Text(
          last == null
              ? 'Not synced yet'
              : 'Last sync: ${DateFormat.yMd().add_Hm().format(last)}',
          key: const ValueKey('sync-last'),
        ),
      ?_errorText(s),
      _buttons([
        FilledButton.tonalIcon(
          key: const ValueKey('sync-now'),
          icon: const Icon(Icons.sync),
          label: const Text('Sync now'),
          onPressed: busy ? null : _syncNow,
        ),
      ]),
      const Divider(height: 32),
      _status(
        s.e2e ? Icons.lock_outline : Icons.lock_open,
        s.e2e ? 'End-to-end encryption is on' : 'End-to-end encryption is off',
      ),
      const SizedBox(height: 8),
      Text(
        s.e2e
            ? 'The server only stores encrypted notes that it can\'t read.'
            : 'The server can read your synced notes. With encryption, it '
                  'only stores a copy it can\'t read.',
      ),
      if (s.e2e && _sync.webKeyChoice) ...[
        const SizedBox(height: 8),
        KeyedSubtree(
          key: ValueKey('${s.webKeyRetention.name}-$_retentionReset'),
          child: WebKeyRetentionField(
            value: s.webKeyRetention,
            onChanged: _setRetention,
          ),
        ),
      ],
      _buttons(
        s.e2e
            ? [
                OutlinedButton(
                  key: const ValueKey('sync-change-passphrase'),
                  onPressed: _changePassphrase,
                  child: const Text('Change passphrase'),
                ),
                OutlinedButton(
                  key: const ValueKey('sync-new-recovery'),
                  onPressed: _newRecoveryCode,
                  child: Text(
                    s.hasRecoveryCode
                        ? 'New recovery code'
                        : 'Create recovery code',
                  ),
                ),
                TextButton(
                  key: const ValueKey('sync-e2e-off'),
                  onPressed: _turnOffE2e,
                  child: const Text('Turn off encryption'),
                ),
              ]
            : [
                OutlinedButton.icon(
                  key: const ValueKey('sync-e2e-on'),
                  icon: const Icon(Icons.lock_outline),
                  // A setup started on this device finishes at the next
                  // sync; a second one can't be started meanwhile.
                  label: Text(
                    s.e2eSetupPending
                        ? 'Turning on encryption…'
                        : 'Turn on encryption',
                  ),
                  onPressed: s.e2eSetupPending ? null : _turnOnE2e,
                ),
              ],
      ),
      const Divider(height: 32),
      Text(
        'Turning sync off deletes your data on the server. The notes on your '
        'devices stay.',
        style: small,
      ),
      _buttons([_turnOffButton()]),
    ];
  }

  List<Widget> _locked(SyncAccountState s) {
    final theme = Theme.of(context);
    return [
      _status(Icons.lock_outline, 'Sync is locked on this device'),
      const SizedBox(height: 8),
      const Text(
        'Your synced notes are end-to-end encrypted. Enter your sync '
        'passphrase or recovery code to sync on this device.',
      ),
      if (s.identity case final id?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Sync account: $id', style: theme.textTheme.bodySmall),
        ),
      ?_errorText(s),
      _buttons([
        FilledButton.icon(
          key: const ValueKey('sync-unlock'),
          icon: const Icon(Icons.key),
          label: const Text('Enter passphrase'),
          onPressed: () => unlockSync(context, _sync, _id),
        ),
      ]),
      const Divider(height: 32),
      Text(
        'Forgot the passphrase and lost the recovery code? Turn sync off '
        '(this deletes the synced copy on the server) and turn it on again '
        'with a new passphrase. The notes on your devices stay.',
        style: theme.textTheme.bodySmall,
      ),
      _buttons([_turnOffButton()]),
    ];
  }

  List<Widget> _signedOut(SyncAccountState s) => [
    _status(
      Icons.cloud_off,
      'Sync stopped',
      color: Theme.of(context).colorScheme.error,
    ),
    const SizedBox(height: 8),
    const Text(
      'This device no longer syncs: the session ended (and signing in '
      'again did not work), or sync was turned off or reset on another '
      'device. Your notes on this device were kept.',
    ),
    ?_errorText(s),
    _buttons([
      FilledButton.icon(
        key: const ValueKey('sync-turn-on-again'),
        icon: const Icon(Icons.cloud_upload_outlined),
        label: const Text('Turn on again'),
        onPressed: () => turnOnSync(context, _sync, _id),
      ),
      OutlinedButton.icon(
        key: const ValueKey('sync-forget'),
        icon: const Icon(Icons.phonelink_erase),
        label: const Text('Forget sync on this device'),
        onPressed: _forget,
      ),
    ]),
  ];
}
