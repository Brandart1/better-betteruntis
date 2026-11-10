/// Teacher and room timetables built from class timetables.
///
/// Student accounts often may view every class timetable (`TT_VIEW:R:1:ALL`)
/// but no teacher or room timetable. The repository then fetches all class
/// weeks and uses the pure helpers here to filter, merge and discover.
library;

import 'dart:async';

import '../core/models.dart';

/// Element types whose timetable can be rebuilt from class timetables.
bool isAggregatable(ElementType t) =>
    t == ElementType.teacher || t == ElementType.room;

/// True if [p] involves [target] as current or originally planned element.
bool periodMatches(Period p, TimetableTarget target) => p.elements.any(
  (e) =>
      e.type == target.type && (e.id == target.id || e.orgId == target.id),
);

/// Filters [classWeeks] down to the periods of [target], merges duplicates
/// (the same period appears in each of its classes) and sorts by start.
List<Period> aggregateFor(
  Iterable<List<Period>> classWeeks,
  TimetableTarget target,
) {
  final byId = <int, Period>{};
  for (final week in classWeeks) {
    for (final p in week) {
      if (!periodMatches(p, target)) continue;
      final seen = byId[p.id];
      byId[p.id] = seen == null ? p : mergePeriods(seen, p);
    }
  }
  final out = byId.values.toList()
    ..sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  return out;
}

/// [a] with the union of both element lists (deduped by type + id + orgId;
/// the first occurrence wins).
Period mergePeriods(Period a, Period b) {
  final seen = <(ElementType, int, int)>{};
  final merged = <ElementRef>[
    for (final e in [...a.elements, ...b.elements])
      if (seen.add((e.type, e.id, e.orgId))) e,
  ];
  return merged.length == a.elements.length ? a : a.copyWithElements(merged);
}

/// Teachers known only by name (synthetic negative ids, see
/// `syntheticTeacherId`) found in [periods], as master elements.
Map<int, MasterElement> discoveredTeachers(Iterable<Period> periods) {
  final out = <int, MasterElement>{};
  void add(int id, String? short, String? long) {
    if (id >= 0) return;
    final s = short?.trim() ?? '';
    final l = long?.trim() ?? '';
    if (s.isEmpty && l.isEmpty) return;
    final name = s.isEmpty ? l : s;
    final longName = l.isEmpty ? name : l;
    final prev = out[id];
    // Prefer an entry that carries a real long name.
    if (prev != null && (prev.longName != prev.name || longName == name)) {
      return;
    }
    out[id] = MasterElement(
      type: ElementType.teacher,
      id: id,
      name: name,
      longName: longName,
    );
  }

  for (final p in periods) {
    for (final e in p.ofType(ElementType.teacher)) {
      add(e.id, e.inlineName, e.inlineLongName);
      if (e.orgId != e.id) add(e.orgId, e.orgInlineName, e.orgInlineLongName);
    }
  }
  return out;
}

/// Runs [task] for every item with at most [limit] running at once. Results
/// keep the order of [items]. [task] must not throw (catch inside).
Future<List<R>> runLimited<T, R>(
  List<T> items,
  int limit,
  Future<R> Function(T item) task,
) async {
  final results = List<R?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      results[i] = await task(items[i]);
    }
  }

  final n = items.length < limit ? items.length : limit;
  await Future.wait([for (var i = 0; i < n; i++) worker()]);
  return results.cast<R>();
}

/// Outcome of fetching all class weeks of one week.
class ClassScan {
  const ClassScan({
    required this.weeks,
    required this.total,
    required this.failed,
  });

  /// Periods per successfully loaded class.
  final List<List<Period>> weeks;
  final int total;

  /// Classes whose week could not be loaded (skipped).
  final int failed;
}
