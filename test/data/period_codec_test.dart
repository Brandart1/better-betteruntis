import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/data/period_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Period round-trips through the cache codec', () {
    final p = Period(
      id: 1,
      lessonId: 2,
      start: DateTime(2026, 11, 9, 8, 0),
      end: DateTime(2026, 11, 9, 8, 45),
      elements: const [
        ElementRef(
          type: ElementType.teacher,
          id: 3,
          orgId: 4,
          inlineName: 'A',
          inlineLongName: 'Anna',
        ),
        ElementRef(type: ElementType.room, id: 0, orgId: 5),
      ],
      flags: const {PeriodFlag.irregular, PeriodFlag.exam},
      lessonText: 'lt',
      substitutionText: 'st',
      infoText: 'it',
      foreColor: 0xFF112233,
      backColor: 0xFF445566,
      homework: [
        Homework(
          id: 9,
          lessonId: 2,
          startDate: DateTime(2026, 11, 9),
          endDate: DateTime(2026, 11, 10),
          text: 'Read',
          remark: 'p. 3',
          completed: true,
        ),
      ],
      exam: const Exam(id: 7, type: 'T', name: 'Test', text: 'ch. 1'),
      isOnline: true,
      onlineLink: 'https://example.org',
    );
    final back = PeriodCodec.decodeList(PeriodCodec.encodeList([p])).single;
    expect(PeriodCodec.toJson(back), PeriodCodec.toJson(p));
    expect(back.start, p.start);
    expect(back.start.isUtc, isFalse);
    expect(back.elements.first.inlineLongName, 'Anna');
    expect(back.elements.last.change, ElementChange.removed);
    expect(back.flags, p.flags);
    expect(back.homework.single.completed, isTrue);
    expect(back.exam!.name, 'Test');
    expect(back.onlineLink, p.onlineLink);
  });

  test('decoding is tolerant', () {
    expect(PeriodCodec.decodeList('not json'), isEmpty);
    final p = PeriodCodec.decodeList(
      '[{"flags":["NOPE"],"elements":[{"type":"ALIEN"}]}]',
    ).single;
    expect(p.flags, {PeriodFlag.unknown});
    expect(p.elements.single.type, ElementType.unknown);
  });

  test('TimeGrid round-trips', () {
    const g = TimeGrid({
      1: [TimeUnit(label: '1', start: 480, end: 525)],
    });
    final back = PeriodCodec.decodeTimeGrid(PeriodCodec.encodeTimeGrid(g))!;
    expect(back.days[1]!.single.end, 525);
  });
}
