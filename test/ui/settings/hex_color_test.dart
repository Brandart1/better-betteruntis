import 'package:better_betteruntis/ui/settings/color_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseHexColor accepts #RGB, #RRGGBB, #AARRGGBB, with or without #', () {
    expect(parseHexColor('#3F6FD8'), 0xFF3F6FD8);
    expect(parseHexColor('3f6fd8'), 0xFF3F6FD8);
    expect(parseHexColor('#abc'), 0xFFAABBCC);
    expect(parseHexColor('#803F6FD8'), 0x803F6FD8);
    expect(parseHexColor(' #3F6FD8 '), 0xFF3F6FD8);
  });

  test('parseHexColor rejects junk', () {
    for (final s in ['', '#', '#12', '#12345', '#1234567', 'zzzzzz', '#3F6FD8FF00']) {
      expect(parseHexColor(s), isNull, reason: s);
    }
  });

  test('formatHexColor round-trips and hides opaque alpha', () {
    expect(formatHexColor(0xFF3F6FD8), '#3F6FD8');
    expect(formatHexColor(0x803F6FD8), '#803F6FD8');
    expect(parseHexColor(formatHexColor(0xFF00000A)), 0xFF00000A);
  });

  testWidgets('typing a hex code reports the color; invalid shows an error', (tester) async {
    int? got;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: HexColorField(value: 0xFF000000, onChanged: (v) => got = v)),
    ));
    await tester.enterText(find.byType(TextField), '#FF8800');
    await tester.pump();
    expect(got, 0xFFFF8800);

    await tester.enterText(find.byType(TextField), '#FF88');
    await tester.pump();
    expect(find.textContaining('Use #RGB'), findsOneWidget);
    expect(got, 0xFFFF8800);
  });

  testWidgets('field follows external changes when not focused', (tester) async {
    Widget build(int v) => MaterialApp(
      home: Scaffold(body: HexColorField(value: v, onChanged: (_) {})),
    );
    await tester.pumpWidget(build(0xFF112233));
    expect(find.text('#112233'), findsOneWidget);
    await tester.pumpWidget(build(0xFF445566));
    expect(find.text('#445566'), findsOneWidget);
  });
}
