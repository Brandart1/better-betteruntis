import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'login_flow.dart';
import 'qr_parser.dart';

/// Credentials form. With a [school] (from the search) the school is shown
/// as a card; without one the user enters the school name/ID manually and,
/// optionally, the server host under "Advanced".
class LoginFormScreen extends ConsumerStatefulWidget {
  const LoginFormScreen({super.key, this.school, this.initialUsername});

  final School? school;
  final String? initialUsername;

  @override
  ConsumerState<LoginFormScreen> createState() => _LoginFormScreenState();
}

class _LoginFormScreenState extends ConsumerState<LoginFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _schoolCtrl = TextEditingController();
  late final _userCtrl = TextEditingController(text: widget.initialUsername);
  final _passCtrl = TextEditingController();
  final _profileCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _passFocus = FocusNode();

  bool _anonymous = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  bool get _manual => widget.school == null;

  @override
  void dispose() {
    for (final c in [
      _schoolCtrl,
      _userCtrl,
      _passCtrl,
      _profileCtrl,
      _hostCtrl,
    ]) {
      c.dispose();
    }
    _passFocus.dispose();
    super.dispose();
  }

  Future<School> _resolveSchool() async {
    if (!_manual) return widget.school!;
    final name = _schoolCtrl.text.trim();
    final host = normalizeHost(_hostCtrl.text);
    if (host != null) {
      // Server given: no lookup needed.
      final id = int.tryParse(name);
      return School(
        schoolId: id ?? 0,
        loginName: name,
        displayName: name,
        address: '',
        host: host,
      );
    }
    return resolveSchool(ref.read(untisApiProvider), name);
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final School school;
      try {
        school = await _resolveSchool();
      } on UntisException catch (e) {
        if (!mounted) return;
        setState(
          () => _error = e.code == UntisException.invalidSchool
              ? "We couldn't find a school called \"${_schoolCtrl.text.trim()}\". "
                    'Use the exact school name from the WebUntis login page, '
                    'or set the server under Advanced.'
              : friendlyLoginError(e),
        );
        return;
      }
      final host = normalizeHost(_hostCtrl.text);
      if (!mounted) return;
      final outcome = await performLogin(
        context,
        ref,
        LoginRequest(
          school: school,
          username: _userCtrl.text,
          passwordOrKey: _passCtrl.text,
          anonymous: _anonymous,
          profileName: _profileCtrl.text,
          hostOverride: _manual || host == school.host ? null : host,
        ),
      );
      if (!mounted) return;
      final message = await handleLoginOutcome(context, ref, outcome);
      if (mounted && message != null) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_manual ? 'Enter details' : 'Log in')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                CenteredContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      if (_manual)
                        TextFormField(
                          key: const ValueKey('schoolField'),
                          controller: _schoolCtrl,
                          enabled: !_busy,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'School name or ID',
                            helperText:
                                'As shown on your WebUntis login page, '
                                'e.g. "gym-musterstadt"',
                            prefixIcon: Icon(Icons.school_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v?.trim().isEmpty ?? true)
                              ? 'Enter your school'
                              : null,
                        )
                      else
                        _SchoolCard(school: widget.school!),
                      const SizedBox(height: 16),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: _error == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _ErrorBanner(message: _error!),
                              ),
                      ),
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 200),
                        crossFadeState: _anonymous
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: _credentials(),
                        secondChild: const SizedBox(width: double.infinity),
                      ),
                      Card.outlined(
                        margin: EdgeInsets.zero,
                        child: SwitchListTile(
                          key: const ValueKey('anonymousSwitch'),
                          value: _anonymous,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() {
                                  _anonymous = v;
                                  _error = null;
                                }),
                          secondary: const Icon(Icons.public_rounded),
                          title: const Text('Log in anonymously'),
                          subtitle: const Text(
                            "View the school's public timetable without an "
                            'account (if your school allows it).',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('profileField'),
                        controller: _profileCtrl,
                        enabled: !_busy,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Profile name (optional)',
                          helperText:
                              'Shown in the account switcher, e.g. "Me" or '
                              '"Little sister"',
                          prefixIcon: Icon(Icons.label_outline_rounded),
                          border: OutlineInputBorder(),
                        ),
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 8),
                      Theme(
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          key: const ValueKey('advancedTile'),
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          leading: const Icon(Icons.tune_rounded),
                          title: const Text('Advanced'),
                          children: [
                            TextFormField(
                              key: const ValueKey('hostField'),
                              controller: _hostCtrl,
                              enabled: !_busy,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: 'Server',
                                hintText:
                                    widget.school?.host ?? 'mese.webuntis.com',
                                helperText: _manual
                                    ? 'Optional. Skips the school lookup.'
                                    : 'Only change this if your school uses '
                                          'its own server.',
                                prefixIcon: const Icon(Icons.dns_outlined),
                                border: const OutlineInputBorder(),
                              ),
                              validator: (v) =>
                                  (v?.trim().isNotEmpty ?? false) &&
                                      normalizeHost(v) == null
                                  ? "That doesn't look like a server address"
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const ValueKey('loginButton'),
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(_anonymous ? 'Continue' : 'Log in'),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your password is only used to sign in and is '
                              'never stored. The app keeps a secure key on '
                              'this device.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _credentials() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      children: [
        TextFormField(
          key: const ValueKey('usernameField'),
          controller: _userCtrl,
          enabled: !_busy,
          autofillHints: const [AutofillHints.username],
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixIcon: Icon(Icons.person_outline_rounded),
            border: OutlineInputBorder(),
          ),
          onFieldSubmitted: (_) => _passFocus.requestFocus(),
          validator: (v) => !_anonymous && (v?.trim().isEmpty ?? true)
              ? 'Enter your username'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('passwordField'),
          controller: _passCtrl,
          focusNode: _passFocus,
          enabled: !_busy,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.key_outlined),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onFieldSubmitted: (_) => _submit(),
          validator: (v) => !_anonymous && (v?.isEmpty ?? true)
              ? 'Enter your password'
              : null,
        ),
      ],
    ),
  );
}

class _SchoolCard extends StatelessWidget {
  const _SchoolCard({required this.school});
  final School school;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: scheme.secondaryContainer,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(Icons.school_rounded, color: scheme.onSecondaryContainer),
        title: Text(
          school.displayName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.onSecondaryContainer,
          ),
        ),
        subtitle: school.address.isEmpty
            ? null
            : Text(
                school.address,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
        trailing: Navigator.canPop(context)
            ? TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('Change'),
              )
            : null,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
