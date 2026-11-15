/**
 * WebUntis relay for the web app (WebUntis sends no CORS headers). Port of
 * server/lib/src/proxy.dart: `/proxy/<host>/<path>?<query>` is forwarded to
 * `https://<host>/<path>?<query>` for allowlisted hosts.
 *
 * What goes upstream: method (GET/POST/HEAD), path, raw query, the body, and
 * only content-type, accept, accept-language and a bearer authorization
 * header, with a neutral user agent. What comes back: status, body and
 * content-type, plus `cache-control: no-store`. Cookies are never forwarded
 * in either direction (same as the Dart server); redirects are not followed
 * and their `location` is dropped.
 *
 * Nothing is logged: no bodies, auth headers, query strings or hosts.
 */
import { allowlistFor, type HostAllowlist, isValidHostname } from "./allowlist";
import type { Env } from "./env";
import { jsonError, readLimited, textError, TooLargeError } from "./http";

export const PROXY_PREFIX = "/proxy/";

/** Request headers copied upstream; everything else is dropped. */
export const FORWARDED_REQUEST_HEADERS = ["content-type", "accept", "accept-language", "authorization"] as const;

export const UPSTREAM_USER_AGENT = "BetterBetterUntis-Web/1.0";

const ALLOWED_METHODS = new Set(["GET", "POST", "HEAD"]);

/** Statuses whose responses must not have a body. */
const NULL_BODY_STATUSES = new Set([101, 103, 204, 205, 304]);

export interface ProxyOptions {
  /** Upstream fetch (tests inject a fake). */
  fetch?: (request: Request) => Promise<Response>;
  maxRequestBodyBytes?: number;
  maxResponseBodyBytes?: number;
  /** Covers the upstream response headers and body. */
  timeoutMs?: number;
}

export const DEFAULT_PROXY_OPTIONS = {
  maxRequestBodyBytes: 1024 * 1024,
  maxResponseBodyBytes: 32 * 1024 * 1024,
  timeoutMs: 45_000,
} as const;

class UpstreamTimeout extends Error {}

export async function handleProxy(
  request: Request,
  env: Env,
  _ctx: ExecutionContext,
  options: ProxyOptions = {},
): Promise<Response> {
  const fetchImpl = options.fetch ?? ((r: Request) => fetch(r));
  const maxRequest = options.maxRequestBodyBytes ?? DEFAULT_PROXY_OPTIONS.maxRequestBodyBytes;
  const maxResponse = options.maxResponseBodyBytes ?? DEFAULT_PROXY_OPTIONS.maxResponseBodyBytes;
  const timeoutMs = options.timeoutMs ?? DEFAULT_PROXY_OPTIONS.timeoutMs;

  const clientIp = request.headers.get("cf-connecting-ip") ?? "unknown";
  const { success } = await env.RL_PROXY.limit({ key: clientIp });
  if (!success) return jsonError(429, "rate_limited", undefined, { "retry-after": "60" });

  let allowlist: HostAllowlist;
  try {
    allowlist = allowlistFor(env.ALLOWED_HOSTS);
  } catch {
    return textError(500, "Proxy misconfigured");
  }

  const target = parseTarget(new URL(request.url), allowlist);
  // Deliberately does not echo the requested host.
  if (target === null) return textError(403, "Forbidden upstream host");

  const method = request.method.toUpperCase();
  if (!ALLOWED_METHODS.has(method)) {
    return textError(405, "Method not allowed", { allow: "GET, POST, HEAD" });
  }

  let body: Uint8Array | undefined;
  // GET/HEAD requests can't carry a body in fetch; WebUntis never needs one.
  if (method === "POST") {
    const declared = Number(request.headers.get("content-length") ?? "NaN");
    if (Number.isFinite(declared) && declared > maxRequest) return textError(413, "Request body too large");
    try {
      body = await readLimited(request.body, maxRequest);
    } catch (e) {
      if (e instanceof TooLargeError) return textError(413, "Request body too large");
      return textError(400, "Bad request body");
    }
  }

  const headers = new Headers();
  for (const name of FORWARDED_REQUEST_HEADERS) {
    const v = request.headers.get(name);
    if (v === null) continue;
    // Only bearer tokens go upstream, never basic credentials.
    if (name === "authorization" && !v.trimStart().toLowerCase().startsWith("bearer ")) continue;
    headers.set(name, v);
  }
  headers.set("user-agent", UPSTREAM_USER_AGENT);

  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      controller.abort();
      reject(new UpstreamTimeout());
    }, timeoutMs);
  });

  try {
    const upstream = new Request(target, {
      method,
      headers,
      body: body !== undefined && body.byteLength > 0 ? body : undefined,
      redirect: "manual",
      signal: controller.signal,
    });
    const work = (async () => {
      const res = await fetchImpl(upstream);
      if (method === "HEAD") await res.body?.cancel().catch(() => {});
      const bytes = method === "HEAD" ? new Uint8Array(0) : await readLimited(res.body, maxResponse);
      return { status: res.status, contentType: res.headers.get("content-type"), bytes };
    })();
    // After a timeout the losing branch may still reject; that's expected.
    work.catch(() => {});
    const { status, contentType, bytes } = await Promise.race([work, timeout]);
    if (status < 200 || status > 599) return textError(502, "Upstream protocol error");
    const out = new Headers({ "cache-control": "no-store" });
    if (contentType !== null) out.set("content-type", contentType);
    const hasBody = method !== "HEAD" && !NULL_BODY_STATUSES.has(status);
    return new Response(hasBody ? bytes : null, { status, headers: out });
  } catch (e) {
    if (e instanceof UpstreamTimeout) return textError(504, "Upstream timeout");
    if (e instanceof TooLargeError) return textError(502, "Upstream response too large");
    return textError(502, "Upstream connection failed");
  } finally {
    if (timer !== undefined) clearTimeout(timer);
    // Stops a still-running upstream fetch or body read.
    controller.abort();
  }
}

/**
 * Parses and validates the proxy target. Returns null unless the URL is a
 * well-formed proxy request for an allowlisted host. The host segment is
 * checked in its raw (still percent-encoded) form, so `%2F`, `%40`, `@`,
 * `:port` etc. are all rejected; the upstream URL is assembled from the
 * validated host and the path, which can't alter the authority.
 */
export function parseTarget(requested: URL, allowlist: HostAllowlist): string | null {
  const path = requested.pathname; // percent-encoded, dot segments resolved
  if (!path.startsWith(PROXY_PREFIX)) return null;
  const afterPrefix = path.slice(PROXY_PREFIX.length);
  const slash = afterPrefix.indexOf("/");
  const rawHost = slash < 0 ? afterPrefix : afterPrefix.slice(0, slash);
  const rest = slash < 0 ? "/" : afterPrefix.slice(slash);

  const host = rawHost.toLowerCase();
  if (!isValidHostname(host) || !allowlist.allows(host)) return null;

  // Belt and braces: no dot segments, empty segments or backslashes in the
  // forwarded path (WebUntis never needs them).
  const segments = rest.slice(1).split("/");
  for (let i = 0; i < segments.length; i++) {
    const lower = segments[i]!.toLowerCase();
    if (lower === "" && i !== segments.length - 1) return null;
    if (
      lower === "." ||
      lower === ".." ||
      lower === "%2e" ||
      lower === "%2e%2e" ||
      lower === ".%2e" ||
      lower === "%2e." ||
      lower.includes("%5c") ||
      lower.includes("%00") ||
      lower.includes("\\")
    ) {
      return null;
    }
  }

  const target = `https://${host}${rest}${requested.search}`;
  // Paranoia: the assembled URL must still point at exactly this host.
  const check = new URL(target);
  if (check.hostname !== host || check.port !== "" || check.username !== "" || check.password !== "") return null;
  return target;
}
