/**
 * Rate-limit keys from client IPs. One IPv6 host usually controls a whole
 * /64 (and can pick a fresh address per request), so IPv6 addresses are
 * keyed by their /64 prefix; IPv4 addresses are used as they are.
 */

const IPV4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;

function isIpv4(s: string): boolean {
  const m = IPV4.exec(s);
  return m !== null && m.slice(1).every((p) => Number(p) <= 255);
}

/** The eight 16-bit groups of an IPv6 address, or null if it isn't one. */
function ipv6Groups(s: string): number[] | null {
  const zone = s.indexOf("%");
  if (zone >= 0) s = s.slice(0, zone);
  if (s.length === 0 || s.length > 45) return null;
  // Embedded IPv4 (e.g. ::ffff:192.0.2.1) -> two hex groups.
  const lastColon = s.lastIndexOf(":");
  if (lastColon >= 0 && s.slice(lastColon + 1).includes(".")) {
    const v4 = s.slice(lastColon + 1);
    if (!isIpv4(v4)) return null;
    const b = v4.split(".").map(Number);
    s = `${s.slice(0, lastColon + 1)}${((b[0]! << 8) | b[1]!).toString(16)}:${((b[2]! << 8) | b[3]!).toString(16)}`;
  }
  const parts = s.split("::");
  if (parts.length > 2) return null;
  const parse = (x: string): number[] | null => {
    if (x === "") return [];
    const out: number[] = [];
    for (const g of x.split(":")) {
      if (!/^[0-9a-fA-F]{1,4}$/.test(g)) return null;
      out.push(parseInt(g, 16));
    }
    return out;
  };
  const head = parse(parts[0]!);
  const rest = parts.length === 2 ? parse(parts[1]!) : [];
  if (head === null || rest === null) return null;
  let groups: number[];
  if (parts.length === 2) {
    const missing = 8 - head.length - rest.length;
    if (missing < 1) return null;
    groups = [...head, ...new Array<number>(missing).fill(0), ...rest];
  } else {
    groups = head;
  }
  if (groups.length !== 8) return null;
  return groups;
}

/**
 * Rate-limit key for a client IP (CF-Connecting-IP): IPv4 unchanged, IPv6
 * as its /64 prefix (`2001:db8:1:2::/64`), IPv4-mapped IPv6 as the IPv4
 * address. Missing or unparsable values become "unknown" / are truncated.
 */
export function rateLimitIpKey(ip: string | null | undefined): string {
  const s = (ip ?? "").trim();
  if (s === "") return "unknown";
  if (isIpv4(s)) return s;
  if (s.includes(":")) {
    const g = ipv6Groups(s);
    if (g !== null) {
      // ::ffff:a.b.c.d (IPv4-mapped)
      if (g.slice(0, 5).every((x) => x === 0) && g[5] === 0xffff) {
        return `${g[6]! >> 8}.${g[6]! & 255}.${g[7]! >> 8}.${g[7]! & 255}`;
      }
      return `${g.slice(0, 4).map((x) => x.toString(16)).join(":")}::/64`;
    }
  }
  return s.slice(0, 64);
}

/** [rateLimitIpKey] of the request's CF-Connecting-IP header. */
export function clientIpKey(request: Request): string {
  return rateLimitIpKey(request.headers.get("cf-connecting-ip"));
}
