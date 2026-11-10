/// Parsing of WebUntis login QR codes / deep links:
/// `untis://setschool?school=&user=&key=&url=&anonymous=&apiUrl=&skipAppSecret=`
library;

/// The decoded contents of a login QR code.
class QrLogin {
  const QrLogin({
    required this.school,
    this.user = '',
    this.key = '',
    this.host,
    this.anonymous = false,
    this.skipAppSecret = false,
  });

  /// School login name (or numeric school id as text).
  final String school;
  final String user;

  /// App key, used as password-or-secret.
  final String key;

  /// Bare server host (e.g. `mese.webuntis.com`), or null when the code
  /// doesn't carry one and the school has to be looked up.
  final String? host;
  final bool anonymous;
  final bool skipAppSecret;

  @override
  bool operator ==(Object other) =>
      other is QrLogin &&
      other.school == school &&
      other.user == user &&
      other.key == key &&
      other.host == host &&
      other.anonymous == anonymous &&
      other.skipAppSecret == skipAppSecret;

  @override
  int get hashCode =>
      Object.hash(school, user, key, host, anonymous, skipAppSecret);

  @override
  String toString() =>
      'QrLogin(school: $school, user: $user, host: $host, '
      'anonymous: $anonymous, skipAppSecret: $skipAppSecret)';
}

/// Parses an `untis://setschool?...` link. Returns null for anything that is
/// not a usable login code (wrong scheme, missing school, missing user/key for
/// a non-anonymous login).
QrLogin? parseUntisQr(String raw) {
  final text = raw.trim();
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'untis') return null;
  if (uri.host.toLowerCase() != 'setschool') return null;

  final Map<String, String> params;
  try {
    params = {
      for (final e in uri.queryParameters.entries) e.key.toLowerCase(): e.value,
    };
  } on FormatException {
    return null;
  }

  String p(String k) => (params[k.toLowerCase()] ?? '').trim();

  final school = p('school');
  if (school.isEmpty) return null;
  final anonymous = _parseBool(p('anonymous'));
  final user = p('user');
  final key = p('key');
  if (!anonymous && (user.isEmpty || key.isEmpty)) return null;

  final host = normalizeHost(p('url')) ?? normalizeHost(p('apiUrl'));
  return QrLogin(
    school: school,
    user: user,
    key: key,
    host: host,
    anonymous: anonymous,
    skipAppSecret: _parseBool(p('skipAppSecret')),
  );
}

bool _parseBool(String v) =>
    const {'true', '1', 'yes', 'on'}.contains(v.toLowerCase());

/// Reduces user/QR input such as `https://mese.webuntis.com/WebUntis/` to the
/// bare host (`mese.webuntis.com`, with `:port` if given). Null when empty or
/// unparsable.
String? normalizeHost(String? input) {
  final t = input?.trim() ?? '';
  if (t.isEmpty) return null;
  final withScheme = t.contains('://') ? t : 'https://$t';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || uri.host.isEmpty) return null;
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}
