final _hostChars = RegExp(r'^[a-z0-9.-]+$');
final _label = RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$');

/// Returns true if [host] is a syntactically valid, already-lowercase DNS
/// hostname: only `[a-z0-9.-]`, no empty labels (so no leading/trailing dot
/// and no `..`), labels of 1-63 chars not starting/ending with `-`, at most
/// 253 chars, and not an all-numeric (IPv4-looking) name.
bool isValidHostname(String host) {
  if (host.isEmpty || host.length > 253) return false;
  if (!_hostChars.hasMatch(host)) return false;
  final labels = host.split('.');
  if (labels.length < 2) return false;
  for (final l in labels) {
    if (!_label.hasMatch(l)) return false;
  }
  // Reject IP literals like 127.0.0.1: the TLD must contain a letter.
  if (!RegExp('[a-z]').hasMatch(labels.last)) return false;
  return true;
}

/// Set of upstream hosts the proxy may talk to.
///
/// Entries are exact hostnames (`webuntis.com`) or wildcards (`*.webuntis.com`)
/// which match any subdomain at any depth but not the bare suffix itself.
class HostAllowlist {
  HostAllowlist._(this._exact, this._suffixes);

  final Set<String> _exact;

  /// Stored with the leading dot, e.g. `.webuntis.com`.
  final List<String> _suffixes;

  /// Parses a comma-separated list. Throws [FormatException] on bad entries.
  factory HostAllowlist.parse(String spec) {
    final exact = <String>{};
    final suffixes = <String>[];
    for (final raw in spec.split(',')) {
      final entry = raw.trim().toLowerCase();
      if (entry.isEmpty) continue;
      if (entry.startsWith('*.')) {
        final suffix = entry.substring(2);
        if (!isValidHostname(suffix)) {
          throw FormatException('Invalid allowlist wildcard "$raw"');
        }
        suffixes.add('.$suffix');
      } else {
        if (!isValidHostname(entry)) {
          throw FormatException('Invalid allowlist host "$raw"');
        }
        exact.add(entry);
      }
    }
    if (exact.isEmpty && suffixes.isEmpty) {
      throw const FormatException('Host allowlist is empty');
    }
    return HostAllowlist._(exact, suffixes);
  }

  /// [host] must already be validated with [isValidHostname].
  bool allows(String host) {
    if (!isValidHostname(host)) return false;
    if (_exact.contains(host)) return true;
    for (final s in _suffixes) {
      if (host.length > s.length && host.endsWith(s)) return true;
    }
    return false;
  }

  @override
  String toString() => [..._exact, ..._suffixes.map((s) => '*$s')].join(',');
}
