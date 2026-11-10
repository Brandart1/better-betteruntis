import 'package:flutter/material.dart';

import '../../core/models.dart';

/// Full-height labeled block for a holiday day. Rotates the label in narrow
/// columns.
class HolidayBlock extends StatelessWidget {
  const HolidayBlock({super.key, required this.holiday});

  final Holiday holiday;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = holiday.longName.isNotEmpty ? holiday.longName : holiday.name;
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 120;
        final text = Text(
          label,
          textAlign: TextAlign.center,
          maxLines: narrow ? 1 : 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: cs.onSecondaryContainer,
          ),
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: cs.secondaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: narrow ? RotatedBox(quarterTurns: 3, child: text) : text,
            ),
          ),
        );
      },
    );
  }
}
