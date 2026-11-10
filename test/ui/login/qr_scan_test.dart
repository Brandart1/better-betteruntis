import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  late ValueChanged<String> feed;
  Widget scanner(ValueChanged<String> onCode) {
    feed = onCode;
    return const ColoredBox(color: Colors.black);
  }

  testWidgets('invalid code shows a snackbar', (tester) async {
    final h = Harness();
    await h.pump(tester, initial: '/login/qr', qrScanner: scanner);
    feed('https://example.com');
    await tester.pumpAndSettle();
    expect(
      find.textContaining("That's not a WebUntis login code"),
      findsOneWidget,
    );
    expect(h.api.loginCalls, isEmpty);
  });

  testWidgets('code without host looks up the school and logs in', (
    tester,
  ) async {
    final h = Harness();
    await h.pump(tester, initial: '/login/qr', qrScanner: scanner);
    feed(
      'untis://setschool?school=humboldt-koeln&user=lea&key=KEY123'
      '&skipAppSecret=true',
    );
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(h.api.searchCalls, ['humboldt-koeln']);
    final a = h.repo.accounts.single;
    expect(a.school.host, 'ajax.webuntis.com');
    expect(a.username, 'lea');
  });

  testWidgets('code with host keeps the host', (tester) async {
    final h = Harness();
    await h.pump(tester, initial: '/login/qr', qrScanner: scanner);
    feed('untis://setschool?school=custom&user=lea&key=K&url=my.host.de');
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(h.repo.accounts.single.school.host, 'my.host.de');
  });

  testWidgets('wrong key shows error and stays', (tester) async {
    final h = Harness();
    await h.pump(tester, initial: '/login/qr', qrScanner: scanner);
    feed('untis://setschool?school=x&user=lea&key=wrong&url=my.host.de');
    await tester.pumpAndSettle();
    expect(find.textContaining("don't match"), findsOneWidget);
    expect(h.repo.accounts, isEmpty);
  });
}
