import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../infocenter/info_providers.dart';
import 'login_flow.dart';

/// Austrian education portal where parents log in with ID Austria.
final bildungsportal = Uri.parse('https://bildung.gv.at');

/// How to log in when the school only lets parents in through ID Austria:
/// Untis apps can't do that login themselves, but WebUntis shows a QR code
/// that logs the app in directly.
class IdAustriaScreen extends ConsumerWidget {
  const IdAustriaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Log in with ID Austria')),
      body: SafeArea(
        child: CenteredContent(
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              Text(
                "Untis apps can't log in with ID Austria directly. Instead, "
                'log in once on the web and scan the code WebUntis shows you.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Easiest on a computer or a second device, so you can scan '
                'the screen with this phone.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _Step(
                n: 1,
                title: 'Log in to bildung.gv.at with ID Austria',
                body:
                    'Open bildung.gv.at in a browser, choose "Login" and sign '
                    'in with ID Austria.',
                action: TextButton.icon(
                  key: const ValueKey('open-bildungsportal'),
                  onPressed: () => ref.read(urlOpenerProvider)(bildungsportal),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open bildung.gv.at'),
                ),
              ),
              const _Step(
                n: 2,
                title: 'Open WebUntis',
                body:
                    "In the portal, open your child's school's WebUntis "
                    '(the WebUntis tile or link).',
              ),
              const _Step(
                n: 3,
                title: 'Show the QR code',
                body:
                    'In WebUntis, click your name / profile picture to open '
                    'your profile, then the tab "Freigaben" (Sharing). Next '
                    'to "Zugriff über Untis Mobile" (Access via Untis Mobile) '
                    'click "Anzeigen" (Display).',
              ),
              const _Step(
                n: 4,
                title: 'Scan it with this app',
                body:
                    'Tap the button below and point the camera at the code. '
                    'If WebUntis is open on this phone, use "Paste link '
                    'instead" on the scanner screen.',
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey('id-austria-scan'),
                onPressed: () => context.push('/login/qr'),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan QR code'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.title,
    required this.body,
    this.action,
  });

  final int n;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Text('$n', style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                ?action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
