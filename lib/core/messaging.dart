/// Writing Untis messages ("Mitteilungen"): new messages, replies, the sent
/// box, read confirmations and revoking. Reading the inbox stays in
/// lib/core/info.dart ([InfoCenterApi.inbox]).
///
/// Calls (from the decompiled official app, not yet seen with a real
/// account; docs/API.md "Messages"): `GET view/v1/messages/permissions`
/// decides what the account may do; recipients come from
/// `view/v1/messages/recipients/...`; sending is a multipart POST with a
/// JSON part `request` to `view/v2/messages` (parents / pupils) or
/// `view/v2/messages/users` (teachers / staff / custom). Attachments and
/// drafts are not supported (yet).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'info.dart';
import 'interfaces.dart';
import 'models.dart';

/// Who a new message goes to (`SendMessageTypes`, also the entries of
/// `permissions[]`). [reply] only means "may reply".
enum RecipientOption {
  parents('PARENTS', 'Parents'),
  students('STUDENTS', 'Pupils'),
  teacher('TEACHER', 'Teachers'),
  staff('STAFF', 'Staff'),
  custom('CUSTOM', 'Others'),
  reply('REPLY', 'Reply');

  const RecipientOption(this.apiName, this.label);
  final String apiName;
  final String label;

  /// Sent to `view/v2/messages/users` with user ids and no option.
  bool get byUserId => this == teacher || this == staff || this == custom;

  /// Recipients are picked by search only (the official app's filter
  /// screen); there is no browsable list.
  bool get searchOnly => this == staff || this == custom;

  static RecipientOption? parse(Object? v) {
    final s = '$v'.trim().toUpperCase();
    for (final o in values) {
      if (o.apiName == s) return o;
    }
    return null;
  }
}

/// `GET view/v1/messages/permissions`.
class MessagePermissions {
  const MessagePermissions({
    this.options = const {},
    this.allowRequestReadConfirmation = false,
    this.canForbidReplies = false,
    this.showSentTab = false,
  });

  /// Nothing allowed (also used when the call fails).
  static const none = MessagePermissions();

  final Set<RecipientOption> options;
  final bool allowRequestReadConfirmation;
  final bool canForbidReplies;
  final bool showSentTab;

  /// Recipient options for a new message, in menu order.
  List<RecipientOption> get composeOptions => [
    for (final o in RecipientOption.values)
      if (o != RecipientOption.reply && options.contains(o)) o,
  ];

  bool get canCompose => composeOptions.isNotEmpty;

  /// Replies need the REPLY permission or any send option (a teacher who
  /// may write may also answer); the message itself must allow it too.
  bool get canReply => options.contains(RecipientOption.reply) || canCompose;

  /// The sent box: the server's flag, or anyone who may write.
  bool get hasSentBox => showSentTab || canCompose;
}

/// One person or group that can receive a message (`Recipient`).
class MessageRecipient {
  const MessageRecipient({
    required this.id,
    required this.displayName,
    this.personId,
    this.userId,
    this.subtitle = '',
  });

  final int id;
  final int? personId;

  /// `userId` (a string in the API; numeric for teachers).
  final String? userId;
  final String displayName;

  /// Class name or the server's subtitle.
  final String subtitle;

  /// Stable key for selection sets.
  String get key => 'p$id';

  @override
  bool operator ==(Object other) =>
      other is MessageRecipient && other.id == id && other.userId == userId;

  @override
  int get hashCode => Object.hash(id, userId);
}

/// A list of recipients under a heading: a class / lesson for parents and
/// pupils (selectable as a whole when [id] is set), or "Class teachers",
/// "Teachers", … for teachers.
class RecipientGroup {
  const RecipientGroup({
    required this.title,
    this.id,
    this.subtitle = '',
    this.section = '',
    this.members = const [],
  });

  /// `groupId` sent as `recipientGroupIds`; null = not selectable as a whole.
  final String? id;
  final String title;
  final String subtitle;

  /// Section heading, e.g. "Lessons" / "Substitutions" / "Class teacher".
  final String section;
  final List<MessageRecipient> members;

  String get key => 'g${id ?? title}';
}

/// What a new message is sent to and with which options.
class OutgoingMessage {
  const OutgoingMessage({
    required this.option,
    required this.subject,
    required this.content,
    this.groups = const [],
    this.recipients = const [],
    this.requestConfirmation = false,
    this.forbidReply = false,
    this.copyToStudent = false,
  });

  final RecipientOption option;
  final List<RecipientGroup> groups;
  final List<MessageRecipient> recipients;
  final String subject;

  /// Plain text (the official app sends the EditText as is).
  final String content;
  final bool requestConfirmation;
  final bool forbidReply;

  /// Only for [RecipientOption.parents].
  final bool copyToStudent;

  bool get hasRecipients => groups.isNotEmpty || recipients.isNotEmpty;
}

/// Answer of a send: how many got it.
typedef SendResult = ({int recipients, int ccRecipients});

/// A message in the sent box.
class SentMessage {
  const SentMessage({
    required this.id,
    required this.subject,
    required this.preview,
    required this.recipients,
    required this.sentAt,
    this.numberOfRecipients = 0,
    this.isRevoked = false,
    this.hasAttachments = false,
    this.confirmed = 0,
    this.confirmationsRequested = 0,
  });

  final int id;
  final String subject;
  final String preview;

  /// Display names of recipients / groups ('' entries dropped).
  final List<String> recipients;
  final DateTime? sentAt;
  final int numberOfRecipients;
  final bool isRevoked;
  final bool hasAttachments;

  /// `requestConfirmationStatus`: confirmed of requested (0/0 = none asked).
  final int confirmed;
  final int confirmationsRequested;
}

/// One recipient's read confirmation (`request-confirmation-status`).
class ReadConfirmation {
  const ReadConfirmation({
    required this.name,
    this.className = '',
    this.confirmedBy = const [],
  });

  final String name;
  final String className;

  /// Who confirmed (the pupil or a parent) and when.
  final List<({String name, DateTime? at})> confirmedBy;

  bool get confirmed => confirmedBy.isNotEmpty;
}

abstract interface class MessagingApi {
  Future<MessagePermissions> messagePermissions({
    required String host,
    required String school,
    required UntisCredentials auth,
  });

  /// Browsable recipients of [option] (empty for search-only options).
  Future<List<RecipientGroup>> messageRecipients({
    required String host,
    required String school,
    required UntisCredentials auth,
    required RecipientOption option,
  });

  Future<List<MessageRecipient>> searchMessageRecipients({
    required String host,
    required String school,
    required UntisCredentials auth,
    required RecipientOption option,
    required String query,
  });

  Future<SendResult> sendMessage({
    required String host,
    required String school,
    required UntisCredentials auth,
    required OutgoingMessage message,
  });

  Future<void> replyToMessage({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int id,
    required String subject,
    required String content,
  });

  Future<List<SentMessage>> sentMessages({
    required String host,
    required String school,
    required UntisCredentials auth,
  });

  Future<InboxMessageDetail> sentMessage({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int id,
  });

  Future<List<ReadConfirmation>> readConfirmations({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int id,
  });

  /// Confirms having read inbox message [id].
  Future<void> confirmMessageRead({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int id,
  });

  /// Revokes sent message [id] (recipients no longer see it).
  Future<void> revokeMessage({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int id,
  });
}

/// [MessagingApi] per account. Permissions are cached for the session; all
/// methods throw [UntisException].
abstract interface class MessagingRepository {
  /// [MessagePermissions.none] for anonymous accounts and when the school
  /// doesn't answer (never throws).
  Future<MessagePermissions> permissions(Account a, {bool force = false});
  Future<List<RecipientGroup>> recipients(Account a, RecipientOption option);
  Future<List<MessageRecipient>> search(
    Account a,
    RecipientOption option,
    String query,
  );
  Future<SendResult> send(Account a, OutgoingMessage message);
  Future<void> reply(
    Account a,
    int id, {
    required String subject,
    required String content,
  });
  Future<List<SentMessage>> sent(Account a);
  Future<InboxMessageDetail> sentMessage(Account a, int id);
  Future<List<ReadConfirmation>> readConfirmations(Account a, int id);
  Future<void> confirmRead(Account a, int id);
  Future<void> revoke(Account a, int id);
}

final messagingRepositoryProvider = Provider<MessagingRepository>(
  (ref) => throw UnimplementedError('override messagingRepositoryProvider'),
);

/// "Re: " + [subject] unless it already is a reply.
String replySubject(String subject) {
  final s = subject.trim();
  if (RegExp(r'^(re|aw|antw)\s*:', caseSensitive: false).hasMatch(s)) return s;
  return s.isEmpty ? 'Re:' : 'Re: $s';
}
