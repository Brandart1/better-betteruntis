import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colleague_lessons.dart';
import '../../core/lesson_notes.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/request_priority.dart';
import '../../core/settings.dart';

/// Key of one week of one timetable. Equality uses the account id (not the
/// Account instance) so re-emitted accounts don't resubscribe the stream.
class WeekRequest {
  const WeekRequest(this.account, this.target, this.weekStart);

  final Account account;
  final TimetableTarget target;
  final DateTime weekStart;

  @override
  bool operator ==(Object other) =>
      other is WeekRequest &&
      other.account.id == account.id &&
      other.target == target &&
      other.weekStart == weekStart;

  @override
  int get hashCode => Object.hash(account.id, target, weekStart);
}

/// A day "My timetable" should show next (set when a notification about a
/// timetable change is opened); the timetable screen jumps there and
/// clears it.
final timetableJumpProvider = NotifierProvider<TimetableJump, DateTime?>(
  TimetableJump.new,
);

class TimetableJump extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void set(DateTime? day) => state = day;
}

/// Periods of one week as loaded, cache-first via
/// [TimetableRepository.watchWeek]. No automatic retry: the UI shows an error
/// with a retry button instead.
final rawWeekPeriodsProvider = StreamProvider.autoDispose
    .family<List<Period>, WeekRequest>(
      (ref, req) => ref
          .watch(timetableRepositoryProvider)
          .watchWeek(req.account, req.target, req.weekStart),
      retry: (_, _) => null,
    );

/// A class week for [colleagueLessonsProvider]: like [rawWeekPeriodsProvider],
/// but its requests run at background priority (lib/core/request_priority.dart),
/// so the classes' timetables never hold up what the user opens.
final colleagueClassWeekProvider = StreamProvider.autoDispose
    .family<List<Period>, WeekRequest>((ref, req) {
      final repo = ref.watch(timetableRepositoryProvider);
      return inBackground(
        () => repo.watchWeek(req.account, req.target, req.weekStart),
      );
    }, retry: (_, _) => null);

/// [rawWeekPeriodsProvider] with the user's lesson notes (own exams and
/// details) applied.
final weekPeriodsProvider = Provider.autoDispose
    .family<AsyncValue<List<Period>>, WeekRequest>((ref, req) {
      final notes = ref.watch(lessonNotesProvider);
      return ref
          .watch(rawWeekPeriodsProvider(req))
          .whenData((p) => applyLessonNotes(p, req.account.id, notes));
    });

/// Whether [target] is [account]'s own timetable as a teacher (the only
/// timetable that gets colleagues' lessons, see [colleagueLessonsProvider]).
bool isOwnTeacherTimetable(Account account, TimetableTarget target) =>
    !account.anonymous &&
    account.elementType == ElementType.teacher &&
    account.elementId > 0 &&
    target == TimetableTarget(ElementType.teacher, account.elementId);

/// Teachers' own timetable: the lessons that colleagues give in the classes
/// and subjects the teacher is assigned to (see lib/core/colleague_lessons.dart),
/// to be shown faded next to the own ones. Empty for everyone else and when
/// [TimetableSettings.showColleagueLessons] is off.
///
/// Starts only once the own week is there, then loads (cache-first, like any
/// timetable) the week of each assigned class through
/// [colleagueClassWeekProvider], at background priority. A class week that
/// is still loading or fails is simply left out: this never errors and
/// never holds up the own timetable.
final colleagueLessonsProvider = Provider.autoDispose
    .family<List<Period>, WeekRequest>((ref, req) {
      if (!isOwnTeacherTimetable(req.account, req.target)) return const [];
      final enabled = ref.watch(
        timetableSettingsProvider.select((s) => s.showColleagueLessons),
      );
      if (!enabled) return const [];
      final own = ref.watch(rawWeekPeriodsProvider(req)).value;
      if (own == null) return const [];
      final me = req.account.elementId;
      final assignments = teachingAssignments(own, me);
      if (assignments.isEmpty) return const [];
      final classIds = {for (final a in assignments) a.$1}.toList()..sort();
      final seen = {for (final p in own) p.id};
      final out = <Period>[];
      for (final c in classIds) {
        final week = ref.watch(
          colleagueClassWeekProvider(
            WeekRequest(
              req.account,
              TimetableTarget(ElementType.klasse, c),
              req.weekStart,
            ),
          ),
        );
        final periods = week.hasValue ? week.value : null;
        if (periods == null) continue;
        out.addAll(colleagueLessons(periods, assignments, me, seen));
      }
      return out;
    });
