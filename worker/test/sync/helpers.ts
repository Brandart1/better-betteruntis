import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { handleSync } from "../../src/sync/router";
import type { SyncDeps } from "../../src/sync/auth";
import type { FetchFn } from "../../src/sync/identity";

export const ORIGIN = "https://bbu.test";
export const HOST = "nessa.webuntis.com";

/** Calls recorded by [fakeUntis]. */
export interface UpstreamCall {
  url: string;
  init: RequestInit | undefined;
}

/**
 * A fake WebUntis: tokens look like `tok.<userId>.<school>`; `app/data`
 * answers with that user id and the school upper-cased as tenant.name.
 * Token `tok.reject.x` gets 401.
 */
export function fakeUntis(calls: UpstreamCall[] = []): FetchFn {
  return async (input, init) => {
    const url = String(input instanceof Request ? input.url : input);
    calls.push({ url, init });
    const auth = new Headers(init?.headers).get("authorization") ?? "";
    const m = /^Bearer tok\.([^.]+)\.(.+)$/.exec(auth);
    if (m === null || m[1] === "reject") return new Response("no", { status: 401 });
    const userId = /^\d+$/.test(m[1]!) ? Number(m[1]) : m[1];
    return Response.json({ user: { id: userId, name: "LOGIN" }, tenant: { id: "7065100", name: m[2]!.toUpperCase() } });
  };
}

let ipCounter = 0;
/** A fresh client IP (RL_SESSION is per IP). */
export function freshIp(): string {
  ipCounter++;
  return `10.${(ipCounter >> 16) & 255}.${(ipCounter >> 8) & 255}.${ipCounter & 255}`;
}

let userCounter = Math.floor(Math.random() * 1e6) * 1000;
/** A user id not used by any other test (storage may be shared between tests). */
export function freshUser(): string {
  return String(++userCounter);
}

/** Calls the sync router directly with the fake WebUntis and an optional clock. */
export async function call(request: Request, deps: SyncDeps = {}, e: typeof env = env): Promise<Response> {
  const ctx = createExecutionContext();
  const res = await handleSync(request, e, ctx, { fetch: fakeUntis(), ...deps });
  await waitOnExecutionContext(ctx);
  return res;
}

export function req(method: string, path: string, init: { token?: string; body?: unknown; headers?: Record<string, string> } = {}): Request {
  // A fresh client IP per request unless given (RL_AUTH is per IP).
  const headers: Record<string, string> = { "cf-connecting-ip": freshIp(), ...init.headers };
  if (init.token !== undefined) headers["authorization"] = `Bearer ${init.token}`;
  let body: string | undefined;
  if (init.body !== undefined) {
    body = typeof init.body === "string" ? init.body : JSON.stringify(init.body);
    headers["content-type"] ??= "application/json";
  }
  return new Request(`${ORIGIN}${path}`, { method, headers, ...(body !== undefined ? { body } : {}) });
}

export interface Login {
  token: string;
  cookie: string;
  body: { token: string; expiresAt: string; identity: IdentityJson; e2e: boolean };
}

/** Logs [userId] of [school] in and returns the session. */
export async function login(userId: string, school = "demo-school", deps: SyncDeps = {}): Promise<Login> {
  const res = await call(
    req("POST", "/api/sync/session", {
      body: { host: HOST, school, untisToken: `tok.${userId}.${school}` },
      headers: { "cf-connecting-ip": freshIp() },
    }),
    deps,
  );
  if (res.status !== 200) throw new Error(`login failed: ${res.status} ${await res.text()}`);
  const body = (await res.json()) as Login["body"];
  return { token: body.token, cookie: res.headers.get("set-cookie") ?? "", body };
}

export interface WireNote {
  key: string;
  exam?: boolean;
  text?: string;
  blob?: string;
  updatedAt: number;
  deleted: boolean;
  seq?: number;
}

export function note(key: string, updatedAt: number, text = "t", extra: Partial<WireNote> = {}): WireNote {
  return { key, exam: false, text, updatedAt, deleted: false, ...extra };
}

export async function put(token: string, notes: unknown[], deps: SyncDeps = {}): Promise<Response> {
  return call(req("PUT", "/api/sync/notes", { token, body: { notes } }), deps);
}

export interface Page {
  notes: WireNote[];
  latestSeq: number;
  more: boolean;
  e2e: boolean;
  identity: IdentityJson;
}

/** `identity` in every answer: `{host, school, userId, epoch}`. */
export interface IdentityJson {
  host: string;
  school: string;
  userId: string;
  epoch: string;
}

export async function get(token: string, since?: number): Promise<Page> {
  const res = await call(req("GET", `/api/sync/notes${since === undefined ? "" : `?since=${since}`}`, { token }));
  if (res.status !== 200) throw new Error(`get failed: ${res.status} ${await res.text()}`);
  return (await res.json()) as Page;
}

/** base64url of [n] bytes of [byte]. */
export function b64(n: number, byte = 7): string {
  let bin = "";
  for (let i = 0; i < n; i++) bin += String.fromCharCode((byte + i) & 255);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** base64url(SHA-256(base64url-decoded [authKey])), like the client's authHash. */
export async function authHashOf(authKey: string): Promise<string> {
  const bin = atob(authKey.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (authKey.length % 4)) % 4));
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return btoa(String.fromCharCode(...digest)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** The auth key (32 bytes) whose hash [e2eHeader] carries by default. */
export const AUTH_KEY = b64(32, 42);
export const AUTH_HASH = await authHashOf(AUTH_KEY);

/** A valid E2E header (authHash of [AUTH_KEY]). */
export function e2eHeader(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    version: 1,
    kdf: { alg: "argon2id", m: 19456, t: 2, p: 1, salt: b64(16) },
    wrappedDek: b64(72, 1),
    wrappedDekRecovery: b64(72, 2),
    check: b64(56, 3),
    authHash: AUTH_HASH,
    ...overrides,
  };
}

/** An encrypted note (key = 43-char base64url "HMAC"). */
export function blobNote(seed: number, updatedAt: number, extra: Partial<WireNote> = {}): WireNote {
  return { key: b64(32, seed), blob: b64(280, seed), updatedAt, deleted: false, ...extra };
}

export async function identityId(userId: string, school = "demo-school"): Promise<number> {
  const row = await env.DB.prepare("SELECT id FROM identities WHERE host = ? AND school = ? AND user_id = ?")
    .bind(HOST, school, userId)
    .first<{ id: number }>();
  if (row === null) throw new Error("no identity");
  return row.id;
}
