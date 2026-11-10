import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/info.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';

/// Key of one info stream. Equality uses the account id (not the instance)
/// so re-emitted accounts don't resubscribe.
class InfoQuery {
  const InfoQuery(this.account, {this.start, this.end});

  final Account account;
  final DateTime? start;
  final DateTime? end;

  @override
  bool operator ==(Object other) =>
      other is InfoQuery &&
      other.account.id == account.id &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(account.id, start, end);
}

/// Queries whose next subscription should bypass the freshness window
/// (pull-to-refresh). Consumed by the stream providers.
final _forceNextProvider = Provider<Set<(Symbol, InfoQuery)>>((ref) => {});

bool _takeForce(Ref ref, Symbol kind, InfoQuery q) =>
    ref.read(_forceNextProvider).remove((kind, q));

/// Messages of the day; [InfoQuery.start] is the day.
final messagesOfDayProvider = StreamProvider.autoDispose
    .family<Cached<List<Message>>, InfoQuery>(
      (ref, q) => ref
          .watch(infoCenterRepositoryProvider)
          .messagesOfDay(q.account, q.start!, force: _takeForce(ref, #motd, q)),
      retry: (_, _) => null,
    );

final inboxProvider = StreamProvider.autoDispose
    .family<Cached<List<InboxMessage>>, InfoQuery>(
      (ref, q) => ref
          .watch(infoCenterRepositoryProvider)
          .inbox(q.account, force: _takeForce(ref, #inbox, q)),
      retry: (_, _) => null,
    );

final homeworkProvider = StreamProvider.autoDispose
    .family<Cached<List<HomeworkItem>>, InfoQuery>(
      (ref, q) => ref
          .watch(infoCenterRepositoryProvider)
          .homework(q.account, q.start!, q.end!, force: _takeForce(ref, #homework, q)),
      retry: (_, _) => null,
    );

final examsProvider = StreamProvider.autoDispose
    .family<Cached<List<ExamItem>>, InfoQuery>(
      (ref, q) => ref
          .watch(infoCenterRepositoryProvider)
          .exams(q.account, q.start!, q.end!, force: _takeForce(ref, #exams, q)),
      retry: (_, _) => null,
    );

final absencesProvider = StreamProvider.autoDispose
    .family<Cached<List<AbsenceItem>>, InfoQuery>(
      (ref, q) => ref
          .watch(infoCenterRepositoryProvider)
          .absences(q.account, q.start!, q.end!, force: _takeForce(ref, #absences, q)),
      retry: (_, _) => null,
    );

final officeHoursProvider = StreamProvider.autoDispose
    .family<Cached<List<OfficeHourItem>>, InfoQuery>(
      (ref, q) => ref
          .watch(infoCenterRepositoryProvider)
          .officeHours(q.account, q.start!, force: _takeForce(ref, #officeHours, q)),
      retry: (_, _) => null,
    );

/// Full inbox message, keyed by (account id, message id).
final inboxMessageProvider = FutureProvider.autoDispose
    .family<InboxMessageDetail, (Account, int)>(
      (ref, k) => ref.watch(infoCenterRepositoryProvider).inboxMessage(k.$1, k.$2),
      retry: (_, _) => null,
    );

/// Pull-to-refresh: resubscribes [provider] (built from query [q]) with
/// `force: true` and completes once the refresh finished (or failed). [kind]
/// is the provider's symbol: #motd, #inbox, #homework, #exams, #absences or
/// #officeHours.
Future<void> forceRefresh<T>(
  WidgetRef ref,
  Symbol kind,
  StreamProvider<Cached<T>> provider,
  InfoQuery q,
) async {
  ref.read(_forceNextProvider).add((kind, q));
  ref.invalidate(provider);
  final done = Completer<void>();
  final sub = ref.listenManual<AsyncValue<Cached<T>>>(provider, (_, next) {
    final settled = next.hasError ||
        (!next.isLoading && next.hasValue && !next.requireValue.refreshing);
    if (settled && !done.isCompleted) done.complete();
  });
  try {
    await done.future.timeout(const Duration(seconds: 30), onTimeout: () {});
  } finally {
    sub.close();
  }
}

/// Opens a URL (attachments, links, mailto, tel). Overridable in tests.
final urlOpenerProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) => (uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  },
);

/// A tiny session-scoped value (tab, range and filter selections).
class SessionValue<T> extends Notifier<T> {
  SessionValue(this._initial);
  final T _initial;

  @override
  T build() => _initial;

  void set(T value) => state = value;
}

/// The Info center tabs.
enum InfoTab { messages, homework, exams, absences, officeHours }

final infoTabProvider = NotifierProvider<SessionValue<InfoTab>, InfoTab>(
  () => SessionValue(InfoTab.messages),
);

/// Tabs available to [a]. Rights only hide tabs when the set is known
/// (non-empty); anonymous accounts get messages of the day only.
List<InfoTab> visibleInfoTabs(Account a) {
  if (a.anonymous) return const [InfoTab.messages];
  final r = a.rights;
  bool has(String right) => r.isEmpty || r.contains(right);
  return [
    InfoTab.messages,
    InfoTab.homework,
    InfoTab.exams,
    if (has('R_MY_ABSENCES')) InfoTab.absences,
    if (has('R_OFFICEHOURS')) InfoTab.officeHours,
  ];
}

/// User-facing text for an info center error.
String describeInfoError(Object? e) {
  if (e is UntisException) {
    if (e.isTimeout) return "The server didn't respond.";
    if (e.isNetwork) return 'No connection.';
    if (e.code == UntisException.noRight) {
      return "Your school doesn't allow this for your account.";
    }
    return e.message;
  }
  return 'Something went wrong: $e';
}
