/**
 * `GET/PUT /api/sync/e2e`: the end-to-end encryption header of the user
 * (salt, KDF parameters, wrapped data keys, check value). The server only
 * checks its shape and sizes; it never sees the passphrase or the data key.
 */
import type { Env } from "../env";
import type { AuthedRequest, SyncDeps } from "./auth";
import { nowOf } from "./auth";
import * as db from "./db";
import { HttpError, isBase64Url, isPlainObject, json, readJsonBody } from "./http";

const MAX_BODY = 4 * 1024;

/** The stored (canonical) header; unknown fields are dropped. */
export interface E2eHeader {
  version: 1;
  kdf: { alg: "argon2id"; m: number; t: number; p: number; salt: string };
  wrappedDek: string;
  wrappedDekRecovery?: string;
  check: string;
}

const bad = (msg: string) => new HttpError(400, "bad_request", msg);

function intIn(v: unknown, min: number, max: number): v is number {
  return typeof v === "number" && Number.isSafeInteger(v) && v >= min && v <= max;
}

/**
 * Validates an E2E header. Sizes: salt 16-64 bytes; wrapped keys and check
 * 16-512 base64url chars (XChaCha20-Poly1305: 24-byte nonce + 32-byte key
 * + 16-byte tag = 96 chars). Argon2id m in KiB (8 MiB - 4 GiB), t 1-64, p 1-16.
 */
export function parseE2eHeader(v: unknown): E2eHeader {
  if (!isPlainObject(v)) throw bad("The E2E header must be a JSON object.");
  if (v["version"] !== 1) throw bad("Unsupported E2E header version.");
  const kdf = v["kdf"];
  if (!isPlainObject(kdf) || kdf["alg"] !== "argon2id") throw bad('kdf.alg must be "argon2id".');
  const { m, t, p, salt } = kdf;
  if (!intIn(m, 8 * 1024, 4 * 1024 * 1024) || !intIn(t, 1, 64) || !intIn(p, 1, 16)) {
    throw bad("kdf.m/t/p out of range.");
  }
  if (!isBase64Url(salt, 22, 86)) throw bad("kdf.salt must be 16-64 bytes, base64url.");
  const { wrappedDek, wrappedDekRecovery, check } = v;
  if (!isBase64Url(wrappedDek, 16, 512)) throw bad("wrappedDek must be base64url (16-512 chars).");
  if (wrappedDekRecovery !== undefined && wrappedDekRecovery !== null && !isBase64Url(wrappedDekRecovery, 16, 512)) {
    throw bad("wrappedDekRecovery must be base64url (16-512 chars).");
  }
  if (!isBase64Url(check, 16, 512)) throw bad("check must be base64url (16-512 chars).");
  return {
    version: 1,
    kdf: { alg: "argon2id", m, t, p, salt },
    wrappedDek,
    ...(typeof wrappedDekRecovery === "string" ? { wrappedDekRecovery } : {}),
    check,
  };
}

export async function getE2e(env: Env, auth: AuthedRequest): Promise<Response> {
  const header = await db.getE2eHeader(env.DB, auth.identityId);
  if (header === null) {
    throw new HttpError(404, "e2e_not_enabled", "End-to-end encryption is not set up for this account.");
  }
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

/**
 * Replaces the header with one for the SAME data key (passphrase change or
 * new recovery code): only allowed if `check` is unchanged, which only a
 * client holding the data key can produce for a new header. 404
 * `e2e_not_enabled` without a header, 409 `e2e_check_mismatch` otherwise.
 */
export async function patchE2e(request: Request, env: Env, auth: AuthedRequest): Promise<Response> {
  const header = parseE2eHeader(await readJsonBody(request, MAX_BODY));
  const result = await db.replaceE2eHeader(env.DB, auth.identityId, JSON.stringify(header), header.check);
  if (result === "missing") {
    throw new HttpError(404, "e2e_not_enabled", "End-to-end encryption is not set up for this account.");
  }
  if (result === "mismatch") {
    throw new HttpError(409, "e2e_check_mismatch", "The new header must keep the same key (check value differs).");
  }
  return json(header);
}
