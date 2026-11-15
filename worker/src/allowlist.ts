/**
 * Upstream host allowlist, ported from server/lib/src/host_allowlist.dart.
 * Shared by the relay (/proxy) and the sync login (WebUntis verification).
 */

const HOST_CHARS = /^[a-z0-9.-]+$/;
const LABEL = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/;

/**
 * True if `host` is a syntactically valid, already-lowercase DNS hostname:
 * only `[a-z0-9.-]` (so IDNs must be punycode, `xn--...`), no empty labels
 * (no leading/trailing dot, no `..`), labels of 1-63 chars not starting or
 * ending with `-`, at most 253 chars, at least two labels, and a TLD with a
 * letter (rejects IPv4 literals). Ports, userinfo, IPv6 and percent-escapes
 * fail the character check.
 */
export function isValidHostname(host: string): boolean {
  if (host.length === 0 || host.length > 253) return false;
  if (!HOST_CHARS.test(host)) return false;
  const labels = host.split(".");
  if (labels.length < 2) return false;
  for (const l of labels) {
    if (!LABEL.test(l)) return false;
  }
  return /[a-z]/.test(labels[labels.length - 1]!);
}

/**
 * Exact hostnames (`webuntis.com`) and wildcards (`*.webuntis.com`, any
 * subdomain depth, but not the bare suffix itself).
 */
export class HostAllowlist {
  private constructor(
    private readonly exact: ReadonlySet<string>,
    /** With the leading dot, e.g. `.webuntis.com`. */
    private readonly suffixes: readonly string[],
  ) {}

  /** Parses a comma-separated list. Throws on bad or no entries. */
  static parse(spec: string): HostAllowlist {
    const exact = new Set<string>();
    const suffixes: string[] = [];
    for (const raw of spec.split(",")) {
      const entry = raw.trim().toLowerCase();
      if (entry === "") continue;
      if (entry.startsWith("*.")) {
        const suffix = entry.slice(2);
        if (!isValidHostname(suffix)) throw new Error(`Invalid allowlist wildcard "${raw}"`);
        suffixes.push(`.${suffix}`);
      } else {
        if (!isValidHostname(entry)) throw new Error(`Invalid allowlist host "${raw}"`);
        exact.add(entry);
      }
    }
    if (exact.size === 0 && suffixes.length === 0) throw new Error("Host allowlist is empty");
    return new HostAllowlist(exact, suffixes);
  }

  /** `host` must already be lowercase (like the Dart version). */
  allows(host: string): boolean {
    if (!isValidHostname(host)) return false;
    if (this.exact.has(host)) return true;
    return this.suffixes.some((s) => host.length > s.length && host.endsWith(s));
  }

  toString(): string {
    return [...this.exact, ...this.suffixes.map((s) => `*${s}`)].join(",");
  }
}

let cached: { spec: string; list: HostAllowlist } | undefined;

/** Parsed allowlist for `env.ALLOWED_HOSTS`, cached per isolate. Throws if invalid. */
export function allowlistFor(spec: string): HostAllowlist {
  if (cached?.spec !== spec) cached = { spec, list: HostAllowlist.parse(spec) };
  return cached.list;
}
