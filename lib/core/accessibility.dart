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
    this.textScale = 1.0,
    this.speechRate = 1.0,
  });

  /// Voice speed steps (1.0 = the engine's normal speed).
  static const speechRates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  /// Text size steps offered in the menu (on top of the system setting).
  static const textScales = [0.85, 1.0, 1.15, 1.3, 1.5];

  final ContrastMode contrast;

  /// The timetable opens on today's day view instead of the week.
  final bool dayViewByDefault;

  /// Bigger day headers (full weekday and date in the day view).
  final bool largeDayHeaders;

  /// Loudspeaker button in the timetable that reads the day aloud.
  final bool speakButton;
  final SpeechLanguage speechLanguage;

  /// Factor on the system text size (1.0 = unchanged).
  final double textScale;

  /// Voice speed factor, 0.5–2.0 (1.0 = normal).
  final double speechRate;

  bool get highContrast => contrast != ContrastMode.off;

  AccessibilitySettings copyWith({
    ContrastMode? contrast,
    bool? dayViewByDefault,
    bool? largeDayHeaders,
    bool? speakButton,
    SpeechLanguage? speechLanguage,
    double? textScale,
    double? speechRate,
  }) => AccessibilitySettings(
    contrast: contrast ?? this.contrast,
    dayViewByDefault: dayViewByDefault ?? this.dayViewByDefault,
    largeDayHeaders: largeDayHeaders ?? this.largeDayHeaders,
    speakButton: speakButton ?? this.speakButton,
    speechLanguage: speechLanguage ?? this.speechLanguage,
    textScale: textScale ?? this.textScale,
    speechRate: speechRate ?? this.speechRate,
  );

  Map<String, Object?> toJson() => {
    'contrast': contrast.name,
    'dayViewByDefault': dayViewByDefault,
    'largeDayHeaders': largeDayHeaders,
    'speakButton': speakButton,
    'speechLanguage': speechLanguage.name,
    'textScale': textScale,
    'speechRate': speechRate,
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
      textScale: switch (j['textScale']) {
        final num n when n >= 0.5 && n <= 3 => n.toDouble(),
        _ => 1.0,
      },
      speechRate: switch (j['speechRate']) {
        final num n when n >= 0.5 && n <= 2 => n.toDouble(),
        _ => 1.0,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AccessibilitySettings &&
      other.contrast == contrast &&
      other.dayViewByDefault == dayViewByDefault &&
      other.largeDayHeaders == largeDayHeaders &&
      other.speakButton == speakButton &&
      other.speechLanguage == speechLanguage &&
      other.textScale == textScale &&
      other.speechRate == speechRate;

  @override
  int get hashCode => Object.hash(
    contrast,
    dayViewByDefault,
    largeDayHeaders,
    speakButton,
    speechLanguage,
    textScale,
    speechRate,
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
