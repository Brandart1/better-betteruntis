import 'package:flutter/material.dart';

import '../../core/models.dart';

/// Up to two initials of an account label ("Max Mustermann" -> "MM").
String accountInitials(Account account) {
  if (account.anonymous && (account.profileName?.trim().isEmpty ?? true)) {
    return '';
  }
  final words = account.label
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  final last = words.length > 1 ? words.last.characters.first : '';
  return (first + last).toUpperCase();
}

final _schemeCache = <(int, Brightness), ColorScheme>{};

/// Circle avatar with initials, tinted with a stable per-account hue so the
/// same person always gets the same color.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.account, this.radius = 20});

  final Account account;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hue = account.id.codeUnits.fold(7, (h, c) => (h * 31 + c) % 360);
    final scheme = _schemeCache.putIfAbsent(
      (hue, brightness),
      () => ColorScheme.fromSeed(
        seedColor: HSVColor.fromAHSV(1, hue.toDouble(), 0.6, 0.8).toColor(),
        brightness: brightness,
      ),
    );
    final initials = accountInitials(account);
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: initials.isEmpty
          ? Icon(Icons.public_rounded, size: radius)
          : Text(
              initials,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: radius * (initials.length > 1 ? 0.75 : 0.9),
              ),
            ),
    );
  }
}
