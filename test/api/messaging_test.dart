import 'dart:convert';
import 'dart:typed_data';

import 'package:better_betteruntis/api/messaging_parsers.dart';
import 'package:better_betteruntis/api/parsers.dart';
import 'package:better_betteruntis/api/untis_api_impl.dart';
import 'package:better_betteruntis/app/routing_api.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/core/messaging.dart';
import 'package:better_betteruntis/data/messaging_repository_impl.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../classreg/class_register_test.dart' show teacherAccount;

const host = 'demo.webuntis.com';
const schoolName = 'demo school';
const creds = UntisCredentials.user('teacher', 'JBSWY3DPEHPK3PXP');

typedef RawReq = ({
  String method,
  Uri uri,
  Map<String, dynamic> headers,
  String? contentType,
  String body,
});

/// Captures raw bodies (multipart can't be JSON-decoded) and answers token
/// requests itself.
class RawAdapter implements HttpClientAdapter {
  RawAdapter(this.handler);
  final ({int status, Object? body}) Function(RawReq r) handler;
  final requests = <RawReq>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final c in requestStream) {
        bytes.addAll(c);
      }
    }
    final body = utf8.decode(bytes);
    if (o.uri.path.endsWith('jsonrpc_intern.do')) {
      return ResponseBody.fromString(
        jsonEncode({
          'id': '1',
          'jsonrpc': '2.0',
          'result': {'token': 'jwt-1'},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    final req = (
      method: o.method,
      uri: o.uri,
      headers: o.headers,
      contentType: o.contentType ?? o.headers['content-type'] as String?,
      body: body,
    );
    requests.add(req);
    final r = handler(req);
    return ResponseBody.fromString(
      r.body == null
          ? ''
          : (r.body is String ? r.body! as String : jsonEncode(r.body)),
      r.status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The parts of a multipart body by name: (headers block, content).
Map<String, ({String headers, String content})> parts(RawReq r) {
  final boundary = RegExp(r'boundary=([^;]+)')
      .firstMatch(r.contentType!)!
      .group(1)!;
  final out = <String, ({String headers, String content})>{};
  for (final chunk in r.body.split('--$boundary')) {
    final i = chunk.indexOf('\r\n\r\n');
    if (i < 0) continue;
    final headers = chunk.substring(0, i);
    final name = RegExp('name="([^"]+)"').firstMatch(headers)?.group(1);
    if (name == null) continue;
    var content = chunk.substring(i + 4);
    if (content.endsWith('\r\n')) {
      content = content.substring(0, content.length - 2);
    }
    out[name] = (headers: headers.toLowerCase(), content: content);
  }
  return out;
}

const pupils = [
  MessageRecipient(id: 501, personId: 501, displayName: 'Lena Bauer'),
  MessageRecipient(id: 9, personId: 502, displayName: 'Jonas Fischer'),
];

void main() {
  group('parsers', () {
    test('permissions', () {
      final p = parseMessagePermissions({
        'permissions': ['PARENTS', 'TEACHER', 'REPLY', 'WHATEVER'],
        'allowRequestReadConfirmation': true,
        'canForbidReplies': false,
        'maxFileCount': 5,
        'showSentTab': true,
      });
      expect(p.options, {
        RecipientOption.parents,
        RecipientOption.teacher,
        RecipientOption.reply,
      });
      expect(p.composeOptions, [
        RecipientOption.parents,
        RecipientOption.teacher,
      ]);
      expect(p.allowRequestReadConfirmation, isTrue);
      expect(p.canForbidReplies, isFalse);
      expect(p.canReply, isTrue);

      final replyOnly = parseMessagePermissions({
        'permissions': ['REPLY'],
      });
      expect(replyOnly.canCompose, isFalse);
      expect(replyOnly.canReply, isTrue);
      expect(replyOnly.hasSentBox, isFalse);
      expect(parseMessagePermissions('junk').canReply, isFalse);
    });

    test('6.8.1 shapes: recipientOptions, groupId, users', () {
      final p = parseMessagePermissions({
        'recipientOptions': ['STUDENTS', 'PARENTS', 'CUSTOM', 'STAFF'],
        'allowRequestReadConfirmation': true,
        'canForbidReplies': true,
        'maxFileCount': 5,
        'maxFileSize': 1000,
        'recipientSearchMaxResult': 50,
        'showDraftsTab': true,
        'showSentTab': true,
      });
      expect(p.options, containsAll([RecipientOption.parents]));
      expect(p.options, hasLength(4));
      expect(p.canForbidReplies, isTrue);
      final g = parseRecipientSections({
        'persons': [
          {'id': 1, 'personId': 501, 'displayName': 'Bauer Lena'},
        ],
        'sections': [
          {
            'sectionType': 'NORMAL_LESSONS',
            'groups': [
              {
                'groupId': 'G7',
                'title': '9b M',
                'subtitle': 'Mathematics',
                'details': 'x',
                'personIds': [501],
              },
            ],
          },
        ],
      });
      expect(g.single.id, 'G7');
      expect(g.single.members.single.displayName, 'Bauer Lena');
      final users = parseMessageRecipients({
        'users': [
          {'id': 3, 'displayName': 'Huber'},
        ],
      });
      expect(users.single.displayName, 'Huber');
    });

    test('send form: request part has no filename, JSON content type', () {
      final f = UntisApiImpl.messageForm({'a': 1});
      final part = f.files.single.value;
      expect(part.filename, isNull);
      expect(part.contentType.toString(), contains('application/json'));
    });

    test('recipient sections: groups with members or personIds', () {
      final groups = parseRecipientSections({
        'sections': [
          {
            'sectionType': 'NORMAL_LESSONS',
            'groups': [
              {
                'id': 'L1',
                'title': '9b M',
                'subtitle': 'Mathematics',
                'personIds': [501, 502],
                'recipients': [],
              },
            ],
          },
          {
            'sectionType': 'CLASSTEACHER',
            'groups': [
              {
                'id': 'C1',
                'title': '9b',
                'recipients': [
                  {
                    'id': 7,
                    'personId': 501,
                    'displayName': 'Bauer Lena',
                    'className': '9b',
                  },
                  {'displayName': 'no id'},
                ],
              },
            ],
          },
        ],
        'persons': [
          {'id': 1, 'personId': 501, 'displayName': 'Bauer Lena'},
          {'id': 2, 'personId': 502, 'displayName': 'Fischer Jonas'},
        ],
      });
      expect(groups.map((g) => (g.id, g.title, g.section)), [
        ('L1', '9b M', 'Lessons'),
        ('C1', '9b', 'Class teacher'),
      ]);
      expect(groups[0].members.map((m) => m.displayName), [
        'Bauer Lena',
        'Fischer Jonas',
      ]);
      expect(groups[1].members.single.subtitle, '9b');
      expect(groups[1].members.single.personId, 501);
    });

    test('teacher groups and search results', () {
      final t = parseRecipientPersonGroups([
        {
          'type': 'CLASS_TEACHERS',
          'persons': [
            {'id': 3, 'userId': '103', 'displayName': 'Huber'},
          ],
        },
        {'type': 'OTHERS', 'persons': []},
      ]);
      expect(t.map((g) => g.title), ['Class teachers', 'Others']);
      expect(t.first.id, isNull);
      expect(t.first.members.single.userId, '103');
      expect(
        parseMessageRecipients({
          'recipients': [
            {'id': 4, 'displayName': 'X'},
          ],
        }).single.id,
        4,
      );
      expect(
        parseMessageRecipients([
          {'id': 5, 'displayName': 'Y'},
        ]).single.id,
        5,
      );
    });

    test('sent messages, confirmations, inbox detail flags', () {
      final sent = parseSentMessages({
        'sentMessages': [
          {
            'id': 1,
            'subject': 'Old',
            'sentDateTime': '2026-11-01T10:00:00',
            'recipientGroups': [
              {'title': '9b'},
            ],
          },
          {
            'id': 2,
            'subject': 'New',
            'contentPreview': 'Hi',
            'sentDateTime': '2026-11-10T10:00:00',
            'recipients': [
              {'displayName': 'Huber'},
            ],
            'isRevoked': true,
            'requestConfirmationStatus': {
              'confirmedRequestCount': 3,
              'totalRequestCount': 5,
            },
          },
          {'subject': 'no id'},
        ],
      });
      expect(sent.map((m) => m.id), [2, 1]);
      expect(sent.first.recipients, ['Huber']);
      expect(sent.first.isRevoked, isTrue);
      expect((sent.first.confirmed, sent.first.confirmationsRequested), (3, 5));
      expect(sent.last.recipients, ['9b']);

      final c = parseReadConfirmations([
        {
          'recipientId': 1,
          'recipientDisplayName': 'Bauer Lena',
          'recipientClassName': '9b',
          'readConfirmationStates': [
            {
              'userId': 9,
              'userDisplayName': 'Bauer Eva',
              'date': '2026-11-10T12:00:00',
            },
          ],
        },
        {'recipientDisplayName': 'Fischer Jonas', 'readConfirmationStates': []},
      ]);
      expect(c.map((x) => x.confirmed), [true, false]);
      expect(c.first.confirmedBy.single.at, DateTime(2026, 11, 10, 12));

      final d = parseInboxMessageDetail({
        'id': 5,
        'subject': 'S',
        'content': 'C',
        'isReplyAllowed': true,
        'messageRequestConfirmation': {'allowSendRequestConfirmation': true},
      }, 5);
      expect(d.replyAllowed, isTrue);
      expect(d.confirmationRequested, isTrue);
      final confirmed = parseInboxMessageDetail({
        'id': 5,
        'messageRequestConfirmation': {
          'allowSendRequestConfirmation': true,
          'confirmationDate': '2026-11-10T12:00:00',
        },
      }, 5);
      expect(confirmed.confirmationRequested, isFalse);
      expect(confirmed.confirmedAt, DateTime(2026, 11, 10, 12));
      expect(confirmed.replyAllowed, isFalse);

      // The official app's field name.
      expect(
        parseInbox({
          'incomeMessages': [
            {'id': 1, 'subject': 'a'},
          ],
        }).single.id,
        1,
      );
    });

    test('send payload per option', () {
      final toParents = sendMessagePayload(
        const OutgoingMessage(
          option: RecipientOption.parents,
          groups: [RecipientGroup(id: 'L1', title: '9b M')],
          recipients: pupils,
          subject: ' Ausflug ',
          content: 'Hallo\nzusammen',
          requestConfirmation: true,
          copyToStudent: true,
        ),
      );
      expect(toParents, {
        'recipientOption': 'PARENTS',
        'recipientGroupIds': ['L1'],
        'subject': 'Ausflug',
        'content': 'Hallo\nzusammen',
        'recipientPersonIds': [501, 502],
        'copyToStudent': true,
        'requestConfirmation': true,
        'forbidReply': false,
      });
      expect(sendMessagePath(RecipientOption.parents), 'view/v2/messages');
      expect(sendMessagePath(RecipientOption.students), 'view/v2/messages');

      final toTeachers = sendMessagePayload(
        const OutgoingMessage(
          option: RecipientOption.teacher,
          recipients: [
            MessageRecipient(id: 3, userId: '103', displayName: 'Huber'),
            MessageRecipient(id: 4, displayName: 'No user id'),
          ],
          subject: 'S',
          content: 'C',
          forbidReply: true,
        ),
      );
      expect(toTeachers, {
        'subject': 'S',
        'content': 'C',
        'requestConfirmation': false,
        'recipientUserIds': [103, 4],
        'forbidReply': true,
      });
      expect(
        sendMessagePath(RecipientOption.teacher),
        'view/v2/messages/users',
      );
      expect(
        sendMessagePayload(
          const OutgoingMessage(
            option: RecipientOption.staff,
            recipients: [
              MessageRecipient(id: 71, userId: '9', displayName: 'Office'),
            ],
            subject: 'S',
            content: 'C',
          ),
        )['recipientUserIds'],
        [71],
      );
      expect(sendMessagePath(RecipientOption.custom), 'view/v2/messages/users');
    });

    test('reply subject', () {
      expect(replySubject('Ausflug'), 'Re: Ausflug');
      expect(replySubject('Re: Ausflug'), 'Re: Ausflug');
      expect(replySubject('AW: x'), 'AW: x');
      expect(replySubject(''), 'Re:');
    });
  });

  group('requests', () {
    late RawAdapter adapter;
    late UntisApiImpl api;
    late ({int status, Object? body}) Function(RawReq r) handler;

    setUp(() {
      handler = (_) => (status: 200, body: const {});
      adapter = RawAdapter((r) => handler(r));
      api = UntisApiImpl(dio: Dio()..httpClientAdapter = adapter);
    });

    test('send to parents: multipart POST with a JSON request part', () async {
      handler = (_) => (
        status: 200,
        body: {'numberOfRecipients': 2, 'numberOfCCRecipients': 2},
      );
      const m = OutgoingMessage(
        option: RecipientOption.parents,
        recipients: pupils,
        subject: 'Ausflug',
        content: 'Hallo ünd tschüss',
        copyToStudent: true,
      );
      final r = await api.sendMessage(
        host: host,
        school: schoolName,
        auth: creds,
        message: m,
      );
      expect(r, (recipients: 2, ccRecipients: 2));
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(
        req.uri.toString(),
        'https://$host/WebUntis/api/rest/view/v2/messages',
      );
      expect(req.headers['Authorization'], 'Bearer jwt-1');
      expect(req.contentType, startsWith('multipart/form-data'));
      final p = parts(req);
      expect(p.keys, ['request']);
      expect(p['request']!.headers, contains('content-type: application/json'));
      expect(p['request']!.headers, isNot(contains('filename')));
      expect(jsonDecode(p['request']!.content), sendMessagePayload(m));

      final logged = api.debugLog.firstWhere(
        (e) => e.method.contains('request body'),
      );
      expect(jsonDecode(logged.json), sendMessagePayload(m));
      expect(
        api.debugLog.map((e) => e.json).join(),
        isNot(contains('JBSWY3DPEHPK3PXP')),
      );
    });

    test(
      'send to teachers goes to /users; 401 retries with a fresh form',
      () async {
        var n = 0;
        handler = (_) => n++ == 0
            ? (status: 401, body: null)
            : (status: 200, body: const {});
        await api.sendMessage(
          host: host,
          school: schoolName,
          auth: creds,
          message: const OutgoingMessage(
            option: RecipientOption.teacher,
            recipients: [
              MessageRecipient(id: 3, userId: '103', displayName: 'Huber'),
            ],
            subject: 'S',
            content: 'C',
          ),
        );
        expect(adapter.requests, hasLength(2));
        for (final req in adapter.requests) {
          expect(req.uri.path, '/WebUntis/api/rest/view/v2/messages/users');
          final body = jsonDecode(parts(req)['request']!.content) as Map;
          expect(body['recipientUserIds'], [103]);
          expect(body.containsKey('recipientOption'), isFalse);
        }
      },
    );

    test('reply, confirm, revoke, sent, permissions paths', () async {
      await api.replyToMessage(
        host: host,
        school: schoolName,
        auth: creds,
        id: 42,
        subject: 'Re: X',
        content: 'Danke',
      );
      final reply = adapter.requests.last;
      expect(reply.uri.path, '/WebUntis/api/rest/view/v2/messages/42/reply');
      expect(jsonDecode(parts(reply)['request']!.content), {
        'subject': 'Re: X',
        'content': 'Danke',
      });

      await api.confirmMessageRead(
        host: host,
        school: schoolName,
        auth: creds,
        id: 42,
      );
      expect(
        (adapter.requests.last.method, adapter.requests.last.uri.path),
        ('POST', '/WebUntis/api/rest/view/v1/messages/42/read-confirmation'),
      );
      handler = (_) => (status: 204, body: null);
      await api.revokeMessage(
        host: host,
        school: schoolName,
        auth: creds,
        id: 43,
      );
      expect(
        (adapter.requests.last.method, adapter.requests.last.uri.path),
        ('POST', '/WebUntis/api/rest/view/v1/messages/43/revoke'),
      );

      handler = (_) => (status: 200, body: {'sentMessages': []});
      await api.sentMessages(host: host, school: schoolName, auth: creds);
      expect(
        adapter.requests.last.uri.path,
        '/WebUntis/api/rest/view/v1/messages/sent',
      );
      handler = (_) => (
        status: 200,
        body: {
          'permissions': ['REPLY'],
        },
      );
      final p = await api.messagePermissions(
        host: host,
        school: schoolName,
        auth: creds,
      );
      expect(p.canReply, isTrue);
      expect(
        adapter.requests.last.uri.path,
        '/WebUntis/api/rest/view/v1/messages/permissions',
      );
      expect(adapter.requests.last.headers['Authorization'], 'Bearer jwt-1');
    });

    test('recipients: lists, search, staff filter', () async {
      handler = (_) => (status: 200, body: {'sections': []});
      await api.messageRecipients(
        host: host,
        school: schoolName,
        auth: creds,
        option: RecipientOption.students,
      );
      expect(
        adapter.requests.last.uri.path,
        '/WebUntis/api/rest/view/v1/messages/recipients/STUDENTS',
      );
      handler = (_) => (status: 200, body: []);
      await api.messageRecipients(
        host: host,
        school: schoolName,
        auth: creds,
        option: RecipientOption.teacher,
      );
      expect(
        adapter.requests.last.uri.path,
        '/WebUntis/api/rest/view/v1/messages/recipients/static/persons',
      );
      await api.searchMessageRecipients(
        host: host,
        school: schoolName,
        auth: creds,
        option: RecipientOption.parents,
        query: 'Bauer L',
      );
      expect(
        adapter.requests.last.uri.path,
        '/WebUntis/api/rest/view/v1/messages/recipients/PARENTS/search',
      );
      expect(
        adapter.requests.last.uri.queryParameters['searchText'],
        'Bauer L',
      );

      final filters = [
        {'type': 'ROLE', 'subFilterName': 'x', 'items': [], 'selected': false},
      ];
      handler = (r) => r.method == 'GET'
          ? (status: 200, body: {'filters': filters})
          : (
              status: 200,
              body: {
                'recipients': [
                  {'id': 71, 'displayName': 'Sekretariat'},
                ],
              },
            );
      final found = await api.searchMessageRecipients(
        host: host,
        school: schoolName,
        auth: creds,
        option: RecipientOption.staff,
        query: 'Sekr',
      );
      expect(found.single.id, 71);
      final post = adapter.requests.last;
      expect(
        post.uri.path,
        '/WebUntis/api/rest/view/v2/messages/recipients/STAFF/filter',
      );
      expect(jsonDecode(post.body), {'filters': filters, 'searchText': 'Sekr'});
    });

    test('server errors carry the message', () async {
      handler = (_) => (
        status: 400,
        body: {
          'errorCode': 'VALIDATION_ERROR',
          'errorMessage': 'Subject missing',
        },
      );
      await expectLater(
        api.replyToMessage(
          host: host,
          school: schoolName,
          auth: creds,
          id: 1,
          subject: '',
          content: 'x',
        ),
        throwsA(
          isA<UntisException>().having(
            (e) => e.message,
            'message',
            'Subject missing',
          ),
        ),
      );
    });
  });

  group('demo and repository', () {
    late FakeUntisApi api;
    late InMemoryAccountRepository accounts;
    late MessagingRepositoryImpl repo;

    setUp(() {
      api = FakeUntisApi(latency: Duration.zero);
      accounts = InMemoryAccountRepository(
        initial: [teacherAccount(), demoAccount()],
      );
      accounts.secrets['teacher'] = 'S';
      accounts.secrets['demo'] = 'S';
      repo = MessagingRepositoryImpl(
        api: RoutingUntisApi(real: api, demo: api),
        accounts: accounts,
      );
    });

    test('teacher may write, a pupil only reply', () async {
      final t = await repo.permissions(teacherAccount());
      expect(t.canCompose, isTrue);
      expect(t.composeOptions.first, RecipientOption.parents);
      final p = await repo.permissions(demoAccount());
      expect(p.canCompose, isFalse);
      expect(p.canReply, isTrue);
    });

    test('send lands in the sent box; revoke marks it', () async {
      final a = teacherAccount();
      final groups = await repo.recipients(a, RecipientOption.parents);
      final r = await repo.send(
        a,
        OutgoingMessage(
          option: RecipientOption.parents,
          groups: [groups.first],
          subject: 'Ausflug',
          content: 'Hallo',
          requestConfirmation: true,
        ),
      );
      expect(r.recipients, 6);
      expect(api.sendMessageCalls.single.subject, 'Ausflug');
      final sent = await repo.sent(a);
      expect(sent.first.subject, 'Ausflug');
      expect(sent.first.confirmationsRequested, 6);
      await repo.revoke(a, sent.first.id);
      expect((await repo.sentMessage(a, sent.first.id)).isRevoked, isTrue);
      expect(api.revokeCalls, [sent.first.id]);
    });

    test('search, reply, confirm; empty messages are refused', () async {
      final a = teacherAccount();
      expect(
        (await repo.search(
          a,
          RecipientOption.staff,
          'sekr',
        )).single.displayName,
        'Sekretariat',
      );
      expect(
        (await repo.search(a, RecipientOption.teacher, 'weber')).single.userId,
        '113',
      );
      await repo.reply(a, 1, subject: 'Re: Wandertag', content: 'Danke!');
      expect(api.replyCalls.single, (
        id: 1,
        subject: 'Re: Wandertag',
        content: 'Danke!',
      ));
      await repo.confirmRead(a, 3);
      expect(api.confirmedReads.keys, [3]);
      final detail = await api.inboxMessage(
        host: a.host,
        school: '',
        auth: creds,
        id: 3,
      );
      expect(detail.confirmationRequested, isFalse);
      expect(detail.confirmedAt, isNotNull);
      expect(
        () => repo.send(
          a,
          const OutgoingMessage(
            option: RecipientOption.parents,
            subject: 'x',
            content: 'y',
          ),
        ),
        throwsA(isA<UntisException>()),
      );
      expect(
        () => repo.reply(a, 1, subject: 'x', content: ' '),
        throwsA(isA<UntisException>()),
      );
    });
  });
}
