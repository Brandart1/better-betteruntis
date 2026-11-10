// Draws the app icon (a small timetable grid) and writes the source PNGs that
// flutter_launcher_icons turns into every platform size:
//   dart run tool/make_icon.dart && dart run flutter_launcher_icons
import 'dart:io';

import 'package:image/image.dart' as img;

const size = 1024;
const ss = 4; // supersampling factor for smooth edges

const background = 0xFF2B47B0;
const backgroundBottom = 0xFF1F3488;

/// Lesson blocks as (column, row, rowSpan, ARGB). Row 3 / column 2 is a free
/// period, a merged double lesson sits in column 1.
const blocks = <(int, int, int, int)>[
  (0, 0, 1, 0xFFFFD54F),
  (1, 0, 1, 0xFFFFFFFF),
  (2, 0, 1, 0xFF4DD0A1),
  (0, 1, 1, 0xFFFFFFFF),
  (1, 1, 2, 0xFFFF8A65),
  (2, 1, 1, 0xFFFFFFFF),
  (0, 2, 1, 0xFF8EC5FF),
  (2, 2, 1, 0xFFFFD54F),
  (0, 3, 1, 0xFF4DD0A1),
  (1, 3, 1, 0xFFFFFFFF),
];

img.Color _c(int argb) => img.ColorRgba8(
  (argb >> 16) & 0xFF,
  (argb >> 8) & 0xFF,
  argb & 0xFF,
  (argb >> 24) & 0xFF,
);

/// Grid of 3 columns x 4 rows, [scale] = share of the icon width it spans.
void _drawGrid(img.Image im, double scale) {
  final s = size * ss;
  final gridW = s * scale;
  final colGap = gridW * 0.065;
  final colW = (gridW - 2 * colGap) / 3;
  final rowH = colW * 0.68;
  final rowGap = colGap * 0.8;
  final gridH = 4 * rowH + 3 * rowGap;
  final x0 = (s - gridW) / 2;
  final y0 = (s - gridH) / 2;
  final radius = colW * 0.16;
  for (final (col, row, span, argb) in blocks) {
    final x = x0 + col * (colW + colGap);
    final y = y0 + row * (rowH + rowGap);
    final h = span * rowH + (span - 1) * rowGap;
    _roundedRect(im, x, y, x + colW, y + h, radius, _c(argb));
  }
}

/// Opaque rounded rectangle. (image 4.3's `fillRect(radius:)` zeroes the
/// alpha channel on RGBA images, so this is drawn by hand.)
void _roundedRect(
  img.Image im,
  double x1,
  double y1,
  double x2,
  double y2,
  double r,
  img.Color color,
) {
  for (var y = y1.floor(); y < y2.ceil(); y++) {
    for (var x = x1.floor(); x < x2.ceil(); x++) {
      final px = x + 0.5, py = y + 0.5;
      final cx = px < x1 + r ? x1 + r : (px > x2 - r ? x2 - r : px);
      final cy = py < y1 + r ? y1 + r : (py > y2 - r ? y2 - r : py);
      final dx = px - cx, dy = py - cy;
      if (dx * dx + dy * dy <= r * r) im.setPixel(x, y, color);
    }
  }
}

img.Image _finish(img.Image big) => img.copyResize(
  big,
  width: size,
  height: size,
  interpolation: img.Interpolation.average,
);

void main() {
  final s = size * ss;

  // Full icon (iOS, web, legacy Android): opaque background + grid.
  final full = img.Image(width: s, height: s, numChannels: 4);
  final top = _c(background), bottom = _c(backgroundBottom);
  for (var y = 0; y < s; y++) {
    final t = y / (s - 1);
    final line = img.ColorRgba8(
      (top.r + (bottom.r - top.r) * t).round(),
      (top.g + (bottom.g - top.g) * t).round(),
      (top.b + (bottom.b - top.b) * t).round(),
      255,
    );
    img.drawLine(full, x1: 0, y1: y, x2: s - 1, y2: y, color: line);
  }
  _drawGrid(full, 0.6);

  // Android adaptive foreground: transparent, grid inside the safe zone.
  final fg = img.Image(width: s, height: s, numChannels: 4);
  _drawGrid(fg, 0.43);

  Directory('assets/icon').createSync(recursive: true);
  File('assets/icon/icon.png').writeAsBytesSync(img.encodePng(_finish(full)));
  File(
    'assets/icon/foreground.png',
  ).writeAsBytesSync(img.encodePng(_finish(fg)));
  stdout.writeln('wrote assets/icon/icon.png and assets/icon/foreground.png');
}
