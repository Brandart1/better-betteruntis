/// User preferences for how the timetable looks, plus their persistence
/// contract. Pure Dart (no Flutter UI); the file-backed store lives in
/// `lib/app/settings_store.dart` and is injected via [settingsStoreProvider].
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sentinel so [TimetableSettings.copyWith] can tell "not passed" from null.
const Object _keep = Object();

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

    int? color(String k) {
      final v = json[k];
      if (v is int) return v & 0xFFFFFFFF;
      if (v is String) {
        final s = v.startsWith('#') ? v.substring(1) : v;
        final n = int.tryParse(s, radix: 16);
        if (n == null) return null;
        return s.length <= 6 ? 0xFF000000 | n : n & 0xFFFFFFFF;
      }
      return null;
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
      other.showCancelled == showCancelled;

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
