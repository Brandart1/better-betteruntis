/// A one-time notice shown when the "Teachers" tab of the timetables menu
/// is first opened (once per device, not per account): teachers' free periods are not a time to contact them. The
/// user must promise not to use the timetables that way, is pointed to the
/// office hours, and learns that a period that looks free often isn't
/// (supervisions, internal meetings are not in the timetable).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings.dart';
import '../infocenter/info_providers.dart';

/// Device-wide settings key: set once the notice was accepted.
const teacherTimetableNoticeKey = 'teacherTimetableNoticeAccepted';

/// Shows the notice unless it was accepted on this device. Returns whether
/// the user may look at teacher timetables now (false: cancelled, or
/// went to the office hours).
Future<bool> ensureTeacherTimetableNotice(
  BuildContext context,
  WidgetRef ref,
) async {
  final store = ref.read(settingsStoreProvider);
  if (await store.read(teacherTimetableNoticeKey) != null) return true;
  if (!context.mounted) return false;
  final choice = await showDialog<TeacherNoticeChoice>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const TeacherTimetableNoticeDialog(),
  );
  if (choice == null || choice == TeacherNoticeChoice.cancel) return false;
  await store.write(
    teacherTimetableNoticeKey,
    DateTime.now().toUtc().toIso8601String(),
  );
  if (choice == TeacherNoticeChoice.officeHours && context.mounted) {
    ref.read(infoTabProvider.notifier).set(InfoTab.officeHours);
    await GoRouter.of(context).push('/info');
    return false;
  }
  return true;
}

/// Wraps the "Teachers" tab of the timetables menu: the first time it is
/// shown on this device, [ensureTeacherTimetableNotice] runs; cancelling
/// calls [onCancel] (e.g. back to the first tab).
class TeacherTimetableNoticeGate extends ConsumerStatefulWidget {
  const TeacherTimetableNoticeGate({
    super.key,
    required this.child,
    this.onCancel,
  });

  final Widget child;
  final VoidCallback? onCancel;

  @override
  ConsumerState<TeacherTimetableNoticeGate> createState() =>
      _TeacherTimetableNoticeGateState();
}

class _TeacherTimetableNoticeGateState
    extends ConsumerState<TeacherTimetableNoticeGate> {
  /// One dialog at a time per tab.
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  Future<void> _check() async {
    if (_showing || !mounted) return;
    _showing = true;
    try {
      final ok = await ensureTeacherTimetableNotice(context, ref);
      if (!ok && mounted) widget.onCancel?.call();
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// How the notice was closed (accepted / office hours only after the
/// promise was ticked).
enum TeacherNoticeChoice { accepted, officeHours, cancel }

class TeacherTimetableNoticeDialog extends StatefulWidget {
  const TeacherTimetableNoticeDialog({super.key});

  @override
  State<TeacherTimetableNoticeDialog> createState() =>
      _TeacherTimetableNoticeDialogState();
}

class _TeacherTimetableNoticeDialogState
    extends State<TeacherTimetableNoticeDialog> {
  bool _promised = false;

  void _close(TeacherNoticeChoice c) => Navigator.of(context).pop(c);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('teacher-notice-dialog'),
        icon: const Icon(Icons.co_present_outlined),
        title: const Text('About teacher timetables'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "This app can show teachers' timetables. Please don't use "
                'them to find a free period to call or visit a teacher: '
                'that time belongs to their work.',
              ),
              const SizedBox(height: 12),
              const Text(
                'To talk to a teacher, use their office hours '
                '(Info center → Office hours) or contact them through the school.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: scheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A period that looks free often isn\'t: hall duty '
                        '(Gangaufsicht), on-call duty, meetings and other '
                        "school tasks usually don't appear in the timetable "
                        'because of the way timetables are generated.',
                        style: TextStyle(color: scheme.onSecondaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const ValueKey('teacher-notice-promise'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _promised,
                onChanged: (v) => setState(() => _promised = v ?? false),
                title: Text(
                  "I won't use teacher timetables to contact teachers in "
                  'their free periods.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('teacher-notice-cancel'),
            onPressed: () => _close(TeacherNoticeChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('teacher-notice-office-hours'),
            onPressed: _promised
                ? () => _close(TeacherNoticeChoice.officeHours)
                : null,
            child: const Text('Open office hours'),
          ),
          FilledButton(
            key: const ValueKey('teacher-notice-accept'),
            onPressed: _promised
                ? () => _close(TeacherNoticeChoice.accepted)
                : null,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
