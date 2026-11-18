/// Parsers and request bodies for writing messages (lib/core/messaging.dart).
/// Shapes from the decompiled official app; tolerant because no real answer
/// has been seen yet.
library;

import '../core/messaging.dart';
import 'parsers.dart';

Map<String, Object?> _map(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry('$k', val)) : const {};

Iterable<Map<String, Object?>> _maps(Object? v) =>
    (v is List ? v : const []).whereType<Map>().map(_map);

int? _int(Object? v) => switch (v) {
  int i => i,
  num n => n.toInt(),
  String s => int.tryParse(s.trim()),
  _ => null,
};

String _str(Object? v) => switch (v) {
  String s => s.trim(),
  num n => n.toString(),
  _ => '',
};

String? _nonBlank(Object? v) {
  final s = _str(v);
  return s.isEmpty ? null : s;
}

bool _bool(Object? v) =>
    v == true || (v is String && v.toLowerCase() == 'true');

String _first(Map<String, Object?> j, List<String> keys) {
  for (final k in keys) {
    final s = _nonBlank(j[k]);
    if (s != null) return s;
  }
  return '';
}

/// `MessagePermissionsResponse`. Unknown options are ignored.
MessagePermissions parseMessagePermissions(Object? raw) {
  final j = _map(raw);
  final list = j['permissions'];
  return MessagePermissions(
    options: {
      for (final p in list is List ? list : const []) ?RecipientOption.parse(p),
    },
    allowRequestReadConfirmation: _bool(j['allowRequestReadConfirmation']),
    canForbidReplies: _bool(j['canForbidReplies']),
    showSentTab: _bool(j['showSentTab']),
  );
}

/// One `Recipient`; null without any id.
MessageRecipient? parseMessageRecipient(Object? raw) {
  final r = _map(raw);
  final id = _int(r['id']) ?? _int(r['personId']) ?? _int(r['userId']);
  if (id == null) return null;
  final name = _first(r, const ['displayName', 'name']);
  return MessageRecipient(
    id: id,
    personId: _int(r['personId']),
    userId: _nonBlank(r['userId']),
    displayName: name.isEmpty ? '#$id' : name,
    subtitle: _first(r, const ['className', 'subtitle']),
  );
}

List<MessageRecipient> parseMessageRecipients(Object? raw) {
  final j = _map(raw);
  final list = raw is List ? raw : (j['recipients'] ?? j['persons']);
  return [
    for (final r in list is List ? list : const []) ?parseMessageRecipient(r),
  ];
}

const _sectionTitles = {
  'NORMAL_LESSONS': 'Lessons',
  'SUBSTITUTIONS': 'Substitutions',
  'CLASSTEACHER': 'Class teacher',
};

/// `RecipientSectionsResponse` (PARENTS / STUDENTS): every group of every
/// section, members from the group's `recipients` or, failing that, its
/// `personIds` looked up in the top-level `persons`.
List<RecipientGroup> parseRecipientSections(Object? raw) {
  final j = _map(raw);
  final persons = <int, MessageRecipient>{};
  for (final p in _maps(j['persons'])) {
    final r = parseMessageRecipient(p);
    if (r != null) persons[r.personId ?? r.id] = r;
  }
  final out = <RecipientGroup>[];
  for (final s in _maps(j['sections'])) {
    final type = _str(s['sectionType']).toUpperCase();
    final section = _sectionTitles[type] ?? '';
    for (final g in _maps(s['groups'])) {
      var members = [
        for (final r in _maps(g['recipients'])) ?parseMessageRecipient(r),
      ];
      if (members.isEmpty) {
        final ids = g['personIds'];
        members = [
          for (final id in ids is List ? ids : const []) ?persons[_int(id)],
        ];
      }
      final title = _first(g, const ['title', 'name']);
      out.add(
        RecipientGroup(
          id: _nonBlank(g['id']),
          title: title.isEmpty ? 'Group' : title,
          subtitle: _first(g, const ['subtitle', 'details']),
          section: section,
          members: members,
        ),
      );
    }
  }
  return out;
}

const _personTypeTitles = {
  'CLASS_TEACHERS': 'Class teachers',
  'TEACHERS': 'Teachers',
  'OTHERS': 'Others',
};

/// `[RecipientsPersonGroup]` (`recipients/static/persons`, TEACHER):
/// headings only, not selectable as a whole.
List<RecipientGroup> parseRecipientPersonGroups(Object? raw) => [
  for (final g in _maps(raw is List ? raw : _map(raw)['groups']))
    RecipientGroup(
      title:
          _personTypeTitles[_str(g['type']).toUpperCase()] ??
          (_str(g['type']).isEmpty ? 'Teachers' : _str(g['type'])),
      members: [for (final r in _maps(g['persons'])) ?parseMessageRecipient(r)],
    ),
];

/// The id a recipient is sent with as `recipientUserIds`: teachers by
/// their numeric `userId`, staff / custom by `id` (as the official app).
int recipientUserId(MessageRecipient r, RecipientOption option) {
  if (option == RecipientOption.teacher) {
    final u = int.tryParse(r.userId ?? '');
    if (u != null) return u;
  }
  return r.id;
}

/// `SendMessageBody` (the `request` part). Fields the official app leaves
/// null are left out (Gson drops nulls by default).
Map<String, Object?> sendMessagePayload(OutgoingMessage m) {
  final byUser = m.option.byUserId;
  return {
    if (!byUser) 'recipientOption': m.option.apiName,
    if (!byUser) 'recipientGroupIds': [for (final g in m.groups) ?g.id],
    'subject': m.subject.trim(),
    'content': m.content,
    if (!byUser)
      'recipientPersonIds': [for (final r in m.recipients) r.personId ?? r.id],
    if (m.option == RecipientOption.parents) 'copyToStudent': m.copyToStudent,
    'requestConfirmation': m.requestConfirmation,
    if (byUser)
      'recipientUserIds': {
        for (final r in m.recipients) recipientUserId(r, m.option),
        // A teacher group picked as a whole: its members.
        for (final g in m.groups)
          for (final r in g.members) recipientUserId(r, m.option),
      }.toList(),
    'forbidReply': m.forbidReply,
  };
}

/// Path of the send call (relative to `api/rest/`).
String sendMessagePath(RecipientOption option) =>
    option.byUserId ? 'view/v2/messages/users' : 'view/v2/messages';

/// `{numberOfRecipients, numberOfCCRecipients}`.
SendResult parseSendResult(Object? raw) {
  final j = _map(raw);
  return (
    recipients: _int(j['numberOfRecipients']) ?? 0,
    ccRecipients: _int(j['numberOfCCRecipients']) ?? 0,
  );
}

SentMessage? _sent(Map<String, Object?> m) {
  final id = _int(m['id']);
  if (id == null) return null;
  final status = _map(m['requestConfirmationStatus']);
  return SentMessage(
    id: id,
    subject: _str(m['subject']),
    preview: _first(m, const ['contentPreview', 'content']),
    recipients: [
      for (final k in const [
        'recipientGroups',
        'recipients',
        'recipientPersons',
      ])
        for (final r in _maps(m[k]))
          if (_first(r, const ['displayName', 'title', 'name']) case final n
              when n.isNotEmpty)
            n,
    ],
    sentAt: parseRestDateTime(m['sentDateTime'] ?? m['sentAt']),
    numberOfRecipients: _int(m['numberOfRecipients']) ?? 0,
    isRevoked: _bool(m['isRevoked']),
    hasAttachments:
        _bool(m['hasAttachments']) || _maps(m['attachments']).isNotEmpty,
    confirmed: _int(status['confirmedRequestCount']) ?? 0,
    confirmationsRequested: _int(status['totalRequestCount']) ?? 0,
  );
}

/// `{sentMessages: [Message]}` (or a plain list), newest first.
List<SentMessage> parseSentMessages(Object? raw) {
  final j = _map(raw);
  final list = raw is List ? raw : (j['sentMessages'] ?? j['messages']);
  final out = [for (final m in _maps(list)) ?_sent(m)];
  out.sort((a, b) {
    final x = a.sentAt, y = b.sentAt;
    if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
    return y.compareTo(x);
  });
  return out;
}

/// `[ReadConfirmationStatus]`.
List<ReadConfirmation> parseReadConfirmations(Object? raw) => [
  for (final r in _maps(raw is List ? raw : _map(raw)['statuses']))
    ReadConfirmation(
      name: _first(r, const ['recipientDisplayName', 'displayName']),
      className: _first(r, const ['recipientClassName', 'className']),
      confirmedBy: [
        for (final s in _maps(r['readConfirmationStates']))
          (
            name: _first(s, const ['userDisplayName', 'displayName']),
            at: parseRestDateTime(s['date']),
          ),
      ],
    ),
];
