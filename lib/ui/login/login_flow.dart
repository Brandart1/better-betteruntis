/// Shared login logic used by the form, the QR scanner and demo mode:
/// duplicate check, 2FA retry loop, error mapping and account creation.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'two_factor_dialog.dart';

/// Everything needed for one login attempt.
class LoginRequest {
  const LoginRequest({
    required this.school,
    required this.username,
    required this.passwordOrKey,
    this.anonymous = false,
    this.profileName,
    this.hostOverride,
    this.skipAppSecret = false,
  });

  final School school;
  final String username;
  final String passwordOrKey;
  final bool anonymous;
  final String? profileName;
  final String? hostOverride;
  final bool skipAppSecret;
}

sealed class LoginOutcome {
  const LoginOutcome();
}

class LoginSucceeded extends LoginOutcome {
  const LoginSucceeded(this.account);
  final Account account;
}

class LoginFailed extends LoginOutcome {
  const LoginFailed(this.message);
  final String message;
}

/// The same school + username is already on this device.
class LoginDuplicate extends LoginOutcome {
  const LoginDuplicate(this.existing);
  final Account existing;
}

/// The user dismissed the 2FA prompt.
class LoginCancelled extends LoginOutcome {
  const LoginCancelled();
}

/// Username used for anonymous (public timetable) logins.
const anonymousUsername = '#anonymous#';

/// Maps API / transport errors to a sentence a student understands.
String friendlyLoginError(Object error) {
  if (error is! UntisException) {
    return 'Something went wrong. Please try again.';
  }
  if (error.isTimeout) {
    return "The server didn't answer in time. If you just mistyped your "
        'password, Untis may be slowing down repeated attempts. Wait a '
        'minute, check your password, and try again.';
  }
  if (error.isNetwork) {
    return "Couldn't reach the server. Check your internet connection "
        'and try again.';
  }
  return switch (error.code) {
    UntisException.invalidPassword =>
      "That username and password don't match. Check them and try again.",
    UntisException.invalidSchool =>
      "We couldn't find that school on the server. Check the school name.",
    UntisException.locked =>
      'This account is temporarily locked after too many attempts. '
          'Wait a bit, then try again.',
    UntisException.noPublicAccess =>
      "This school doesn't offer a public timetable. Log in with your "
          'own account instead.',
    UntisException.invalidClientTime =>
      'Your device clock seems off. Turn on automatic date & time in your '
          'device settings, then try again.',
    UntisException.noRight =>
      "Your account isn't allowed to use the mobile app. Ask your school's "
          'WebUntis admin.',
    UntisException.tooManyResults =>
      'Too many schools match. Be more specific.',
    UntisException.twoFactorRequired => 'This account needs a two-factor code.',
    _ => 'Login failed (${error.code}). ${error.message}',
  };
}

/// Finds a school by login name, numeric id or free text. Prefers an exact
/// match on loginName/schoolId; otherwise accepts a single search hit.
/// Throws [UntisException] (invalidSchool when nothing fits).
Future<School> resolveSchool(UntisApi api, String query) async {
  final q = query.trim();
  final results = await api.searchSchools(q);
  final id = int.tryParse(q);
  for (final s in results) {
    if (s.loginName.toLowerCase() == q.toLowerCase() ||
        (id != null && s.schoolId == id)) {
      return s;
    }
  }
  if (results.length == 1) return results.single;
  throw UntisException(
    UntisException.invalidSchool,
    results.isEmpty ? 'No school "$q"' : 'Several schools match "$q"',
  );
}

final _random = Random();

/// Unique, time-ordered local account id.
String newAccountId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
    '${_random.nextInt(1 << 32).toRadixString(36)}';

bool _sameSchool(School a, School b) =>
    a.loginName.toLowerCase() == b.loginName.toLowerCase() ||
    (a.schoolId != 0 && a.schoolId == b.schoolId);

Account? findDuplicate(Iterable<Account> accounts, LoginRequest r) {
  final user = r.anonymous ? anonymousUsername : r.username.trim();
  for (final a in accounts) {
    if (!_sameSchool(a.school, r.school)) continue;
    if (a.anonymous != r.anonymous) continue;
    if (r.anonymous || a.username.toLowerCase() == user.toLowerCase()) {
      return a;
    }
  }
  return null;
}

/// Runs a complete login including the 2FA prompt and persists the account.
/// Never throws; the outcome says what happened.
Future<LoginOutcome> performLogin(
  BuildContext context,
  WidgetRef ref,
  LoginRequest r,
) async {
  final api = ref.read(untisApiProvider);
  final repo = ref.read(accountRepositoryProvider);

  try {
    final existing = await repo.watchAccounts().first.timeout(
      const Duration(seconds: 3),
      onTimeout: () => const [],
    );
    final dup = findDuplicate(existing, r);
    if (dup != null) return LoginDuplicate(dup);
  } catch (_) {
    // Can't read accounts: don't block the login on it.
  }

  final username = r.anonymous ? anonymousUsername : r.username.trim();
  String? token;
  LoginResult result;
  while (true) {
    try {
      result = await api.login(
        school: r.school,
        username: username,
        passwordOrKey: r.anonymous ? '' : r.passwordOrKey,
        anonymous: r.anonymous,
        twoFactorToken: token,
        skipAppSecret: r.skipAppSecret,
        hostOverride: r.hostOverride,
      );
      break;
    } on UntisException catch (e) {
      if (e.code != UntisException.twoFactorRequired) {
        return LoginFailed(friendlyLoginError(e));
      }
      if (!context.mounted) return const LoginCancelled();
      token = await showTwoFactorDialog(
        context,
        errorText: token == null
            ? null
            : "That code didn't work. Codes change every 30 seconds — "
                  'try the current one.',
      );
      if (token == null) return const LoginCancelled();
    } catch (e) {
      return LoginFailed(friendlyLoginError(e));
    }
  }

  final profile = r.profileName?.trim();
  final account = Account(
    id: newAccountId(),
    school: r.school,
    username: username,
    anonymous: r.anonymous,
    displayName: result.displayName.trim().isEmpty
        ? (r.anonymous ? 'Public timetable' : username)
        : result.displayName,
    profileName: (profile?.isEmpty ?? true) ? null : profile,
    elementType: result.elementType,
    elementId: result.elementId,
    klassenIds: result.klassenIds,
    rights: result.rights,
    masterDataTimestamp: result.masterData.timestamp,
    hostOverride: r.hostOverride,
  );
  try {
    final stored = await repo.add(account, result.secret, result.masterData);
    return LoginSucceeded(stored);
  } catch (e) {
    return const LoginFailed(
      "Logged in, but the account couldn't be saved on this device. "
      'Please try again.',
    );
  }
}

/// Navigates with go_router when available (no-op in bare test harnesses).
void goSafely(BuildContext context, String location) {
  GoRouter.maybeOf(context)?.go(location);
}

/// Common handling for outcomes that aren't screen-specific. Returns the
/// error message to display, or null when nothing needs to be shown.
Future<String?> handleLoginOutcome(
  BuildContext context,
  WidgetRef ref,
  LoginOutcome outcome,
) async {
  switch (outcome) {
    case LoginSucceeded(:final account):
      if (!context.mounted) return null;
      final messenger = ScaffoldMessenger.maybeOf(context);
      goSafely(context, '/');
      messenger?.showSnackBar(
        SnackBar(content: Text('Signed in as ${account.label}')),
      );
      return null;
    case LoginFailed(:final message):
      return message;
    case LoginCancelled():
      return null;
    case LoginDuplicate(:final existing):
      if (!context.mounted) return null;
      final switchTo = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.people_alt_outlined),
          title: const Text('Already added'),
          content: Text(
            '${existing.label} at ${existing.school.displayName} is already '
            'on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('OK'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Switch to it'),
            ),
          ],
        ),
      );
      if (switchTo == true) {
        await ref.read(accountRepositoryProvider).setActive(existing.id);
        if (context.mounted) goSafely(context, '/');
      }
      return null;
  }
}

/// Centers [child] and caps its width so screens look good on iPad.
class CenteredContent extends StatelessWidget {
  const CenteredContent({
    super.key,
    required this.child,
    this.maxWidth = 480,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: padding, child: child),
    ),
  );
}
