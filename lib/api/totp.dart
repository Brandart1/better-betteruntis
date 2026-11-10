/// RFC 6238 TOTP as used by WebUntis (HMAC-SHA1, 30 s step, 6 digits).
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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
  final key = base32Decode(secret);
  if (key.isEmpty) return 0;
  final counter = timeMillis ~/ 30000;
  final msg = ByteData(8)..setInt64(0, counter, Endian.big);
  final hash = Hmac(sha1, key).convert(msg.buffer.asUint8List()).bytes;
  final offset = hash[hash.length - 1] & 0x0F;
  final binary =
      ((hash[offset] & 0x7F) << 24) |
      ((hash[offset + 1] & 0xFF) << 16) |
      ((hash[offset + 2] & 0xFF) << 8) |
      (hash[offset + 3] & 0xFF);
  return binary % 1000000;
}
