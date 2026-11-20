/// The daily notifications (Settings → Notifications): at the user's time,
/// a summary of the day's changes and tests, and reminders about tests and
/// homework a chosen number of days ahead. School and own (custom) tests and
/// homework both count.
///
/// The text is built by pure functions ([dailySummary], [dailyReminders]);
/// [RepositoryDailyPlanner] loads what they need. [ChangeChecker] decides
/// when they are shown or scheduled.
library;

import 'dart:async';

import 'change_sources.dart';
import 'info.dart';
import 'interfaces.dart';
import 'lesson_notes.dart';
import 'models.dart';
import 'notifications.dart';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _plusDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

String _subject(NameResolver names, int? id) {
  if (id == null || id == 0) return '';
  final ref = ElementRef(type: ElementType.subject, id: id, orgId: id);
  final long = names.longName(ref).trim();
  return long.isNotEmpty ? long : names.shortName(ref).trim();
}

/// "Maths · Schularbeit", "Maths (own)".
String examLabel(ExamItem e, NameResolver names) {
  final parts = <String>[];
  for (final p in [
    _subject(names, e.subjectId),
    e.custom?.title ?? '',
    e.examType,
    e.name,
  ]) {
    final t = p.trim();
    if (t.isNotEmpty && !parts.contains(t)) parts.add(t);
  }
  final label = parts.isEmpty ? 'Test' : parts.join(' · ');
  return e.custom != null ? '$label (own)' : label;
}

/// "English: p. 34, ex. 2" (first line, shortened).
String homeworkLabel(HomeworkItem h, NameResolver names) {
  final subject = [
    _subject(names, h.subjectId),
    h.custom?.title ?? '',
  ].map((t) => t.trim()).firstWhere((t) => t.isNotEmpty, orElse: () => '');
  var text = h.text.trim().split('\n').first.trim();
  if (text.length > 80) text = '${text.substring(0, 79)}…';
  final label = [subject, text].where((t) => t.isNotEmpty).join(': ');
  final shown = label.isEmpty ? 'Homework' : label;
  return h.custom != null ? '$shown (own)' : shown;
}

/// The summary of [day]: its changes (as in the change notifications, without
/// the date) and its tests. Null when the day has neither lessons nor tests
/// (weekend, holidays).
AppNotification? dailySummary(
  Account account,
  DateTime day,
  List<Period> periods,
  NameResolver names,
  List<ExamItem> exams,
) {
  final ofDay = [
    for (final p in periods)
      if (_sameDay(p.start, day)) p,
  ];
  final tests = [
    for (final e in exams)
      if (_sameDay(e.start, day)) e,
  ]..sort((a, b) => a.start.compareTo(b.start));
  if (ofDay.isEmpty && tests.isEmpty) return null;
  final changes = timetableChanges(
    ofDay,
    names,
    days: [day],
    now: DateTime(day.year, day.month, day.day),
  );
  final lines = [
    ...timetableLines(changes, withDay: false),
    for (final e in tests) 'Test ${hhmm(e.start)}: ${examLabel(e, names)}',
  ];
  final n = changes.length;
  final what = [
    if (n > 0) n == 1 ? '1 change' : '$n changes',
    if (tests.isNotEmpty)
      tests.length == 1 ? '1 test' : '${tests.length} tests',
  ];
  return AppNotification(
    id: dailySummaryId(account.id),
    title:
        '${shortDay(day)}: ${what.isEmpty ? 'no changes' : what.join(', ')}'
        ' · ${account.label}',
    body: lines.isEmpty ? 'Your timetable is as planned.' : _body(lines),
    payload: NotificationTarget.timetable(account.id, day).payload,
  );
}

/// Reminders shown on [day]: tests [NotificationSettings.examReminderDays]
/// later and homework due [NotificationSettings.homeworkReminderDays]
/// later (not done yet). Null when there is nothing.
AppNotification? dailyReminders(
  Account account,
  DateTime day,
  NotificationSettings s,
  NameResolver names, {
  required List<ExamItem> exams,
  required List<HomeworkItem> homework,
}) {
  final lines = <String>[];
  final days = <DateTime>[];
  if (s.examReminderDays > 0) {
    final on = _plusDays(day, s.examReminderDays);
    final tests = [
      for (final e in exams)
        if (_sameDay(e.start, on)) e,
    ]..sort((a, b) => a.start.compareTo(b.start));
    for (final e in tests) {
      lines.add(
        'Test ${shortDay(on)} ${hhmm(e.start)}: ${examLabel(e, names)}',
      );
    }
    if (tests.isNotEmpty) days.add(on);
  }
  if (s.homeworkReminderDays > 0) {
    final on = _plusDays(day, s.homeworkReminderDays);
    final due = [
      for (final h in homework)
        if (!h.completed && _sameDay(h.dueOn, on)) h,
    ];
    for (final h in due) {
      lines.add('Homework for ${shortDay(on)}: ${homeworkLabel(h, names)}');
    }
    if (due.isNotEmpty) days.add(on);
  }
  if (lines.isEmpty) return null;
  days.sort();
  return AppNotification(
    id: dailyRemindersId(account.id),
    title: 'Coming up · ${account.label}',
    body: _body(lines),
    payload: NotificationTarget.timetable(account.id, days.first).payload,
  );
}

String _body(List<String> lines, {int max = 8}) => [
  ...lines.take(max),
  if (lines.length > max) '+${lines.length - max} more',
].join('\n');

/// Loads the day's timetable ("My timetable", cache-first: the change check
/// refreshed it just before), the school's tests and homework and the
/// user's own ones, and builds the [DailyDigest].
class RepositoryDailyPlanner implements DailyPlanner {
  RepositoryDailyPlanner({
    required this.timetables,
    required this.info,
    required this.notes,
  });

  final TimetableRepository timetables;
  final InfoCenterRepository info;

  /// All lesson notes (lib/core/lesson_notes.dart), for own tests and
  /// homework.
  final Future<Map<String, LessonNote>> Function() notes;

  static const _timeout = Duration(seconds: 45);

  @override
  Future<DailyDigest?> digest(
    Account account,
    NotificationSettings s,
    DateTime day,
  ) async {
    final target = account.personalTarget;
    if (target == null) return null;
    final names = await timetables
        .watchNames(account)
        .first
        .timeout(const Duration(seconds: 30));
    List<Period> periods = const [];
    if (s.dailySummary) {
      final monday = _plusDays(day, -(day.weekday - 1));
      // Failure: unknown, keep what was scheduled before.
      periods = await timetables
          .week(account, target, monday)
          .timeout(_timeout);
    }
    final examDays = [
      if (s.dailySummary) 0,
      if (s.examReminderDays > 0) s.examReminderDays,
    ];
    final lessonNotes = await notes();
    var exams = <ExamItem>[];
    if (examDays.isNotEmpty) {
      final from = _plusDays(day, examDays.reduce((a, b) => a < b ? a : b));
      final to = _plusDays(day, examDays.reduce((a, b) => a > b ? a : b));
      exams = [
        ...await _load(info.exams(account, from, _plusDays(to, 1))),
        ...customExams(lessonNotes, account.id, from, to, grid: names.timeGrid),
      ];
    }
    var homework = <HomeworkItem>[];
    if (s.homeworkReminderDays > 0) {
      final on = _plusDays(day, s.homeworkReminderDays);
      homework = [
        ...await _load(info.homework(account, day, _plusDays(on, 1))),
        ...customHomework(lessonNotes, account.id, on, on),
      ];
    }
    return DailyDigest(
      summary: s.dailySummary
          ? dailySummary(account, day, periods, names, exams)
          : null,
      reminders: dailyReminders(
        account,
        day,
        s,
        names,
        exams: exams,
        homework: homework,
      ),
    );
  }

  /// The school's list, or empty when it can't be loaded (not every
  /// account may see tests or homework; own ones still count).
  Future<List<T>> _load<T>(Stream<Cached<List<T>>> stream) async {
    try {
      final last = await stream.last.timeout(_timeout);
      return last.data ?? <T>[];
    } catch (_) {
      return <T>[];
    }
  }
}
