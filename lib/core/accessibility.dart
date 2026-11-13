/// Accessibility preferences (global, also before any account exists):
/// high-contrast mode, day view by default with larger day headers, and a
/// read-aloud button for the day's timetable. Persisted in the
/// [SettingsStore] like [TimetableSettings].
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings.dart';

/// High contrast: [off], black on white ([light]) or white on black ([dark]).
/// Either one makes the whole app monochrome.
enum ContrastMode {
  off,
  light,
  dark;

  static ContrastMode parse(Object? v) =>
      values.firstWhere((m) => m.name == v, orElse: () => off);
}

/// Language of the read-aloud text and voice, independent of the app's
/// language. [system] follows the device language (German if it is German,
/// else English).
enum SpeechLanguage {
  system,
  en,
  de;

  static SpeechLanguage parse(Object? v) =>
      values.firstWhere((m) => m.name == v, orElse: () => system);

  /// The concrete language for [deviceLanguageCode] ("de", "en", …).
  SpeechLanguage resolve(String deviceLanguageCode) => switch (this) {
    system => deviceLanguageCode.toLowerCase() == 'de' ? de : en,
    _ => this,
  };

  /// BCP-47 tag for the speech engine.
  String get voiceTag => this == de ? 'de-DE' : 'en-US';
}

class AccessibilitySettings {
  const AccessibilitySettings({
    this.contrast = ContrastMode.off,
    this.dayViewByDefault = false,
    this.largeDayHeaders = false,
    this.speakButton = false,
    this.speechLanguage = SpeechLanguage.system,
  });

  final ContrastMode contrast;

  /// The timetable opens on today's day view instead of the week.
  final bool dayViewByDefault;

  /// Bigger day headers (full weekday and date in the day view).
  final bool largeDayHeaders;

  /// Loudspeaker button in the timetable that reads the day aloud.
  final bool speakButton;
  final SpeechLanguage speechLanguage;

  bool get highContrast => contrast != ContrastMode.off;

  AccessibilitySettings copyWith({
    ContrastMode? contrast,
    bool? dayViewByDefault,
    bool? largeDayHeaders,
    bool? speakButton,
    SpeechLanguage? speechLanguage,
  }) => AccessibilitySettings(
    contrast: contrast ?? this.contrast,
    dayViewByDefault: dayViewByDefault ?? this.dayViewByDefault,
    largeDayHeaders: largeDayHeaders ?? this.largeDayHeaders,
    speakButton: speakButton ?? this.speakButton,
    speechLanguage: speechLanguage ?? this.speechLanguage,
  );

  Map<String, Object?> toJson() => {
    'contrast': contrast.name,
    'dayViewByDefault': dayViewByDefault,
    'largeDayHeaders': largeDayHeaders,
    'speakButton': speakButton,
    'speechLanguage': speechLanguage.name,
  };

  /// Tolerant: anything unknown falls back to the default.
  factory AccessibilitySettings.fromJson(Object? raw) {
    final j = raw is Map ? raw : const {};
    bool b(String k) => j[k] == true;
    return AccessibilitySettings(
      contrast: ContrastMode.parse(j['contrast']),
      dayViewByDefault: b('dayViewByDefault'),
      largeDayHeaders: b('largeDayHeaders'),
      speakButton: b('speakButton'),
      speechLanguage: SpeechLanguage.parse(j['speechLanguage']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AccessibilitySettings &&
      other.contrast == contrast &&
      other.dayViewByDefault == dayViewByDefault &&
      other.largeDayHeaders == largeDayHeaders &&
      other.speakButton == speakButton &&
      other.speechLanguage == speechLanguage;

  @override
  int get hashCode => Object.hash(
    contrast,
    dayViewByDefault,
    largeDayHeaders,
    speakButton,
    speechLanguage,
  );
}

final accessibilityProvider =
    NotifierProvider<AccessibilityNotifier, AccessibilitySettings>(
      AccessibilityNotifier.new,
    );

class AccessibilityNotifier extends Notifier<AccessibilitySettings> {
  static const storeKey = 'accessibility';
  bool _changed = false;

  @override
  AccessibilitySettings build() {
    final store = ref.watch(settingsStoreProvider);
    final cached = store.peek(storeKey);
    if (cached != null) return AccessibilitySettings.fromJson(cached);
    unawaited(_load(store));
    return const AccessibilitySettings();
  }

  Future<void> _load(SettingsStore store) async {
    try {
      final raw = await store.read(storeKey);
      if (!ref.mounted || _changed || raw == null) return;
      state = AccessibilitySettings.fromJson(raw);
    } catch (_) {
      // Unreadable: keep defaults.
    }
  }

  void update(AccessibilitySettings Function(AccessibilitySettings s) change) {
    _changed = true;
    final value = change(state);
    if (value == state) return;
    state = value;
    unawaited(
      ref
          .read(settingsStoreProvider)
          .write(storeKey, value.toJson())
          .catchError((_) {}),
    );
  }
}
