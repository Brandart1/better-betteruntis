import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks for a 2FA (TOTP) code. Returns the trimmed code, or null if cancelled.
Future<String?> showTwoFactorDialog(
  BuildContext context, {
  String? errorText,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => TwoFactorDialog(errorText: errorText),
);

class TwoFactorDialog extends StatefulWidget {
  const TwoFactorDialog({super.key, this.errorText});

  final String? errorText;

  @override
  State<TwoFactorDialog> createState() => _TwoFactorDialogState();
}

class _TwoFactorDialogState extends State<TwoFactorDialog> {
  final _controller = TextEditingController();
  bool get _valid => _controller.text.trim().length >= 6;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_valid) Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.shield_outlined),
      title: const Text('Two-factor code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your account is protected with two-factor authentication. '
            'Enter the 6-digit code from your authenticator app.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('twoFactorField'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
            decoration: InputDecoration(
              hintText: '000000',
              errorText: widget.errorText,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? _submit : null,
          child: const Text('Verify'),
        ),
      ],
    );
  }
}
