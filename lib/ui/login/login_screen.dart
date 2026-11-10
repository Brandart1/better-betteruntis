import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'login_flow.dart';

/// School the "Try the demo" button logs into (user/password `demo`). Only
/// works when [untisApiProvider] is a demo/fake implementation, unless the
/// shell supplies [LoginScreen.onTryDemo].
const demoSchool = School(
  schoolId: 0,
  loginName: 'demo',
  displayName: 'Demo School',
  address: 'Sample data — nothing is sent anywhere',
  host: 'demo.invalid',
);

/// Welcome screen: school search plus QR / manual / demo entry points.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.addingAccount = false, this.onTryDemo});

  /// True when opened from the account switcher: shows a close button and
  /// the title "Add account".
  final bool addingAccount;

  /// Overrides the default demo action (logging in as `demo` at
  /// [demoSchool]), e.g. to switch the app's providers into demo mode.
  final Future<void> Function(BuildContext context)? onTryDemo;

  static const searchDebounce = Duration(milliseconds: 300);

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _SearchStatus { idle, loading, results, empty, tooMany, error }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _requestId = 0;

  _SearchStatus _status = _SearchStatus.idle;
  List<School> _results = const [];
  String _error = '';
  bool _demoBusy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      _requestId++;
      setState(() => _status = _SearchStatus.idle);
      return;
    }
    _debounce = Timer(LoginScreen.searchDebounce, () => _search(q));
    setState(() {}); // update clear button
  }

  Future<void> _search(String query) async {
    final id = ++_requestId;
    setState(() => _status = _SearchStatus.loading);
    try {
      final results = await ref.read(untisApiProvider).searchSchools(query);
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = results;
        _status = results.isEmpty ? _SearchStatus.empty : _SearchStatus.results;
      });
    } on UntisException catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        if (e.code == UntisException.tooManyResults) {
          _status = _SearchStatus.tooMany;
        } else {
          _status = _SearchStatus.error;
          _error = friendlyLoginError(e);
        }
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _status = _SearchStatus.error;
        _error = friendlyLoginError(e);
      });
    }
  }

  void _retry() {
    final q = _controller.text.trim();
    if (q.length >= 2) _search(q);
  }

  void _clear() {
    _debounce?.cancel();
    _requestId++;
    _controller.clear();
    setState(() => _status = _SearchStatus.idle);
    _focus.requestFocus();
  }

  void _openSchool(School school) {
    _focus.unfocus();
    context.push('/login/form', extra: school);
  }

  void _openManual() => context.push('/login/form');
  void _openQr() => context.push('/login/qr');

  Future<void> _tryDemo() async {
    if (_demoBusy) return;
    setState(() => _demoBusy = true);
    try {
      if (widget.onTryDemo != null) {
        await widget.onTryDemo!(context);
        return;
      }
      final outcome = await performLogin(
        context,
        ref,
        const LoginRequest(
          school: demoSchool,
          username: 'demo',
          passwordOrKey: 'demo',
          profileName: 'Demo',
        ),
      );
      if (!mounted) return;
      final message = await handleLoginOutcome(context, ref, outcome);
      if (message != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("The demo isn't available right now. $message"),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _demoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final searching = _status != _SearchStatus.idle;
    return Scaffold(
      appBar: widget.addingAccount
          ? AppBar(
              leading: CloseButton(
                onPressed: () => context.canPop()
                    ? context.pop()
                    : Navigator.maybePop(context),
              ),
              title: const Text('Add account'),
            )
          : null,
      body: SafeArea(
        child: CenteredContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_demoBusy) const LinearProgressIndicator(),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: searching
                    ? const SizedBox(width: double.infinity, height: 16)
                    : _WelcomeHeader(addingAccount: widget.addingAccount),
              ),
              _SearchField(
                controller: _controller,
                focusNode: _focus,
                onChanged: _onChanged,
                onClear: _clear,
                onSubmitted: (q) {
                  _debounce?.cancel();
                  if (q.trim().length >= 2) _search(q.trim());
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(
                    key: ValueKey(_status),
                    child: _buildBody(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final actions = _SecondaryActions(
      onQr: _openQr,
      onManual: _openManual,
      onDemo: widget.addingAccount ? null : _tryDemo,
      demoBusy: _demoBusy,
    );
    switch (_status) {
      case _SearchStatus.idle:
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            const _Hint(
              icon: Icons.travel_explore_rounded,
              title: 'Find your school',
              message:
                  'Type its name or city, e.g. "Goethe Gymnasium Berlin". '
                  'Add as many schools and accounts as you like.',
            ),
            const SizedBox(height: 16),
            actions,
          ],
        );
      case _SearchStatus.loading:
        return const Padding(
          padding: EdgeInsets.only(top: 48),
          child: Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Searching schools…'),
              ],
            ),
          ),
        );
      case _SearchStatus.results:
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: _results.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 4),
          itemBuilder: (context, i) {
            if (i == _results.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: TextButton.icon(
                    onPressed: _openManual,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text("Not listed? Enter details manually"),
                  ),
                ),
              );
            }
            return _SchoolTile(
              school: _results[i],
              onTap: () => _openSchool(_results[i]),
            );
          },
        );
      case _SearchStatus.empty:
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            _Hint(
              icon: Icons.search_off_rounded,
              title: 'No schools found',
              message:
                  'Nothing matches "${_controller.text.trim()}". Check the '
                  'spelling, try the city, or scan the QR code from your '
                  'WebUntis profile.',
            ),
            const SizedBox(height: 16),
            actions,
          ],
        );
      case _SearchStatus.tooMany:
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: const [
            _Hint(
              icon: Icons.manage_search_rounded,
              title: 'Too many results — be more specific',
              message:
                  'Lots of schools match. Add the city or more of the name, '
                  'e.g. "Humboldt Köln".',
            ),
          ],
        );
      case _SearchStatus.error:
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            _Hint(
              icon: Icons.cloud_off_rounded,
              title: "Couldn't search",
              message: _error,
              isError: true,
              action: FilledButton.tonalIcon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ),
            const SizedBox(height: 16),
            actions,
          ],
        );
    }
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.addingAccount});
  final bool addingAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: addingAccount ? 8 : 40, bottom: 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primaryContainer, scheme.tertiaryContainer],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              Icons.calendar_view_week_rounded,
              size: 38,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          if (addingAccount) ...[
            Text(
              'Add another account',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Same school or a different one — switch between them anytime.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            Text(
              'Welcome to',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            Text(
              'BetterBetterUntis',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your timetable — fast, clear and available offline.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      key: const ValueKey('schoolSearchField'),
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: 'School name or city',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded),
                onPressed: onClear,
              ),
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }
}

class _SchoolTile extends StatelessWidget {
  const _SchoolTile({required this.school, required this.onTap});
  final School school;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: scheme.secondaryContainer,
          foregroundColor: scheme.onSecondaryContainer,
          child: const Icon(Icons.school_outlined),
        ),
        title: Text(school.displayName),
        subtitle: school.address.isEmpty ? null : Text(school.address),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({
    required this.icon,
    required this.title,
    required this.message,
    this.isError = false,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isError;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        children: [
          Icon(
            icon,
            size: 40,
            color: isError ? scheme.error : scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions({
    required this.onQr,
    required this.onManual,
    required this.onDemo,
    required this.demoBusy,
  });

  final VoidCallback onQr;
  final VoidCallback onManual;
  final VoidCallback? onDemo;
  final bool demoBusy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: onQr,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan QR code'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onManual,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Enter details manually'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        if (onDemo != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: demoBusy ? null : onDemo,
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: const Text('Try the demo'),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Tip: in WebUntis on the web, open your profile → "Data access" '
          'to show a login QR code.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
