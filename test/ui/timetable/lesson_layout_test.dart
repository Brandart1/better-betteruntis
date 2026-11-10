import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/ui/timetable/lesson_layout.dart';
import 'package:flutter_test/flutter_test.dart';

Period p(int id, int lesson, int startMin, int endMin, {int teacher = 1}) {
  final d = DateTime(2026, 11, 9);
  return Period(
    id: id,
    lessonId: lesson,
    start: DateTime(d.year, d.month, d.day, 0, startMin),
    end: DateTime(d.year, d.month, d.day, 0, endMin),
    elements: [
      ElementRef(type: ElementType.teacher, id: teacher, orgId: teacher),
    ],
    flags: const {},
  );
}

void main() {
  test('merges touching periods of the same lesson', () {
    final blocks = layoutDay([p(2, 1, 515, 560), p(1, 1, 465, 510)]);
    expect(blocks, hasLength(1));
    expect(blocks.single.periods.map((e) => e.id), [1, 2]);
  });

  test('does not merge different teachers or large gaps', () {
    expect(
      layoutDay([p(1, 1, 465, 510), p(2, 1, 515, 560, teacher: 2)]),
      hasLength(2),
    );
    expect(layoutDay([p(1, 1, 465, 510), p(2, 1, 600, 645)]), hasLength(2));
  });

  test('merges parallel double lessons independently', () {
    final blocks = layoutDay([
      p(1, 1, 465, 510),
      p(2, 2, 465, 510, teacher: 2),
      p(3, 1, 515, 560),
      p(4, 2, 515, 560, teacher: 2),
    ]);
    expect(blocks, hasLength(2));
    expect(blocks.map((b) => b.columns), [2, 2]);
    expect(blocks.map((b) => b.column).toSet(), {0, 1});
  });

  test('assigns sub-columns within overlap clusters only', () {
    final blocks = layoutDay([
      p(1, 1, 480, 600),
      p(2, 2, 500, 540),
      p(3, 3, 545, 590),
      p(4, 4, 700, 745),
    ]);
    final byId = {for (final b in blocks) b.first.id: b};
    expect(byId[1]!.column, 0);
    expect(byId[2]!.column, 1);
    expect(byId[3]!.column, 1);
    expect(byId[1]!.columns, 2);
    expect(byId[4]!.columns, 1);
    expect(overlappingBlocks(blocks, byId[1]!), hasLength(3));
  });
}
