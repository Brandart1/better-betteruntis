/// Read-aloud text for one day of a timetable ("First lesson: Maths with
/// Anna Müller in room R101. …"), in English or German independent of the
/// app's language, plus the text-to-speech engine wrapper.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/accessibility.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import 'lesson_layout.dart';
import 'timetable_utils.dart';

class _Words {
  const _Words({
    required this.weekdays,
    required this.months,
    required this.ordinals,
    required this.lesson,
    required this.lessonsRange,
    required this.and,
    required this.withTeacher,
    required this.inRoom,
    required this.cancelled,
    required this.substitution,
    required this.exam,
    required this.noLessons,
    required this.holiday,
    required this.date,
  });

  final List<String> weekdays;
  final List<String> months;
  final List<String> ordinals;

  /// "{ordinal} lesson" / "{ordinal} Stunde".
  final String Function(String ordinal) lesson;
  final String Function(int from, int to) lessonsRange;
  final String and;
  final String withTeacher;
  final String inRoom;
  final String cancelled;
  final String substitution;
  final String exam;
  final String noLessons;
  final String holiday;
  final String Function(String weekday, int day, String month) date;
}

final _en = _Words(
  weekdays: const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ],
  months: const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ],
  ordinals: const [
    'first',
    'second',
    'third',
    'fourth',
    'fifth',
    'sixth',
    'seventh',
    'eighth',
    'ninth',
    'tenth',
    'eleventh',
    'twelfth',
    'thirteenth',
    'fourteenth',
    'fifteenth',
  ],
  lesson: (o) => '$o lesson',
  lessonsRange: (a, b) => 'lessons $a to $b',
  and: 'and',
  withTeacher: 'with',
  inRoom: 'in room',
  cancelled: 'cancelled',
  substitution: 'substitution',
  exam: 'exam',
  noLessons: 'No lessons.',
  holiday: 'Holiday',
  date: (w, d, m) => '$w, $d $m.',
);

final _de = _Words(
  weekdays: const [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ],
  months: const [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ],
  ordinals: const [
    'erste',
    'zweite',
    'dritte',
    'vierte',
    'fünfte',
    'sechste',
    'siebte',
    'achte',
    'neunte',
    'zehnte',
    'elfte',
    'zwölfte',
    'dreizehnte',
    'vierzehnte',
    'fünfzehnte',
  ],
  lesson: (o) => '$o Stunde',
  lessonsRange: (a, b) => 'Stunden $a bis $b',
  and: 'und',
  withTeacher: 'bei',
  inRoom: 'in Raum',
  cancelled: 'entfällt',
  substitution: 'Vertretung',
  exam: 'Prüfung',
  noLessons: 'Keine Stunden.',
  holiday: 'Frei',
  date: (w, d, m) => '$w, $d. $m.',
);

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Names that are placeholders rather than real names ("?", "#12").
bool _usable(String n) {
  final t = n.trim();
  return t.isNotEmpty && t != '?' && !RegExp(r'^#-?\d+$').hasMatch(t);
}

String _joinAnd(List<String> parts, String and) => switch (parts.length) {
  0 => '',
  1 => parts.first,
  _ => '${parts.sublist(0, parts.length - 1).join(', ')} $and ${parts.last}',
};

/// Lesson numbers of [b] (one per period, e.g. 2 and 3 for a double
/// lesson). From the school's time grid when every period starts in one of
/// its units (the unit's label if it is a number, else its position), else
/// counted from the day's own lessons: the n-th distinct start time is
/// lesson n. Parallel lessons share a number.
List<int> lessonNumbersOf(
  TimeGrid grid,
  LessonBlock b,
  Iterable<Period> dayPeriods,
) {
  final starts = {for (final p in b.periods) minuteOfDay(p.start)}.toList()
    ..sort();
  if (!grid.isFallback) {
    final units = [...unitsFor(grid, b.start.weekday)]
      ..sort((x, y) => x.start.compareTo(y.start));
    final labelsAreNumbers = units.every(
      (u) => (int.tryParse(u.label.trim()) ?? 0) > 0,
    );
    final nums = <int>{};
    for (final s in starts) {
      // A lesson may start a few minutes after its unit (late grids).
      final i = units.indexWhere((u) => s >= u.start - 5 && s < u.end);
      if (i < 0) {
        nums.clear();
        break;
      }
      // Several units in one period (a 90-minute double): count them all.
      final end = b.periods
          .where((p) => minuteOfDay(p.start) == s)
          .map((p) => minuteOfDay(p.end))
          .reduce((a, c) => a > c ? a : c);
      for (var k = i; k < units.length && units[k].start < end; k++) {
        nums.add(labelsAreNumbers ? int.parse(units[k].label.trim()) : k + 1);
      }
    }
    if (nums.isNotEmpty) return nums.toList()..sort();
  }
  final dayStarts = {for (final p in dayPeriods) minuteOfDay(p.start)}.toList()
    ..sort();
  return [for (final s in starts) dayStarts.indexOf(s) + 1];
}

/// "First lesson", "First and second lesson", "Lessons 3 to 5".
String _when(_Words w, List<int> nums) {
  final first = nums.first, last = nums.last;
  String ord(int n) => n <= w.ordinals.length ? w.ordinals[n - 1] : '$n.';
  if (nums.length == 1) return _cap(w.lesson(ord(first)));
  if (nums.length == 2) {
    return _cap(w.lesson('${ord(first)} ${w.and} ${ord(last)}'));
  }
  return _cap(w.lessonsRange(first, last));
}

/// The text read aloud for [date]: the date, then one sentence per lesson
/// (subjects, teachers, rooms; cancelled / substitution / exam), or
/// "No lessons" / the holiday.
String daySpeech({
  required DateTime date,
  required List<Period> periods,
  required NameResolver names,
  required SpeechLanguage language,
  bool showCancelled = true,
}) {
  final w = language == SpeechLanguage.de ? _de : _en;
  final out = <String>[
    w.date(w.weekdays[date.weekday - 1], date.day, w.months[date.month - 1]),
  ];
  final holiday = holidayOn(names.holidays, date);
  // Numbering counts every lesson of the day, also hidden cancelled ones.
  final dayPeriods = periods.where((p) => sameDay(p.start, date)).toList();
  final blocks = layoutDay(
    dayPeriods.where((p) => showCancelled || !p.isCancelled),
  )..sort((a, b) => a.start.compareTo(b.start));
  if (blocks.isEmpty) {
    out.add(
      holiday != null
          ? '${w.holiday}: ${holiday.longName.isNotEmpty ? holiday.longName : holiday.name}.'
          : w.noLessons,
    );
    return out.join(' ');
  }
  for (final b in blocks) {
    final p = b.first;
    List<String> current(ElementType t, {bool long = true}) => [
      for (final r in p.ofType(t))
        if (r.change != ElementChange.removed)
          long ? names.longName(r) : names.shortName(r),
    ].where(_usable).toSet().toList();
    final subjects = current(ElementType.subject);
    final teachers = current(ElementType.teacher);
    final rooms = current(ElementType.room, long: false);
    var what = _joinAnd(
      subjects.isNotEmpty
          ? subjects
          : [if (_usable(p.lessonText)) p.lessonText],
      w.and,
    );
    if (teachers.isNotEmpty) {
      what = '$what ${w.withTeacher} ${_joinAnd(teachers, w.and)}'.trim();
    }
    if (rooms.isNotEmpty) {
      what = '$what ${w.inRoom} ${_joinAnd(rooms, w.and)}'.trim();
    }
    final notes = [
      if (b.isCancelled)
        w.cancelled
      else ...[
        if (b.isExam) w.exam,
        if (b.isIrregular) w.substitution,
      ],
    ];
    final sentence = [if (what.isNotEmpty) what, ...notes].join(', ');
    final nums = lessonNumbersOf(names.timeGrid, b, dayPeriods);
    out.add('${_when(w, nums)}: $sentence.');
  }
  return out.join(' ');
}

/// Speaks text with the operating system's text-to-speech engine.
abstract interface class Speaker {
  /// [rate]: speed factor, 1.0 = the engine's normal speed (0.5–2.0).
  Future<void> speak(String text, SpeechLanguage language, {double rate = 1});
  Future<void> stop();

  /// Whether something is being read right now.
  ValueListenable<bool> get speaking;
}

/// The flutter_tts rate for speed factor [factor]: iOS/macOS treat 0.5 as
/// normal speed (range 0–1), Android and the web 1.0 (2.0 = double).
double engineRate(double factor, TargetPlatform platform) {
  final f = factor.clamp(0.5, 2.0);
  return switch (platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => (0.5 * f).clamp(0.0, 1.0),
    _ => f,
  };
}

class TtsSpeaker implements Speaker {
  TtsSpeaker() {
    _tts.setCompletionHandler(() => _speaking.value = false);
    _tts.setCancelHandler(() => _speaking.value = false);
    _tts.setErrorHandler((_) => _speaking.value = false);
  }

  final _tts = FlutterTts();
  final _speaking = ValueNotifier(false);

  @override
  ValueListenable<bool> get speaking => _speaking;

  @override
  Future<void> speak(
    String text,
    SpeechLanguage language, {
    double rate = 1,
  }) async {
    await _tts.stop();
    try {
      await _tts.setLanguage(language.voiceTag);
    } catch (_) {
      // Voice not installed: the engine keeps its default voice.
    }
    try {
      await _tts.setSpeechRate(engineRate(rate, defaultTargetPlatform));
    } catch (_) {
      // Keep the engine's speed.
    }
    _speaking.value = true;
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    _speaking.value = false;
    await _tts.stop();
  }
}

/// Overridden with a fake in tests.
final speakerProvider = Provider<Speaker>((ref) {
  final s = TtsSpeaker();
  ref.onDispose(s.stop);
  return s;
});
