import 'package:better_betteruntis/ui/login/qr_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseUntisQr', () {
    test('parses a standard WebUntis code', () {
      final qr = parseUntisQr(
        'untis://setschool?url=mese.webuntis.com&school=gym-test'
        '&user=max.muster&key=ABCDEF123456',
      );
      expect(
        qr,
        const QrLogin(
          school: 'gym-test',
          user: 'max.muster',
          key: 'ABCDEF123456',
          host: 'mese.webuntis.com',
        ),
      );
    });

    test('takes the host from apiUrl and parses our extras', () {
      final qr = parseUntisQr(
        'untis://setschool?school=gym-test&user=u&key=k'
        '&apiUrl=https%3A%2F%2Fmy.server.de%3A8443%2FWebUntis%2Fjsonrpc_intern.do'
        '&skipAppSecret=true',
      )!;
      expect(qr.host, 'my.server.de:8443');
      expect(qr.skipAppSecret, isTrue);
      expect(qr.anonymous, isFalse);
    });

    test('url wins over apiUrl; strips scheme and path', () {
      final qr = parseUntisQr(
        'untis://setschool?school=s&user=u&key=k'
        '&url=https://a.webuntis.com/WebUntis/&apiUrl=b.example.com',
      )!;
      expect(qr.host, 'a.webuntis.com');
    });

    test('host is null when missing', () {
      expect(
        parseUntisQr('untis://setschool?school=s&user=u&key=k')!.host,
        isNull,
      );
    });

    test('anonymous codes need no user or key', () {
      final qr = parseUntisQr('untis://setschool?school=s&anonymous=1')!;
      expect(qr.anonymous, isTrue);
      expect(qr.user, '');
    });

    test('rejects missing params', () {
      expect(parseUntisQr('untis://setschool?user=u&key=k'), isNull);
      expect(parseUntisQr('untis://setschool?school=s&user=u'), isNull);
      expect(parseUntisQr('untis://setschool?school=s&key=k'), isNull);
      expect(parseUntisQr('untis://setschool?school=&user=u&key=k'), isNull);
    });

    test('rejects junk', () {
      expect(parseUntisQr(''), isNull);
      expect(parseUntisQr('hello world'), isNull);
      expect(
        parseUntisQr('https://example.com/?school=s&user=u&key=k'),
        isNull,
      );
      expect(parseUntisQr('untis://other?school=s&user=u&key=k'), isNull);
      expect(
        parseUntisQr('untis://setschool?school=%E0%A4%A&user=u&key=k'),
        isNull,
      );
      expect(parseUntisQr('::::'), isNull);
    });

    test('tolerates whitespace and case', () {
      final qr = parseUntisQr('  UNTIS://SetSchool?School=s&User=u&Key=k \n');
      expect(qr?.school, 's');
    });
  });

  test('normalizeHost', () {
    expect(
      normalizeHost(' https://x.webuntis.com/WebUntis '),
      'x.webuntis.com',
    );
    expect(normalizeHost('x.webuntis.com'), 'x.webuntis.com');
    expect(normalizeHost(''), isNull);
    expect(normalizeHost(null), isNull);
  });
}
