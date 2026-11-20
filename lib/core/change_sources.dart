/// The built-in [ChangeSource]s: changes in the own timetable and new inbox
/// messages. Change detection itself ([timetableChanges], [messageChanges])
/// is pure and tested on its own.
library;

import 'dart:async';

import 'info.dart';
import 'interfaces.dart';
import 'models.dart';
import 'notifications.dart';

/// The sources every check runs, in the app and in the background. New
/// kinds are added here together with a switch in [NotificationSettings].
List<ChangeSource> defaultChangeSources({
  required TimetableRepository timetables,
  required InfoCenterRepository info,
}) => [TimetableChangeSource(timetables), MessageChangeSource(info)];

// ---- Timetable ------------------------------------------------------------------

/// Today plus the next [daysAhead] school days (Saturday and Sunday are
/// skipped, today is always included).
List<DateTime> notificationDays(DateTime now, int daysAhead) {
  final today = DateTime(now.year, now.month, now.day);
  final days = [today];
  var d = today;
  while (days.length < daysAhead + 1) {
    d = DateTime(d.year, d.month, d.day + 1);
    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      continue;
    }
    days.add(d);
  }
  return days;
}

/// Whether [p] differs from the plan in a way worth a notification.
bool isNotableChange(Period p) {
  return p.isCancelled || p.isIrregular || p.substitutionText.trim().isNotEmpty;
}

/// The notable changes among [periods] on [days] (only lessons that haven't
/// ended before [now]). Keys are `yyyy-mm-dd|periodId`.
List<ChangeItem> timetableChanges(
  Iterable<Period> periods,
  NameResolver names, {
  required List<DateTime> days,
  required DateTime now,
}) {
  final wanted = {for (final d in days) ymd(d)};
  final out = <ChangeItem>[];
  final sorted = periods.toList()..sort((a, b) => a.start.compareTo(b.start));
  for (final p in sorted) {
    final day = ymd(p.start);
    if (!wanted.contains(day) || !p.end.isAfter(now)) continue;
    if (!isNotableChange(p)) continue;
    out.add(
      ChangeItem(
        key: '$day|${p.id}',
        signature: _signature(p),
        text: describeChange(p, names),
        start: p.start,
        end: p.end,
      ),
    );
  }
  return out;
}

String _signature(Period p) {
  final changed = [
    for (final e in p.elements)
      if (e.change != ElementChange.regular)
        '${e.type.code}:${e.orgId}>${e.id}',
  ]..sort();
  return [
    if (p.isCancelled) 'C',
    if (p.flags.contains(PeriodFlag.irregular)) 'I',
    changed.join(','),
    p.substitutionText.trim(),
  ].join('|');
}

/// E.g. "M cancelled", "D: teacher MUE → HUB, room R1 → R7",
/// "PH: extra lesson – Supplierung".
String describeChange(Period p, NameResolver names) {
  String nameOf(ElementRef e, {bool original = false}) {
    final n = names.shortName(e, original: original).trim();
    return n.isEmpty ? '?' : n;
  }

  final subjects = [
    for (final e in p.ofType(ElementType.subject))
      if (e.id != 0 || e.orgId != 0) nameOf(e),
  ];
  final what = subjects.isNotEmpty
      ? subjects.join('/')
      : (p.customTitle.isNotEmpty ? p.customTitle : 'Lesson');
  final note = p.substitutionText.trim();
  String withNote(String s) => note.isEmpty ? s : '$s – $note';

  if (p.isCancelled) return withNote('$what cancelled');

  final parts = <String>[];
  for (final type in const [
    ElementType.teacher,
    ElementType.room,
    ElementType.subject,
    ElementType.klasse,
  ]) {
    final label = switch (type) {
      ElementType.teacher => 'teacher',
      ElementType.room => 'room',
      ElementType.subject => 'subject',
      _ => 'class',
    };
    for (final e in p.ofType(type)) {
      switch (e.change) {
        case ElementChange.substituted:
          parts.add('$label ${nameOf(e, original: true)} → ${nameOf(e)}');
        case ElementChange.removed:
          parts.add('no $label ${nameOf(e, original: true)}');
        case ElementChange.added:
          // An added lesson lists all its elements as added; say it once.
          if (type == ElementType.teacher || type == ElementType.room) {
            parts.add('$label ${nameOf(e)}');
          }
        case ElementChange.regular:
          break;
      }
    }
  }
  final added =
      p.elements.isNotEmpty &&
      p.elements.every(
        (e) =>
            e.change == ElementChange.added ||
            e.change == ElementChange.regular,
      ) &&
      p.elements.any((e) => e.change == ElementChange.added);
  if (parts.isEmpty) return withNote('$what changed');
  if (added) return withNote('$what: extra lesson (${parts.join(', ')})');
  return withNote('$what: ${parts.join(', ')}');
}

/// Body lines for timetable changes: one per lesson, consecutive lessons
/// with the same change merged ("Tue 18.11. 08:00–09:40: M cancelled").
List<String> timetableLines(List<ChangeItem> fresh) {
  final items = [
    ...fresh,
  ]..sort((a, b) => (a.start ?? DateTime(0)).compareTo(b.start ?? DateTime(0)));
  final lines = <String>[];
  ChangeItem? first;
  DateTime? end;
  void flush() {
    final f = first;
    if (f == null) return;
    final s = f.start;
    lines.add(
      s == null
          ? f.text
          : '${shortDay(s)} ${hhmm(s)}–${hhmm(end ?? f.end ?? s)}: ${f.text}',
    );
  }

  for (final i in items) {
    final f = first;
    final sameDay =
        f?.start != null && i.start != null && ymd(f!.start!) == ymd(i.start!);
    final adjacent =
        end != null &&
        i.start != null &&
        i.start!.difference(end).inMinutes.abs() <= 20;
    if (f != null && sameDay && adjacent && f.text == i.text) {
      if (i.end != null && i.end!.isAfter(end)) end = i.end;
      continue;
    }
    flush();
    first = i;
    end = i.end;
  }
  flush();
  return lines;
}

/// Substitutions, cancellations and room changes in the account's own
/// timetable ("My timetable": the own element, or the selected child).
class TimetableChangeSource extends ChangeSource {
  const TimetableChangeSource(this.timetables);

  final TimetableRepository timetables;

  static const sourceId = 'timetable';

  @override
  String get id => sourceId;

  @override
  bool enabledIn(NotificationSettings s) => s.timetable;

  @override
  String scope(Account account, NotificationSettings s) {
    final t = account.personalTarget;
    return t == null ? '' : '${t.type.apiName}:${t.id}:${s.daysAhead}';
  }

  @override
  Future<List<ChangeItem>?> current(
    Account account,
    NotificationSettings s,
    DateTime now,
  ) async {
    final target = account.personalTarget;
    if (target == null) return null;
    final days = notificationDays(now, s.daysAhead);
    final mondays = <String, DateTime>{};
    for (final d in days) {
      final m = DateTime(d.year, d.month, d.day - (d.weekday - 1));
      mondays[ymd(m)] = m;
    }
    final periods = <Period>[];
    for (final monday in mondays.values) {
      // Any failure: unknown, so the source is skipped (no false "news"
      // once a week that couldn't be loaded comes back).
      await timetables.refresh(account, target, monday);
      periods.addAll(
        await timetables
            .watchWeek(account, target, monday)
            .first
            .timeout(const Duration(seconds: 30)),
      );
    }
    final names = await timetables
        .watchNames(account)
        .first
        .timeout(const Duration(seconds: 30));
    return timetableChanges(periods, names, days: days, now: now);
  }

  @override
  String title(int count) =>
      count == 1 ? 'Timetable change' : 'Timetable changes';

  @override
  List<String> lines(List<ChangeItem> fresh) => timetableLines(fresh);

  @override
  NotificationTarget target(Account account, List<ChangeItem> fresh) {
    final days = [
      for (final i in fresh)
        if (i.start != null) i.start!,
    ]..sort();
    final d = days.isEmpty ? DateTime.now() : days.first;
    return NotificationTarget.timetable(
      account.id,
      DateTime(d.year, d.month, d.day),
    );
  }
}

// ---- Messages -------------------------------------------------------------------

/// All inbox messages as items; read ones are only recorded (silent).
List<ChangeItem> messageChanges(Iterable<InboxMessage> inbox) => [
  for (final m in inbox)
    ChangeItem(
      key: '${m.id}',
      signature: '',
      text: [
        if (m.sender.trim().isNotEmpty) '${m.sender.trim()}: ',
        m.subject.trim().isEmpty ? '(no subject)' : m.subject.trim(),
      ].join(),
      silent: m.isRead,
    ),
];

/// New, unread messages in the REST inbox.
class MessageChangeSource extends ChangeSource {
  const MessageChangeSource(this.info);

  final InfoCenterRepository info;

  static const sourceId = 'messages';

  @override
  String get id => sourceId;

  @override
  bool enabledIn(NotificationSettings s) => s.messages;

  @override
  Future<List<ChangeItem>?> current(
    Account account,
    NotificationSettings s,
    DateTime now,
  ) async {
    if (account.anonymous) return null;
    final last = await info
        .inbox(account, force: true)
        .last
        .timeout(const Duration(seconds: 45));
    final data = last.data;
    if (last.error != null || data == null) return null;
    return messageChanges(data);
  }

  @override
  String title(int count) => count == 1 ? 'New message' : '$count new messages';

  @override
  NotificationTarget target(Account account, List<ChangeItem> fresh) =>
      NotificationTarget.inbox(account.id);
}
