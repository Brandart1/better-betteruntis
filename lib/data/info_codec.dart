/// JSON codecs for the info-center cache ([InfoCache] rows).
///
/// Dates are stored as local ISO-8601 strings without zone. Decoding is
/// tolerant: a malformed item is dropped; a malformed document decodes to
/// null (treated as "not cached").
library;

import 'dart:convert';

import '../core/info.dart';
import '../core/interfaces.dart';

class InfoCodec<T> {
  const InfoCodec(this._encode, this._decode);

  final Object? Function(T value) _encode;
  final T Function(Object? json) _decode;

  String encode(T value) => jsonEncode(_encode(value));

  /// Null when [json] cannot be decoded.
  T? decode(String json) {
    try {
      return _decode(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  /// Codec for lists; items that fail to decode are skipped.
  static InfoCodec<List<E>> list<E>(
    Map<String, Object?> Function(E) enc,
    E Function(Map<String, Object?>) dec,
  ) => InfoCodec<List<E>>((l) => [for (final e in l) enc(e)], (j) {
    if (j is! List) throw const FormatException('not a list');
    final out = <E>[];
    for (final m in j) {
      if (m is! Map) continue;
      try {
        out.add(dec(m.cast<String, Object?>()));
      } catch (_) {
        // Skip just this item.
      }
    }
    return out;
  });
}

String? _d(DateTime? d) => d?.toIso8601String();
DateTime _dt(Object? v) => DateTime.parse(v! as String);
DateTime? _dtOrNull(Object? v) => v is String ? DateTime.tryParse(v) : null;
String _s(Object? v) => v is String ? v : '';
bool _b(Object? v) => v == true;
int _i(Object? v) => v is num ? v.toInt() : 0;
List<int> _ints(Object? v) =>
    v is List ? v.whereType<num>().map((n) => n.toInt()).toList() : const [];

List<Map<String, Object?>> _encAtt(List<({String name, String url})> a) => [
  for (final x in a) {'name': x.name, 'url': x.url},
];
List<({String name, String url})> _decAtt(Object? v) => [
  if (v is List)
    for (final m in v.whereType<Map>())
      (name: _s(m['name']), url: _s(m['url'])),
];

final messagesCodec = InfoCodec.list<Message>(
  (m) => {
    'id': m.id,
    'subject': m.subject,
    'body': m.bodyHtml,
    'attachments': _encAtt(m.attachments),
  },
  (j) => Message(
    id: _i(j['id']),
    subject: _s(j['subject']),
    bodyHtml: _s(j['body']),
    attachments: _decAtt(j['attachments']),
  ),
);

Map<String, Object?> _encInbox(InboxMessage m) => {
  'id': m.id,
  'subject': m.subject,
  'preview': m.preview,
  'sender': m.sender,
  'sentAt': _d(m.sentAt),
  'isRead': m.isRead,
  'hasAttachments': m.hasAttachments,
};

InboxMessage _decInbox(Map<String, Object?> j) => InboxMessage(
  id: _i(j['id']),
  subject: _s(j['subject']),
  preview: _s(j['preview']),
  sender: _s(j['sender']),
  sentAt: _dtOrNull(j['sentAt']),
  isRead: _b(j['isRead']),
  hasAttachments: _b(j['hasAttachments']),
);

final inboxCodec = InfoCodec.list<InboxMessage>(_encInbox, _decInbox);

final inboxDetailCodec = InfoCodec<InboxMessageDetail>(
  (m) => {
    'id': m.id,
    'subject': m.subject,
    'body': m.bodyHtml,
    'sender': m.sender,
    'sentAt': _d(m.sentAt),
    'attachments': _encAtt(m.attachments),
  },
  (j) {
    final m = (j! as Map).cast<String, Object?>();
    return InboxMessageDetail(
      id: _i(m['id']),
      subject: _s(m['subject']),
      bodyHtml: _s(m['body']),
      sender: _s(m['sender']),
      sentAt: _dtOrNull(m['sentAt']),
      attachments: _decAtt(m['attachments']),
    );
  },
);

final homeworkCodec = InfoCodec.list<HomeworkItem>(
  (h) => {
    'id': h.id,
    'lessonId': h.lessonId,
    'assignedOn': _d(h.assignedOn),
    'dueOn': _d(h.dueOn),
    'text': h.text,
    'remark': h.remark,
    'completed': h.completed,
    'subjectId': h.subjectId,
    'teacherIds': h.teacherIds,
    'klassenIds': h.klassenIds,
    'attachments': _encAtt(h.attachments),
  },
  (j) => HomeworkItem(
    id: _i(j['id']),
    lessonId: _i(j['lessonId']),
    assignedOn: _dt(j['assignedOn']),
    dueOn: _dt(j['dueOn']),
    text: _s(j['text']),
    remark: _s(j['remark']),
    completed: _b(j['completed']),
    subjectId: j['subjectId'] is num ? (j['subjectId']! as num).toInt() : null,
    teacherIds: _ints(j['teacherIds']),
    klassenIds: _ints(j['klassenIds']),
    attachments: _decAtt(j['attachments']),
  ),
);

final examsCodec = InfoCodec.list<ExamItem>(
  (e) => {
    'id': e.id,
    'start': _d(e.start),
    'end': _d(e.end),
    'examType': e.examType,
    'name': e.name,
    'text': e.text,
    'subjectId': e.subjectId,
    'klassenIds': e.klassenIds,
    'roomIds': e.roomIds,
    'teacherIds': e.teacherIds,
  },
  (j) => ExamItem(
    id: _i(j['id']),
    start: _dt(j['start']),
    end: _dt(j['end']),
    examType: _s(j['examType']),
    name: _s(j['name']),
    text: _s(j['text']),
    subjectId: j['subjectId'] is num ? (j['subjectId']! as num).toInt() : null,
    klassenIds: _ints(j['klassenIds']),
    roomIds: _ints(j['roomIds']),
    teacherIds: _ints(j['teacherIds']),
  ),
);

final absencesCodec = InfoCodec.list<AbsenceItem>(
  (a) => {
    'id': a.id,
    'start': _d(a.start),
    'end': _d(a.end),
    'excused': a.excused,
    'reason': a.reason,
    'text': a.text,
    'excuseStatus': a.excuseStatus,
  },
  (j) => AbsenceItem(
    id: _i(j['id']),
    start: _dt(j['start']),
    end: _dt(j['end']),
    excused: _b(j['excused']),
    reason: _s(j['reason']),
    text: _s(j['text']),
    excuseStatus: _s(j['excuseStatus']),
  ),
);

final officeHoursCodec = InfoCodec.list<OfficeHourItem>(
  (o) => {
    'id': o.id,
    'start': _d(o.start),
    'end': _d(o.end),
    'teacherName': o.teacherName,
    'teacherId': o.teacherId,
    'rooms': o.rooms,
    'email': o.email,
    'phone': o.phone,
    'registrationPossible': o.registrationPossible,
    'registered': o.registered,
  },
  (j) => OfficeHourItem(
    id: _i(j['id']),
    start: _dt(j['start']),
    end: _dt(j['end']),
    teacherName: _s(j['teacherName']),
    teacherId: _i(j['teacherId']),
    rooms: _s(j['rooms']),
    email: _s(j['email']),
    phone: _s(j['phone']),
    registrationPossible: _b(j['registrationPossible']),
    registered: _b(j['registered']),
  ),
);
