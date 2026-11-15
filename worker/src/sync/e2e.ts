/**
 * `GET/PUT/PATCH /api/sync/e2e`: the end-to-end encryption header of the
 * user (salt, KDF parameters, wrapped data keys, check value, auth hash).
 * The server only checks its shape and sizes; it never sees the passphrase
 * or the data key.
 *
 * `authHash` = base64url(SHA-256(authKey)) with authKey = HKDF-SHA256(DEK,
 * info "bbu-header-auth-v1", 32 bytes). A PATCH must present authKey, which
 * only a holder of the DEK can derive.
 */
import type { Env } from "../env";
import type { AuthedRequest, SyncDeps } from "./auth";
import { nowOf } from "./auth";
import * as db from "./db";
import {
  base64UrlDecode,
  constantTimeEqual,
  HttpError,
  isBase64Url,
  isPlainObject,
  json,
  noContent,
  readJsonBody,
  sha256Base64Url,
} from "./http";

const MAX_BODY = 4 * 1024;

/** The stored (canonical) header; unknown fields are dropped. */
export interface E2eHeader {
  version: 1;
  kdf: { alg: "argon2id"; m: number; t: number; p: number; salt: string };
  wrappedDek: string;
  wrappedDekRecovery?: string;
  check: string;
  /** base64url(SHA-256(authKey)), 43 chars. */
  authHash: string;
}

/** Server-side bounds of the Argon2id parameters (the client uses m 19456, t 2, p 1). */
export const KDF_BOUNDS = {
  m: { min: 19_456, max: 262_144 },
  t: { min: 2, max: 16 },
  p: { min: 1, max: 16 },
  /** Salt length in bytes (exactly). */
  saltBytes: 16,
} as const;

/** Length of a base64url-encoded 32-byte value (authHash, authKey). */
const B64_32 = 43;

const bad = (msg: string) => new HttpError(400, "bad_request", msg);

function intIn(v: unknown, min: number, max: number): v is number {
  return typeof v === "number" && Number.isSafeInteger(v) && v >= min && v <= max;
}

/**
 * Validates an E2E header. Sizes: salt exactly 16 bytes; wrapped keys and
 * check 16-512 base64url chars (XChaCha20-Poly1305: 24-byte nonce + 32-byte
 * key + 16-byte tag = 96 chars); authHash 43 chars. Argon2id m in KiB
 * 19456-262144, t 2-16, p 1-16 (weaker parameters are refused so a
 * compromised or buggy client can't store an easily brute-forced header).
 */
export function parseE2eHeader(v: unknown): E2eHeader {
  if (!isPlainObject(v)) throw bad("The E2E header must be a JSON object.");
  if (v["version"] !== 1) throw bad("Unsupported E2E header version.");
  const kdf = v["kdf"];
  if (!isPlainObject(kdf) || kdf["alg"] !== "argon2id") throw bad('kdf.alg must be "argon2id".');
  const { m, t, p, salt } = kdf;
  if (
    !intIn(m, KDF_BOUNDS.m.min, KDF_BOUNDS.m.max) ||
    !intIn(t, KDF_BOUNDS.t.min, KDF_BOUNDS.t.max) ||
    !intIn(p, KDF_BOUNDS.p.min, KDF_BOUNDS.p.max)
  ) {
    throw bad("kdf.m/t/p out of range.");
  }
  if (typeof salt !== "string" || base64UrlDecode(salt)?.byteLength !== KDF_BOUNDS.saltBytes) {
    throw bad("kdf.salt must be 16 bytes, base64url.");
  }
  const { wrappedDek, wrappedDekRecovery, check, authHash } = v;
  if (!isBase64Url(wrappedDek, 16, 512)) throw bad("wrappedDek must be base64url (16-512 chars).");
  if (wrappedDekRecovery !== undefined && wrappedDekRecovery !== null && !isBase64Url(wrappedDekRecovery, 16, 512)) {
    throw bad("wrappedDekRecovery must be base64url (16-512 chars).");
  }
  if (!isBase64Url(check, 16, 512)) throw bad("check must be base64url (16-512 chars).");
  if (!isBase64Url(authHash, B64_32, B64_32)) throw bad("authHash must be 43 base64url chars (SHA-256).");
  return {
    version: 1,
    kdf: { alg: "argon2id", m, t, p, salt },
    wrappedDek,
    ...(typeof wrappedDekRecovery === "string" ? { wrappedDekRecovery } : {}),
    check,
    authHash,
  };
}

export async function getE2e(env: Env, auth: AuthedRequest): Promise<Response> {
  const header = await db.getE2eHeader(env.DB, auth.identityId);
  if (header === null) throw notEnabled();
  return json(JSON.parse(header) as unknown);
}

/**
 * Creates the header once. Also deletes the account's plaintext notes in
 * the same batch (the client re-uploads them encrypted). 409 `e2e_exists`
 * if a header exists; resetting goes through DELETE /api/sync/account.
 */
export async function putE2e(request: Request, env: Env, auth: AuthedRequest, deps: SyncDeps): Promise<Response> {
  const header = parseE2eHeader(await readJsonBody(request, MAX_BODY));
  const created = await db.createE2eHeader(env.DB, auth.identityId, JSON.stringify(header), nowOf(deps));
  if (!created) {
    throw new HttpError(409, "e2e_exists", "End-to-end encryption is already set up; reset the account to change it.");
  }
  return json(header, 201);
}

const notEnabled = () =>
  new HttpError(404, "e2e_not_enabled", "End-to-end encryption is not set up for this account.");
const authFailed = () => new HttpError(403, "e2e_auth_failed", "The auth key doesn't match this account's header.");

/**
 * Replaces the header with one for the SAME data key (passphrase change or
 * new recovery code). Body: `{"header": {...}, "authKey": "<43 chars>"}`.
 * Allowed only if SHA-256(authKey) equals the stored `authHash` (proves the
 * caller holds the DEK, not just a session) and the new header keeps that
 * `authHash`. `check` may change (it is not compared). 404
 * `e2e_not_enabled` without a header, 403 `e2e_auth_failed` otherwise.
 */
export async function patchE2e(request: Request, env: Env, auth: AuthedRequest): Promise<Response> {
  const body = await readJsonBody(request, MAX_BODY);
  if (!isPlainObject(body)) throw bad('Body must be {"header": {...}, "authKey": "..."}.');
  const header = parseE2eHeader(body["header"]);
  const keyBytes = parseAuthKey(body["authKey"]);
  const storedHash = await verifyAuthKey(env, auth, keyBytes);
  if (!constantTimeEqual(header.authHash, storedHash)) throw authFailed();

  const result = await db.replaceE2eHeader(env.DB, auth.identityId, JSON.stringify(header), storedHash);
  if (result === "missing") throw notEnabled();
  if (result === "mismatch") throw authFailed(); // reset + new header in between
  return json(header);
}

/**
 * `DELETE /api/sync/e2e`, body `{"authKey": "..."}`: turns E2E off for the
 * account without signing devices out. Deletes the header and ALL notes of
 * the identity (they are encrypted; the clients re-upload in plaintext) in
 * one batch; sessions stay. 204; 404 `e2e_not_enabled`; 403 `e2e_auth_failed`.
 */
export async function deleteE2e(request: Request, env: Env, auth: AuthedRequest): Promise<Response> {
  const body = await readJsonBody(request, MAX_BODY);
  if (!isPlainObject(body)) throw bad('Body must be {"authKey": "..."}.');
  const keyBytes = parseAuthKey(body["authKey"]);
  const storedHash = await verifyAuthKey(env, auth, keyBytes);
  const result = await db.deleteE2e(env.DB, auth.identityId, storedHash);
  if (result === "missing") throw notEnabled();
  if (result === "mismatch") throw authFailed();
  return noContent();
}

function parseAuthKey(v: unknown): Uint8Array {
  const bytes = isBase64Url(v, B64_32, B64_32) ? base64UrlDecode(v) : null;
  if (bytes === null || bytes.byteLength !== 32) throw bad("authKey must be 43 base64url chars (32 bytes).");
  return bytes;
}

/**
 * Checks SHA-256(authKey) against the stored header's authHash (constant
 * time); returns the stored authHash. 404 without a header, 403 on mismatch.
 */
async function verifyAuthKey(env: Env, auth: AuthedRequest, keyBytes: Uint8Array): Promise<string> {
  const storedJson = await db.getE2eHeader(env.DB, auth.identityId);
  if (storedJson === null) throw notEnabled();
  const storedHash = (JSON.parse(storedJson) as Partial<E2eHeader>).authHash;
  if (typeof storedHash !== "string") throw authFailed();
  if (!constantTimeEqual(await sha256Base64Url(keyBytes), storedHash)) throw authFailed();
  return storedHash;
}
