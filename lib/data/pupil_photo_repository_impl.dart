import 'dart:async';
import 'dart:typed_data';

import '../core/class_register.dart';
import '../core/interfaces.dart';
import '../core/models.dart';
import '../core/pupil_photos.dart';

/// [PupilPhotoRepository] on top of [PupilPhotoApi]: photos (and "has no
/// photo") are kept in memory per account and pupil for the session, never
/// on disk. At most [maxParallel] photos load at once. A failed load (e.g.
/// offline) is not remembered, so the next screen tries again.
class PupilPhotoRepositoryImpl implements PupilPhotoRepository {
  PupilPhotoRepositoryImpl({required this.api, required this.accounts});

  final UntisApi api;
  final AccountRepository accounts;

  static const maxParallel = 4;

  final _loaded = <String, Uint8List?>{};
  final _pending = <String, Future<Uint8List?>>{};
  var _running = 0;
  final _queue = <Completer<void>>[];

  static String _key(Account a, ClassRegStudent s) => '${a.id}|${s.id}';

  @override
  Uint8List? cached(Account account, ClassRegStudent student) =>
      _loaded[_key(account, student)];

  @override
  Future<Uint8List?> photo(Account account, ClassRegStudent student) {
    final key = _key(account, student);
    if (_loaded.containsKey(key)) return Future.value(_loaded[key]);
    final Object a = api;
    if (a is! PupilPhotoApi || !hasClassRegister(account)) {
      return Future.value();
    }
    return _pending[key] ??= _load(a, account, student, key);
  }

  Future<Uint8List?> _load(
    PupilPhotoApi a,
    Account account,
    ClassRegStudent student,
    String key,
  ) async {
    if (_running >= maxParallel) {
      final turn = Completer<void>();
      _queue.add(turn);
      await turn.future; // The finishing load handed over its slot.
    } else {
      _running++;
    }
    try {
      final auth = await accounts.credentials(account.id);
      final img = await a.pupilPhoto(
        host: account.host,
        school: account.school.loginName,
        auth: auth,
        studentId: student.id,
        imageUrl: student.imageUrl,
      );
      _loaded[key] = img;
      return img;
    } catch (_) {
      return null;
    } finally {
      _pending.remove(key);
      if (_queue.isNotEmpty) {
        _queue.removeAt(0).complete();
      } else {
        _running--;
      }
    }
  }

  @override
  void clear() {
    _loaded.clear();
  }
}
