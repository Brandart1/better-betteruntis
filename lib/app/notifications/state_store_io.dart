import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/notifications.dart';

/// [NotificationStateStore] in its own file (`notification_state.json` in
/// the app support directory), read fresh on every [load] because the
/// Android background check writes it from another isolate. Writes are
/// atomic (temp file + rename).
class FileNotificationStateStore implements NotificationStateStore {
  FileNotificationStateStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static const fileName = 'notification_state.json';

  final Future<Directory> Function() _directory;
  Future<void> _writing = Future.value();

  Future<File> _file() async => File('${(await _directory()).path}/$fileName');

  @override
  Future<Map<String, Object?>> load() async {
    await _writing;
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is Map) {
        return {for (final e in decoded.entries) '${e.key}': e.value};
      }
    } catch (_) {
      // Corrupt: start over (the next run only records a baseline).
    }
    return {};
  }

  @override
  Future<void> save(Map<String, Object?> state) {
    final json = jsonEncode(state);
    return _writing = _writing.then((_) async {
      try {
        final f = await _file();
        await f.parent.create(recursive: true);
        // Per process and store: the background isolate has its own.
        final tmp = File('${f.path}.$pid.$hashCode.tmp');
        await tmp.writeAsString(json, flush: true);
        await tmp.rename(f.path);
      } catch (_) {
        // Disk full / no access: notifications may repeat, nothing breaks.
      }
    });
  }
}
