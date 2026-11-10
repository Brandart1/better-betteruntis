import 'package:flutter/material.dart';

import 'timetable_utils.dart';

/// Tappable day header ("Mon" + day number); today is highlighted.
class DayHeader extends StatelessWidget {
  const DayHeader({
    super.key,
    required this.date,
    required this.isToday,
    this.onTap,
  });

  final DateTime date;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final weekday = dateFormat(context, 'E').format(date);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Semantics(
        button: onTap != null,
        label: dateFormat(context, 'EEEE d MMMM').format(date),
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                weekday,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isToday ? cs.primary : cs.onSurfaceVariant,
                  fontWeight: isToday ? FontWeight.bold : null,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(color: cs.primary, shape: BoxShape.circle)
                    : null,
                child: Text(
                  '${date.day}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isToday ? cs.onPrimary : cs.onSurface,
                    fontWeight: isToday ? FontWeight.bold : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
