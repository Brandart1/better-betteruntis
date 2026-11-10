import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import 'color_picker_sheet.dart';
import 'lesson_preview.dart';

/// Lesson states with a configurable color.
enum LessonColorKind { regular, irregular, cancelled, exam }

extension on LessonColorKind {
  String get label => switch (this) {
    LessonColorKind.regular => 'Regular',
    LessonColorKind.irregular => 'Substitution',
    LessonColorKind.cancelled => 'Cancelled',
    LessonColorKind.exam => 'Exam',
  };

  int? valueIn(TimetableSettings s) => switch (this) {
    LessonColorKind.regular => s.regularColor,
    LessonColorKind.irregular => s.irregularColor,
    LessonColorKind.cancelled => s.cancelledColor,
    LessonColorKind.exam => s.examColor,
  };

  TimetableSettings apply(TimetableSettings s, int? v) => switch (this) {
    LessonColorKind.regular => s.copyWith(regularColor: v),
    LessonColorKind.irregular => s.copyWith(irregularColor: v),
    LessonColorKind.cancelled => s.copyWith(cancelledColor: v),
    LessonColorKind.exam => s.copyWith(examColor: v),
  };

  /// Theme default background (mirrors [LessonStyle.of]).
  Color themeDefault(ColorScheme cs) => switch (this) {
    LessonColorKind.regular => cs.primaryContainer,
    LessonColorKind.irregular => cs.tertiaryContainer,
    LessonColorKind.cancelled => cs.surfaceContainerHighest,
    LessonColorKind.exam => cs.errorContainer,
  };
}

/// Route `/settings`: lesson colors and text, with a live preview on top.
class TimetableSettingsScreen extends ConsumerWidget {
  const TimetableSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(timetableSettingsProvider);
    final notifier = ref.read(timetableSettingsProvider.notifier);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    void resetAll() {
      final before = ref.read(timetableSettingsProvider);
      notifier.reset();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Settings reset'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => notifier.set(before),
            ),
          ),
        );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            key: const ValueKey('reset-all'),
            onPressed: s == const TimetableSettings() ? null : resetAll,
            child: const Text('Reset all'),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text('Preview', style: theme.textTheme.labelLarge),
                  ),
                  const LessonPreview(),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const _Section('Lesson colors'),
                for (final kind in LessonColorKind.values)
                  _ColorTile(
                    kind: kind,
                    value: kind.valueIn(s),
                    defaultColor: kind.themeDefault(cs),
                    onChanged: (v) =>
                        notifier.update((cur) => kind.apply(cur, v)),
                  ),
                SwitchListTile(
                  key: const ValueKey('school-colors'),
                  title: const Text('School colors'),
                  subtitle: const Text(
                    'Use the subject colors set by your school for regular lessons and substitutions',
                  ),
                  value: s.useSchoolColors,
                  onChanged: (v) =>
                      notifier.update((c) => c.copyWith(useSchoolColors: v)),
                ),
                const _Section('Text'),
                _SizeSlider(
                  key: const ValueKey('subject-size-slider'),
                  label: 'Subject size',
                  value: s.subjectFontSize,
                  min: TimetableSettings.minSubjectFontSize,
                  max: TimetableSettings.maxSubjectFontSize,
                  onChanged: (v) =>
                      notifier.update((c) => c.copyWith(subjectFontSize: v)),
                ),
                _SizeSlider(
                  key: const ValueKey('detail-size-slider'),
                  label: 'Teacher & room size',
                  value: s.detailFontSize,
                  min: TimetableSettings.minDetailFontSize,
                  max: TimetableSettings.maxDetailFontSize,
                  onChanged: (v) =>
                      notifier.update((c) => c.copyWith(detailFontSize: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('bold-subject'),
                  title: const Text('Bold subject'),
                  value: s.boldSubject,
                  onChanged: (v) =>
                      notifier.update((c) => c.copyWith(boldSubject: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('center-text'),
                  title: const Text('Center text'),
                  subtitle: const Text(
                    'Center lesson text horizontally and vertically',
                  ),
                  value: s.centerText,
                  onChanged: (v) =>
                      notifier.update((c) => c.copyWith(centerText: v)),
                ),
                const _Section('Lessons'),
                SwitchListTile(
                  key: const ValueKey('show-cancelled'),
                  title: const Text('Show cancelled lessons'),
                  value: s.showCancelled,
                  onChanged: (v) =>
                      notifier.update((c) => c.copyWith(showCancelled: v)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _ColorTile extends StatelessWidget {
  const _ColorTile({
    required this.kind,
    required this.value,
    required this.defaultColor,
    required this.onChanged,
  });

  final LessonColorKind kind;
  final int? value;
  final Color defaultColor;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = value == null ? defaultColor : Color(value!);
    final hex = value == null
        ? 'Theme default'
        : '#${(value! & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    return ListTile(
      key: ValueKey('color-${kind.name}'),
      leading: Container(
        key: ValueKey('swatch-${kind.name}'),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: cs.outlineVariant),
        ),
      ),
      title: Text(kind.label),
      subtitle: Text(hex),
      trailing: value == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              tooltip: 'Reset ${kind.label.toLowerCase()} color',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => onChanged(null),
            ),
      onTap: () => showLessonColorPicker(
        context,
        title: '${kind.label} lessons',
        value: value,
        defaultColor: defaultColor,
        onChanged: onChanged,
      ),
    );
  }
}

class _SizeSlider extends StatelessWidget {
  const _SizeSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              Text('${value.round()} pt', style: theme.textTheme.labelLarge),
              const SizedBox(width: 8),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            label: '${value.round()}',
            semanticFormatterCallback: (v) => '$label ${v.round()}',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
