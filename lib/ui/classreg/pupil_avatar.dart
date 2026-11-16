import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/class_register.dart';
import '../../core/models.dart';
import '../../core/pupil_photos.dart';

/// Leading avatar of a pupil in the class register: the pupil's photo (or
/// initials when there is none or it can't be shown) with a small
/// present / absent badge. With photos turned off ([showPupilPhotosProvider])
/// it is the plain present / absent icon.
class PupilAvatar extends ConsumerStatefulWidget {
  const PupilAvatar({
    super.key,
    required this.account,
    required this.student,
    required this.absent,
  });

  final Account account;
  final ClassRegStudent student;
  final bool absent;

  static const radius = 20.0;

  @override
  ConsumerState<PupilAvatar> createState() => _PupilAvatarState();
}

class _PupilAvatarState extends ConsumerState<PupilAvatar> {
  Uint8List? _photo;
  bool _requested = false;

  @override
  void didUpdateWidget(PupilAvatar old) {
    super.didUpdateWidget(old);
    if (old.student.id != widget.student.id ||
        old.account.id != widget.account.id) {
      _photo = null;
      _requested = false;
    }
  }

  void _request() {
    if (_requested) return;
    _requested = true;
    final repo = ref.read(pupilPhotoRepositoryProvider);
    _photo = repo.cached(widget.account, widget.student);
    if (_photo != null) return;
    final student = widget.student.id;
    repo.photo(widget.account, widget.student).then((img) {
      if (mounted && img != null && widget.student.id == student) {
        setState(() => _photo = img);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final absent = widget.absent;
    final statusBg = absent ? cs.errorContainer : cs.secondaryContainer;
    final statusFg = absent ? cs.onErrorContainer : cs.onSecondaryContainer;
    final statusIcon = absent ? Icons.close : Icons.check;
    if (!ref.watch(showPupilPhotosProvider)) {
      return CircleAvatar(
        radius: PupilAvatar.radius,
        backgroundColor: statusBg,
        foregroundColor: statusFg,
        child: Icon(statusIcon),
      );
    }
    _request();
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: PupilAvatar.radius * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: absent ? Border.all(color: cs.error, width: 2) : null,
                ),
                child: ClipOval(
                  child: PupilPhoto(
                    key: ValueKey('pupil-photo-${widget.student.id}'),
                    student: widget.student,
                    photo: _photo,
                    dimmed: absent,
                  ),
                ),
              ),
            ),
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                key: ValueKey('pupil-status-${widget.student.id}'),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: statusBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 1.5),
                ),
                child: Icon(statusIcon, size: 12, color: statusFg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pupil's photo filling its box, or their initials (also when [photo]
/// can't be decoded).
class PupilPhoto extends StatelessWidget {
  const PupilPhoto({
    super.key,
    required this.student,
    this.photo,
    this.dimmed = false,
  });

  final ClassRegStudent student;
  final Uint8List? photo;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final img = photo;
    final fallback = PupilInitials(student: student);
    if (img == null) return fallback;
    return Image.memory(
      img,
      key: const ValueKey('pupil-photo-image'),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      opacity: dimmed ? const AlwaysStoppedAnimation(0.55) : null,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// Initials on a color picked from the pupil's id; a person icon when the
/// name has none.
class PupilInitials extends StatelessWidget {
  const PupilInitials({super.key, required this.student});

  final ClassRegStudent student;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = [
      (cs.primaryContainer, cs.onPrimaryContainer),
      (cs.secondaryContainer, cs.onSecondaryContainer),
      (cs.tertiaryContainer, cs.onTertiaryContainer),
    ];
    final (bg, fg) = palette[student.id.abs() % palette.length];
    final initials = student.initials;
    return ColoredBox(
      color: bg,
      child: LayoutBuilder(
        builder: (context, c) {
          final size = c.biggest.shortestSide;
          return Center(
            child: initials.isEmpty
                ? Icon(Icons.person, color: fg, size: size * 0.55)
                : Text(
                    initials,
                    key: const ValueKey('pupil-initials'),
                    // Fixed size: the box doesn't grow with the text size.
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: fg,
                      fontSize: size * 0.38,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          );
        },
      ),
    );
  }
}

/// The pupil's photo, large, in a dialog (long press on a pupil). Does
/// nothing when photos are turned off.
Future<void> showPupilPhotoDialog(
  BuildContext context,
  WidgetRef ref,
  Account account,
  ClassRegStudent student,
) async {
  if (!ref.read(showPupilPhotosProvider)) return;
  final repo = ref.read(pupilPhotoRepositoryProvider);
  final future = repo.photo(account, student);
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      key: const ValueKey('pupil-photo-dialog'),
      title: Text(student.displayName),
      content: FutureBuilder<Uint8List?>(
        future: future,
        initialData: repo.cached(account, student),
        builder: (context, snap) {
          final side = (MediaQuery.sizeOf(context).shortestSide * 0.7).clamp(
            120.0,
            320.0,
          );
          return SizedBox.square(
            dimension: side,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child:
                  snap.connectionState != ConnectionState.done &&
                      snap.data == null
                  ? const Center(child: CircularProgressIndicator())
                  : PupilPhoto(student: student, photo: snap.data),
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
