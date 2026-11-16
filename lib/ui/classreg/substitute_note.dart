import 'package:flutter/material.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../common/large_text.dart';

/// Name of the substitute teacher [sub] ("another teacher" when unknown).
String substituteName(ElementRef? sub, NameResolver? names) {
  if (sub == null || sub.id <= 0) return 'another teacher';
  final long = names?.longName(sub) ?? '';
  if (long.isNotEmpty && !long.startsWith('#')) return long;
  final short = names?.shortName(sub) ?? sub.inlineName ?? '';
  return short.isNotEmpty ? short : 'another teacher';
}

/// Banner of the read-only class register of a lesson a substitute held.
class SubstituteNote extends StatelessWidget {
  const SubstituteNote({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Text(
      'Entered by substitute $name. They held this lesson instead of you, '
      'so you can view its absences, topic and entries but not change them.',
      style: TextStyle(color: cs.onTertiaryContainer),
    );
    return Container(
      key: const ValueKey('classreg-substitute-note'),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: isLargeText(context)
          ? text
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.swap_horiz, color: cs.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(child: text),
              ],
            ),
    );
  }
}
