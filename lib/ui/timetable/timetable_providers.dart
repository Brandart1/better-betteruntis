import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';

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

/// Periods of one week, cache-first via [TimetableRepository.watchWeek].
/// No automatic retry: the UI shows an error with a retry button instead.
final weekPeriodsProvider = StreamProvider.autoDispose
    .family<List<Period>, WeekRequest>(
      (ref, req) => ref
          .watch(timetableRepositoryProvider)
          .watchWeek(req.account, req.target, req.weekStart),
      retry: (_, _) => null,
    );
