import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../export/csv_export.dart';
import '../../export/export_model.dart';
import 'export_service.dart';

/// Display name of the exported element: classes and rooms by short name,
/// teachers and students by long name, the own timetable by the account.
String exportElementName(
  NameResolver? names,
  Account account,
  TimetableTarget target,
) {
  final e = names?.element(target.type, target.id);
  if (e != null) {
    final long =
        target.type == ElementType.teacher ||
        target.type == ElementType.student;
    final n = (long ? e.longName : e.name).trim();
    if (n.isNotEmpty && n != '?') return n;
  }
  if (target.type == account.elementType && target.id == account.elementId) {
    return account.label;
  }
  return '${target.type.apiName.toLowerCase()} ${target.id}';
}

/// Opens the export bottom sheet for [target] with [initialWeek] (any day of
/// the week shown) preselected.
Future<void> showExportSheet(
  BuildContext context, {
  required Account account,
  required TimetableTarget target,
  required DateTime initialWeek,
  String? elementName,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => ExportSheet(
    account: account,
    target: target,
    initialWeek: initialWeek,
    elementName: elementName,
  ),
);

DateTime _monday(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({
    super.key,
    required this.account,
    required this.target,
    required this.initialWeek,
    this.elementName,
  });

  final Account account;
  final TimetableTarget target;
  final DateTime initialWeek;
  final String? elementName;

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  ExportKind _kind = ExportKind.regular;
  late DateTime _week = _monday(widget.initialWeek);
  ExportFormat _format = ExportFormat.pdf;
  bool _colors = true;
  bool _landscape = true;
  String? _separator;
  bool _busy = false;
  String? _progress;
  String? _error;
  final _buttonKey = GlobalKey();

  String? get _locale => Localizations.maybeLocaleOf(context)?.toLanguageTag();

  void _step(int weeks) => setState(
    () => _week = DateTime(_week.year, _week.month, _week.day + 7 * weeks),
  );

  Future<void> _pickWeek() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _week,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Pick a day of the week',
    );
    if (picked != null && mounted) setState(() => _week = _monday(picked));
  }

  Rect? _origin() {
    final box = _buttonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _export(NameResolver names) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Preparing…';
    });
    try {
      final settings = ref.read(timetableSettingsProvider);
      final options = ExportOptions(
        kind: _kind,
        weekStart: _week,
        format: _format,
        colors: _colors,
        landscape: _landscape,
        separator: _separator ?? defaultCsvSeparator(_locale),
      );
      final t = await prepareExport(
        repo: ref.read(timetableRepositoryProvider),
        names: names,
        account: widget.account,
        target: widget.target,
        elementName:
            widget.elementName ??
            exportElementName(names, widget.account, widget.target),
        options: options,
        palette: ExportPalette.fromSettings(settings),
        locale: _locale,
        onProgress: (m) {
          if (mounted) setState(() => _progress = m);
        },
      );
      if (mounted) setState(() => _progress = 'Creating ${_format.label}…');
      final bytes = await generateExport(
        t,
        options,
        fonts: ref.read(exportFontsProvider),
      );
      final dir = await ref.read(exportDirectoryProvider)();
      final file = await writeExport(dir, t, options, bytes);
      if (!mounted) return;
      final origin = _origin();
      setState(() => _progress = 'Sharing…');
      await ref.read(exportShareProvider)(
        file,
        origin: origin,
        subject: t.title,
      );
      if (mounted) navigator.pop();
    } catch (e) {
      final msg = e is ExportException
          ? e.message
          : e is UntisException
          ? (e.isNetwork || e.isTimeout
                ? 'No connection – could not load the timetable.'
                : e.message)
          : 'Export failed: $e';
      if (mounted) setState(() => _error = msg);
      messenger?.showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = ref.watch(nameResolverProvider).value;
    final weekLabel = exportWeekRange(
      _week,
      DateTime(_week.year, _week.month, _week.day + 4),
      _locale,
    );
    final separator = _separator ?? defaultCsvSeparator(_locale);

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title, style: theme.textTheme.titleSmall),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: AbsorbPointer(
        absorbing: _busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Export timetable', style: theme.textTheme.titleLarge),
            section('What'),
            SegmentedButton<ExportKind>(
              key: const ValueKey('export-kind'),
              segments: const [
                ButtonSegment(
                  value: ExportKind.regular,
                  label: Text('Regular timetable'),
                  icon: Icon(Icons.repeat),
                ),
                ButtonSegment(
                  value: ExportKind.week,
                  label: Text('Specific week'),
                  icon: Icon(Icons.date_range),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 8),
            if (_kind == ExportKind.regular)
              Text(
                'The usual weekly timetable without substitutions or '
                'cancellations, derived from the next $kRegularSampleWeeks weeks.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('export-prev-week'),
                    tooltip: 'Previous week',
                    onPressed: () => _step(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      key: const ValueKey('export-week'),
                      onPressed: _pickWeek,
                      icon: const Icon(Icons.calendar_month),
                      label: Text(weekLabel),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('export-next-week'),
                    tooltip: 'Next week',
                    onPressed: () => _step(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            section('Format'),
            Wrap(
              spacing: 8,
              children: [
                for (final f in ExportFormat.values)
                  ChoiceChip(
                    key: ValueKey('export-format-${f.name}'),
                    label: Text(f.label),
                    selected: _format == f,
                    onSelected: (_) => setState(() => _format = f),
                  ),
              ],
            ),
            if (_format == ExportFormat.csv) ...[
              section('Separator'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: ',', label: Text('Comma ( , )')),
                  ButtonSegment(value: ';', label: Text('Semicolon ( ; )')),
                ],
                selected: {separator},
                onSelectionChanged: (s) => setState(() => _separator = s.first),
              ),
            ],
            if (_format != ExportFormat.csv)
              SwitchListTile(
                key: const ValueKey('export-colors'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Include colors'),
                subtitle: const Text(
                  'Lesson colors from the timetable settings',
                ),
                value: _colors,
                onChanged: (v) => setState(() => _colors = v),
              ),
            if (_format == ExportFormat.pdf)
              SwitchListTile(
                key: const ValueKey('export-landscape'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Landscape'),
                subtitle: const Text('A4, one page'),
                value: _landscape,
                onChanged: (v) => setState(() => _landscape = v),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: _buttonKey,
              onPressed: _busy || names == null ? null : () => _export(names),
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              label: Text(_busy ? (_progress ?? 'Exporting…') : 'Export'),
            ),
          ],
        ),
      ),
    );
  }
}
