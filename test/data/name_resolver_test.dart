import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/data/name_resolver_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final r = NameResolverImpl(
    elements: [
      teacher(1, 'MUE'),
      teacher(2, 'OLD', active: false),
      const MasterElement(
        type: ElementType.teacher,
        id: 3,
        name: 'HID',
        longName: 'Hidden',
        displayAllowed: false,
      ),
    ],
  );
  const t = ElementType.teacher;

  test('inactive teacher still resolves', () {
    const ref = ElementRef(type: t, id: 2, orgId: 2);
    expect(r.shortName(ref), 'OLD');
    expect(r.longName(ref), 'OLD long');
  });

  test('missing id uses inline name, then ?', () {
    const ref = ElementRef(
      type: t,
      id: 99,
      orgId: 99,
      inlineName: 'INL',
      inlineLongName: 'Inline Name',
    );
    expect(r.shortName(ref), 'INL');
    expect(r.longName(ref), 'Inline Name');
    expect(r.shortName(const ElementRef(type: t, id: 99, orgId: 99)), '?');
  });

  test('removed element shows the original', () {
    const ref = ElementRef(type: t, id: 0, orgId: 1);
    expect(ref.change, ElementChange.removed);
    expect(r.shortName(ref), 'MUE');
    expect(r.shortName(ref, original: true), 'MUE');
  });

  test('substitution resolves both', () {
    const ref = ElementRef(type: t, id: 1, orgId: 2);
    expect(r.shortName(ref), 'MUE');
    expect(r.shortName(ref, original: true), 'OLD');
    expect(r.longName(ref, original: true), 'OLD long');
  });

  test('elementsOf filters only when onlyActive', () {
    expect([for (final e in r.elementsOf(t)) e.id], [1]);
    expect(r.elementsOf(t, onlyActive: false), hasLength(3));
  });

  test('time grid falls back', () {
    expect(r.timeGrid.days.keys, [1, 2, 3, 4, 5]);
  });
}
