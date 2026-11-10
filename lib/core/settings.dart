/// User preferences for how the timetable looks, plus their persistence
/// contract. Pure Dart (no Flutter UI); the file-backed store lives in
/// `lib/app/settings_store.dart` and is injected via [settingsStoreProvider].
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sentinel so [TimetableSettings.copyWith] can tell "not passed" from null.
const Object _keep = Object();

/// How the color of a special lesson state (exam, substitution, cancelled)
/// is applied: [fill] paints the whole lesson in the state color, [border]
/// keeps the lesson's normal color (subject / school / regular) and draws a
/// thick border in the state color.
enum StateColorMode {
  fill,
  border;

  /// Tolerant parse: unknown values fall back to [def].
  static StateColorMode parse(Object? v, StateColorMode def) {
    for (final m in values) {
      if (m.name == v) return m;
    }
    return def;
  }
}

/// Immutable timetable styling options. Colors are ARGB (0xAARRGGBB); null
/// means "use the theme-derived default".
class TimetableSettings {
  const TimetableSettings({
    this.centerText = true,
    this.subjectFontSize = 15,
    this.detailFontSize = 12,
    this.boldSubject = true,
    this.useSchoolColors = true,
    this.regularColor,
    this.irregularColor,
    this.cancelledColor,
    this.examColor,
    this.showCancelled = true,
    this.subjectColors = const {},
    this.examMode = StateColorMode.fill,
    this.irregularMode = StateColorMode.fill,
    this.cancelledMode = StateColorMode.fill,
  });

  static const minSubjectFontSize = 11.0;
  static const maxSubjectFontSize = 22.0;
  static const minDetailFontSize = 9.0;
  static const maxDetailFontSize = 18.0;

  final bool centerText;
  final double subjectFontSize;
  final double detailFontSize;
  final bool boldSubject;
  final bool useSchoolColors;
  final int? regularColor;
  final int? irregularColor;
  final int? cancelledColor;
  final int? examColor;
  final bool showCancelled;

  /// Custom colors per subject, keyed by [subjectKey] of the subject's short
  /// name (subject ids differ per school/account, settings are global).
  /// Highest priority for a lesson's base color.
  final Map<String, int> subjectColors;

  /// Fill vs border per special state. Everything defaults to fill (the
  /// user's choice); border keeps the lesson's base color.
  final StateColorMode examMode;
  final StateColorMode irregularMode;
  final StateColorMode cancelledMode;

  /// Normalized key for [subjectColors]: trimmed, upper case.
  static String subjectKey(String shortName) => shortName.trim().toUpperCase();

  /// Custom color of the subject with short name [shortName], if any.
  int? subjectColorFor(String? shortName) {
    if (shortName == null || subjectColors.isEmpty) return null;
    final k = subjectKey(shortName);
    return k.isEmpty ? null : subjectColors[k];
  }

  /// Sets ([color] non-null) or removes the custom color of a subject.
  TimetableSettings withSubjectColor(String shortName, int? color) {
    final k = subjectKey(shortName);
    if (k.isEmpty) return this;
    final next = {...subjectColors};
    if (color == null) {
      next.remove(k);
    } else {
      next[k] = color & 0xFFFFFFFF;
    }
    return copyWith(subjectColors: next);
  }

  /// Pass `null` for a color to reset it to the theme default; omit it to keep.
  TimetableSettings copyWith({
    bool? centerText,
    double? subjectFontSize,
    double? detailFontSize,
    bool? boldSubject,
    bool? useSchoolColors,
    Object? regularColor = _keep,
    Object? irregularColor = _keep,
    Object? cancelledColor = _keep,
    Object? examColor = _keep,
    bool? showCancelled,
    Map<String, int>? subjectColors,
    StateColorMode? examMode,
    StateColorMode? irregularMode,
    StateColorMode? cancelledMode,
  }) {
    int? pick(Object? v, int? old) => identical(v, _keep) ? old : v as int?;
    return TimetableSettings(
      centerText: centerText ?? this.centerText,
      subjectFontSize: subjectFontSize ?? this.subjectFontSize,
      detailFontSize: detailFontSize ?? this.detailFontSize,
      boldSubject: boldSubject ?? this.boldSubject,
      useSchoolColors: useSchoolColors ?? this.useSchoolColors,
      regularColor: pick(regularColor, this.regularColor),
      irregularColor: pick(irregularColor, this.irregularColor),
      cancelledColor: pick(cancelledColor, this.cancelledColor),
      examColor: pick(examColor, this.examColor),
      showCancelled: showCancelled ?? this.showCancelled,
      subjectColors: subjectColors == null
          ? this.subjectColors
          : Map.unmodifiable(subjectColors),
      examMode: examMode ?? this.examMode,
      irregularMode: irregularMode ?? this.irregularMode,
      cancelledMode: cancelledMode ?? this.cancelledMode,
    );
  }

  Map<String, Object?> toJson() => {
    'centerText': centerText,
    'subjectFontSize': subjectFontSize,
    'detailFontSize': detailFontSize,
    'boldSubject': boldSubject,
    'useSchoolColors': useSchoolColors,
    'regularColor': regularColor,
    'irregularColor': irregularColor,
    'cancelledColor': cancelledColor,
    'examColor': examColor,
    'showCancelled': showCancelled,
    'subjectColors': subjectColors,
    'examMode': examMode.name,
    'irregularMode': irregularMode.name,
    'cancelledMode': cancelledMode.name,
  };

  /// Tolerant parse: missing or wrongly typed fields fall back to defaults,
  /// font sizes are clamped to their slider ranges.
  factory TimetableSettings.fromJson(Object? json) {
    const d = TimetableSettings();
    if (json is! Map) return d;
    bool b(String k, bool def) {
      final v = json[k];
      if (v is bool) return v;
      if (v == 'true' || v == 1) return true;
      if (v == 'false' || v == 0) return false;
      return def;
    }

    double size(String k, double def, double min, double max) {
      final v = json[k];
      final n = v is num
          ? v.toDouble()
          : (v is String ? double.tryParse(v) : null);
      if (n == null || n.isNaN) return def;
      return n.clamp(min, max).toDouble();
    }

    int? colorOf(Object? v) {
      if (v is int) return v & 0xFFFFFFFF;
      if (v is String) {
        final s = v.startsWith('#') ? v.substring(1) : v;
        final n = int.tryParse(s, radix: 16);
        if (n == null) return null;
        return s.length <= 6 ? 0xFF000000 | n : n & 0xFFFFFFFF;
      }
      return null;
    }

    int? color(String k) => colorOf(json[k]);

    final subjects = <String, int>{};
    if (json['subjectColors'] case final Map m) {
      m.forEach((k, v) {
        if (k is! String) return;
        final key = subjectKey(k);
        final c = colorOf(v);
        if (key.isNotEmpty && c != null) subjects[key] = c;
      });
    }

    return TimetableSettings(
      centerText: b('centerText', d.centerText),
      subjectFontSize: size(
        'subjectFontSize',
        d.subjectFontSize,
        minSubjectFontSize,
        maxSubjectFontSize,
      ),
      detailFontSize: size(
        'detailFontSize',
        d.detailFontSize,
        minDetailFontSize,
        maxDetailFontSize,
      ),
      boldSubject: b('boldSubject', d.boldSubject),
      useSchoolColors: b('useSchoolColors', d.useSchoolColors),
      regularColor: color('regularColor'),
      irregularColor: color('irregularColor'),
      cancelledColor: color('cancelledColor'),
      examColor: color('examColor'),
      showCancelled: b('showCancelled', d.showCancelled),
      subjectColors: Map.unmodifiable(subjects),
      examMode: StateColorMode.parse(json['examMode'], d.examMode),
      irregularMode: StateColorMode.parse(
        json['irregularMode'],
        d.irregularMode,
      ),
      cancelledMode: StateColorMode.parse(
        json['cancelledMode'],
        d.cancelledMode,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TimetableSettings &&
      other.centerText == centerText &&
      other.subjectFontSize == subjectFontSize &&
      other.detailFontSize == detailFontSize &&
      other.boldSubject == boldSubject &&
      other.useSchoolColors == useSchoolColors &&
      other.regularColor == regularColor &&
      other.irregularColor == irregularColor &&
      other.cancelledColor == cancelledColor &&
      other.examColor == examColor &&
      other.showCancelled == showCancelled &&
      _mapEquals(other.subjectColors, subjectColors) &&
      other.examMode == examMode &&
      other.irregularMode == irregularMode &&
      other.cancelledMode == cancelledMode;

  static bool _mapEquals(Map<String, int> a, Map<String, int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    centerText,
    subjectFontSize,
    detailFontSize,
    boldSubject,
    useSchoolColors,
    regularColor,
    irregularColor,
    cancelledColor,
    examColor,
    showCancelled,
    Object.hashAllUnordered([
      for (final e in subjectColors.entries) Object.hash(e.key, e.value),
    ]),
    examMode,
    irregularMode,
    cancelledMode,
  );
}

/// Key/value store for JSON-encodable settings sections.
abstract interface class SettingsStore {
  /// Value of [key] if it is already loaded (synchronous), else null.
  Object? peek(String key);

  /// Loads (once) and returns the value of [key], or null.
  Future<Object?> read(String key);

  /// Persists [value] (JSON-encodable) under [key].
  Future<void> write(String key, Object? value);
}

/// Non-persistent store (tests, and the default when nothing is overridden).
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([Map<String, Object?>? initial]) : values = {...?initial};

  final Map<String, Object?> values;

  @override
  Object? peek(String key) => values[key];

  @override
  Future<Object?> read(String key) async => values[key];

  @override
  Future<void> write(String key, Object? value) async => values[key] = value;
}

/// Overridden in main.dart with the file-backed store.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => MemorySettingsStore(),
);

/// Current timetable settings. Starts with the stored value if the store has
/// it loaded already, otherwise with defaults and swaps in the stored value
/// as soon as it is read (unless the user changed something meanwhile).
final timetableSettingsProvider =
    NotifierProvider<TimetableSettingsNotifier, TimetableSettings>(
      TimetableSettingsNotifier.new,
    );

class TimetableSettingsNotifier extends Notifier<TimetableSettings> {
  static const storeKey = 'timetable';
  bool _changed = false;

  @override
  TimetableSettings build() {
    final store = ref.watch(settingsStoreProvider);
    final cached = store.peek(storeKey);
    if (cached != null) return TimetableSettings.fromJson(cached);
    unawaited(_load(store));
    return const TimetableSettings();
  }

  Future<void> _load(SettingsStore store) async {
    try {
      final raw = await store.read(storeKey);
      if (!ref.mounted || _changed || raw == null) return;
      state = TimetableSettings.fromJson(raw);
    } catch (_) {
      // Unreadable settings: keep defaults.
    }
  }

  /// Replaces the settings and persists them.
  void set(TimetableSettings value) {
    _changed = true;
    if (value == state) return;
    state = value;
    unawaited(
      ref
          .read(settingsStoreProvider)
          .write(storeKey, value.toJson())
          .catchError((_) {}),
    );
  }

  void update(TimetableSettings Function(TimetableSettings s) change) =>
      set(change(state));

  void reset() => set(const TimetableSettings());
}
