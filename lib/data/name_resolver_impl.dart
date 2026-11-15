/// [NameResolver] over ALL master-data entries of one account.
library;

import '../core/interfaces.dart';
import '../core/models.dart';

class NameResolverImpl implements NameResolver {
  NameResolverImpl({
    required Iterable<MasterElement> elements,
    this.holidays = const [],
    this.schoolYears = const [],
    TimeGrid? timeGrid,
  }) : timeGrid = (timeGrid == null || timeGrid.days.isEmpty)
           ? TimeGrid.fallback()
           : timeGrid,
       _elements = {for (final e in elements) (e.type, e.id): e};

  final Map<(ElementType, int), MasterElement> _elements;

  @override
  final List<Holiday> holidays;

  @override
  final List<SchoolYear> schoolYears;

  @override
  final TimeGrid timeGrid;

  static const placeholder = '?';

  @override
  MasterElement? element(ElementType type, int id) => _elements[(type, id)];

  @override
  List<MasterElement> elementsOf(ElementType type, {bool onlyActive = true}) {
    final list = [
      for (final e in _elements.values)
        if (e.type == type && (!onlyActive || (e.active && e.displayAllowed)))
          e,
    ];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  String shortName(ElementRef ref, {bool original = false}) =>
      _resolve(ref, original, (e) => e.name, [ref.inlineName], [ref.orgInlineName]);

  @override
  String longName(ElementRef ref, {bool original = false}) => _resolve(
    ref,
    original,
    (e) => e.longName.isNotEmpty ? e.longName : e.name,
    [ref.inlineLongName, ref.inlineName],
    [ref.orgInlineLongName, ref.orgInlineName],
  );

  String _resolve(
    ElementRef ref,
    bool original,
    String Function(MasterElement) pick,
    List<String?> inline,
    List<String?> orgInline,
  ) {
    // A removed element (id 0) is displayed by its original.
    final useOrg = original || (ref.id == 0 && ref.orgId != 0);
    final id = useOrg ? ref.orgId : ref.id;
    final e = id == 0 ? null : element(ref.type, id);
    if (e != null) {
      final n = pick(e);
      if (n.trim().isNotEmpty) return n;
    }
    if (useOrg) {
      for (final n in orgInline) {
        if (n != null && n.trim().isNotEmpty) return n;
      }
    }
    // Inline names describe the current element (or the original when it was
    // removed). For the original of a substitution they would name the wrong
    // element, so they are skipped there.
    final inlineDescribesId = !useOrg || ref.id == 0 || ref.id == ref.orgId;
    if (inlineDescribesId) {
      for (final n in inline) {
        if (n != null && n.trim().isNotEmpty) return n;
      }
    }
    return placeholder;
  }
}
