import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/settings.dart';

/// [SettingsStore] backed by one JSON file (`settings.json` in the app
/// support directory). Reads once, writes are coalesced (only the latest
/// pending state is written) and atomic (temp file + rename).
class FileSettingsStore implements SettingsStore {
  FileSettingsStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  /// Creates the store and loads the file before returning, so the first
  /// frame already uses the saved settings.
  static Future<FileSettingsStore> open({
    Future<Directory> Function()? directory,
  }) async {
    final store = FileSettingsStore(directory: directory);
    await store._ensureLoaded();
    return store;
  }

  static const fileName = 'settings.json';

  final Future<Directory> Function() _directory;
  Map<String, Object?>? _values;
  Future<void>? _loading;
  Future<void>? _writing;
  bool _dirty = false;

  Future<File> _file() async => File('${(await _directory()).path}/$fileName');

  Future<void> _ensureLoaded() => _loading ??= () async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map) {
          _values = {for (final e in decoded.entries) '${e.key}': e.value};
          return;
        }
      }
    } catch (_) {
      // Corrupt or unreadable file: start empty, overwrite on next write.
    }
    _values = {};
  }();

  @override
  Object? peek(String key) => _values?[key];

  @override
  Future<Object?> read(String key) async {
    await _ensureLoaded();
    return _values![key];
  }

  @override
  Future<void> write(String key, Object? value) async {
    await _ensureLoaded();
    _values![key] = value;
    _dirty = true;
    return _writing ??= _flush();
  }

  Future<void> _flush() async {
    try {
      while (_dirty) {
        _dirty = false;
        final f = await _file();
        await f.parent.create(recursive: true);
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(jsonEncode(_values), flush: true);
        await tmp.rename(f.path);
      }
    } finally {
      _writing = null;
    }
  }
}
