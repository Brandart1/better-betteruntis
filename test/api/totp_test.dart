import 'package:better_betteruntis/api/totp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

  test('base32 decodes RFC secret, skipping invalid chars and lowercase', () {
    expect(String.fromCharCodes(base32Decode(secret)), '12345678901234567890');
    expect(
      String.fromCharCodes(base32Decode('gezd-gnbv gy3t qojq=1890')),
      String.fromCharCodes(base32Decode('GEZDGNBVGY3TQOJQ')),
    );
  });

  // RFC 6238 Appendix B, SHA1. Values are 8 digits; we compare the last 6.
  const vectors = {
    59: 94287082,
    1111111109: 7081804,
    1111111111: 14050471,
    1234567890: 89005924,
    2000000000: 69279037,
    20000000000: 65353130,
  };
  vectors.forEach((seconds, expected) {
    test('RFC 6238 vector T=$seconds', () {
      expect(totp(secret, seconds * 1000), expected % 1000000);
    });
  });

  test('empty or invalid secret yields 0', () {
    expect(totp('', 59000), 0);
    expect(totp('!!!-189', 59000), 0);
  });
}
