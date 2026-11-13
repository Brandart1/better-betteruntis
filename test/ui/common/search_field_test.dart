import 'package:better_betteruntis/ui/common/search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('filled search field: typing reports, clear resets', (t) async {
    final seen = <String>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSearchField(
            fieldKey: const ValueKey('s'),
            hintText: 'Search',
            onChanged: seen.add,
          ),
        ),
      ),
    );
    final field = t.widget<TextField>(find.byKey(const ValueKey('s')));
    expect(field.decoration!.filled, isTrue);
    expect(find.byTooltip('Clear'), findsNothing);
    await t.enterText(find.byKey(const ValueKey('s')), '10a');
    await t.pump();
    expect(seen.last, '10a');
    await t.tap(find.byTooltip('Clear'));
    await t.pump();
    expect(seen.last, '');
    expect(find.text('10a'), findsNothing);
    expect(find.byTooltip('Clear'), findsNothing);
  });
}
