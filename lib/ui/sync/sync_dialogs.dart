/// Dialogs of the sync settings: opt-in flow (disclaimer, encryption choice,
/// passphrase, recovery code), unlock, confirmations and a progress dialog.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../sync/sync_controller.dart';

/// The privacy notice on GitHub.
final kSyncPrivacyUrl = Uri.parse(
  'https://github.com/Brandart1/better-betteruntis/blob/main/docs/PRIVACY.md',
);

/// Minimum passphrase length (see docs/SYNC-PLAN.md).
const kMinPassphraseLength = 8;

/// A finished action's result (also for `void` actions, where "null" would
/// not tell success from cancel).
typedef SyncDone<T> = ({T value});

/// User-facing text for an error thrown by the sync controller.
String syncErrorText(Object e) =>
    e is SyncException ? e.message : 'Something went wrong: $e';

/// The whole opt-in flow for [accountId]: disclaimer, encryption choice,
/// passphrase, then the recovery code (once) and, if the server already has
/// encryption for this account, the unlock dialog.
Future<void> turnOnSync(
  BuildContext context,
  SyncController sync,
  String accountId,
) async {
  final agreed = await showDialog<bool>(
    context: context,
    builder: (_) => const SyncDisclaimerDialog(),
  );
  if (agreed != true || !context.mounted) return;
  final encrypt = await showDialog<bool>(
    context: context,
    builder: (_) => const SyncEncryptionChoiceDialog(),
  );
  if (encrypt == null || !context.mounted) return;
  final SyncDone<SyncEnableResult>? done;
  if (encrypt) {
    done = await showDialog<SyncDone<SyncEnableResult>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PassphraseDialog<SyncEnableResult>(
        title: 'Set a sync passphrase',
        intro:
            'You need this passphrase on every device that syncs. Nobody, '
            'not even the developer, can recover it for you.',
        confirmLabel: 'Turn on sync',
        offerRecoveryCode: true,
        action: (pass, recovery) => sync.enable(
          accountId,
          SyncEnableOptions(passphrase: pass, withRecoveryCode: recovery),
        ),
      ),
    );
  } else {
    done = await runSyncAction(
      context,
      title: 'Turning on sync',
      action: () => sync.enable(accountId, const SyncEnableOptions()),
    );
  }
  final result = done?.value;
  if (result == null || !context.mounted) return;
  if (result.recoveryCode case final code?) {
    await showRecoveryCode(context, code);
    if (!context.mounted) return;
  }
  if (result.state.phase == SyncPhase.locked) {
    await unlockSync(context, sync, accountId, alreadyEncrypted: true);
  }
}

/// Asks for the passphrase or recovery code and unlocks [accountId].
/// Returns whether it worked.
Future<bool> unlockSync(
  BuildContext context,
  SyncController sync,
  String accountId, {
  bool alreadyEncrypted = false,
}) async {
  final done = await showDialog<SyncDone<SyncAccountState>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UnlockDialog(
      alreadyEncrypted: alreadyEncrypted,
      action: (secret) => sync.unlock(accountId, secret),
    ),
  );
  return done != null;
}

/// Shows [code] once with a copy button; closes only after "I saved it".
Future<void> showRecoveryCode(BuildContext context, String code) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RecoveryCodeDialog(code: code),
    );

/// A yes/no question; [destructive] colors the confirm button red.
Future<bool> confirmSync(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('sync-confirm'),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return ok == true;
}

/// Runs [action] behind a progress dialog. On failure the dialog shows the
/// error with "Try again" / "Close"; returns null when closed that way.
Future<SyncDone<T>?> runSyncAction<T>(
  BuildContext context, {
  required String title,
  required Future<T> Function() action,
}) => showDialog<SyncDone<T>>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ActionDialog<T>(title: title, action: action),
);

class _ActionDialog<T> extends StatefulWidget {
  const _ActionDialog({required this.title, required this.action});
  final String title;
  final Future<T> Function() action;

  @override
  State<_ActionDialog<T>> createState() => _ActionDialogState<T>();
}

class _ActionDialogState<T> extends State<_ActionDialog<T>> {
  String? _error;

  @override
  void initState() {
    super.initState();
    // Not during build: the action changes provider state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  Future<void> _run() async {
    if (_error != null) setState(() => _error = null);
    try {
      final value = await widget.action();
      if (mounted) Navigator.of(context).pop((value: value));
    } catch (e) {
      if (mounted) setState(() => _error = syncErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return PopScope(
      canPop: error != null,
      child: AlertDialog(
        key: const ValueKey('sync-progress'),
        title: Text(widget.title),
        content: error == null
            ? Semantics(
                liveRegion: true,
                label: 'Please wait',
                child: const Row(
                  children: [
                    SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    SizedBox(width: 16),
                    Expanded(child: Text('Please wait…')),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: Text(
                  error,
                  key: const ValueKey('sync-action-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
        actions: error == null
            ? null
            : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                FilledButton(onPressed: _run, child: const Text('Try again')),
              ],
      ),
    );
  }
}

/// Step 1 of the opt-in: what is stored where; needs an explicit "I agree".
class SyncDisclaimerDialog extends StatelessWidget {
  const SyncDisclaimerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('sync-disclaimer'),
      title: const Text('Turn on sync?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your custom exams and lesson details are then stored on the '
              'BetterBetterUntis server (hosted by Cloudflare), under your '
              'WebUntis school and user id. That is how your other devices '
              'find them.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Turning sync off deletes them on the server. The notes on '
              'your devices stay.',
            ),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('sync-privacy'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Privacy notice'),
                onPressed: () => launchUrl(
                  kSyncPrivacyUrl,
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('sync-agree'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('I agree'),
        ),
      ],
    );
  }
}

/// Step 2 of the opt-in: pops true (encrypt) or false (no encryption).
class SyncEncryptionChoiceDialog extends StatelessWidget {
  const SyncEncryptionChoiceDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget option({
      required Key key,
      required IconData icon,
      required String title,
      required String subtitle,
      required bool value,
    }) => Card.outlined(
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: key,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: () => Navigator.of(context).pop(value),
      ),
    );
    return AlertDialog(
      key: const ValueKey('sync-encryption-choice'),
      title: const Text('Encrypt your notes?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            option(
              key: const ValueKey('sync-choose-e2e'),
              icon: Icons.lock_outline,
              title: 'Encrypt with a passphrase (recommended)',
              subtitle:
                  'The server only stores encrypted notes that it can\'t '
                  'read. You enter the passphrase once on each device.',
              value: true,
            ),
            option(
              key: const ValueKey('sync-choose-plain'),
              icon: Icons.lock_open,
              title: 'No encryption',
              subtitle:
                  'Simpler, but the server (and anyone with access to it) '
                  'can read your notes.',
              value: false,
            ),
            const SizedBox(height: 12),
            Text(
              'Good to know: if you forget the passphrase and have no '
              'recovery code, nobody can get the synced copy back. Only '
              'that copy is lost; the notes on your devices stay and can be '
              'synced again with a new passphrase.\n\n'
              'In the web version the app itself is loaded from the server, '
              'so encryption there protects less than in the phone apps. It '
              'still protects the stored data.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Rough passphrase strength for the hint below the field.
enum PassphraseStrength {
  tooShort('Too short (at least $kMinPassphraseLength characters)'),
  weak('Weak: longer or with more kinds of characters is better'),
  ok('OK'),
  strong('Strong');

  const PassphraseStrength(this.label);
  final String label;

  static PassphraseStrength of(String p) {
    if (p.length < kMinPassphraseLength) return tooShort;
    var kinds = 0;
    for (final re in [
      RegExp('[a-z]'),
      RegExp('[A-Z]'),
      RegExp('[0-9]'),
      RegExp(r'[^a-zA-Z0-9]'),
    ]) {
      if (re.hasMatch(p)) kinds++;
    }
    final score = (p.length >= 12 ? 2 : 0) + (p.length >= 16 ? 1 : 0) + kinds;
    if (score >= 5) return strong;
    if (score >= 3) return ok;
    return weak;
  }
}

/// Sets a new passphrase (entered twice) and runs [action] with it. Stays
/// open with the error if [action] throws; pops the result on success.
class PassphraseDialog<T> extends StatefulWidget {
  const PassphraseDialog({
    super.key,
    required this.title,
    required this.intro,
    required this.confirmLabel,
    required this.action,
    this.offerRecoveryCode = false,
  });

  final String title;
  final String intro;
  final String confirmLabel;

  /// Shows "Create a recovery code" (passed to [action]).
  final bool offerRecoveryCode;
  final Future<T> Function(String passphrase, bool withRecoveryCode) action;

  @override
  State<PassphraseDialog<T>> createState() => _PassphraseDialogState<T>();
}

class _PassphraseDialogState<T> extends State<PassphraseDialog<T>> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  var _obscure = true;
  var _recovery = true;
  var _busy = false;
  var _submitted = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  String? get _firstError =>
      _submitted && _first.text.length < kMinPassphraseLength
      ? 'At least $kMinPassphraseLength characters'
      : null;
  String? get _secondError =>
      _submitted && _first.text != _second.text ? 'Doesn\'t match' : null;

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (_firstError != null || _secondError != null) return;
    setState(() => _busy = true);
    try {
      final value = await widget.action(_first.text, _recovery);
      if (mounted) Navigator.of(context).pop((value: value));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = syncErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strength = PassphraseStrength.of(_first.text);
    final visibility = IconButton(
      tooltip: _obscure ? 'Show passphrase' : 'Hide passphrase',
      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
      onPressed: () => setState(() => _obscure = !_obscure),
    );
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        key: const ValueKey('sync-passphrase-dialog'),
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.intro),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('sync-passphrase'),
                controller: _first,
                obscureText: _obscure,
                enabled: !_busy,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Passphrase',
                  errorText: _firstError,
                  helperText: _first.text.isEmpty ? null : strength.label,
                  helperMaxLines: 3,
                  suffixIcon: visibility,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('sync-passphrase-repeat'),
                controller: _second,
                obscureText: _obscure,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Repeat passphrase',
                  errorText: _secondError,
                ),
              ),
              if (widget.offerRecoveryCode)
                CheckboxListTile(
                  key: const ValueKey('sync-with-recovery'),
                  contentPadding: EdgeInsets.zero,
                  value: _recovery,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _recovery = v ?? true),
                  title: const Text('Create a recovery code (recommended)'),
                  subtitle: const Text(
                    'Unlocks sync if you forget the passphrase.',
                  ),
                ),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    key: const ValueKey('sync-dialog-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('sync-passphrase-submit'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? Semantics(
                    label: 'Please wait',
                    child: const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}

/// Unlocks E2E with the passphrase or (toggle) the recovery code. A wrong
/// secret keeps the dialog open with the error below the field.
class UnlockDialog extends StatefulWidget {
  const UnlockDialog({
    super.key,
    required this.action,
    this.alreadyEncrypted = false,
  });

  final Future<SyncAccountState> Function(String secret) action;

  /// Shown right after turning sync on: the server already had encryption.
  final bool alreadyEncrypted;

  @override
  State<UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<UnlockDialog> {
  final _field = TextEditingController();
  var _recovery = false;
  var _obscure = true;
  var _busy = false;
  String? _fieldError;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final secret = _field.text.trim();
    if (secret.isEmpty) {
      setState(
        () => _fieldError = _recovery
            ? 'Enter your recovery code'
            : 'Enter your passphrase',
      );
      return;
    }
    setState(() {
      _busy = true;
      _fieldError = null;
      _error = null;
    });
    try {
      final state = await widget.action(_recovery ? secret : _field.text);
      if (mounted) Navigator.of(context).pop((value: state));
    } on SyncException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.wrongSecret) {
          _fieldError = e.message;
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = syncErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        key: const ValueKey('sync-unlock-dialog'),
        title: const Text('Unlock sync'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.alreadyEncrypted
                    ? 'Sync for this account is already end-to-end '
                          'encrypted (set up on another device). Enter the '
                          'sync passphrase to use it here.'
                    : _recovery
                    ? 'Enter the recovery code you saved when you turned '
                          'on encryption.'
                    : 'Your synced notes are end-to-end encrypted. Enter '
                          'your sync passphrase to use them on this device.',
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('sync-unlock-field'),
                controller: _field,
                obscureText: !_recovery && _obscure,
                enabled: !_busy,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                style: _recovery
                    ? const TextStyle(fontFamily: 'monospace')
                    : null,
                textCapitalization: _recovery
                    ? TextCapitalization.characters
                    : TextCapitalization.none,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: _recovery ? 'Recovery code' : 'Passphrase',
                  errorText: _fieldError,
                  errorMaxLines: 3,
                  suffixIcon: _recovery
                      ? null
                      : IconButton(
                          tooltip: _obscure
                              ? 'Show passphrase'
                              : 'Hide passphrase',
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey('sync-unlock-toggle'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _recovery = !_recovery;
                          _field.clear();
                          _fieldError = null;
                        }),
                  child: Text(
                    _recovery
                        ? 'Use the passphrase instead'
                        : 'Use a recovery code instead',
                  ),
                ),
              ),
              if (_error case final error?)
                Text(
                  error,
                  key: const ValueKey('sync-dialog-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('sync-unlock-submit'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? Semantics(
                    label: 'Please wait',
                    child: const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Text('Unlock'),
          ),
        ],
      ),
    );
  }
}

/// The recovery code, shown once. "Done" needs the "I saved it" tick.
class RecoveryCodeDialog extends StatefulWidget {
  const RecoveryCodeDialog({super.key, required this.code});
  final String code;

  @override
  State<RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<RecoveryCodeDialog> {
  var _saved = false;
  var _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _saved,
      child: AlertDialog(
        key: const ValueKey('sync-recovery-dialog'),
        title: const Text('Your recovery code'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'If you forget your passphrase, this code unlocks sync. '
                'Write it down or save it in a password manager.',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        widget.code,
                        key: const ValueKey('sync-recovery-code'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('sync-recovery-copy'),
                      tooltip: _copied ? 'Copied' : 'Copy recovery code',
                      icon: Icon(_copied ? Icons.check : Icons.copy),
                      onPressed: _copy,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'It won\'t be shown again. You can create a new one later in '
                'the sync settings (the old one then stops working).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              CheckboxListTile(
                key: const ValueKey('sync-recovery-saved'),
                contentPadding: EdgeInsets.zero,
                value: _saved,
                onChanged: (v) => setState(() => _saved = v ?? false),
                title: const Text('I saved the recovery code'),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            key: const ValueKey('sync-recovery-done'),
            onPressed: _saved ? () => Navigator.of(context).pop() : null,
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
