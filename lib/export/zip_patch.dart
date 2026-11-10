/// Minimal ZIP rewriting, used to add features to the generated XLSX that the
/// excel package has no API for (frozen panes). Only what the excel package
/// writes is supported: no ZIP64, no encryption, stored or deflated entries.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Deflate, Inflate, ZipDecoder;

/// UTF-8 text of entry [name] in [zip], or null if missing / unreadable.
String? readZipText(Uint8List zip, String name) {
  try {
    final file = ZipDecoder().decodeBytes(zip).findFile(name);
    if (file == null) return null;
    return utf8.decode(file.content as List<int>);
  } catch (_) {
    return null;
  }
}

/// Returns a copy of [zip] in which every entry whose name satisfies
/// [select] is replaced by `patch(text)`. Unchanged entries are copied
/// byte-for-byte. Returns [zip] unchanged if it can't be parsed.
Uint8List patchZipText(
  Uint8List zip,
  bool Function(String name) select,
  String Function(String name, String text) patch,
) {
  try {
    return _patch(zip, select, patch);
  } catch (_) {
    return zip;
  }
}

Uint8List _patch(
  Uint8List zip,
  bool Function(String name) select,
  String Function(String name, String text) patch,
) {
  final bd = ByteData.sublistView(zip);
  var eocd = -1;
  for (var i = zip.length - 22; i >= 0 && i >= zip.length - 22 - 0xFFFF; i--) {
    if (bd.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) return zip;
  final count = bd.getUint16(eocd + 10, Endian.little);
  var cd = bd.getUint32(eocd + 16, Endian.little);

  final out = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  for (var n = 0; n < count; n++) {
    if (bd.getUint32(cd, Endian.little) != 0x02014b50) return zip;
    var method = bd.getUint16(cd + 10, Endian.little);
    final time = bd.getUint16(cd + 12, Endian.little);
    final date = bd.getUint16(cd + 14, Endian.little);
    var crc = bd.getUint32(cd + 16, Endian.little);
    var compSize = bd.getUint32(cd + 20, Endian.little);
    var size = bd.getUint32(cd + 24, Endian.little);
    final nameLen = bd.getUint16(cd + 28, Endian.little);
    final extraLen = bd.getUint16(cd + 30, Endian.little);
    final commentLen = bd.getUint16(cd + 32, Endian.little);
    final local = bd.getUint32(cd + 42, Endian.little);
    final nameBytes = zip.sublist(cd + 46, cd + 46 + nameLen);
    final name = utf8.decode(nameBytes, allowMalformed: true);
    cd += 46 + nameLen + extraLen + commentLen;

    final lNameLen = bd.getUint16(local + 26, Endian.little);
    final lExtraLen = bd.getUint16(local + 28, Endian.little);
    final dataStart = local + 30 + lNameLen + lExtraLen;
    var data = zip.sublist(dataStart, dataStart + compSize);

    if (select(name)) {
      final plain = method == 8
          ? Inflate(data).getBytes()
          : method == 0
          ? data
          : null;
      if (plain != null) {
        final patched = utf8.encode(patch(name, utf8.decode(plain)));
        data = Uint8List.fromList(Deflate(patched).getBytes());
        method = 8;
        crc = crc32(patched);
        compSize = data.length;
        size = patched.length;
      }
    }

    final offset = out.length;
    final lh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x0800, Endian.little) // UTF-8 names
      ..setUint16(8, method, Endian.little)
      ..setUint16(10, time, Endian.little)
      ..setUint16(12, date, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, compSize, Endian.little)
      ..setUint32(22, size, Endian.little)
      ..setUint16(26, nameLen, Endian.little)
      ..setUint16(28, 0, Endian.little);
    out
      ..add(lh.buffer.asUint8List())
      ..add(nameBytes)
      ..add(data);

    final ch = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint16(10, method, Endian.little)
      ..setUint16(12, time, Endian.little)
      ..setUint16(14, date, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, compSize, Endian.little)
      ..setUint32(24, size, Endian.little)
      ..setUint16(28, nameLen, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(ch.buffer.asUint8List())
      ..add(nameBytes);
  }

  final cdOffset = out.length;
  final cdBytes = central.takeBytes();
  out.add(cdBytes);
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, count, Endian.little)
    ..setUint16(10, count, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(end.buffer.asUint8List());
  return out.takeBytes();
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
