/// Small badges next to a pupil in "Absences & lesson topic" (birthday,
/// class duties, exemptions) and the seating plan view of the pupils.
library;

import 'package:flutter/material.dart';

import '../../core/class_register.dart';
import '../../core/models.dart';
import 'pupil_avatar.dart';

/// What the badges of one pupil show on the lesson's day.
class PupilNotes {
  const PupilNotes({
    this.birthday = false,
    this.roles = const [],
    this.exemptions = const [],
  });

  final bool birthday;
  final List<ClassRole> roles;
  final List<ClassRegExemption> exemptions;

  bool get isEmpty => !birthday && roles.isEmpty && exemptions.isEmpty;

  /// The notes of every pupil of [regs] (the periods of one lesson block)
  /// on [day]; pupils without any are left out.
  static Map<int, PupilNotes> of(
    Iterable<PeriodRegister> regs,
    Iterable<ClassRegStudent> students,
    DateTime day,
  ) {
    final roles = <int, List<ClassRole>>{};
    final exemptions = <int, List<ClassRegExemption>>{};
    final seenRoles = <(int, int?, String)>{};
    final seenExemptions = <Object>{};
    for (final r in regs) {
      for (final c in r.classRoles) {
        if (!c.appliesOn(day) ||
            !seenRoles.add((c.studentId, c.dutyId, c.label))) {
          continue;
        }
        (roles[c.studentId] ??= []).add(c);
      }
      for (final e in r.exemptions) {
        if (!e.appliesOn(day)) continue;
        if (!seenExemptions.add(e.id ?? (e.studentId, e.label))) continue;
        (exemptions[e.studentId] ??= []).add(e);
      }
    }
    final out = <int, PupilNotes>{};
    for (final s in students) {
      final n = PupilNotes(
        birthday: isBirthday(s.birthDate, day),
        roles: roles[s.id] ?? const [],
        exemptions: exemptions[s.id] ?? const [],
      );
      if (!n.isEmpty) out[s.id] = n;
    }
    return out;
  }
}

/// A row of small badges; nothing when [notes] is empty.
class PupilBadges extends StatelessWidget {
  const PupilBadges({super.key, required this.notes, this.studentId});

  final PupilNotes notes;
  final int? studentId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (notes.birthday)
          _Badge(
            key: ValueKey('pupil-birthday-$studentId'),
            icon: Icons.cake_outlined,
            label: 'Birthday',
            background: scheme.tertiaryContainer,
            foreground: scheme.onTertiaryContainer,
          ),
        for (final r in notes.roles)
          _Badge(
            key: ValueKey('pupil-duty-$studentId-${r.dutyId}'),
            icon: Icons.badge_outlined,
            label: r.label,
            background: scheme.secondaryContainer,
            foreground: scheme.onSecondaryContainer,
          ),
        for (final e in notes.exemptions)
          _Badge(
            key: ValueKey('pupil-exempt-$studentId'),
            icon: Icons.do_not_disturb_on_outlined,
            label: e.label,
            background: scheme.surfaceContainerHighest,
            foreground: scheme.onSurfaceVariant,
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: foreground);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 3),
          Flexible(
            child: Text(label, style: style, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// The pupils laid out as in [plan]; pupils without a seat follow below.
/// Tapping a seat calls [onTap] (switch present / absent), a long press
/// [onLongPress].
class SeatingPlanView extends StatelessWidget {
  const SeatingPlanView({
    super.key,
    required this.account,
    required this.plan,
    required this.students,
    required this.absent,
    required this.notes,
    this.onTap,
    this.onLongPress,
  });

  final Account account;
  final SeatingPlan plan;

  /// The lesson's pupils (only they are shown, seated or not).
  final List<ClassRegStudent> students;
  final Set<int> absent;
  final Map<int, PupilNotes> notes;
  final void Function(ClassRegStudent)? onTap;
  final void Function(ClassRegStudent)? onLongPress;

  static const seatWidth = 88.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byId = {for (final s in students) s.id: s};
    final seated = <int>{};
    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var r = 0; r < plan.rows; r++)
          Row(
            children: [
              for (var c = 0; c < plan.columns; c++)
                switch (byId[plan.seats[(r, c)]]) {
                  final s? when seated.add(s.id) => _seat(context, s),
                  _ => const SizedBox(width: seatWidth + 4, height: 96),
                },
            ],
          ),
      ],
    );
    final unseated = [
      for (final s in students)
        if (!seated.contains(s.id)) s,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plan.name.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(plan.name, style: theme.textTheme.labelLarge),
          ),
        SingleChildScrollView(
          key: const ValueKey('classreg-seating-plan'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: grid,
        ),
        if (unseated.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Without a seat', style: theme.textTheme.labelLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              children: [for (final s in unseated) _seat(context, s)],
            ),
          ),
        ],
      ],
    );
  }

  Widget _seat(BuildContext context, ClassRegStudent s) {
    final theme = Theme.of(context);
    final isAbsent = absent.contains(s.id);
    final n = notes[s.id];
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isAbsent ? scheme.errorContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey('classreg-seat-${s.id}'),
          borderRadius: BorderRadius.circular(10),
          onTap: onTap == null ? null : () => onTap!(s),
          onLongPress: onLongPress == null ? null : () => onLongPress!(s),
          child: SizedBox(
            width: seatWidth,
            height: 92,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      PupilAvatar(
                        account: account,
                        student: s,
                        absent: isAbsent,
                      ),
                      if (n != null)
                        Positioned(
                          right: -6,
                          top: -4,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (n.birthday)
                                Icon(
                                  Icons.cake,
                                  size: 14,
                                  color: scheme.tertiary,
                                  semanticLabel: 'Birthday',
                                ),
                              if (n.roles.isNotEmpty)
                                Icon(
                                  Icons.badge,
                                  size: 14,
                                  color: scheme.secondary,
                                  semanticLabel: n.roles
                                      .map((r) => r.label)
                                      .join(', '),
                                ),
                              if (n.exemptions.isNotEmpty)
                                Icon(
                                  Icons.do_not_disturb_on,
                                  size: 14,
                                  color: scheme.outline,
                                  semanticLabel: 'Exempt',
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.firstName.isNotEmpty ? s.firstName : s.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(
                    s.lastName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
