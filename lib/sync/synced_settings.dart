/// The user's customisation settings that the optional sync carries along
/// with the lesson notes (docs/SYNC-PLAN.md, "Synced settings"):
/// everything of [TimetableSettings] (colours, subject colours, text,
/// lessons) and of [AccessibilitySettings].
///
/// Each setting is one record of the notes API under the reserved key
/// `settings|<name>` ([settingsRemoteKey]); `text` is the JSON value,
/// `exam` is always false. A setting at its default value has no record
/// (reset to default = tombstone). Lesson note keys always start with a
/// date (`YYYY-MM-DD|…`, [lessonNoteKey] without the account id), so the
/// two namespaces can't collide.
///
/// Names: `timetable.<field>`, `timetable.subjectColor.<SUBJECT>` (one
/// record per subject, so colours of different subjects merge) and
/// `accessibility.<field>`. Values are canonical JSON (integral numbers as
/// int), so every platform compares them the same way.
///
/// [SettingStamp]s (value + updatedAt per name, tombstones included) are
/// kept app-wide in the [SettingsStore] under [SyncedSettingStamps.storeKey];
/// the settings themselves stay in their own stores.
library;

import 'dart:convert';

import '../core/accessibility.dart';
import '../core/notifications.dart';
import '../core/settings.dart';

/// Reserved key namespace of synced settings on the server.
const String settingsKeyPrefix = 'settings|';

/// Whether a server key (local note key without the account id) belongs to
/// the synced settings, not to a lesson note.
bool isSettingsKey(String remoteKey) => remoteKey.startsWith(settingsKeyPrefix);

String settingsRemoteKey(String name) => '$settingsKeyPrefix$name';

const String _timetable = 'timetable.';
const String _subjectColor = 'timetable.subjectColor.';
const String _accessibility = 'accessibility.';

/// Synced fields of [TimetableSettings.toJson] (subject colours separately).
const List<String> _timetableFields = [
  'centerText',
  'subjectFontSize',
  'detailFontSize',
  'boldSubject',
  'useSchoolColors',
  'regularColor',
  'irregularColor',
  'cancelledColor',
  'examColor',
  'showCancelled',
  'examMode',
  'irregularMode',
  'cancelledMode',
  'supervisionColor',
  'roomBookingColor',
  'supervisionMode',
  'roomBookingMode',
  'showColleagueLessons',
];

/// Synced fields of [AccessibilitySettings.toJson] (all of them: the
/// maintainer decided accessibility choices belong to the person).
const List<String> _accessibilityFields = [
  'contrast',
  'dayViewByDefault',
  'largeDayHeaders',
  'speakButton',
  'speechLanguage',
  'textScale',
  'speechRate',
];

/// JSON value with integral numbers as int (web and native encode doubles
/// differently: `15` vs `15.0`).
Object? canonicalValue(Object? v) {
  if (v is num) {
    if (v.isFinite && v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toInt();
    }
    return v.toDouble();
  }
  return v;
}

String _encode(Object? v) => jsonEncode(canonicalValue(v));

bool sameSettingValue(Object? a, Object? b) => _encode(a) == _encode(b);

/// The synced settings that differ from their defaults, by name.
Map<String, Object> syncedSettingsOf(
  TimetableSettings timetable,
  AccessibilitySettings accessibility,
) {
  final out = <String, Object>{};
  void section(
    String prefix,
    List<String> fields,
    Map<String, Object?> json,
    Map<String, Object?> defaults,
  ) {
    for (final f in fields) {
      final v = canonicalValue(json[f]);
      if (v == null || sameSettingValue(v, defaults[f])) continue;
      out['$prefix$f'] = v;
    }
  }

  section(
    _timetable,
    _timetableFields,
    timetable.toJson(),
    const TimetableSettings().toJson(),
  );
  for (final e in timetable.subjectColors.entries) {
    out['$_subjectColor${e.key}'] = e.value;
  }
  section(
    _accessibility,
    _accessibilityFields,
    accessibility.toJson(),
    const AccessibilitySettings().toJson(),
  );
  return out;
}

/// [timetable] with [changes] applied (value null = default).
TimetableSettings applyTimetableChanges(
  TimetableSettings timetable,
  Map<String, Object?> changes,
) {
  final j = timetable.toJson();
  final defaults = const TimetableSettings().toJson();
  final colors = {...timetable.subjectColors};
  var touched = false;
  for (final e in changes.entries) {
    final name = e.key;
    if (name.startsWith(_subjectColor)) {
      final subject = name.substring(_subjectColor.length);
      final v = e.value;
      if (v is int) {
        colors[subject] = v;
      } else {
        colors.remove(subject);
      }
      touched = true;
    } else if (name.startsWith(_timetable)) {
      final f = name.substring(_timetable.length);
      if (!_timetableFields.contains(f)) continue;
      j[f] = e.value ?? defaults[f];
      touched = true;
    }
  }
  if (!touched) return timetable;
  j['subjectColors'] = colors;
  return TimetableSettings.fromJson(j);
}

/// [accessibility] with [changes] applied (value null = default).
AccessibilitySettings applyAccessibilityChanges(
  AccessibilitySettings accessibility,
  Map<String, Object?> changes,
) {
  final j = accessibility.toJson();
  final defaults = const AccessibilitySettings().toJson();
  var touched = false;
  for (final e in changes.entries) {
    if (!e.key.startsWith(_accessibility)) continue;
    final f = e.key.substring(_accessibility.length);
    if (!_accessibilityFields.contains(f)) continue;
    j[f] = e.value ?? defaults[f];
    touched = true;
  }
  return touched ? AccessibilitySettings.fromJson(j) : accessibility;
}

/// Result of reading a remote setting.
sealed class RemoteSettingValue {
  const RemoteSettingValue();
}

/// A setting this app version doesn't know (from a newer version): ignored.
class UnknownSetting extends RemoteSettingValue {
  const UnknownSetting();
}

/// A known setting with a value this app can't use (wrong type, out of
/// range, not normalised): skipped and counted.
class InvalidSetting extends RemoteSettingValue {
  const InvalidSetting();
}

/// A usable value; null = the default.
class SettingValue extends RemoteSettingValue {
  const SettingValue(this.value);
  final Object? value;
}

// ------------------------------------------- settings of one account only

/// Favourite classes, teachers and rooms (lib/core/favourites.dart): one record
/// per favourite, `favourite.<TYPE>#<id>` with the value `true`;
/// unstarring leaves a tombstone. Element ids belong to one school, so
/// these go only to the server of the account they belong to.
const String favouritePrefix = 'favourite.';

final _favouriteName = RegExp(r'^favourite\.(CLASS|TEACHER|ROOM)#-?\d{1,12}$');

bool isFavouriteSetting(String name) => _favouriteName.hasMatch(name);

/// Notification options of one account (lib/core/notifications.dart):
/// `notifications.<field>`, one record per option that isn't at its
/// default. Not `enabled`: turning notifications on needs the system
/// permission on each device, so every device decides that itself.
const String notificationPrefix = 'notifications.';

const List<String> _notificationFields = [
  'timetable',
  'messages',
  'daysAhead',
  'dailySummary',
  'dailyMinute',
  'examReminderDays',
  'homeworkReminderDays',
];

bool isNotificationSetting(String name) =>
    name.startsWith(notificationPrefix) &&
    _notificationFields.contains(name.substring(notificationPrefix.length));

/// Settings that belong to one account and go only to its server.
bool isAccountSetting(String name) =>
    isFavouriteSetting(name) || isNotificationSetting(name);

/// The notification options of every account that differ from the
/// defaults, as synced settings (stamp keys).
Map<String, Object> notificationSettingsOf(NotificationPrefs prefs) {
  final defaults = const NotificationSettings().toJson();
  return {
    for (final e in prefs.byAccount.entries)
      for (final f in e.value.toJson().entries)
        if (_notificationFields.contains(f.key) &&
            f.value != null &&
            !sameSettingValue(defaults[f.key], f.value))
          accountSettingKey(e.key, '$notificationPrefix${f.key}'):
              canonicalValue(f.value)!,
  };
}

/// [s] with synced [changes] (`notifications.<field>` → value, null = the
/// default) applied; other names are ignored.
NotificationSettings applyNotificationChanges(
  NotificationSettings s,
  Map<String, Object?> changes,
) {
  final json = s.toJson();
  final defaults = const NotificationSettings().toJson();
  var changed = false;
  for (final e in changes.entries) {
    if (!isNotificationSetting(e.key)) continue;
    final f = e.key.substring(notificationPrefix.length);
    json[f] = e.value ?? defaults[f];
    changed = true;
  }
  return changed ? NotificationSettings.fromJson(json) : s;
}

/// Local stamp key of [name] belonging to [accountId] only (app-wide
/// settings use the plain name).
String accountSettingKey(String accountId, String name) => '@$accountId|$name';

/// (account id, name) of a stamp key from [accountSettingKey], or null for
/// an app-wide setting.
(String, String)? splitAccountSetting(String key) {
  if (!key.startsWith('@')) return null;
  final bar = key.indexOf('|');
  if (bar < 2) return null;
  return (key.substring(1, bar), key.substring(bar + 1));
}

/// The favourites of every account as synced settings (stamp keys).
Map<String, Object> favouriteSettingsOf(Map<String, Set<String>> favourites) =>
    {
      for (final e in favourites.entries)
        for (final k in e.value)
          if (isFavouriteSetting('$favouritePrefix$k'))
            accountSettingKey(e.key, '$favouritePrefix$k'): true,
    };

/// Whether this app version syncs a setting called [name].
bool isKnownSetting(String name) {
  if (name.startsWith(favouritePrefix)) return isFavouriteSetting(name);
  if (name.startsWith(notificationPrefix)) return isNotificationSetting(name);
  if (name.startsWith(_subjectColor)) return true;
  if (name.startsWith(_timetable)) {
    return _timetableFields.contains(name.substring(_timetable.length));
  }
  if (name.startsWith(_accessibility)) {
    return _accessibilityFields.contains(name.substring(_accessibility.length));
  }
  return false;
}

/// Reads the JSON [text] of the remote setting [name] (a tombstone: pass
/// [deleted]). A value is only accepted if it survives the settings'
/// own parsing unchanged; the default value counts as "no value".
RemoteSettingValue readRemoteSetting(
  String name,
  String text, {
  bool deleted = false,
}) {
  if (!isKnownSetting(name)) return const UnknownSetting();
  if (isFavouriteSetting(name)) {
    if (deleted) return const SettingValue(null);
    try {
      return jsonDecode(text) == true
          ? const SettingValue(true)
          : const InvalidSetting();
    } on FormatException {
      return const InvalidSetting();
    }
  }
  if (isNotificationSetting(name)) {
    if (deleted) return const SettingValue(null);
    final Object? raw;
    try {
      raw = canonicalValue(jsonDecode(text));
    } on FormatException {
      return const InvalidSetting();
    }
    final f = name.substring(notificationPrefix.length);
    final got = canonicalValue(
      NotificationSettings.fromJson({f: raw}).toJson()[f],
    );
    if (raw == null || !sameSettingValue(got, raw)) {
      return const InvalidSetting();
    }
    return sameSettingValue(const NotificationSettings().toJson()[f], raw)
        ? const SettingValue(null)
        : SettingValue(got);
  }
  if (name.startsWith(_subjectColor)) {
    final subject = name.substring(_subjectColor.length);
    if (subject.isEmpty || TimetableSettings.subjectKey(subject) != subject) {
      return const InvalidSetting();
    }
  }
  if (deleted) return const SettingValue(null);
  final Object? raw;
  try {
    raw = canonicalValue(jsonDecode(text));
  } on FormatException {
    return const InvalidSetting();
  }
  if (raw == null) return const InvalidSetting();
  final parsed = syncedSettingsOf(
    applyTimetableChanges(const TimetableSettings(), {name: raw}),
    applyAccessibilityChanges(const AccessibilitySettings(), {name: raw}),
  );
  final got = parsed[name];
  if (got == null) {
    // Parsed to the default: fine if it was the default, else rejected.
    final def = _defaultOf(name);
    return def != null && sameSettingValue(def, raw)
        ? const SettingValue(null)
        : const InvalidSetting();
  }
  return sameSettingValue(got, raw)
      ? SettingValue(got)
      : const InvalidSetting();
}

Object? _defaultOf(String name) {
  if (name.startsWith(_subjectColor)) return null;
  if (name.startsWith(_timetable)) {
    return const TimetableSettings().toJson()[name.substring(
      _timetable.length,
    )];
  }
  return const AccessibilitySettings().toJson()[name.substring(
    _accessibility.length,
  )];
}

/// Value and last change of one synced setting ([value] null: default,
/// i.e. a tombstone). [at] 0: set before this device synced settings.
class SettingStamp {
  const SettingStamp(this.value, this.at);
  final Object? value;
  final int at;

  bool get deleted => value == null;

  Map<String, Object?> toJson() => {'v': ?value, 'at': at};

  static SettingStamp? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = j['at'];
    if (at is! num) return null;
    return SettingStamp(canonicalValue(j['v']), at.toInt());
  }
}

/// The stamps of all synced settings (app-wide).
class SyncedSettingStamps {
  SyncedSettingStamps([Map<String, SettingStamp>? stamps])
    : stamps = stamps ?? {};

  static const storeKey = 'syncedSettings';

  final Map<String, SettingStamp> stamps;

  static SyncedSettingStamps decode(Object? raw) {
    final out = SyncedSettingStamps();
    if (raw is Map) {
      for (final e in raw.entries) {
        final s = SettingStamp.fromJson(e.value);
        if (s != null) out.stamps['${e.key}'] = s;
      }
    }
    return out;
  }

  Map<String, Object?> toJson() => {
    for (final e in stamps.entries) e.key: e.value.toJson(),
  };

  static int _after(int old, int now) => now > old ? now : old + 1;

  /// Stamps what differs between [current] and the stamps: changed values
  /// and resets get [now] (always above the version they replace); values
  /// without a stamp get [now], or 0 when [initial] (found at start-up:
  /// set before settings were synced, so any synced version wins over
  /// them). Returns whether anything changed.
  bool reconcile(
    Map<String, Object> current,
    int now, {
    required bool initial,
  }) {
    var changed = false;
    for (final e in current.entries) {
      final st = stamps[e.key];
      if (st == null) {
        stamps[e.key] = SettingStamp(e.value, initial ? 0 : now);
        changed = true;
      } else if (st.deleted || !sameSettingValue(st.value, e.value)) {
        stamps[e.key] = SettingStamp(e.value, _after(st.at, now));
        changed = true;
      }
    }
    for (final e in stamps.entries.toList()) {
      if (e.value.deleted || current.containsKey(e.key)) continue;
      stamps[e.key] = SettingStamp(null, _after(e.value.at, now));
      changed = true;
    }
    return changed;
  }
}
