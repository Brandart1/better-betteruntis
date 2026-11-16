/// Generated placeholder "photos" for the demo class register: a head and
/// shoulders silhouette on a color picked from the pupil id, as an
/// uncompressed 24-bit BMP (decodable everywhere, no zlib needed on the web).
library;

import 'dart:typed_data';

/// Background colors (RGB) of the placeholders.
const _colors = [
  [0x5C, 0x6B, 0xC0],
  [0x26, 0xA6, 0x9A],
  [0xEF, 0x6C, 0x00],
  [0x8E, 0x24, 0xAA],
  [0x43, 0xA0, 0x47],
  [0xD8, 0x1B, 0x60],
];

/// A [size] x [size] placeholder portrait for pupil [seed] (BMP bytes).
Uint8List placeholderPortrait(int seed, {int size = 96}) {
  final bg = _colors[seed.abs() % _colors.length];
  final fg = [for (final c in bg) c + (255 - c) * 3 ~/ 5];
  final rowBytes = (size * 3 + 3) & ~3;
  final pixels = rowBytes * size;
  final out = ByteData(54 + pixels);
  // BITMAPFILEHEADER
  out
    ..setUint8(0, 0x42)
    ..setUint8(1, 0x4D)
    ..setUint32(2, 54 + pixels, Endian.little)
    ..setUint32(10, 54, Endian.little)
    // BITMAPINFOHEADER
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, size, Endian.little)
    ..setInt32(22, size, Endian.little) // bottom-up rows
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 24, Endian.little)
    ..setUint32(34, pixels, Endian.little);
  final c = size / 2;
  final headY = size * 0.38, headR = size * 0.2;
  final bodyY = size * 1.05, bodyR = size * 0.42;
  for (var row = 0; row < size; row++) {
    final y = size - 1 - row; // BMP rows go bottom-up
    for (var x = 0; x < size; x++) {
      final dxh = x - c, dyh = y - headY, dyb = y - bodyY;
      final inHead = dxh * dxh + dyh * dyh <= headR * headR;
      final inBody = dxh * dxh + dyb * dyb <= bodyR * bodyR;
      final px = inHead || inBody ? fg : bg;
      final o = 54 + row * rowBytes + x * 3;
      out
        ..setUint8(o, px[2]) // BGR
        ..setUint8(o + 1, px[1])
        ..setUint8(o + 2, px[0]);
    }
  }
  return out.buffer.asUint8List();
}
