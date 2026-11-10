import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/data/name_resolver_impl.dart';
import 'package:better_betteruntis/ui/settings/subject_colors_screen.dart';
import 'package:flutter_test/flutter_test.dart';

MasterElement subject(int id, String name, {bool active = true, bool display = true}) =>
    MasterElement(
      type: ElementType.subject,
      id: id,
      name: name,
      longName: name,
      active: active,
      displayAllowed: display,
    );

void main() {
  test('subjects hidden with displayAllowed:false are still offered', () {
    final names = NameResolverImpl(
      elements: [
        subject(1, 'M', display: false),
        subject(2, 'E', display: false),
        subject(3, 'OLD', active: false, display: false),
      ],
    );
    expect(colorableSubjects(names).map((e) => e.name), ['E', 'M']);
  });

  test('all subjects when none is active', () {
    final names = NameResolverImpl(
      elements: [subject(1, 'M', active: false), subject(2, 'D', active: false)],
    );
    expect(colorableSubjects(names).map((e) => e.name), ['D', 'M']);
  });
}
