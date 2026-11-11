import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import 'color_picker_sheet.dart';
import 'lesson_preview.dart';
import 'subject_colors_screen.dart';

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

  /// Fill/border mode of a special state; null for regular lessons.
  StateColorMode? modeIn(TimetableSettings s) => switch (this) {
    LessonColorKind.regular => null,
    LessonColorKind.irregular => s.irregularMode,
    LessonColorKind.cancelled => s.cancelledMode,
    LessonColorKind.exam => s.examMode,
  };

  TimetableSettings applyMode(TimetableSettings s, StateColorMode m) =>
      switch (this) {
        LessonColorKind.regular => s,
        LessonColorKind.irregular => s.copyWith(irregularMode: m),
        LessonColorKind.cancelled => s.copyWith(cancelledMode: m),
        LessonColorKind.exam => s.copyWith(examMode: m),
      };

  /// Theme default color (mirrors [LessonStyle.of]): the background in fill
  /// mode, the border color in border mode.
  Color themeDefault(ColorScheme cs, [StateColorMode? mode]) {
    final border = mode == StateColorMode.border;
    return switch (this) {
      LessonColorKind.regular => cs.primaryContainer,
      LessonColorKind.irregular => border ? cs.tertiary : cs.tertiaryContainer,
      LessonColorKind.cancelled =>
        border ? cs.outline : cs.surfaceContainerHighest,
      LessonColorKind.exam => border ? cs.error : cs.errorContainer,
    };
  }
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
            // With an action, SnackBars persist by default; time out instead.
            persist: false,
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
                    defaultColor: kind.themeDefault(cs, kind.modeIn(s)),
                    onChanged: (v) =>
                        notifier.update((cur) => kind.apply(cur, v)),
                    mode: kind.modeIn(s),
                    onModeChanged: (m) =>
                        notifier.update((cur) => kind.applyMode(cur, m)),
                  ),
                ListTile(
                  key: const ValueKey('subject-colors'),
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Subject colors'),
                  subtitle: Text(
                    s.subjectColors.isEmpty
                        ? 'Own colors for single subjects'
                        : '${s.subjectColors.length} custom',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SubjectColorsScreen(),
                    ),
                  ),
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
    this.mode,
    this.onModeChanged,
  });

  final LessonColorKind kind;
  final int? value;
  final Color defaultColor;
  final ValueChanged<int?> onChanged;

  /// Fill/border choice (special states only).
  final StateColorMode? mode;
  final ValueChanged<StateColorMode>? onModeChanged;

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
      // The fill/border choice sits right under the color, so it reads as
      // part of the row without squeezing the title on narrow phones.
      subtitle: mode == null
          ? Text(hex)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hex),
                const SizedBox(height: 6),
                // Scales down instead of overflowing on very narrow screens.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: SegmentedButton<StateColorMode>(
                    key: ValueKey('mode-${kind.name}'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: StateColorMode.fill,
                        label: Text('Fill'),
                        icon: Icon(Icons.format_color_fill, size: 18),
                        tooltip: 'Color the whole lesson',
                      ),
                      ButtonSegment(
                        value: StateColorMode.border,
                        label: Text('Border'),
                        icon: Icon(Icons.border_outer, size: 18),
                        tooltip: 'Color only the border',
                      ),
                    ],
                    selected: {mode!},
                    onSelectionChanged: (sel) => onModeChanged?.call(sel.first),
                  ),
                ),
              ],
            ),
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
