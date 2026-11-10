import 'package:flutter/material.dart';

import '../timetable/lesson_style.dart';

/// Preset lesson colors: mid tones and deeper shades that read well with
/// either black or white text, in light and dark mode.
const kPresetLessonColors = <int>[
  0xFFE57373, 0xFFD32F2F, 0xFFF06292, 0xFFC2185B, //
  0xFFBA68C8, 0xFF7B1FA2, 0xFF9575CD, 0xFF5C6BC0, //
  0xFF303F9F, 0xFF64B5F6, 0xFF1976D2, 0xFF4DD0E1, //
  0xFF0097A7, 0xFF4DB6AC, 0xFF00796B, 0xFF81C784, //
  0xFF388E3C, 0xFFFFF176, 0xFFFFD54F, 0xFFFFB74D, //
  0xFFF57C00, 0xFFA1887F, 0xFF90A4AE, 0xFF546E7A, //
];

/// Bottom sheet to pick a lesson color. Every change is reported live via
/// [onChanged] (null = reset to the theme default).
Future<void> showLessonColorPicker(
  BuildContext context, {
  required String title,
  required int? value,
  required Color defaultColor,
  required ValueChanged<int?> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ColorPickerSheet(
      title: title,
      value: value,
      defaultColor: defaultColor,
      onChanged: onChanged,
    ),
  );
}

class ColorPickerSheet extends StatefulWidget {
  const ColorPickerSheet({
    super.key,
    required this.title,
    required this.value,
    required this.defaultColor,
    required this.onChanged,
  });

  final String title;
  final int? value;
  final Color defaultColor;
  final ValueChanged<int?> onChanged;

  @override
  State<ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<ColorPickerSheet> {
  late int? _value = widget.value;

  Color get _shown => _value == null ? widget.defaultColor : Color(_value!);

  void _set(int? v) {
    setState(() => _value = v);
    widget.onChanged(v);
  }

  /// Color for [hue] keeping the current color's saturation/lightness within
  /// a range that stays usable as a card background.
  int _fromHue(double hue) {
    final hsl = HSLColor.fromColor(_shown);
    final s = hsl.saturation < 0.45 ? 0.6 : hsl.saturation;
    final l = hsl.lightness.clamp(0.35, 0.75);
    return HSLColor.fromAHSL(1, hue, s, l).toColor().toARGB32();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shown = _shown;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: shown,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Text(
                  'Aa',
                  style: TextStyle(
                    color: onColorFor(shown),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(widget.title, style: theme.textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              const perRow = 8;
              const spacing = 8.0;
              final size = ((c.maxWidth - spacing * (perRow - 1)) / perRow)
                  .clamp(28.0, 48.0);
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final argb in kPresetLessonColors)
                    _Swatch(
                      key: ValueKey('preset-${argb.toRadixString(16)}'),
                      color: Color(argb),
                      size: size,
                      selected: _value == argb,
                      onTap: () => _set(argb),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text('Hue', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          HueSlider(
            key: const ValueKey('hue-slider'),
            hue: HSLColor.fromColor(shown).hue,
            onChanged: (h) => _set(_fromHue(h)),
          ),
          const SizedBox(height: 20),
          OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _value == null
                    ? null
                    : () {
                        _set(null);
                        Navigator.of(context).pop();
                      },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset to default'),
              ),

              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.color,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label:
          'Color #${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
      child: InkResponse(
        onTap: onTap,
        radius: size / 2 + 4,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? cs.onSurface : cs.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: size * 0.5, color: onColorFor(color))
              : null,
        ),
      ),
    );
  }
}

/// Horizontal rainbow bar with a draggable thumb (0–360°).
class HueSlider extends StatelessWidget {
  const HueSlider({super.key, required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  static const _height = 28.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        void report(double dx) => onChanged((dx / w).clamp(0.0, 1.0) * 360);
        final thumbX = (hue / 360).clamp(0.0, 1.0) * w;
        return Semantics(
          slider: true,
          label: 'Hue',
          value: '${hue.round()}°',
          increasedValue: '${((hue + 10) % 360).round()}°',
          decreasedValue: '${((hue - 10) % 360).round()}°',
          onIncrease: () => onChanged((hue + 10) % 360),
          onDecrease: () => onChanged((hue - 10) % 360),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => report(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => report(d.localPosition.dx),
            child: SizedBox(
              height: _height + 8,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: _height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_height / 2),
                      border: Border.all(color: cs.outlineVariant),
                      gradient: LinearGradient(
                        colors: [
                          for (var h = 0; h <= 360; h += 60)
                            HSLColor.fromAHSL(
                              1,
                              h.toDouble() % 360,
                              0.75,
                              0.55,
                            ).toColor(),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: thumbX - (_height + 8) / 2,
                    child: Container(
                      width: _height + 8,
                      height: _height + 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: HSLColor.fromAHSL(
                          1,
                          hue % 360,
                          0.75,
                          0.55,
                        ).toColor(),
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(blurRadius: 3, color: Colors.black38),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
