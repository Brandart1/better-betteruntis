import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accessibility.dart';
import 'timetable_utils.dart';

/// Tappable day header ("Mon" + day number); today is highlighted.
///
/// With [AccessibilitySettings.largeDayHeaders] the text is bigger, and the
/// day view ([wide]) spells out the weekday and date ("Monday, 10 November").
class DayHeader extends ConsumerWidget {
  const DayHeader({
    super.key,
    required this.date,
    required this.isToday,
    this.onTap,
    this.wide = false,
  });

  final DateTime date;
  final bool isToday;
  final VoidCallback? onTap;

  /// The header spans a whole day view (not a week-grid column).
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final large = ref.watch(
      accessibilityProvider.select((a) => a.largeDayHeaders),
    );
    final Widget content;
    if (large && wide) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Text(
          dateFormat(context, 'EEEE, d MMMM').format(date),
          key: const ValueKey('day-header-large'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: isToday ? cs.primary : cs.onSurface,
            fontWeight: FontWeight.bold,
            decoration: isToday ? TextDecoration.underline : null,
          ),
        ),
      );
    } else {
      final weekday = dateFormat(context, 'E').format(date);
      final circle = large ? 38.0 : 28.0;
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              weekday,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style:
                  (large
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.labelSmall)
                      ?.copyWith(
                        color: isToday ? cs.primary : cs.onSurfaceVariant,
                        fontWeight: isToday || large ? FontWeight.bold : null,
                      ),
            ),
            const SizedBox(height: 2),
            Container(
              width: circle,
              height: circle,
              alignment: Alignment.center,
              decoration: isToday
                  ? BoxDecoration(color: cs.primary, shape: BoxShape.circle)
                  : null,
              child: Text(
                '${date.day}',
                style:
                    (large
                            ? theme.textTheme.titleLarge
                            : theme.textTheme.titleSmall)
                        ?.copyWith(
                          color: isToday ? cs.onPrimary : cs.onSurface,
                          fontWeight: isToday || large ? FontWeight.bold : null,
                        ),
              ),
            ),
          ],
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Semantics(
        button: onTap != null,
        label: dateFormat(context, 'EEEE d MMMM').format(date),
        excludeSemantics: true,
        child: content,
      ),
    );
  }
}
