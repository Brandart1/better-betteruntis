/// Pupil photos in the teacher's class register ("Absences & lesson topic").
///
/// How the server delivers them is **not known yet** (docs/API.md "Pupil
/// photos (assumed)"): the API tries an image URL sent with the pupil, then
/// a few guessed endpoints, and logs what it got. Photos are personal data:
/// they are kept in memory for the session only ([PupilPhotoRepository]),
/// never on disk and never synced.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'class_register.dart';
import 'interfaces.dart';
import 'models.dart';
import 'settings.dart';

/// Optional API capability: a pupil's photo.
abstract interface class PupilPhotoApi {
  /// The photo of pupil [studentId] (image bytes), or null when the server
  /// has none / no photo source works. [imageUrl] is the image URL sent
  /// with the pupil (getPeriodData2017 `referencedStudents`), when any.
  Future<Uint8List?> pupilPhoto({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int studentId,
    String? imageUrl,
  });
}

/// Session cache of pupil photos.
abstract interface class PupilPhotoRepository {
  /// The photo of [student] in [account]'s school, or null (none, not
  /// supported, or loading failed). Never throws.
  Future<Uint8List?> photo(Account account, ClassRegStudent student);

  /// The photo if it is already loaded (null otherwise).
  Uint8List? cached(Account account, ClassRegStudent student);

  /// Forgets every loaded photo.
  void clear();
}

/// Without a real implementation (tests, unsupported API): no photos.
class NoPupilPhotos implements PupilPhotoRepository {
  const NoPupilPhotos();

  @override
  Future<Uint8List?> photo(Account account, ClassRegStudent student) async =>
      null;

  @override
  Uint8List? cached(Account account, ClassRegStudent student) => null;

  @override
  void clear() {}
}

/// Overridden in lib/data/data_providers.dart.
final pupilPhotoRepositoryProvider = Provider<PupilPhotoRepository>(
  (ref) => const NoPupilPhotos(),
);

/// Whether pupil photos are shown (default on). Stored on this device only
/// (settings key [PupilPhotosSetting.storeKey], not synced).
final showPupilPhotosProvider = NotifierProvider<PupilPhotosSetting, bool>(
  PupilPhotosSetting.new,
);

class PupilPhotosSetting extends Notifier<bool> {
  static const storeKey = 'pupilPhotos';
  bool _changed = false;

  @override
  bool build() {
    final store = ref.watch(settingsStoreProvider);
    final cached = store.peek(storeKey);
    if (cached is bool) return cached;
    unawaited(_load(store));
    return true;
  }

  Future<void> _load(SettingsStore store) async {
    try {
      final raw = await store.read(storeKey);
      if (!ref.mounted || _changed || raw is! bool) return;
      state = raw;
    } catch (_) {
      // Unreadable: keep the default.
    }
  }

  void set(bool value) {
    _changed = true;
    if (value == state) return;
    state = value;
    unawaited(
      ref.read(settingsStoreProvider).write(storeKey, value).catchError((_) {}),
    );
  }
}
