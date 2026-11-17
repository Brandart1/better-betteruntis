import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/info.dart';
import '../../core/messaging.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../timetable/timetable_utils.dart';
import 'html_text.dart';
import 'info_common.dart';
import 'info_providers.dart';
import 'message_compose_screen.dart';

final sentMessageProvider = FutureProvider.autoDispose
    .family<InboxMessageDetail, (Account, int)>(
      (ref, k) =>
          ref.watch(messagingRepositoryProvider).sentMessage(k.$1, k.$2),
      retry: (_, _) => null,
    );

final readConfirmationsProvider = FutureProvider.autoDispose
    .family<List<ReadConfirmation>, (Account, int)>(
      (ref, k) =>
          ref.watch(messagingRepositoryProvider).readConfirmations(k.$1, k.$2),
      retry: (_, _) => null,
    );

/// `/info/messages/sent`: messages the user sent.
class SentMessagesScreen extends ConsumerWidget {
  const SentMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider).value;
    final perms = watchMessagePermissions(ref, account);
    Widget body;
    if (account == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final p = sentMessagesProvider(InfoQuery(account));
      final now = DateTime.now();
      body = switch (ref.watch(p)) {
        AsyncValue(value: final list?) => RefreshIndicator(
          onRefresh: () => ref.refresh(p.future),
          child: list.isEmpty
              ? const CenteredScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: InfoEmptyState(
                        icon: Icons.outbox_outlined,
                        title: 'No sent messages',
                      ),
                    ),
                  ],
                )
              : CenteredScrollView(
                  slivers: [
                    SliverList.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 56),
                      itemBuilder: (context, i) =>
                          SentMessageTile(message: list[i], now: now),
                    ),
                  ],
                ),
        ),
        AsyncValue(error: final e?) => InfoErrorState(
          title: 'Could not load sent messages',
          error: e,
          onRetry: () => ref.invalidate(p),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Sent')),
      body: body,
      floatingActionButton: perms.canCompose
          ? FloatingActionButton.extended(
              key: const ValueKey('sent-compose'),
              onPressed: () => context.push('/info/messages/new'),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('New message'),
            )
          : null,
    );
  }
}

class SentMessageTile extends StatelessWidget {
  const SentMessageTile({super.key, required this.message, required this.now});
  final SentMessage message;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final theme = Theme.of(context);
    final to = m.recipients.isEmpty
        ? (m.numberOfRecipients > 0
              ? '${m.numberOfRecipients} recipients'
              : 'Unknown recipients')
        : m.recipients.join(', ');
    return ListTile(
      key: ValueKey('sent-${m.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.tertiaryContainer,
        child: Icon(
          m.isRevoked ? Icons.undo : Icons.outbox_outlined,
          color: theme.colorScheme.onTertiaryContainer,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text('To $to', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text(
            formatRelativeDate(context, m.sentAt, now),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.subject.isEmpty ? '(No subject)' : m.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (m.isRevoked || m.confirmationsRequested > 0)
            Text(
              [
                if (m.isRevoked) 'Revoked',
                if (m.confirmationsRequested > 0)
                  'Read ${m.confirmed} of ${m.confirmationsRequested} confirmed',
              ].join(' · '),
              style: theme.textTheme.labelSmall,
            ),
        ],
      ),
      onTap: () => context.push('/info/messages/sent/${m.id}'),
    );
  }
}

/// `/info/messages/sent/:id`: one sent message, its read confirmations and
/// revoking it.
class SentMessageDetailScreen extends ConsumerWidget {
  const SentMessageDetailScreen({super.key, required this.messageId});
  final int messageId;

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    Account account,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke message?'),
        content: const Text(
          'Recipients will no longer be able to read it. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('sent-revoke-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(messagingRepositoryProvider).revoke(account, messageId);
      ref.invalidate(sentMessageProvider((account, messageId)));
      ref.invalidate(sentMessagesProvider(InfoQuery(account)));
      messenger.showSnackBar(const SnackBar(content: Text('Message revoked')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not revoke: ${describeInfoError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider).value;
    final theme = Theme.of(context);
    Widget body;
    InboxMessageDetail? loaded;
    if (account == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final p = sentMessageProvider((account, messageId));
      final confirmations =
          ref.watch(readConfirmationsProvider((account, messageId))).value ??
          const <ReadConfirmation>[];
      body = switch (ref.watch(p)) {
        AsyncValue(value: final d?) => CenteredScrollView(
          slivers: [
            SliverList.list(
              children: [
                SelectableText(
                  d.subject.isEmpty ? '(No subject)' : d.subject,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  d.recipients.isEmpty
                      ? 'Sent'
                      : 'To ${d.recipients.join(', ')}',
                  style: theme.textTheme.titleSmall,
                ),
                if (d.sentAt != null)
                  Text(
                    dateFormat(
                      context,
                      'EEE, d MMM yyyy, HH:mm',
                    ).format(d.sentAt!),
                    style: theme.textTheme.bodySmall,
                  ),
                if (d.isRevoked)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: InfoChip(
                        'Revoked',
                        key: ValueKey('sent-revoked'),
                        icon: Icons.undo,
                      ),
                    ),
                  ),
                const Divider(height: 32),
                HtmlBody(
                  d.bodyHtml,
                  style: theme.textTheme.bodyLarge,
                  onLinkTap: (href) => openLink(context, ref, href),
                ),
                if (confirmations.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  InfoSectionHeader(
                    'Read confirmations '
                    '(${confirmations.where((c) => c.confirmed).length} of '
                    '${confirmations.length})',
                  ),
                  for (final c in confirmations)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        c.confirmed
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: c.confirmed ? theme.colorScheme.primary : null,
                        semanticLabel: c.confirmed
                            ? 'Confirmed'
                            : 'Not confirmed',
                      ),
                      title: Text(
                        c.className.isEmpty
                            ? c.name
                            : '${c.name} (${c.className})',
                      ),
                      subtitle: c.confirmed
                          ? Text(
                              c.confirmedBy
                                  .map(
                                    (x) => x.at == null
                                        ? x.name
                                        : '${x.name}, ${dateFormat(context, 'd MMM, HH:mm').format(x.at!)}',
                                  )
                                  .join('; '),
                            )
                          : null,
                    ),
                ],
              ],
            ),
          ],
        ),
        AsyncValue(error: final e?) => InfoErrorState(
          title: 'Could not load the message',
          error: e,
          onRetry: () => ref.invalidate(p),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
      loaded = ref.watch(p).value;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sent message'),
        actions: [
          if (account != null && loaded != null && !loaded.isRevoked)
            IconButton(
              key: const ValueKey('sent-revoke'),
              tooltip: 'Revoke',
              icon: const Icon(Icons.undo),
              onPressed: () => _revoke(context, ref, account),
            ),
        ],
      ),
      body: body,
    );
  }
}
