/**
 * Sync sessions: `POST/DELETE /api/sync/session`, session lookup for the
 * other endpoints, cookie and CSRF rules (docs/SYNC-PLAN.md, security 4).
 */
import type { Env } from "../env";
import { allowlistFor } from "../allowlist";
import { clientIpKey } from "../ip";
import * as db from "./db";
import {
  base64UrlEncode,
  HttpError,
  isJsonContentType,
  isPlainObject,
  json,
  noContent,
  readJsonBody,
  sha256Hex,
} from "./http";
import { verifyUntisIdentity, type FetchFn, type SyncIdentity } from "./identity";

/**
 * `__Host-` prefix: the browser only accepts it with Secure, Path=/ and no
 * Domain, so a sibling (sub)domain can't set or overwrite it (no cookie
 * tossing / session fixation). Path=/ means it is also sent to /proxy and
 * the assets; the relay never forwards cookies (src/proxy.ts).
 */
export const COOKIE_NAME = "__Host-bbu_sync";
export const COOKIE_PATH = "/";
export const CSRF_HEADER = "x-bbu-sync";
export const SESSION_TTL_MS = 90 * 24 * 60 * 60 * 1000;
const MAX_SESSION_BODY = 16 * 1024;
const TOKEN_SHAPE = /^[A-Za-z0-9_-]{43}$/;

/** Injectable dependencies (tests). */
export interface SyncDeps {
  /** Upstream fetch for the WebUntis check. */
  fetch?: FetchFn;
  /** Current time in ms. */
  now?: () => number;
}

export function nowOf(deps: SyncDeps): number {
  return deps.now ? deps.now() : Date.now();
}

/** A new identity epoch: 16 random bytes, base64url without padding (22 chars). */
export function newEpoch(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

/** A new session token: 32 random bytes, base64url without padding (43 chars). */
export function newSessionToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

/** Hex SHA-256 of a session token (the only form stored). */
export const hashSessionToken = sha256Hex;

/** Short, non-reversible tag of an identity for logs. */
export async function identityLogTag(who: SyncIdentity): Promise<string> {
  return (await sha256Hex(`${who.host}|${who.school}|${who.userId}`)).slice(0, 12);
}

export function sessionCookie(value: string, maxAgeSeconds: number): string {
  return `${COOKIE_NAME}=${value}; Path=${COOKIE_PATH}; HttpOnly; Secure; SameSite=Strict; Max-Age=${maxAgeSeconds}`;
}

export const CLEAR_COOKIE = sessionCookie("", 0);

export interface PresentedToken {
  token: string;
  viaCookie: boolean;
}

/**
 * The bearer token, else the `__Host-bbu_sync` cookie, else null (Basic
 * auth is ignored). Throws 401 if the request carries more than one such
 * cookie (defence in depth; `__Host-` already stops siblings setting it).
 */
export function presentedToken(request: Request): PresentedToken | null {
  const cookieHeader = request.headers.get("cookie");
  if (cookieCount(cookieHeader, COOKIE_NAME) > 1) throw unauthorized();
  const auth = request.headers.get("authorization");
  if (auth !== null) {
    const parts = auth.trim().split(/\s+/);
    if (parts.length === 2 && parts[0]!.toLowerCase() === "bearer") {
      return { token: parts[1]!, viaCookie: false };
    }
  }
  const cookie = cookieValue(cookieHeader, COOKIE_NAME);
  if (cookie !== null && cookie !== "") return { token: cookie, viaCookie: true };
  return null;
}

function cookieValue(header: string | null, name: string): string | null {
  if (header === null) return null;
  for (const part of header.split(";")) {
    const i = part.indexOf("=");
    if (i < 0) continue;
    if (part.slice(0, i).trim() === name) return part.slice(i + 1).trim();
  }
  return null;
}

function cookieCount(header: string | null, name: string): number {
  if (header === null) return 0;
  let n = 0;
  for (const part of header.split(";")) {
    const i = part.indexOf("=");
    if (i >= 0 && part.slice(0, i).trim() === name) n++;
  }
  return n;
}

function normOrigin(s: string): string | null {
  try {
    const u = new URL(s);
    if (u.protocol !== "https:" && u.protocol !== "http:") return null;
    return u.origin.toLowerCase();
  } catch {
    return null;
  }
}

/**
 * True if the request's `Origin` is the Worker's own origin (request URL)
 * or env.PUBLIC_ORIGIN.
 */
function sameOrigin(request: Request, env: Env): boolean {
  const origin = request.headers.get("origin")?.trim();
  if (!origin || origin === "null") return false;
  const o = normOrigin(origin);
  if (o === null) return false;
  if (o === new URL(request.url).origin.toLowerCase()) return true;
  const pub = env.PUBLIC_ORIGIN?.trim();
  return !!pub && normOrigin(pub) === o;
}

/**
 * CSRF rule for cookie-authenticated, state-changing requests: the
 * `X-BBU-Sync: 1` header, or an `Origin` equal to this origin / PUBLIC_ORIGIN.
 */
export function passesCsrfCheck(request: Request, env: Env): boolean {
  if (request.headers.get(CSRF_HEADER)?.trim() === "1") return true;
  return sameOrigin(request, env);
}

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

export const unauthorized = () => new HttpError(401, "unauthorized", "A valid sync session is required.");
const csrfRejected = () => new HttpError(403, "csrf_rejected", "Cross-site request rejected (send X-BBU-Sync: 1).");
const rateLimited = () =>
  new HttpError(429, "rate_limited", "Too many requests, try again later.", { "retry-after": "60" });

/** How long an IP stays blocked after exceeding RL_AUTH (failed lookups). */
export const AUTH_BLOCK_MS = 60_000;
/** Isolate-local blocked marks (IP key -> until, ms); bounded. */
const authBlocked = new Map<string, number>();
const AUTH_BLOCKED_MAX = 10_000;

function blockCacheKey(ipKey: string): Request {
  // Synthetic URL, never fetched; only a key for caches.default.
  return new Request(`https://rl-auth.invalid/${encodeURIComponent(ipKey)}`);
}

/**
 * True if [ipKey] exceeded the failed-lookup limit recently: checked in
 * this isolate's memory and in `caches.default` (per Cloudflare location;
 * a no-op on workers.dev, where the Map still catches repeat offenders).
 */
async function isAuthBlocked(ipKey: string, now: number): Promise<boolean> {
  const until = authBlocked.get(ipKey);
  if (until !== undefined) {
    if (until > now) return true;
    authBlocked.delete(ipKey);
  }
  try {
    const hit = typeof caches !== "undefined" ? await caches.default.match(blockCacheKey(ipKey)) : undefined;
    if (hit !== undefined && Number(await hit.text()) > now) return true;
  } catch {
    // Cache unavailable: the Map and the limiter itself still apply.
  }
  return false;
}

async function markAuthBlocked(ipKey: string, now: number): Promise<void> {
  if (authBlocked.size >= AUTH_BLOCKED_MAX) authBlocked.clear();
  authBlocked.set(ipKey, now + AUTH_BLOCK_MS);
  try {
    if (typeof caches !== "undefined") {
      await caches.default.put(
        blockCacheKey(ipKey),
        new Response(String(now + AUTH_BLOCK_MS), { headers: { "cache-control": `max-age=${AUTH_BLOCK_MS / 1000}` } }),
      );
    }
  } catch {
    // Best effort.
  }
}

/**
 * Charges one failed lookup (unknown/expired token) to RL_AUTH; over the
 * limit, the IP is marked blocked for [AUTH_BLOCK_MS].
 */
async function chargeAuthMiss(env: Env, ipKey: string, now: number): Promise<void> {
  if (!(await env.RL_AUTH.limit({ key: ipKey })).success) await markAuthBlocked(ipKey, now);
}

/** Test hook: forget all blocked marks of this isolate. */
export function resetAuthBlocks(): void {
  authBlocked.clear();
}

export interface AuthedRequest extends db.SessionInfo {
  tokenHash: string;
}

export interface AuthOptions {
  /** A write (PUT notes, PUT/PATCH/DELETE e2e): also counts against RL_WRITE. */
  write?: boolean;
}

/**
 * Requires a valid session (bearer or cookie; CSRF rule for cookie +
 * state-changing method). Rate limits: RL_AUTH counts only FAILED lookups
 * per client IP; an IP over that limit is marked blocked and gets 429
 * before D1 is asked (random tokens can't cause unlimited lookups). Then
 * RL_SYNC (and RL_WRITE for writes) per identity, so more sessions don't
 * buy more requests. Throws HttpError.
 */
export async function authenticate(
  request: Request,
  env: Env,
  deps: SyncDeps,
  options: AuthOptions = {},
): Promise<AuthedRequest> {
  const presented = presentedToken(request);
  if (presented === null || !TOKEN_SHAPE.test(presented.token)) throw unauthorized();
  if (presented.viaCookie && !SAFE_METHODS.has(request.method) && !passesCsrfCheck(request, env)) {
    throw csrfRejected();
  }
  const ipKey = clientIpKey(request);
  const now = nowOf(deps);
  if (await isAuthBlocked(ipKey, now)) throw rateLimited();
  const tokenHash = await hashSessionToken(presented.token);
  const session = await db.findSession(env.DB, tokenHash, now);
  if (session === null) {
    await chargeAuthMiss(env, ipKey, now);
    throw unauthorized();
  }
  const idKey = `id:${session.identityId}`;
  if (!(await env.RL_SYNC.limit({ key: idKey })).success) throw rateLimited();
  if (options.write && !(await env.RL_WRITE.limit({ key: idKey })).success) throw rateLimited();
  return { ...session, tokenHash };
}

/** `POST /api/sync/session`. */
export async function createSessionHandler(request: Request, env: Env, deps: SyncDeps): Promise<Response> {
  const { success } = await env.RL_SESSION.limit({ key: clientIpKey(request) });
  if (!success) throw rateLimited();
  // A browser only sends Origin; a cross-site one is never a legitimate login.
  if (request.headers.has("origin") && !sameOrigin(request, env)) throw csrfRejected();
  if (!isJsonContentType(request)) {
    throw new HttpError(415, "unsupported_media_type", "Expected application/json.");
  }
  const body = await readJsonBody(request, MAX_SESSION_BODY);
  if (!isPlainObject(body)) throw new HttpError(400, "bad_request", "Expected a JSON object.");
  const { host, school, untisToken } = body;
  if (
    typeof host !== "string" ||
    host === "" ||
    host.length > 253 ||
    typeof school !== "string" ||
    school.trim() === "" ||
    school.length > 200 ||
    typeof untisToken !== "string" ||
    untisToken === ""
  ) {
    throw new HttpError(400, "bad_request", "host, school and untisToken are required strings.");
  }

  let allowlist;
  try {
    allowlist = allowlistFor(env.ALLOWED_HOSTS);
  } catch {
    throw new HttpError(500, "server_misconfigured", "The host allowlist is invalid.");
  }
  const now = nowOf(deps);
  const identity = await verifyUntisIdentity({
    host,
    school,
    untisToken,
    allowlist,
    now,
    ...(deps.fetch ? { fetch: deps.fetch } : {}),
  });

  const token = newSessionToken();
  const expiresAt = now + SESSION_TTL_MS;
  const epoch = newEpoch();
  const stored = await db.createSession(env.DB, await hashSessionToken(token), identity, now, expiresAt, epoch);
  // Browsers (they send Origin) use the HttpOnly cookie; keeping the token
  // out of the body keeps it away from page scripts. Native apps send no
  // Origin and get the token for their bearer header.
  const browser = request.headers.has("origin");
  return json(
    {
      ...(browser ? {} : { token }),
      expiresAt: new Date(expiresAt).toISOString(),
      identity: { ...identity, epoch: stored.epoch },
      e2e: stored.e2e,
      // The epoch is only stored when the identity is created: a different
      // one means the identity (a sync of this account) existed already.
      existing: stored.epoch !== epoch,
    },
    200,
    { "set-cookie": sessionCookie(token, SESSION_TTL_MS / 1000) },
  );
}

/**
 * `DELETE /api/sync/session`: deletes the presented session (if any) and
 * clears the cookie. 204 also without a valid session; a cookie-only
 * logout must pass the CSRF rule (no forced logouts). Two sync cookies ->
 * 401 (with the cookie cleared). Only logouts with an unknown token count
 * against RL_AUTH.
 */
export async function deleteSessionHandler(request: Request, env: Env, deps: SyncDeps = {}): Promise<Response> {
  let presented: PresentedToken | null;
  try {
    presented = presentedToken(request);
  } catch (e) {
    if (e instanceof HttpError) throw new HttpError(e.status, e.code, e.message, { "set-cookie": CLEAR_COOKIE });
    throw e;
  }
  if (presented !== null) {
    if (presented.viaCookie && !passesCsrfCheck(request, env)) throw csrfRejected();
    if (TOKEN_SHAPE.test(presented.token)) {
      const ipKey = clientIpKey(request);
      const now = nowOf(deps);
      if (await isAuthBlocked(ipKey, now)) throw rateLimited();
      if (!(await db.deleteSession(env.DB, await hashSessionToken(presented.token)))) {
        await chargeAuthMiss(env, ipKey, now);
      }
    }
  }
  return noContent({ "set-cookie": CLEAR_COOKIE });
}
