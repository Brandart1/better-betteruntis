import 'package:better_betteruntis/app/routing_api.dart';
import 'package:better_betteruntis/core/info.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/messaging.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/data/messaging_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_info.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/infocenter/info_center_screen.dart';
import 'package:better_betteruntis/ui/infocenter/message_compose_screen.dart';
import 'package:better_betteruntis/ui/infocenter/messages_tab.dart';
import 'package:better_betteruntis/ui/infocenter/sent_messages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../classreg/class_register_test.dart' show teacherAccount;

void main() {
  late FakeInfoCenterRepository info;
  late FakeUntisApi api;
  late InMemoryAccountRepository accounts;

  setUp(() {
    info = FakeInfoCenterRepository();
    api = FakeUntisApi(latency: Duration.zero);
    accounts = InMemoryAccountRepository(
      initial: [teacherAccount(), demoAccount()],
    );
    accounts.secrets['teacher'] = 'S';
    accounts.secrets['demo'] = 'S';
  });

  Future<void> pump(WidgetTester tester, {Account? acct}) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int id(GoRouterState s) => int.parse(s.pathParameters['id']!);
    final router = GoRouter(
      initialLocation: '/info',
      routes: [
        GoRoute(
          path: '/info',
          builder: (_, _) => const InfoCenterScreen(),
          routes: [
            GoRoute(
              path: 'message/:id',
              builder: (_, s) => MessageDetailScreen(messageId: id(s)),
              routes: [
                GoRoute(
                  path: 'reply',
                  builder: (_, s) => ComposeMessageScreen(replyTo: id(s)),
                ),
              ],
            ),
            GoRoute(
              path: 'messages/new',
              builder: (_, _) => const ComposeMessageScreen(),
            ),
            GoRoute(
              path: 'messages/sent',
              builder: (_, _) => const SentMessagesScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, s) => SentMessageDetailScreen(messageId: id(s)),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          infoCenterRepositoryProvider.overrideWithValue(info),
          messagingRepositoryProvider.overrideWithValue(
            MessagingRepositoryImpl(
              api: RoutingUntisApi(real: api, demo: api),
              accounts: accounts,
            ),
          ),
          activeAccountProvider.overrideWith(
            (ref) => Stream.value(acct ?? teacherAccount()),
          ),
          nameResolverProvider.overrideWith(
            (ref) => Stream<NameResolver>.value(FakeNameResolver()),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('teacher: compose to a class of parents, sent box, revoke', (
    tester,
  ) async {
    await pump(tester);
    await tapKey(tester, 'inbox-compose');
    expect(find.text('New message'), findsOneWidget);
    expect(find.text('Parents'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('compose-copy-to-student')),
      findsOneWidget,
    );
    expect(find.text('Attachments are not supported yet.'), findsOneWidget);

    // Nothing chosen yet: refused locally.
    await tapKey(tester, 'compose-send');
    expect(find.text('Choose at least one recipient.'), findsOneWidget);
    expect(api.sendMessageCalls, isEmpty);

    await tapKey(tester, 'compose-add-recipients');
    expect(find.text('Lessons'), findsOneWidget);
    await tapKey(tester, 'recipient-group-check-gL-9b-M');
    expect(find.text('Done (1)'), findsOneWidget);
    await tapKey(tester, 'recipients-done');
    expect(
      find.byKey(const ValueKey('recipient-chip-gL-9b-M')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('compose-subject')),
      'Wandertag',
    );
    await tester.enterText(
      find.byKey(const ValueKey('compose-content')),
      'Bitte festes Schuhwerk.',
    );
    await tapKey(tester, 'compose-request-confirmation');
    await tapKey(tester, 'compose-send');

    final sent = api.sendMessageCalls.single;
    expect(sent.option, RecipientOption.parents);
    expect(sent.groups.map((g) => g.id), ['L-9b-M']);
    expect(sent.recipients, isEmpty);
    expect(sent.subject, 'Wandertag');
    expect(sent.requestConfirmation, isTrue);
    expect(sent.forbidReply, isFalse);
    expect(find.text('Message sent to 6 recipients'), findsOneWidget);
    expect(find.byType(InfoCenterScreen), findsOneWidget);

    await tapKey(tester, 'inbox-sent');
    expect(find.byKey(const ValueKey('sent-900')), findsOneWidget);
    expect(find.text('Read 0 of 6 confirmed'), findsOneWidget);
    await tapKey(tester, 'sent-801');
    expect(find.textContaining('Read confirmations (4 of 6)'), findsOneWidget);
    await tapKey(tester, 'sent-revoke');
    await tapKey(tester, 'sent-revoke-confirm');
    expect(api.revokeCalls, [801]);
    expect(find.byKey(const ValueKey('sent-revoked')), findsOneWidget);
    expect(find.byKey(const ValueKey('sent-revoke')), findsNothing);
  });

  testWidgets('teacher: pick a colleague by search', (tester) async {
    await pump(tester);
    await tapKey(tester, 'inbox-compose');
    await tapKey(tester, 'compose-option');
    await tester.tap(find.text('Teachers').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('compose-copy-to-student')), findsNothing);

    await tapKey(tester, 'compose-add-recipients');
    await tester.enterText(
      find.byKey(const ValueKey('recipients-search')),
      'Weber',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tapKey(tester, 'recipient-p13');
    await tapKey(tester, 'recipients-done');
    expect(find.byKey(const ValueKey('recipient-chip-p13')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('compose-subject')),
      'Vertretung',
    );
    await tester.enterText(
      find.byKey(const ValueKey('compose-content')),
      'Kannst du Freitag?',
    );
    await tapKey(tester, 'compose-forbid-reply');
    await tapKey(tester, 'compose-send');
    final m = api.sendMessageCalls.single;
    expect(m.option, RecipientOption.teacher);
    expect(m.recipients.single.userId, '113');
    expect(m.forbidReply, isTrue);
  });

  testWidgets('reply and read confirmation from the inbox', (tester) async {
    final d = info.inboxDetails[2]!;
    info.inboxDetails[2] = InboxMessageDetail(
      id: d.id,
      subject: d.subject,
      bodyHtml: d.bodyHtml,
      sender: d.sender,
      sentAt: d.sentAt,
      replyAllowed: true,
      confirmationRequested: true,
    );
    // A pupil may only reply.
    await pump(tester, acct: demoAccount());
    expect(find.byKey(const ValueKey('inbox-compose')), findsNothing);
    expect(find.byKey(const ValueKey('inbox-sent')), findsNothing);

    await tapKey(tester, 'inbox-2');
    await tapKey(tester, 'message-confirm-read');
    expect(api.confirmedReads.keys, [2]);
    expect(find.text('Read confirmation sent'), findsOneWidget);

    await tapKey(tester, 'message-reply');
    expect(find.text('To Anna Müller'), findsOneWidget);
    expect(find.text('Original message'), findsOneWidget);
    final subject = tester.widget<TextField>(
      find.byKey(const ValueKey('compose-subject')),
    );
    expect(subject.controller!.text, 'Re: ${d.subject}');
    await tester.enterText(
      find.byKey(const ValueKey('compose-content')),
      'Ist überwiesen.',
    );
    await tapKey(tester, 'compose-send');
    expect(api.replyCalls.single, (
      id: 2,
      subject: 'Re: ${d.subject}',
      content: 'Ist überwiesen.',
    ));
    expect(find.text('Reply sent'), findsOneWidget);
    expect(find.byType(MessageDetailScreen), findsOneWidget);
  });

  testWidgets('no reply button when the message forbids it; send errors show', (
    tester,
  ) async {
    await pump(tester);
    await tapKey(tester, 'inbox-1');
    expect(find.byKey(const ValueKey('message-reply')), findsNothing);
    expect(find.byKey(const ValueKey('message-confirm-read')), findsNothing);

    final d = info.inboxDetails[3]!;
    info.inboxDetails[3] = InboxMessageDetail(
      id: d.id,
      subject: d.subject,
      bodyHtml: d.bodyHtml,
      sender: d.sender,
      sentAt: d.sentAt,
      replyAllowed: true,
    );
    api.messageSendError = const UntisException(-1, 'Server says no');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapKey(tester, 'inbox-3');
    await tapKey(tester, 'message-reply');
    await tester.enterText(
      find.byKey(const ValueKey('compose-content')),
      'Hallo',
    );
    await tapKey(tester, 'compose-send');
    expect(find.text('Could not send: Server says no'), findsOneWidget);
    expect(find.byType(ComposeMessageScreen), findsOneWidget);
  });

  testWidgets('leaving with text asks before discarding', (tester) async {
    await pump(tester);
    await tapKey(tester, 'inbox-compose');
    await tester.enterText(
      find.byKey(const ValueKey('compose-content')),
      'Entwurf',
    );
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard message?'), findsOneWidget);
    await tapKey(tester, 'compose-discard');
    expect(find.byType(ComposeMessageScreen), findsNothing);
    expect(find.byType(InfoCenterScreen), findsOneWidget);
  });
}
