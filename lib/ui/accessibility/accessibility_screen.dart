import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accessibility.dart';
import '../timetable/day_speech.dart';

/// Accessibility options. Reachable from the login screen and the drawer, so
/// they can be set before the first login.
class AccessibilityScreen extends ConsumerWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(accessibilityProvider);
    final notifier = ref.read(accessibilityProvider.notifier);
    final theme = Theme.of(context);
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Accessibility')),
      body: ListView(
        children: [
          section('High contrast'),
          RadioGroup<ContrastMode>(
            groupValue: a.contrast,
            onChanged: (v) => notifier.update((s) => s.copyWith(contrast: v)),
            child: const Column(
              children: [
                RadioListTile(
                  key: ValueKey('contrast-off'),
                  value: ContrastMode.off,
                  title: Text('Off'),
                  subtitle: Text('Normal colors'),
                ),
                RadioListTile(
                  key: ValueKey('contrast-light'),
                  value: ContrastMode.light,
                  title: Text('Black on white'),
                  subtitle: Text('The whole app in black and white'),
                ),
                RadioListTile(
                  key: ValueKey('contrast-dark'),
                  value: ContrastMode.dark,
                  title: Text('White on black'),
                  subtitle: Text('The whole app in white and black'),
                ),
              ],
            ),
          ),
          section('Text size'),
          _TextSizeTile(
            value: a.textScale,
            onChanged: (v) => notifier.update((s) => s.copyWith(textScale: v)),
          ),
          section('Timetable'),
          SwitchListTile(
            key: const ValueKey('a11y-day-view'),
            title: const Text('Open on the day view'),
            subtitle: const Text(
              "Show today's lessons instead of the whole week",
            ),
            value: a.dayViewByDefault,
            onChanged: (v) =>
                notifier.update((s) => s.copyWith(dayViewByDefault: v)),
          ),
          SwitchListTile(
            key: const ValueKey('a11y-large-headers'),
            title: const Text('Larger day headers'),
            subtitle: const Text(
              'Bigger weekday and date; the day view spells them out',
            ),
            value: a.largeDayHeaders,
            onChanged: (v) =>
                notifier.update((s) => s.copyWith(largeDayHeaders: v)),
          ),
          section('Read aloud'),
          SwitchListTile(
            key: const ValueKey('a11y-speak'),
            secondary: const Icon(Icons.volume_up),
            title: const Text('Loudspeaker button'),
            subtitle: const Text(
              "Reads the day's lessons with your device's voice",
            ),
            value: a.speakButton,
            onChanged: (v) =>
                notifier.update((s) => s.copyWith(speakButton: v)),
          ),
          ListTile(
            key: const ValueKey('a11y-speech-language'),
            enabled: a.speakButton,
            title: const Text('Voice language'),
            subtitle: const Text('Independent of the app language'),
            trailing: DropdownButton<SpeechLanguage>(
              value: a.speechLanguage,
              onChanged: !a.speakButton
                  ? null
                  : (v) =>
                        notifier.update((s) => s.copyWith(speechLanguage: v)),
              items: const [
                DropdownMenuItem(
                  value: SpeechLanguage.system,
                  child: Text('Device language'),
                ),
                DropdownMenuItem(
                  value: SpeechLanguage.en,
                  child: Text('English'),
                ),
                DropdownMenuItem(
                  value: SpeechLanguage.de,
                  child: Text('Deutsch'),
                ),
              ],
            ),
          ),
          if (a.speakButton)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('a11y-test-voice'),
                  icon: const Icon(Icons.record_voice_over_outlined),
                  label: const Text('Test the voice'),
                  onPressed: () {
                    final lang = a.speechLanguage.resolve(
                      WidgetsBinding
                          .instance
                          .platformDispatcher
                          .locale
                          .languageCode,
                    );
                    ref
                        .read(speakerProvider)
                        .speak(
                          lang == SpeechLanguage.de
                              ? 'Erste Stunde: Mathematik bei Frau Müller in Raum 101.'
                              : 'First lesson: Maths with Ms Müller in room 101.',
                          lang,
                        );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Slider over [AccessibilitySettings.textScales] with a live sample.
class _TextSizeTile extends StatelessWidget {
  const _TextSizeTile({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  static const _labels = ['Small', 'Default', 'Large', 'Larger', 'Largest'];

  @override
  Widget build(BuildContext context) {
    const steps = AccessibilitySettings.textScales;
    var i = steps.indexOf(value);
    if (i < 0) i = steps.indexOf(1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_decrease, size: 20),
              Expanded(
                child: Slider(
                  key: const ValueKey('a11y-text-size'),
                  value: i.toDouble(),
                  max: steps.length - 1.0,
                  divisions: steps.length - 1,
                  label: _labels[i],
                  semanticFormatterCallback: (v) => _labels[v.round()],
                  onChanged: (v) => onChanged(steps[v.round()]),
                ),
              ),
              const Icon(Icons.text_increase, size: 28),
            ],
          ),
          Text(
            '${_labels[i]} · ${(steps[i] * 100).round()} %',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'First lesson: Maths with Anna Müller in room R101',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
