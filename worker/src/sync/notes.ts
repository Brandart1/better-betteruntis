/** `GET/PUT /api/sync/notes`: the user's lesson notes, last write wins per key. */
import type { Env } from "../env";
import type { AuthedRequest, SyncDeps } from "./auth";
import { nowOf } from "./auth";
import * as db from "./db";
import { hasBadChars, HttpError, isBase64Url, isPlainObject, json, readJsonBody } from "./http";

export const LIMITS = {
  pageSize: 1000,
  maxNotesPerRequest: 500,
  maxBodyBytes: 1024 * 1024,
  maxNotesPerUser: 20_000,
  maxKeyLength: 256,
  maxTextLength: 4000,
  /** E2E key: base64url HMAC-SHA256 (32 bytes, unpadded). */
  e2eKeyLength: 43,
  /** E2E blob: base64url of at most 16 KiB of ciphertext. */
  maxBlobChars: Math.ceil((16 * 1024 * 4) / 3),
  /** `updatedAt` may be at most this far in the future. */
  maxClockSkewMs: 5 * 60 * 1000,
} as const;

/** Wire form of a stored note. */
export function noteToJson(r: db.NoteRow): Record<string, unknown> {
  if (r.blob !== null) {
    return { key: r.key, blob: r.blob, updatedAt: r.updated_at, deleted: r.deleted === 1, seq: r.seq };
  }
  return {
    key: r.key,
    exam: r.exam === 1,
    text: r.text ?? "",
    updatedAt: r.updated_at,
    deleted: r.deleted === 1,
    seq: r.seq,
  };
}

export async function getNotes(request: Request, env: Env, auth: AuthedRequest): Promise<Response> {
  const params = new URL(request.url).searchParams;
  const all = params.getAll("since");
  let since = 0;
  if (all.length > 0) {
    if (all.length !== 1 || !/^\d{1,15}$/.test(all[0]!)) {
      throw new HttpError(400, "bad_request", '"since" must be a non-negative integer.');
    }
    since = Number(all[0]);
  }
  const page = await db.changes(env.DB, auth.identityId, since, LIMITS.pageSize + 1);
  const more = page.notes.length > LIMITS.pageSize;
  const notes = more ? page.notes.slice(0, LIMITS.pageSize) : page.notes;
  return json({ notes: notes.map(noteToJson), latestSeq: page.latestSeq, more, e2e: page.e2e });
}

const bad = (msg: string) => new HttpError(400, "bad_request", msg);

/** Parses one note of a PUT body; [i] is only used in messages (never user data). */
function parseNote(v: unknown, i: number, now: number): db.NoteInput {
  const shape = `notes[${i}] must be {key, exam, text, updatedAt, deleted} or {key, blob, updatedAt, deleted}.`;
  if (!isPlainObject(v)) throw bad(shape);
  const { key, exam, text, blob, updatedAt, deleted } = v;
  if (typeof key !== "string" || typeof deleted !== "boolean" || typeof updatedAt !== "number") throw bad(shape);
  if (!Number.isSafeInteger(updatedAt) || updatedAt < 0) throw bad(`notes[${i}]: updatedAt must be an integer >= 0.`);
  if (updatedAt > now + LIMITS.maxClockSkewMs) {
    throw new HttpError(400, "clock_skew", `notes[${i}]: updatedAt is more than 5 minutes in the future.`);
  }
  if (blob !== undefined) {
    // End-to-end encrypted note: key = base64url HMAC, blob = base64url ciphertext.
    if (exam !== undefined || text !== undefined) throw bad(`notes[${i}]: an encrypted note has no exam/text.`);
    if (!isBase64Url(key, LIMITS.e2eKeyLength, LIMITS.e2eKeyLength)) {
      throw bad(`notes[${i}]: key of an encrypted note must be ${LIMITS.e2eKeyLength} base64url chars.`);
    }
    if (!isBase64Url(blob, 1, LIMITS.maxBlobChars)) {
      throw bad(`notes[${i}]: blob must be base64url, at most ${LIMITS.maxBlobChars} chars.`);
    }
    return { key, exam: null, text: null, blob, updatedAt, deleted };
  }
  if (typeof exam !== "boolean" || typeof text !== "string") throw bad(shape);
  if (key.length === 0) throw bad(`notes[${i}]: key must not be empty.`);
  if (key.length > LIMITS.maxKeyLength) throw bad(`notes[${i}]: key longer than ${LIMITS.maxKeyLength} chars.`);
  if (text.length > LIMITS.maxTextLength) throw bad(`notes[${i}]: text longer than ${LIMITS.maxTextLength} chars.`);
  if (hasBadChars(key) || hasBadChars(text)) throw bad(`notes[${i}]: NUL or unpaired surrogate.`);
  return { key, exam, text, blob: null, updatedAt, deleted };
}

/**
 * Collapses duplicate keys of one request the way applying them in order
 * with last-write-wins would: the highest updatedAt wins, ties keep the
 * earlier one. Keeps first-occurrence order.
 */
export function mergeDuplicates(notes: db.NoteInput[]): db.NoteInput[] {
  const byKey = new Map<string, db.NoteInput>();
  for (const n of notes) {
    const prev = byKey.get(n.key);
    if (prev === undefined || n.updatedAt > prev.updatedAt) byKey.set(n.key, n);
  }
  return [...byKey.values()];
}

export async function putNotes(request: Request, env: Env, auth: AuthedRequest, deps: SyncDeps): Promise<Response> {
  const body = await readJsonBody(request, LIMITS.maxBodyBytes);
  if (!isPlainObject(body)) throw bad("Body must be a JSON object.");
  const list = body["notes"];
  if (!Array.isArray(list)) throw bad('"notes" must be an array.');
  if (list.length > LIMITS.maxNotesPerRequest) {
    throw new HttpError(413, "batch_too_large", `At most ${LIMITS.maxNotesPerRequest} notes per request.`);
  }
  const now = nowOf(deps);
  const parsed = list.map((v, i) => parseNote(v, i, now));
  const encrypted = parsed.filter((n) => n.blob !== null).length;
  if (encrypted !== 0 && encrypted !== parsed.length) throw bad("Plaintext and encrypted notes can't be mixed.");
  const notes = mergeDuplicates(parsed);
  const e2eMode = encrypted > 0;

  if (notes.length === 0) {
    const page = await db.changes(env.DB, auth.identityId, Number.MAX_SAFE_INTEGER, 0);
    return json({ notes: [], latestSeq: page.latestSeq, e2e: page.e2e });
  }
  const out = await db.putNotes(env.DB, auth.identityId, notes, e2eMode, LIMITS.maxNotesPerUser);
  if (!out.ok) {
    switch (out.reason) {
      case "too_many_notes":
        throw new HttpError(413, "too_many_notes", `At most ${LIMITS.maxNotesPerUser} notes per user.`);
      case "e2e_required":
        throw new HttpError(409, "e2e_required", "This account uses end-to-end encryption; send encrypted notes.");
      case "e2e_not_enabled":
        throw new HttpError(409, "e2e_not_enabled", "End-to-end encryption is not set up for this account.");
    }
  }
  const { result } = out;
  return json({ notes: result.notes.map(noteToJson), latestSeq: result.latestSeq, e2e: result.e2e });
}
