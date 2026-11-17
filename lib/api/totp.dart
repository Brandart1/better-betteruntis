/// RFC 6238 TOTP as used by WebUntis (HMAC-SHA1, 30 s step, 6 digits).
library;

import 'dart:typed_data';

import 'package:otp/otp.dart';

const _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Decodes Base32 after uppercasing; characters outside the alphabet
/// (padding, spaces, dashes, ...) are skipped.
Uint8List base32Decode(String input) {
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final ch in input.toUpperCase().split('')) {
    final v = _base32Alphabet.indexOf(ch);
    if (v < 0) continue;
    buffer = ((buffer << 5) | v) & 0xFFFF;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((buffer >> bits) & 0xFF);
    }
  }
  return Uint8List.fromList(out);
}

/// Computes the 6-digit TOTP for [secret] (Base32) at [timeMillis].
/// Returns 0 when the secret is empty or decodes to no bytes.
int totp(String secret, int timeMillis) {
  // Normalise like base32Decode: uppercase, drop everything outside the
  // alphabet (spaces, dashes, padding).
  final clean = secret.toUpperCase().replaceAll(RegExp('[^A-Z2-7]'), '');
  if (base32Decode(clean).isEmpty) return 0;
  return int.parse(
    OTP.generateTOTPCodeString(
      clean,
      timeMillis,
      length: 6,
      interval: 30,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    ),
  );
}
