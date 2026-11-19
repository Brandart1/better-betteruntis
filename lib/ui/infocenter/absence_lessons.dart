import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';

/// The weeks of the account's own timetable (for parents: the selected
/// child's) that absences are compared with.
class AbsenceWeeks {
  AbsenceWeeks(this.account, Iterable<DateTime> mondays)
    : mondays = (mondays.toSet().toList()..sort());

  final Account account;
  final List<DateTime> mondays;

  late final String _key =
      '${account.id}|${account.activeChild?.id}|${mondays.map((m) => m.millisecondsSinceEpoch).join(',')}';

  @override
  bool operator ==(Object other) => other is AbsenceWeeks && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}

/// At most this many weeks are loaded at once.
const absenceWeeksConcurrency = 2;

/// Lessons of [AbsenceWeeks] from [TimetableRepository.week]: weeks known
/// already come from the cache, the others are loaded a few at a time. A
/// week that can't be loaded is left out (null when none could be).
final absenceLessonsProvider = FutureProvider.autoDispose
    .family<List<Period>?, AbsenceWeeks>((ref, q) async {
      final target = q.account.personalTarget;
      if (target == null || q.mondays.isEmpty) return const [];
      final repo = ref.watch(timetableRepositoryProvider);
      final out = <Period>[];
      var loaded = 0;
      var next = 0;
      Future<void> worker() async {
        while (next < q.mondays.length) {
          final m = q.mondays[next++];
          try {
            out.addAll(await repo.week(q.account, target, m));
            loaded++;
          } catch (_) {}
        }
      }

      await Future.wait([
        for (var i = 0; i < absenceWeeksConcurrency; i++) worker(),
      ]);
      return loaded == 0 ? null : out;
    });
