/**
 * Verifies a WebUntis REST bearer token with WebUntis itself
 * (`GET https://<host>/WebUntis/api/rest/view/v1/app/data`) and turns the
 * answer into a sync identity. The identity is taken from WebUntis' answer
 * only, never from the client.
 */
import { HostAllowlist, isValidHostname } from "../allowlist";
import { readLimited, TooLargeError } from "../http";
import { HttpError, isPlainObject, utf8Decode } from "./http";

export const APP_DATA_PATH = "/WebUntis/api/rest/view/v1/app/data";
export const UPSTREAM_USER_AGENT = "BetterBetterUntis-Sync (+https://github.com/Brandart1/better-betteruntis)";
const TIMEOUT_MS = 15_000;
const MAX_RESPONSE_BYTES = 4 * 1024 * 1024;
const TOKEN_CHARS = /^[A-Za-z0-9._~+/=-]+$/;

/** Who a user is: one WebUntis user of one school. */
export interface SyncIdentity {
  /** WebUntis host, lower case. */
  host: string;
  /** School login name (tenant.name), lower case. */
  school: string;
  /** WebUntis `user.id`, as a string. */
  userId: string;
}

export type FetchFn = (input: Request | string | URL, init?: RequestInit) => Promise<Response>;

export interface VerifyOptions {
  host: string;
  school: string;
  untisToken: string;
  /** Hosts that may be asked (see ../allowlist.ts). */
  allowlist: HostAllowlist;
  /** Upstream fetch (injectable for tests); defaults to the global fetch. */
  fetch?: FetchFn;
  /** Current time in ms (tests). */
  now?: number;
}

export interface AppDataIdentity {
  userId: string;
  tenantName: string;
  tenantId: string | null;
}

/**
 * Extracts `user.id`, `tenant.name` (and `tenant.id`) from a decoded
 * `app/data` body. Observed shape (2026):
 * `{"user": {"id": 1234, ...}, "tenant": {"id": "7065100", "name": "SCHOOL", ...}}`.
 * `user.id` is the account id (stable per school, also for parents). Null if
 * missing or not scalar.
 */
export function parseAppDataIdentity(body: unknown): AppDataIdentity | null {
  if (!isPlainObject(body)) return null;
  const user = body["user"];
  const tenant = body["tenant"];
  if (!isPlainObject(user) || !isPlainObject(tenant)) return null;
  const userId = scalarId(user["id"]);
  const name = tenant["name"];
  if (userId === null || typeof name !== "string" || name.trim() === "" || name.length > 200) return null;
  return { userId, tenantName: name.trim(), tenantId: scalarId(tenant["id"]) };
}

/** A non-negative integer, or a short string without whitespace or `|`. */
function scalarId(v: unknown): string | null {
  if (typeof v === "number") return Number.isSafeInteger(v) && v >= 0 ? String(v) : null;
  if (typeof v === "string") {
    const s = v.trim();
    if (s === "" || s.length > 64 || /[\s|]/.test(s)) return null;
    return s;
  }
  return null;
}

/**
 * Decodes (without verifying!) a JWT payload; null if [token] isn't a JWT
 * with a JSON object payload. Only used to reject early and to cross-check.
 */
export function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length !== 3 || !/^[A-Za-z0-9_-]+$/.test(parts[1]!)) return null;
  try {
    const b64 = parts[1]!.replace(/-/g, "+").replace(/_/g, "/");
    const bin = atob(b64 + "===".slice((b64.length + 3) % 4));
    const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
    const decoded = JSON.parse(utf8Decode(bytes) ?? "") as unknown;
    return isPlainObject(decoded) ? decoded : null;
  } catch {
    return null;
  }
}

const unexpected = () => new HttpError(502, "unexpected_response", "WebUntis sent an unexpected answer.");
const unreachable = () => new HttpError(502, "upstream_unreachable", "WebUntis could not be reached.");
const invalidToken = (msg: string) => new HttpError(401, "invalid_token", msg);
const schoolMismatch = () => new HttpError(401, "school_mismatch", "The token does not belong to this school.");

/** Verifies the token; throws [HttpError] on any failure. */
export async function verifyUntisIdentity(opts: VerifyOptions): Promise<SyncIdentity> {
  const now = opts.now ?? Date.now();
  const host = opts.host.trim().toLowerCase();
  if (!isValidHostname(host) || !opts.allowlist.allows(host)) {
    throw new HttpError(403, "host_not_allowed", "This WebUntis host is not allowed.");
  }
  const token = opts.untisToken;
  if (token.length === 0 || token.length > 8192 || !TOKEN_CHARS.test(token)) {
    throw invalidToken("The WebUntis token is malformed.");
  }
  const claims = decodeJwtPayload(token);
  const exp = claims?.["exp"];
  if (typeof exp === "number" && exp * 1000 < now - 60_000) {
    // Untrusted, but WebUntis would reject an expired token anyway.
    throw invalidToken("The WebUntis token has expired.");
  }

  const body = await fetchAppData(opts.fetch ?? ((i, init) => fetch(i, init)), host, token);
  const found = parseAppDataIdentity(body);
  if (found === null) throw unexpected();
  if (found.tenantName.toLowerCase() !== opts.school.trim().toLowerCase()) throw schoolMismatch();
  const jwtTenant = claims?.["tenant_id"];
  if (
    jwtTenant !== undefined &&
    jwtTenant !== null &&
    found.tenantId !== null &&
    String(jwtTenant) !== found.tenantId
  ) {
    throw schoolMismatch();
  }
  return { host, school: found.tenantName.toLowerCase(), userId: found.userId };
}

async function fetchAppData(fetchFn: FetchFn, host: string, token: string): Promise<unknown> {
  let res: Response;
  const signal = AbortSignal.timeout(TIMEOUT_MS);
  try {
    res = await fetchFn(`https://${host}${APP_DATA_PATH}`, {
      method: "GET",
      redirect: "manual",
      signal,
      headers: {
        authorization: `Bearer ${token}`,
        accept: "application/json",
        "user-agent": UPSTREAM_USER_AGENT,
      },
    });
  } catch {
    throw unreachable();
  }
  if (res.status === 401 || res.status === 403) {
    await res.body?.cancel().catch(() => {});
    throw invalidToken("WebUntis did not accept the token.");
  }
  if (res.status !== 200) {
    await res.body?.cancel().catch(() => {});
    throw unexpected();
  }
  let bytes: Uint8Array;
  try {
    bytes = await readLimited(res.body, MAX_RESPONSE_BYTES);
  } catch (e) {
    if (e instanceof TooLargeError) throw unexpected();
    throw unreachable(); // aborted / connection reset while reading
  }
  const text = utf8Decode(bytes);
  if (text === null) throw unexpected();
  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw unexpected();
  }
}
