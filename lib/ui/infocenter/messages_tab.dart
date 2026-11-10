import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/info.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../timetable/timetable_utils.dart';
import 'html_text.dart';
import 'info_common.dart';
import 'info_providers.dart';

/// Day shown in the "Today" section (session-scoped offset from today).
final motdDayOffsetProvider = NotifierProvider<SessionValue<int>, int>(
  () => SessionValue(0),
);

/// Messages of the day (with day stepping) and, for non-anonymous accounts,
/// the inbox.
class MessagesTab extends ConsumerWidget {
  const MessagesTab({super.key, required this.account});
  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final offset = ref.watch(motdDayOffsetProvider);
    final day = addDays(dateOnly(now), offset);
    final motdQ = InfoQuery(account, start: day);
    final inboxQ = InfoQuery(account);
    final motdP = messagesOfDayProvider(motdQ);
    final inboxP = inboxProvider(inboxQ);
    final motd = ref.watch(motdP);
    final showInbox = !account.anonymous;
    final inbox = showInbox ? ref.watch(inboxP) : null;

    Future<void> refresh() => Future.wait([
      forceRefresh(ref, #motd, motdP, motdQ),
      if (showInbox) forceRefresh(ref, #inbox, inboxP, inboxQ),
    ]);

    final motdStatus = InfoStatus.of(motd);
    final inboxStatus = inbox == null ? null : InfoStatus.of(inbox);
    final dayLabel = formatDay(context, day, now);

    return InfoFrame(
      statuses: [motdStatus, ?inboxStatus],
      onRefresh: refresh,
      slivers: [
        SliverToBoxAdapter(
          child: InfoSectionHeader(
            offset == 0 ? 'Today' : dayLabel,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (offset != 0)
                  TextButton(
                    onPressed: () => ref.read(motdDayOffsetProvider.notifier).set(0),
                    child: const Text('Today'),
                  ),
                IconButton(
                  tooltip: 'Previous day',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () =>
                      ref.read(motdDayOffsetProvider.notifier).set(offset - 1),
                ),
                IconButton(
                  tooltip: 'Next day',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () =>
                      ref.read(motdDayOffsetProvider.notifier).set(offset + 1),
                ),
              ],
            ),
          ),
        ),
        ..._section<List<Message>>(
          context,
          value: motd,
          errorText: 'Could not load messages of the day',
          onRetry: () => forceRefresh(ref, #motd, motdP, motdQ),
          empty: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Text(
              offset == 0 ? 'No messages today' : 'No messages on this day',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          build: (list) => [
            SliverList.list(children: [for (final m in list) MessageOfDayCard(message: m)]),
          ],
        ),
        if (inbox != null) ...[
          const SliverToBoxAdapter(child: InfoSectionHeader('Inbox')),
          ..._section<List<InboxMessage>>(
            context,
            value: inbox,
            errorText: 'Could not load the inbox',
            onRetry: () => forceRefresh(ref, #inbox, inboxP, inboxQ),
            empty: const InfoEmptyState(
              icon: Icons.inbox_outlined,
              title: 'Your inbox is empty',
            ),
            build: (list) {
              final sorted = [...list]
                ..sort((a, b) => (b.sentAt ?? DateTime(0)).compareTo(a.sentAt ?? DateTime(0)));
              return [
                SliverList.separated(
                  itemCount: sorted.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
                  itemBuilder: (context, i) => InboxTile(message: sorted[i], now: now),
                ),
              ];
            },
          ),
        ],
      ],
    );
  }

  /// Inline loading / error / empty / content slivers of one section.
  List<Widget> _section<T extends List<Object?>>(
    BuildContext context, {
    required AsyncValue<Cached<T>> value,
    required String errorText,
    required VoidCallback onRetry,
    required Widget empty,
    required List<Widget> Function(T data) build,
  }) {
    final status = InfoStatus.of(value);
    final data = value.value?.data;
    if (data == null) {
      if (status.failed) {
        return [
          SliverToBoxAdapter(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
              title: Text(errorText),
              subtitle: Text(describeInfoError(status.error)),
              trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
            ),
          ),
        ];
      }
      return const [SliverToBoxAdapter(child: InfoSkeleton(count: 2, shrinkWrap: true))];
    }
    if (data.isEmpty) return [SliverToBoxAdapter(child: empty)];
    return build(data);
  }
}

/// Expandable card for one message of the day.
class MessageOfDayCard extends ConsumerStatefulWidget {
  const MessageOfDayCard({super.key, required this.message});
  final Message message;

  @override
  ConsumerState<MessageOfDayCard> createState() => _MessageOfDayCardState();
}

class _MessageOfDayCardState extends ConsumerState<MessageOfDayCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final theme = Theme.of(context);
    final preview = htmlToPlainText(m.bodyHtml).replaceAll('\n', ' ');
    return Card.filled(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      m.subject.isEmpty ? 'Message' : m.subject,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (m.attachments.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.attach_file, size: 18),
                    ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (!_expanded)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: HtmlBody(
                    m.bodyHtml,
                    onLinkTap: (href) => openLink(context, ref, href),
                  ),
                ),
                AttachmentList(m.attachments),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class InboxTile extends StatelessWidget {
  const InboxTile({super.key, required this.message, required this.now});
  final InboxMessage message;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final theme = Theme.of(context);
    final unread = !m.isRead;
    final weight = unread ? FontWeight.bold : null;
    return ListTile(
      key: ValueKey('inbox-${m.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: SizedBox(
        width: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Text(
                m.sender.isEmpty ? '?' : m.sender.characters.first.toUpperCase(),
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
            if (unread)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  key: const ValueKey('unread-dot'),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.surface, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              m.sender.isEmpty ? 'Unknown sender' : m.sender,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: weight),
            ),
          ),
          if (m.hasAttachments)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.attach_file, size: 16, semanticLabel: 'Has attachments'),
            ),
          Text(
            formatRelativeDate(context, m.sentAt, now),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: weight,
              color: unread ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
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
            style: TextStyle(
              fontWeight: weight,
              color: unread ? theme.colorScheme.onSurface : null,
            ),
          ),
          if (m.preview.isNotEmpty)
            Text(m.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
      onTap: () => context.push('/info/message/${m.id}'),
    );
  }
}

/// `/info/message/:id`: full inbox message.
class MessageDetailScreen extends ConsumerWidget {
  const MessageDetailScreen({super.key, required this.messageId});
  final int messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider).value;
    final theme = Theme.of(context);
    Widget body;
    if (account == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final p = inboxMessageProvider((account, messageId));
      final detail = ref.watch(p);
      body = switch (detail) {
        AsyncValue(value: final d?) => CenteredScrollView(
          slivers: [
            SliverList.list(
              children: [
                SelectableText(
                  d.subject.isEmpty ? '(No subject)' : d.subject,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.sender.isEmpty ? 'Unknown sender' : d.sender,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (d.sentAt != null)
                      Text(
                        dateFormat(context, 'EEE, d MMM yyyy, HH:mm').format(d.sentAt!),
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
                const Divider(height: 32),
                HtmlBody(
                  d.bodyHtml,
                  style: theme.textTheme.bodyLarge,
                  onLinkTap: (href) => openLink(context, ref, href),
                ),
                if (d.attachments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  InfoSectionHeader('Attachments (${d.attachments.length})'),
                  AttachmentList(d.attachments, dense: false),
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
    }
    return Scaffold(appBar: AppBar(title: const Text('Message')), body: body);
  }
}
