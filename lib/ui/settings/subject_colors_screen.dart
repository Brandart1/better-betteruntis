import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import 'color_picker_sheet.dart';

/// One row of [SubjectColorsScreen].
class _SubjectEntry {
  const _SubjectEntry(this.key, this.name, this.longName, this.schoolColor);

  /// [TimetableSettings.subjectKey] of [name].
  final String key;
  final String name;
  final String longName;
  final int? schoolColor;
}

/// Subjects offered for custom colors. Schools often flag subjects
/// `displayAllowed: false` for students (like rooms), so that flag is
/// ignored; inactive subjects (e.g. past school years) are left out unless
/// none are active.
List<MasterElement> colorableSubjects(NameResolver names) {
  final all = names.elementsOf(ElementType.subject, onlyActive: false);
  final active = [for (final e in all) if (e.active) e];
  return active.isEmpty ? all : active;
}

/// Custom colors per subject. Lists the active subjects of the active
/// account's master data (sorted by name) plus every subject that already
/// has a custom color (colors are global and keyed by short name, so they
/// may come from another account).
class SubjectColorsScreen extends ConsumerStatefulWidget {
  const SubjectColorsScreen({super.key});

  /// Above this many subjects a search field is shown.
  static const searchThreshold = 12;

  @override
  ConsumerState<SubjectColorsScreen> createState() =>
      _SubjectColorsScreenState();
}

class _SubjectColorsScreenState extends ConsumerState<SubjectColorsScreen> {
  String _query = '';

  List<_SubjectEntry> _entries(
    List<MasterElement> subjects,
    TimetableSettings s,
  ) {
    final byKey = <String, _SubjectEntry>{};
    for (final e in subjects) {
      final key = TimetableSettings.subjectKey(e.name);
      if (key.isEmpty || byKey.containsKey(key)) continue;
      byKey[key] = _SubjectEntry(key, e.name.trim(), e.longName, e.backColor);
    }
    for (final key in s.subjectColors.keys) {
      byKey.putIfAbsent(key, () => _SubjectEntry(key, key, '', null));
    }
    return byKey.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(timetableSettingsProvider);
    final notifier = ref.read(timetableSettingsProvider.notifier);
    final namesAsync = ref.watch(nameResolverProvider);
    final cs = Theme.of(context).colorScheme;

    final subjects = namesAsync.hasValue
        ? colorableSubjects(namesAsync.value!)
        : const <MasterElement>[];
    final all = _entries(subjects, s);
    final q = _query.toLowerCase();
    final shown = q.isEmpty
        ? all
        : all
              .where(
                (e) =>
                    e.name.toLowerCase().contains(q) ||
                    e.longName.toLowerCase().contains(q),
              )
              .toList();

    void resetAll() {
      final before = s.subjectColors;
      notifier.update((c) => c.copyWith(subjectColors: const {}));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Subject colors reset'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () =>
                  notifier.update((c) => c.copyWith(subjectColors: before)),
            ),
          ),
        );
    }

    Color fallback(_SubjectEntry e) {
      final argb = (s.useSchoolColors ? e.schoolColor : null) ?? s.regularColor;
      return argb == null ? cs.primaryContainer : Color(argb);
    }

    final Widget body;
    if (namesAsync.isLoading && !namesAsync.hasValue && all.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (all.isEmpty) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No subjects known yet. Open a timetable first.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (all.length > SubjectColorsScreen.searchThreshold)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                key: const ValueKey('subject-search'),
                decoration: const InputDecoration(
                  hintText: 'Search subjects',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
          for (final e in shown)
            _SubjectTile(
              entry: e,
              value: s.subjectColors[e.key],
              defaultColor: fallback(e),
              onChanged: (v) =>
                  notifier.update((c) => c.withSubjectColor(e.key, v)),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subject colors'),
        actions: [
          TextButton(
            key: const ValueKey('reset-subject-colors'),
            onPressed: s.subjectColors.isEmpty ? null : resetAll,
            child: const Text('Reset all'),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _SubjectTile extends StatelessWidget {
  const _SubjectTile({
    required this.entry,
    required this.value,
    required this.defaultColor,
    required this.onChanged,
  });

  final _SubjectEntry entry;
  final int? value;
  final Color defaultColor;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = value == null ? defaultColor : Color(value!);
    final long = entry.longName.trim();
    final subtitle = [
      if (long.isNotEmpty && long != entry.name) long,
      value == null ? 'Default' : formatHexColor(value!),
    ].join(' · ');
    return ListTile(
      key: ValueKey('subject-${entry.key}'),
      leading: Container(
        key: ValueKey('subject-swatch-${entry.key}'),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: cs.outlineVariant),
        ),
      ),
      title: Text(entry.name),
      subtitle: Text(subtitle),
      trailing: value == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              key: ValueKey('subject-reset-${entry.key}'),
              tooltip: 'Reset ${entry.name} color',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => onChanged(null),
            ),
      onTap: () => showLessonColorPicker(
        context,
        title: long.isNotEmpty ? long : entry.name,
        value: value,
        defaultColor: defaultColor,
        onChanged: onChanged,
      ),
    );
  }
}
