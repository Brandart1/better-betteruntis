/** `GET/PUT /api/sync/notes`: the user's lesson notes, last write wins per key. */
import type { Env } from "../env";
import type { AuthedRequest, SyncDeps } from "./auth";
import { nowOf, unauthorized } from "./auth";
import * as db from "./db";
import { hasBadChars, HttpError, isBase64Url, isPlainObject, json, readJsonBody } from "./http";

export const LIMITS = {
  pageSize: 1000,
  maxNotesPerRequest: 500,
  maxBodyBytes: 1024 * 1024,
  /** Live (non-deleted) notes per user; tombstones don't count here (they do in bytes). */
  maxNotesPerUser: 5_000,
  /** Stored bytes per user: UTF-8 key + text/homework/blob over all notes incl. tombstones. */
  maxBytesPerUser: 5 * 1024 * 1024,
  /**
   * Accepted note writes per user and UTC day (inserts and overwrites,
   * tombstones included; older/tied notes that aren't written don't count).
   * Protects the app-wide D1 daily write allowance (free plan: 100 000 rows
   * written per day for the whole app; used up, sync stops for everyone).
   */
  maxWritesPerDay: 5_000,
  maxKeyLength: 256,
  maxTextLength: 4000,
  /** The user's homework of a lesson (plaintext notes), like [maxTextLength]. */
  maxHomeworkLength: 4000,
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
    homework: r.homework ?? "",
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
  if (page === null) throw unauthorized(); // identity deleted after the session lookup
  const more = page.notes.length > LIMITS.pageSize;
  const notes = more ? page.notes.slice(0, LIMITS.pageSize) : page.notes;
  return json({
    notes: notes.map(noteToJson),
    latestSeq: page.latestSeq,
    more,
    e2e: page.e2e,
    identity: auth.identity,
  });
}

const bad = (msg: string) => new HttpError(400, "bad_request", msg);

/** Parses one note of a PUT body; [i] is only used in messages (never user data). */
function parseNote(v: unknown, i: number, now: number): db.NoteInput {
  const shape = `notes[${i}] must be {key, exam, text, homework?, updatedAt, deleted} or {key, blob, updatedAt, deleted}.`;
  if (!isPlainObject(v)) throw bad(shape);
  const { key, exam, text, homework, blob, updatedAt, deleted } = v;
  if (typeof key !== "string" || typeof deleted !== "boolean" || typeof updatedAt !== "number") throw bad(shape);
  if (!Number.isSafeInteger(updatedAt) || updatedAt < 0) throw bad(`notes[${i}]: updatedAt must be an integer >= 0.`);
  if (updatedAt > now + LIMITS.maxClockSkewMs) {
    throw new HttpError(400, "clock_skew", `notes[${i}]: updatedAt is more than 5 minutes in the future.`, {}, {
      serverTime: now,
    });
  }
  if (blob !== undefined) {
    // End-to-end encrypted note: key = base64url HMAC, blob = base64url ciphertext.
    if (exam !== undefined || text !== undefined || homework !== undefined) {
      throw bad(`notes[${i}]: an encrypted note has no exam/text/homework.`);
    }
    if (!isBase64Url(key, LIMITS.e2eKeyLength, LIMITS.e2eKeyLength)) {
      throw bad(`notes[${i}]: key of an encrypted note must be ${LIMITS.e2eKeyLength} base64url chars.`);
    }
    if (!isBase64Url(blob, 1, LIMITS.maxBlobChars)) {
      throw bad(`notes[${i}]: blob must be base64url, at most ${LIMITS.maxBlobChars} chars.`);
    }
    return { key, exam: null, text: null, blob, updatedAt, deleted };
  }
  // homework is optional: app versions before it don't send it ('' then).
  if (typeof exam !== "boolean" || typeof text !== "string") throw bad(shape);
  if (homework !== undefined && typeof homework !== "string") throw bad(shape);
  const hw = homework ?? "";
  if (key.length === 0) throw bad(`notes[${i}]: key must not be empty.`);
  if (key.length > LIMITS.maxKeyLength) throw bad(`notes[${i}]: key longer than ${LIMITS.maxKeyLength} chars.`);
  if (text.length > LIMITS.maxTextLength) throw bad(`notes[${i}]: text longer than ${LIMITS.maxTextLength} chars.`);
  if (hw.length > LIMITS.maxHomeworkLength) {
    throw bad(`notes[${i}]: homework longer than ${LIMITS.maxHomeworkLength} chars.`);
  }
  if (hasBadChars(key) || hasBadChars(text) || hasBadChars(hw)) throw bad(`notes[${i}]: NUL or unpaired surrogate.`);
  // Plaintext tombstones are stored blanked (nothing of a deleted note stays).
  if (deleted) return { key, exam: false, text: "", homework: "", blob: null, updatedAt, deleted };
  return { key, exam, text, homework: hw, blob: null, updatedAt, deleted };
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

/** Seconds from [now] (ms) to the next UTC midnight (at least 1). */
export function secondsToNextUtcDay(now: number): number {
  const next = (Math.floor(now / db.DAY_MS) + 1) * db.DAY_MS;
  return Math.max(1, Math.ceil((next - now) / 1000));
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
    if (page === null) throw unauthorized();
    return json({ notes: [], latestSeq: page.latestSeq, e2e: page.e2e, identity: auth.identity });
  }
  let out: db.PutOutcome;
  try {
    out = await db.writeNotes(
      env.DB,
      auth.identityId,
      notes,
      e2eMode,
      { maxNotes: LIMITS.maxNotesPerUser, maxBytes: LIMITS.maxBytesPerUser, dailyWrites: LIMITS.maxWritesPerDay },
      now,
    );
  } catch (e) {
    if (e instanceof db.WriteContendedError) {
      throw new HttpError(503, "busy", "Too many concurrent writes, try again.", { "retry-after": "5" });
    }
    throw e;
  }
  if (!out.ok) {
    switch (out.reason) {
      case "identity_gone":
        throw unauthorized();
      case "daily_limit":
        throw new HttpError(
          429,
          "daily_limit",
          `At most ${LIMITS.maxWritesPerDay} note writes per user and day (UTC).`,
          { "retry-after": String(secondsToNextUtcDay(now)) },
        );
      case "too_many_notes":
        throw new HttpError(413, "too_many_notes", `At most ${LIMITS.maxNotesPerUser} notes per user.`);
      case "storage_quota":
        throw new HttpError(413, "storage_quota", `At most ${LIMITS.maxBytesPerUser} bytes of notes per user.`);
      case "e2e_required":
        throw new HttpError(409, "e2e_required", "This account uses end-to-end encryption; send encrypted notes.");
      case "e2e_not_enabled":
        throw new HttpError(409, "e2e_not_enabled", "End-to-end encryption is not set up for this account.");
    }
  }
  const { result } = out;
  return json({
    notes: result.notes.map(noteToJson),
    latestSeq: result.latestSeq,
    e2e: result.e2e,
    identity: auth.identity,
  });
}
