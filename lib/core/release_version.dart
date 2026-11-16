/// Release versions as used in tags and release notes (`v0.4.8-alpha.7`,
/// `v0.4.7-beta`, `v0.5.0`), with their order: X.Y.Z first, then
/// alpha.N < beta < stable. Pure Dart.
library;

/// Release channels, in pre-release order.
enum ReleaseChannel {
  alpha,
  beta,
  stable;

  /// `alpha`/`beta`/`stable`; anything else (e.g. `dev`) is null.
  static ReleaseChannel? tryParse(String s) {
    for (final c in values) {
      if (c.name == s.trim().toLowerCase()) return c;
    }
    return null;
  }
}

/// One release: `0.4.8-alpha.7`. A plain `-alpha` is the first alpha
/// (alpha.1); betas carry no number (`-beta`, `-beta.N` is accepted and
/// ordered by N).
class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(
    this.major,
    this.minor,
    this.patch, {
    this.channel = ReleaseChannel.stable,
    this.number = 0,
  });

  final int major;
  final int minor;
  final int patch;
  final ReleaseChannel channel;

  /// Pre-release number (alpha.N); 0 for stable. Plain `-alpha` is 1.
  final int number;

  static final _re = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta)(?:\.(\d+))?)?(?:\+[0-9A-Za-z.]*)?$',
    caseSensitive: false,
  );

  /// Parses `v0.4.8-alpha.7`, `0.4.8-alpha`, `0.4.7-beta`, `0.5.0`,
  /// `0.5.0+81` (the build number is ignored) and file names like
  /// `v0.4.8-alpha.7.md`. Null for anything else.
  static ReleaseVersion? tryParse(String? s) {
    if (s == null) return null;
    var t = s.trim();
    if (t.toLowerCase().endsWith('.md')) t = t.substring(0, t.length - 3);
    final m = _re.firstMatch(t);
    if (m == null) return null;
    final nums = [for (var i = 1; i <= 3; i++) int.tryParse(m.group(i)!)];
    if (nums.contains(null)) return null;
    final pre = m.group(4)?.toLowerCase();
    final channel = pre == null
        ? ReleaseChannel.stable
        : ReleaseChannel.tryParse(pre)!;
    final n = m.group(5) == null ? null : int.tryParse(m.group(5)!);
    if (m.group(5) != null && n == null) return null;
    return ReleaseVersion(
      nums[0]!,
      nums[1]!,
      nums[2]!,
      channel: channel,
      number: channel == ReleaseChannel.stable ? 0 : (n ?? 1),
    );
  }

  /// Same X.Y.Z as [o].
  bool sameCore(ReleaseVersion o) =>
      major == o.major && minor == o.minor && patch == o.patch;

  @override
  int compareTo(ReleaseVersion o) {
    for (final (a, b) in [
      (major, o.major),
      (minor, o.minor),
      (patch, o.patch),
      (channel.index, o.channel.index),
      (number, o.number),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  bool operator <(ReleaseVersion o) => compareTo(o) < 0;
  bool operator >(ReleaseVersion o) => compareTo(o) > 0;
  bool operator <=(ReleaseVersion o) => compareTo(o) <= 0;
  bool operator >=(ReleaseVersion o) => compareTo(o) >= 0;

  @override
  bool operator ==(Object other) =>
      other is ReleaseVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, channel, number);

  /// Normalized form, without `v`: `0.4.8-alpha.1` (also for a plain
  /// `-alpha` tag), `0.4.7-beta`, `0.5.0`.
  @override
  String toString() {
    final core = '$major.$minor.$patch';
    return switch (channel) {
      ReleaseChannel.stable => core,
      ReleaseChannel.beta => number <= 1 ? '$core-beta' : '$core-beta.$number',
      ReleaseChannel.alpha => '$core-alpha.$number',
    };
  }
}
