import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'login_flow.dart';
import 'qr_parser.dart';

/// Resolves the school of a QR code and logs in with its key. When the code
/// carries a host, a lookup is only attempted for a nicer display name.
Future<LoginOutcome> performQrLogin(
  BuildContext context,
  WidgetRef ref,
  QrLogin qr,
) async {
  final api = ref.read(untisApiProvider);
  School school;
  if (qr.host == null) {
    try {
      school = await resolveSchool(api, qr.school);
    } on UntisException catch (e) {
      return LoginFailed(
        e.code == UntisException.invalidSchool ||
                e.code == UntisException.tooManyResults
            ? "The school \"${qr.school}\" from this code couldn't be found."
            : friendlyLoginError(e),
      );
    } catch (e) {
      return LoginFailed(friendlyLoginError(e));
    }
  } else {
    school = School(
      schoolId: int.tryParse(qr.school) ?? 0,
      loginName: qr.school,
      displayName: qr.school,
      address: '',
      host: qr.host!,
    );
    try {
      final found = await resolveSchool(
        api,
        qr.school,
      ).timeout(const Duration(seconds: 5));
      school = School(
        schoolId: found.schoolId,
        loginName: found.loginName,
        displayName: found.displayName,
        address: found.address,
        host: qr.host!,
      );
    } catch (_) {
      // Name lookup is cosmetic; the code has everything needed.
    }
  }
  if (!context.mounted) return const LoginCancelled();
  return performLogin(
    context,
    ref,
    LoginRequest(
      school: school,
      username: qr.user,
      passwordOrKey: qr.key,
      anonymous: qr.anonymous,
      skipAppSecret: qr.skipAppSecret,
    ),
  );
}

/// Camera QR scanner for `untis://setschool?...` codes, with a "paste link"
/// fallback (simulators, iPads without a usable camera angle, deep links).
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key, this.scanner});

  /// Replaces the camera preview (used by tests). Receives the callback to
  /// feed raw scanned strings into.
  final Widget Function(ValueChanged<String> onCode)? scanner;

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  MobileScannerController? _controller;
  bool _busy = false;
  String? _lastInvalid;

  @override
  void initState() {
    super.initState();
    if (widget.scanner == null) {
      _controller = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && raw.isNotEmpty) {
        handleCode(raw);
        return;
      }
    }
  }

  Future<void> handleCode(String raw) async {
    if (_busy) return;
    final qr = parseUntisQr(raw);
    final messenger = ScaffoldMessenger.of(context);
    if (qr == null) {
      if (_lastInvalid == raw) return; // don't spam for the same code
      _lastInvalid = raw;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              "That's not a WebUntis login code. In WebUntis, open your "
              'profile → "Data access" to show the right one.',
            ),
          ),
        );
      return;
    }
    setState(() => _busy = true);
    unawaited(_controller?.stop());
    try {
      final outcome = await performQrLogin(context, ref, qr);
      if (!mounted) return;
      final message = await handleLoginOutcome(context, ref, outcome);
      if (message != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
      if (outcome is! LoginSucceeded) {
        _lastInvalid = null;
        unawaited(_controller?.start());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pasteLink() async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _PasteLinkDialog(),
    );
    if (text != null && text.trim().isNotEmpty && mounted) {
      _lastInvalid = null;
      await handleCode(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Scan QR code'),
        actions: [
          if (_controller != null)
            IconButton(
              tooltip: 'Flashlight',
              icon: const Icon(Icons.flashlight_on_outlined),
              onPressed: () => _controller!.toggleTorch(),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          widget.scanner?.call(handleCode) ??
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) => _CameraError(
                  message:
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera access is off. Allow it in Settings, or '
                            'paste the link instead.'
                      : "The camera couldn't start. You can paste the link "
                            'instead.',
                ),
              ),
          const _Viewfinder(),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Open WebUntis in a browser, go to your profile → '
                        '"Data access" and point the camera at the QR code.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _pasteLink,
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('Paste link instead'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_busy)
            const ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Signing in…', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 3),
          borderRadius: BorderRadius.circular(28),
        ),
      ),
    ),
  );
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PasteLinkDialog extends StatefulWidget {
  const _PasteLinkDialog();

  @override
  State<_PasteLinkDialog> createState() => _PasteLinkDialogState();
}

class _PasteLinkDialogState extends State<_PasteLinkDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Paste login link'),
    content: TextField(
      key: const ValueKey('qrLinkField'),
      controller: _ctrl,
      autofocus: true,
      keyboardType: TextInputType.url,
      decoration: const InputDecoration(
        hintText: 'untis://setschool?school=…',
        border: OutlineInputBorder(),
      ),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _ctrl.text),
        child: const Text('Use link'),
      ),
    ],
  );
}
