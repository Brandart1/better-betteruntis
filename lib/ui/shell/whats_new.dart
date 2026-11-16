/// "What's new": a dialog with the notes of the releases since the version
/// last opened (once, at start, when an account is shown) and a screen to
/// reread the notes of the current and earlier releases.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/release_notes.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../common/markdown_text.dart';
import '../infocenter/info_common.dart' show openLink;

/// Wraps the app (below MaterialApp). As soon as accounts exist (i.e. the
/// timetable is shown, not the login screen) it compares the stored
/// [lastVersionOpenedKey] with the running release once per start and, if
/// releases were missed, shows [WhatsNewDialog] on [navigatorKey]. The
/// version is stored only after the dialog is closed.
class WhatsNewChecker extends ConsumerStatefulWidget {
  const WhatsNewChecker({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<WhatsNewChecker> createState() => _WhatsNewCheckerState();
}

class _WhatsNewCheckerState extends ConsumerState<WhatsNewChecker> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    if (!ref.read(whatsNewCheckEnabledProvider)) return;
    ref.listenManual(accountsProvider, (_, next) {
      if (_started || (next.value?.isEmpty ?? true)) return;
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
    }, fireImmediately: true);
  }

  Future<void> _check() async {
    final current = await ref.read(currentReleaseProvider.future);
    if (current == null || !mounted) return;
    final all = await ref.read(releaseNotesIndexProvider.future);
    final store = ref.read(settingsStoreProvider);
    final decision = decideWhatsNew(
      stored: await store.read(lastVersionOpenedKey),
      current: current,
      all: all,
      channel: ref.read(releaseChannelProvider),
    );
    switch (decision) {
      case WhatsNewNothing():
        return;
      case WhatsNewStoreSilently():
        await store.write(lastVersionOpenedKey, current.toString());
      case WhatsNewShow(:final notes):
        if (!mounted) return;
        // The navigator may not exist yet on the very first frame.
        var context = widget.navigatorKey.currentContext;
        for (var i = 0; context == null && i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          context = widget.navigatorKey.currentContext;
        }
        // Not shown: keep the old version so it is shown next time.
        if (context == null || !context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => WhatsNewDialog(notes: notes),
        );
        await store.write(lastVersionOpenedKey, current.toString());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The notes of the missed releases, newest first (expanded), older ones
/// collapsed.
class WhatsNewDialog extends StatelessWidget {
  const WhatsNewDialog({super.key, required this.notes});

  final List<ReleaseNote> notes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('whats-new-dialog'),
      icon: const Icon(Icons.new_releases_outlined),
      title: const Text("What's new"),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: ReleaseNotesList(notes: notes, shrinkWrap: true),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('whats-new-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// One expandable tile per release; the first is expanded.
class ReleaseNotesList extends StatelessWidget {
  const ReleaseNotesList({
    super.key,
    required this.notes,
    this.shrinkWrap = false,
  });

  final List<ReleaseNote> notes;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: shrinkWrap,
      itemCount: notes.length,
      itemBuilder: (context, i) => ExpansionTile(
        key: ValueKey('release-${notes[i].tag}'),
        initiallyExpanded: i == 0,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text('Version ${notes[i].version}'),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [_NoteBody(notes[i])],
      ),
    );
  }
}

class _NoteBody extends ConsumerWidget {
  const _NoteBody(this.note);

  final ReleaseNote note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(releaseNoteTextProvider(note.assetPath));
    return switch (text) {
      AsyncData(:final value) => MarkdownText(
        value,
        onLinkTap: (href) => openLink(context, ref, href),
      ),
      AsyncError() => const Text("Couldn't load the release notes."),
      _ => const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

/// Reread the notes anytime (from the menu): the current release and the
/// earlier ones, newest first, with the same channel rule.
class WhatsNewScreen extends ConsumerWidget {
  const WhatsNewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(releaseNotesIndexProvider);
    final current = ref.watch(currentReleaseProvider);
    final channel = ref.watch(releaseChannelProvider);
    Widget body;
    if (all is AsyncData<List<ReleaseNote>> && !current.isLoading) {
      final cur = current.value;
      final notes = [
        for (final n in all.value)
          if ((cur == null || n.version <= cur) &&
              noteVisibleIn(n.version, channel))
            n,
      ];
      body = notes.isEmpty
          ? const Center(child: Text('No release notes available.'))
          : ReleaseNotesList(notes: notes);
    } else {
      body = const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(title: const Text("What's new")),
      body: body,
    );
  }
}
