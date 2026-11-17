import 'dart:async';

import '../core/info.dart';
import '../core/interfaces.dart';
import '../core/messaging.dart';
import '../core/models.dart';

/// [MessagingRepository] on top of [MessagingApi]. Only the permissions are
/// cached (per account, for the session); everything else is loaded fresh.
class MessagingRepositoryImpl implements MessagingRepository {
  MessagingRepositoryImpl({required this.api, required this.accounts});

  final UntisApi api;
  final AccountRepository accounts;

  final _permissions = <String, MessagePermissions>{};

  MessagingApi get _api {
    final Object a = api;
    if (a is MessagingApi) return a;
    throw const UntisException(-1, 'Messages are not supported here.');
  }

  /// Runs [call] with [a]'s credentials; anonymous accounts have no inbox.
  Future<T> _run<T>(
    Account a,
    Future<T> Function(String host, String school, UntisCredentials auth) call,
  ) async {
    if (a.anonymous) {
      throw const UntisException(UntisException.noRight, 'No messages');
    }
    final auth = await accounts.credentials(a.id);
    try {
      return await call(a.host, a.school.loginName, auth);
    } on UntisException {
      rethrow;
    } catch (e) {
      throw UntisException(-1, '$e');
    }
  }

  @override
  Future<MessagePermissions> permissions(
    Account a, {
    bool force = false,
  }) async {
    if (a.anonymous || api is! MessagingApi) return MessagePermissions.none;
    final cached = force ? null : _permissions[a.id];
    if (cached != null) return cached;
    try {
      return _permissions[a.id] = await _run(
        a,
        (host, school, auth) =>
            _api.messagePermissions(host: host, school: school, auth: auth),
      );
    } catch (_) {
      // Older servers / no right: read-only inbox as before. Not cached, so
      // a later open tries again.
      return MessagePermissions.none;
    }
  }

  @override
  Future<List<RecipientGroup>> recipients(Account a, RecipientOption option) =>
      _run(
        a,
        (host, school, auth) => _api.messageRecipients(
          host: host,
          school: school,
          auth: auth,
          option: option,
        ),
      );

  @override
  Future<List<MessageRecipient>> search(
    Account a,
    RecipientOption option,
    String query,
  ) => _run(
    a,
    (host, school, auth) => _api.searchMessageRecipients(
      host: host,
      school: school,
      auth: auth,
      option: option,
      query: query,
    ),
  );

  @override
  Future<SendResult> send(Account a, OutgoingMessage message) async {
    if (!message.hasRecipients) {
      throw const UntisException(-1, 'Choose at least one recipient.');
    }
    if (message.content.trim().isEmpty) {
      throw const UntisException(-1, 'The message is empty.');
    }
    return _run(
      a,
      (host, school, auth) => _api.sendMessage(
        host: host,
        school: school,
        auth: auth,
        message: message,
      ),
    );
  }

  @override
  Future<void> reply(
    Account a,
    int id, {
    required String subject,
    required String content,
  }) async {
    if (content.trim().isEmpty) {
      throw const UntisException(-1, 'The message is empty.');
    }
    return _run(
      a,
      (host, school, auth) => _api.replyToMessage(
        host: host,
        school: school,
        auth: auth,
        id: id,
        subject: subject,
        content: content,
      ),
    );
  }

  @override
  Future<List<SentMessage>> sent(Account a) => _run(
    a,
    (host, school, auth) =>
        _api.sentMessages(host: host, school: school, auth: auth),
  );

  @override
  Future<InboxMessageDetail> sentMessage(Account a, int id) => _run(
    a,
    (host, school, auth) =>
        _api.sentMessage(host: host, school: school, auth: auth, id: id),
  );

  @override
  Future<List<ReadConfirmation>> readConfirmations(Account a, int id) => _run(
    a,
    (host, school, auth) =>
        _api.readConfirmations(host: host, school: school, auth: auth, id: id),
  );

  @override
  Future<void> confirmRead(Account a, int id) => _run(
    a,
    (host, school, auth) =>
        _api.confirmMessageRead(host: host, school: school, auth: auth, id: id),
  );

  @override
  Future<void> revoke(Account a, int id) => _run(
    a,
    (host, school, auth) =>
        _api.revokeMessage(host: host, school: school, auth: auth, id: id),
  );
}
