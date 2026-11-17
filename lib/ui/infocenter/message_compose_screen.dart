import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/info.dart';
import '../../core/messaging.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'html_text.dart';
import 'info_common.dart';
import 'info_providers.dart';

/// What [account] may do with messages. [MessagePermissions.none] while
/// loading, on errors and without a messaging repository, so the compose
/// UI simply stays hidden.
final messagePermissionsProvider = FutureProvider.autoDispose
    .family<MessagePermissions, InfoQuery>(
      (ref, q) => ref.watch(messagingRepositoryProvider).permissions(q.account),
      retry: (_, _) => null,
    );

MessagePermissions watchMessagePermissions(WidgetRef ref, Account? a) {
  if (a == null || a.anonymous) return MessagePermissions.none;
  return ref.watch(messagePermissionsProvider(InfoQuery(a))).value ??
      MessagePermissions.none;
}

final sentMessagesProvider = FutureProvider.autoDispose
    .family<List<SentMessage>, InfoQuery>(
      (ref, q) => ref.watch(messagingRepositoryProvider).sent(q.account),
      retry: (_, _) => null,
    );

/// `/info/messages/new` (new message) and `/info/message/:id/reply`
/// ([replyTo] set: answer that inbox message).
class ComposeMessageScreen extends ConsumerStatefulWidget {
  const ComposeMessageScreen({super.key, this.replyTo});
  final int? replyTo;

  @override
  ConsumerState<ComposeMessageScreen> createState() =>
      _ComposeMessageScreenState();
}

class _ComposeMessageScreenState extends ConsumerState<ComposeMessageScreen> {
  final _subject = TextEditingController();
  final _content = TextEditingController();
  RecipientOption? _option;
  var _groups = <String, RecipientGroup>{};
  var _people = <String, MessageRecipient>{};
  var _requestConfirmation = false;
  var _forbidReply = false;
  var _copyToStudent = false;
  var _sending = false;
  var _subjectPrefilled = false;

  bool get _reply => widget.replyTo != null;

  @override
  void dispose() {
    _subject.dispose();
    _content.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _content.text.trim().isNotEmpty ||
      (!_reply &&
          (_subject.text.trim().isNotEmpty ||
              _groups.isNotEmpty ||
              _people.isNotEmpty));

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickRecipients(Account account, RecipientOption option) async {
    final picked = await Navigator.of(context).push<RecipientSelection>(
      MaterialPageRoute(
        builder: (_) => RecipientPickerScreen(
          account: account,
          option: option,
          initial: (
            groups: _groups.values.toList(),
            people: _people.values.toList(),
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _groups = {for (final g in picked.groups) g.key: g};
      _people = {for (final p in picked.people) p.key: p};
    });
  }

  Future<void> _send(Account account) async {
    final option = _option;
    final subject = _subject.text.trim();
    final content = _content.text;
    if (!_reply && (option == null || (_groups.isEmpty && _people.isEmpty))) {
      _snack('Choose at least one recipient.');
      return;
    }
    if (subject.isEmpty) {
      _snack('Enter a subject.');
      return;
    }
    if (content.trim().isEmpty) {
      _snack('Write a message.');
      return;
    }
    setState(() => _sending = true);
    final repo = ref.read(messagingRepositoryProvider);
    try {
      String done;
      if (_reply) {
        await repo.reply(
          account,
          widget.replyTo!,
          subject: subject,
          content: content,
        );
        done = 'Reply sent';
      } else {
        final perms =
            ref.read(messagePermissionsProvider(InfoQuery(account))).value ??
            MessagePermissions.none;
        final r = await repo.send(
          account,
          OutgoingMessage(
            option: option!,
            groups: _groups.values.toList(),
            recipients: _people.values.toList(),
            subject: subject,
            content: content,
            requestConfirmation:
                perms.allowRequestReadConfirmation && _requestConfirmation,
            forbidReply: perms.canForbidReplies && _forbidReply,
            copyToStudent: option == RecipientOption.parents && _copyToStudent,
          ),
        );
        done = r.recipients > 0
            ? 'Message sent to ${r.recipients} '
                  '${r.recipients == 1 ? 'recipient' : 'recipients'}'
            : 'Message sent';
      }
      ref.invalidate(sentMessagesProvider(InfoQuery(account)));
      if (!mounted) return;
      _snack(done);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _snack('Could not send: ${describeInfoError(e)}');
    }
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard message?'),
        content: const Text('What you wrote will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep writing'),
          ),
          TextButton(
            key: const ValueKey('compose-discard'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountProvider).value;
    final perms = watchMessagePermissions(ref, account);
    final options = perms.composeOptions;
    if (!_reply && _option == null && options.isNotEmpty) {
      _option = options.first;
    }
    final option = _option;

    InboxMessageDetail? original;
    if (_reply && account != null) {
      original = ref
          .watch(inboxMessageProvider((account, widget.replyTo!)))
          .value;
      if (original != null && !_subjectPrefilled) {
        _subjectPrefilled = true;
        _subject.text = replySubject(original.subject);
      }
    }

    final theme = Theme.of(context);
    final fields = <Widget>[
      if (_reply)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.reply),
          title: Text(
            original == null
                ? 'Reply'
                : 'To ${original.sender.isEmpty ? 'the sender' : original.sender}',
          ),
        )
      else ...[
        if (options.length > 1)
          DropdownButtonFormField<RecipientOption>(
            key: const ValueKey('compose-option'),
            initialValue: option,
            decoration: const InputDecoration(labelText: 'Send to'),
            items: [
              for (final o in options)
                DropdownMenuItem(value: o, child: Text(o.label)),
            ],
            onChanged: (o) => setState(() {
              if (o == _option) return;
              // Ids of one option mean nothing for another.
              _option = o;
              _groups = {};
              _people = {};
            }),
          ),
        const SizedBox(height: 8),
        if (option != null && account != null)
          _RecipientsField(
            groups: _groups.values.toList(),
            people: _people.values.toList(),
            onAdd: () => _pickRecipients(account, option),
            onRemoveGroup: (g) => setState(() => _groups.remove(g.key)),
            onRemovePerson: (p) => setState(() => _people.remove(p.key)),
          ),
      ],
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('compose-subject'),
        controller: _subject,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Subject'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('compose-content'),
        controller: _content,
        minLines: 6,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Message',
          alignLabelWithHint: true,
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      if (!_reply) ...[
        const SizedBox(height: 8),
        if (perms.allowRequestReadConfirmation)
          SwitchListTile(
            key: const ValueKey('compose-request-confirmation'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Request read confirmation'),
            value: _requestConfirmation,
            onChanged: (v) => setState(() => _requestConfirmation = v),
          ),
        if (perms.canForbidReplies)
          SwitchListTile(
            key: const ValueKey('compose-forbid-reply'),
            contentPadding: EdgeInsets.zero,
            title: const Text("Don't allow replies"),
            value: _forbidReply,
            onChanged: (v) => setState(() => _forbidReply = v),
          ),
        if (option == RecipientOption.parents)
          SwitchListTile(
            key: const ValueKey('compose-copy-to-student'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Send a copy to the pupils'),
            value: _copyToStudent,
            onChanged: (v) => setState(() => _copyToStudent = v),
          ),
      ],
      const SizedBox(height: 8),
      Text(
        'Attachments are not supported yet.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      if (original != null) ...[
        const Divider(height: 32),
        Text('Original message', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          htmlToPlainText(original.bodyHtml),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ];

    final canSend = account != null && !_sending && (_reply || option != null);
    return PopScope(
      canPop: !_dirty || _sending,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        // Navigator.pop skips this PopScope.
        if (await _confirmDiscard() && mounted) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_reply ? 'Reply' : 'New message'),
          actions: [
            if (_sending)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                key: const ValueKey('compose-send'),
                tooltip: 'Send',
                icon: const Icon(Icons.send),
                onPressed: canSend ? () => _send(account) : null,
              ),
          ],
        ),
        body: account == null
            ? const Center(child: CircularProgressIndicator())
            : !_reply && options.isEmpty
            ? const InfoEmptyState(
                icon: Icons.block,
                title: "Your school doesn't let you write messages",
              )
            : CenteredScrollView(slivers: [SliverList.list(children: fields)]),
      ),
    );
  }
}

class _RecipientsField extends StatelessWidget {
  const _RecipientsField({
    required this.groups,
    required this.people,
    required this.onAdd,
    required this.onRemoveGroup,
    required this.onRemovePerson,
  });

  final List<RecipientGroup> groups;
  final List<MessageRecipient> people;
  final VoidCallback onAdd;
  final ValueChanged<RecipientGroup> onRemoveGroup;
  final ValueChanged<MessageRecipient> onRemovePerson;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Recipients'),
      isEmpty: false,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final g in groups)
            InputChip(
              key: ValueKey('recipient-chip-${g.key}'),
              avatar: const Icon(Icons.groups_outlined, size: 18),
              label: Text(g.title),
              onDeleted: () => onRemoveGroup(g),
            ),
          for (final p in people)
            InputChip(
              key: ValueKey('recipient-chip-${p.key}'),
              label: Text(p.displayName),
              onDeleted: () => onRemovePerson(p),
            ),
          TextButton.icon(
            key: const ValueKey('compose-add-recipients'),
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_alt),
            label: Text(groups.isEmpty && people.isEmpty ? 'Choose' : 'Add'),
          ),
        ],
      ),
    );
  }
}

typedef RecipientSelection = ({
  List<RecipientGroup> groups,
  List<MessageRecipient> people,
});

/// Picks recipients of one [option]: the school's groups (own lessons,
/// class; teachers by kind) or, with a search text, the server's search.
class RecipientPickerScreen extends ConsumerStatefulWidget {
  const RecipientPickerScreen({
    super.key,
    required this.account,
    required this.option,
    required this.initial,
  });

  final Account account;
  final RecipientOption option;
  final RecipientSelection initial;

  @override
  ConsumerState<RecipientPickerScreen> createState() =>
      _RecipientPickerScreenState();
}

class _RecipientPickerScreenState extends ConsumerState<RecipientPickerScreen> {
  late final _groups = {for (final g in widget.initial.groups) g.key: g};
  late final _people = {for (final p in widget.initial.people) p.key: p};
  late Future<List<RecipientGroup>> _book;
  Future<List<MessageRecipient>>? _results;
  Timer? _debounce;
  var _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _book = ref
        .read(messagingRepositoryProvider)
        .recipients(widget.account, widget.option);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _query = q.trim();
        _results = _query.isEmpty
            ? null
            : ref
                  .read(messagingRepositoryProvider)
                  .search(widget.account, widget.option, _query);
      });
    });
  }

  void _togglePerson(MessageRecipient p) => setState(() {
    if (_people.remove(p.key) == null) _people[p.key] = p;
  });

  /// Groups with an id are picked as a whole; the others (teachers by
  /// kind) select or clear all their members.
  void _toggleGroup(RecipientGroup g) => setState(() {
    if (g.id != null) {
      if (_groups.remove(g.key) == null) _groups[g.key] = g;
      return;
    }
    final all = g.members.every((m) => _people.containsKey(m.key));
    for (final m in g.members) {
      if (all) {
        _people.remove(m.key);
      } else {
        _people[m.key] = m;
      }
    }
  });

  bool? _groupValue(RecipientGroup g) {
    if (g.id != null) return _groups.containsKey(g.key);
    if (g.members.isEmpty) return false;
    final n = g.members.where((m) => _people.containsKey(m.key)).length;
    return n == 0 ? false : (n == g.members.length ? true : null);
  }

  Widget _personTile(MessageRecipient p) => CheckboxListTile(
    key: ValueKey('recipient-${p.key}'),
    value: _people.containsKey(p.key),
    onChanged: (_) => _togglePerson(p),
    title: Text(p.displayName),
    subtitle: p.subtitle.isEmpty ? null : Text(p.subtitle),
    controlAffinity: ListTileControlAffinity.leading,
  );

  Widget _list<T>(
    Future<List<T>> future,
    List<Widget> Function(List<T>) build, {
    required String empty,
    required VoidCallback retry,
  }) => FutureBuilder<List<T>>(
    future: future,
    builder: (context, snap) {
      if (snap.hasError) {
        return InfoErrorState(
          title: 'Could not load recipients',
          error: snap.error!,
          onRetry: retry,
        );
      }
      final data = snap.data;
      if (data == null) return const Center(child: CircularProgressIndicator());
      if (data.isEmpty) {
        return InfoEmptyState(icon: Icons.person_search, title: empty);
      }
      return ListView(children: build(data));
    },
  );

  @override
  Widget build(BuildContext context) {
    final count = _groups.length + _people.length;
    final theme = Theme.of(context);
    final results = _results;
    final Widget body;
    if (results != null) {
      body = _list<MessageRecipient>(
        results,
        (list) => [for (final p in list) _personTile(p)],
        empty: 'Nobody found',
        retry: () => _onQuery(_query),
      );
    } else if (widget.option.searchOnly) {
      body = const InfoEmptyState(
        icon: Icons.person_search,
        title: 'Search for recipients by name',
      );
    } else {
      body = _list<RecipientGroup>(
        _book,
        (groups) {
          var section = '';
          return [
            for (final g in groups) ...[
              if (g.section.isNotEmpty && g.section != section) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    section = g.section,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
              ExpansionTile(
                key: ValueKey('recipient-group-${g.key}'),
                leading: Checkbox(
                  key: ValueKey('recipient-group-check-${g.key}'),
                  tristate: g.id == null,
                  value: _groupValue(g),
                  onChanged: g.id == null && g.members.isEmpty
                      ? null
                      : (_) => _toggleGroup(g),
                ),
                title: Text(g.title),
                subtitle: Text(
                  [
                    if (g.subtitle.isNotEmpty) g.subtitle,
                    '${g.members.length} ${g.members.length == 1 ? 'person' : 'people'}',
                  ].join(' · '),
                ),
                children: [for (final m in g.members) _personTile(m)],
              ),
            ],
          ];
        },
        empty: 'No recipients. Search by name.',
        retry: () => setState(_load),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.option.label),
        actions: [
          TextButton(
            key: const ValueKey('recipients-done'),
            onPressed: () => Navigator.of(context).pop<RecipientSelection>((
              groups: _groups.values.toList(),
              people: _people.values.toList(),
            )),
            child: Text(count == 0 ? 'Done' : 'Done ($count)'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const ValueKey('recipients-search'),
              autofocus: widget.option.searchOnly,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onQuery,
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
