/**
 * All SQL of the sync API. Every statement is a fixed string with bound
 * parameters; user data never becomes part of SQL text. Every note/session
 * query is scoped by the identity id taken from the caller's session.
 *
 * D1 has no interactive transactions: multi-statement changes go through
 * `db.batch()`, which runs the statements as one transaction (and D1
 * executes one query/batch at a time per database, so a batch is also
 * isolated from concurrent requests).
 */
import type { SyncIdentity } from "./identity";

/** The identity as the API shows it: who (from WebUntis) + this incarnation's epoch. */
export interface IdentityJson extends SyncIdentity {
  /** 22-char base64url random tag, new when the identity row is (re-)created. */
  epoch: string;
}

export interface SessionInfo {
  identityId: number;
  identity: IdentityJson;
  expiresAt: number;
}

/** A note as stored. Plaintext: exam/text set, blob null. E2E: blob set. */
export interface NoteRow {
  key: string;
  exam: number | null;
  text: string | null;
  blob: string | null;
  updated_at: number;
  deleted: number;
  seq: number;
}

/** A validated note to write (keys distinct within one write). */
export interface NoteInput {
  key: string;
  exam: boolean | null;
  text: string | null;
  blob: string | null;
  updatedAt: number;
  deleted: boolean;
}

/** Max expired sessions deleted per session creation (bounded purge). */
const PURGE_BATCH = 100;
/** Sessions kept per identity; older ones are dropped on login. */
export const MAX_SESSIONS_PER_IDENTITY = 30;

// --- sessions -------------------------------------------------------------

/**
 * Creates the identity if needed (with the new random [epoch], used only on
 * insert) and a session for it, purges up to [PURGE_BATCH] expired sessions
 * and trims old sessions of the identity, in one batch. Returns whether the
 * identity has an E2E header and its stored epoch.
 */
export async function createSession(
  db: D1Database,
  tokenHash: string,
  who: SyncIdentity,
  now: number,
  expiresAt: number,
  epoch: string,
): Promise<{ e2e: boolean; epoch: string }> {
  const idOf = "SELECT id FROM identities WHERE host = ?1 AND school = ?2 AND user_id = ?3";
  const results = await db.batch([
    db
      .prepare(
        "DELETE FROM sessions WHERE token_hash IN " +
          "(SELECT token_hash FROM sessions WHERE expires_at <= ?1 LIMIT ?2)",
      )
      .bind(now, PURGE_BATCH),
    db
      .prepare(
        "INSERT INTO identities (host, school, user_id, epoch, created_at) VALUES (?1, ?2, ?3, ?5, ?4) " +
          "ON CONFLICT (host, school, user_id) DO NOTHING",
      )
      .bind(who.host, who.school, who.userId, now, epoch),
    db
      .prepare(
        "INSERT INTO sessions (token_hash, identity_id, created_at, expires_at) " +
          `SELECT ?4, id, ?5, ?6 FROM identities WHERE host = ?1 AND school = ?2 AND user_id = ?3`,
      )
      .bind(who.host, who.school, who.userId, tokenHash, now, expiresAt),
    db
      .prepare(
        `DELETE FROM sessions WHERE identity_id = (${idOf}) AND token_hash NOT IN ` +
          `(SELECT token_hash FROM sessions WHERE identity_id = (${idOf}) ` +
          "ORDER BY created_at DESC, token_hash LIMIT ?4)",
      )
      .bind(who.host, who.school, who.userId, MAX_SESSIONS_PER_IDENTITY),
    db
      .prepare(
        "SELECT i.epoch, EXISTS (SELECT 1 FROM e2e_headers WHERE identity_id = i.id) AS e2e " +
          "FROM identities AS i WHERE host = ?1 AND school = ?2 AND user_id = ?3",
      )
      .bind(who.host, who.school, who.userId),
  ]);
  const row = results[4]!.results[0] as { e2e: number; epoch: string };
  return { e2e: row.e2e === 1, epoch: row.epoch };
}

/** The unexpired session for [tokenHash], or null. */
export async function findSession(db: D1Database, tokenHash: string, now: number): Promise<SessionInfo | null> {
  const row = await db
    .prepare(
      "SELECT s.identity_id, s.expires_at, i.host, i.school, i.user_id, i.epoch " +
        "FROM sessions AS s JOIN identities AS i ON i.id = s.identity_id " +
        "WHERE s.token_hash = ?1 AND s.expires_at > ?2",
    )
    .bind(tokenHash, now)
    .first<{ identity_id: number; expires_at: number; host: string; school: string; user_id: string; epoch: string }>();
  if (row === null) return null;
  return {
    identityId: row.identity_id,
    identity: { host: row.host, school: row.school, userId: row.user_id, epoch: row.epoch },
    expiresAt: row.expires_at,
  };
}

/** Deletes the session; returns whether it existed. */
export async function deleteSession(db: D1Database, tokenHash: string): Promise<boolean> {
  const r = await db.prepare("DELETE FROM sessions WHERE token_hash = ?1").bind(tokenHash).run();
  return (r.meta.changes ?? 0) > 0;
}

// --- account ----------------------------------------------------------------

/**
 * Deletes the identity and everything belonging to it (one batch). The
 * counters on the identity row need no update (the row goes too).
 */
export async function deleteIdentity(db: D1Database, identityId: number): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM notes WHERE identity_id = ?1").bind(identityId),
    db.prepare("DELETE FROM e2e_headers WHERE identity_id = ?1").bind(identityId),
    db.prepare("DELETE FROM sessions WHERE identity_id = ?1").bind(identityId),
    db.prepare("DELETE FROM identities WHERE id = ?1").bind(identityId),
  ]);
}

// --- notes ------------------------------------------------------------------

const NOTE_COLUMNS = "key, exam, text, blob, updated_at, deleted, seq";

/** Milliseconds per UTC day (budget days are `floor(ms / DAY_MS)`). */
export const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Notes changed after [since] (ordered by seq, at most [limit]) plus the
 * identity's state; null if the identity row doesn't exist (any more).
 */
export async function changes(
  db: D1Database,
  identityId: number,
  since: number,
  limit: number,
): Promise<{ notes: NoteRow[]; latestSeq: number; e2e: boolean } | null> {
  const stmts = [stateStatement(db, identityId)];
  // A pull that can't find anything (since >= last_seq) still costs the
  // index probe only; limit 0 (state only) skips the query entirely.
  if (limit > 0) {
    stmts.push(
      db
        .prepare(`SELECT ${NOTE_COLUMNS} FROM notes WHERE identity_id = ?1 AND seq > ?2 ORDER BY seq LIMIT ?3`)
        .bind(identityId, since, limit),
    );
  }
  const [state, notes] = await db.batch(stmts);
  const st = readState(state!);
  if (st === null) return null;
  return { notes: (notes?.results ?? []) as unknown as NoteRow[], latestSeq: st.latestSeq, e2e: st.e2e };
}

function stateStatement(db: D1Database, identityId: number): D1PreparedStatement {
  // O(1): the counters live on the identity row.
  return db
    .prepare(
      "SELECT last_seq, note_count, bytes, budget_day, budget_used, " +
        "EXISTS (SELECT 1 FROM e2e_headers WHERE identity_id = ?1) AS e2e FROM identities WHERE id = ?1",
    )
    .bind(identityId);
}

interface State {
  latestSeq: number;
  e2e: boolean;
  noteCount: number;
  bytes: number;
  budgetDay: number;
  budgetUsed: number;
}

/** The state row, or null if the identity doesn't exist. */
function readState(r: D1Result): State | null {
  const row = r.results[0] as
    | { last_seq: number; e2e: number; note_count: number; bytes: number; budget_day: number; budget_used: number }
    | undefined;
  if (row === undefined) return null;
  return {
    latestSeq: row.last_seq,
    e2e: row.e2e === 1,
    noteCount: row.note_count,
    bytes: row.bytes,
    budgetDay: row.budget_day,
    budgetUsed: row.budget_used,
  };
}

export interface PutResult {
  /** Stored version of every given key (in input order). */
  notes: NoteRow[];
  latestSeq: number;
  e2e: boolean;
}

export type PutOutcome =
  | { ok: true; result: PutResult }
  | {
      ok: false;
      reason: "too_many_notes" | "storage_quota" | "daily_limit" | "e2e_required" | "e2e_not_enabled" | "identity_gone";
    };

/** Per-identity limits of a notes write. */
export interface WriteLimits {
  /** Live (non-deleted) notes. */
  maxNotes: number;
  /** Sum of UTF-8 bytes of key + text/blob over all stored notes incl. tombstones. */
  maxBytes: number;
  /** Accepted note writes (inserts and overwrites, tombstones included) per UTC day. */
  dailyWrites: number;
}

/** The notes as a JSON parameter for `json_each` (data never enters SQL text). */
function encodeNotes(notes: NoteInput[]): { notesJson: string } {
  return {
    notesJson: JSON.stringify(
      notes.map((n) => ({
        k: n.key,
        e: n.exam === null ? null : n.exam ? 1 : 0,
        t: n.text,
        b: n.blob,
        u: n.updatedAt,
        d: n.deleted ? 1 : 0,
      })),
    ),
  };
}

/** Stored size of a note row (alias [a]): UTF-8 bytes of key + text + blob. */
const size = (a: string) =>
  `(length(CAST(${a}.key AS BLOB)) + coalesce(length(CAST(${a}.text AS BLOB)), 0) + ` +
  `coalesce(length(CAST(${a}.blob AS BLOB)), 0))`;

/**
 * CTE over the request (?2 = notes JSON): `c` = the given notes, `idx` =
 * position in the request.
 */
const GIVEN =
  "WITH c AS (SELECT CAST(j.key AS INTEGER) AS idx, " +
  "json_extract(j.value, '$.k') AS key, json_extract(j.value, '$.e') AS exam, " +
  "json_extract(j.value, '$.t') AS text, json_extract(j.value, '$.b') AS blob, " +
  "json_extract(j.value, '$.u') AS updated_at, json_extract(j.value, '$.d') AS deleted " +
  "FROM json_each(?2) AS j) ";

/** Notes of `c` that would be written (new key or newer than stored; ?1 = identity id), stored row as `n`. */
const NEWER_JOIN =
  "FROM c LEFT JOIN notes AS n ON n.identity_id = ?1 AND n.key = c.key " +
  "WHERE (n.key IS NULL OR n.updated_at < c.updated_at)";

/**
 * `GIVEN` + `agg`: one row summing the notes that would be written: their
 * number, the change of the live-note count, the change of the stored
 * size, and the highest request position (seqs are `base + idx + 1`). One
 * primary key lookup per given note.
 */
const AGG =
  GIVEN +
  ", agg AS MATERIALIZED (SELECT count(*) AS writes, " +
  "coalesce(sum((c.deleted = 0) - (n.key IS NOT NULL AND n.deleted = 0)), 0) AS live, " +
  `coalesce(sum(${size("c")} - coalesce(${size("n")}, 0)), 0) AS delta, ` +
  `coalesce(max(c.idx) + 1, 0) AS span ${NEWER_JOIN}) `;

/** Budget used today (?7 = today's UTC day number), from the identity row. */
const USED_TODAY = "(CASE WHEN budget_day = ?7 THEN budget_used ELSE 0 END)";

/** The stored rows of the keys in JSON array ?2 (identity ?1): one lookup per key. */
const READ_BACK =
  "SELECT n.key, n.exam, n.text, n.blob, n.updated_at, n.deleted, n.seq " +
  "FROM json_each(?2) AS j CROSS JOIN notes AS n ON n.identity_id = ?1 AND n.key = j.value";

/** Random marker of one write (16 bytes, hex). */
function newNonce(): string {
  const b = new Uint8Array(16);
  crypto.getRandomValues(b);
  return [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
}

/** Attempts before a write that keeps losing races answers "busy". */
const MAX_WRITE_ATTEMPTS = 3;

/** Thrown when a write lost races [MAX_WRITE_ATTEMPTS] times (→ 503). */
export class WriteContendedError extends Error {
  override name = "WriteContendedError";
}

type Refusal = Extract<PutOutcome, { ok: false }>["reason"];

/**
 * Last-write-wins upsert of [notes] (distinct keys) for [identityId].
 *
 * One batch (one transaction; D1 runs one at a time per database):
 * 1. the identity's state (O(1); also tells whether the identity exists),
 * 2. ONE aggregated, guarded UPDATE of the identity row: `note_count`,
 *    `bytes` and the daily budget move by the sums over the notes that will
 *    be written (`agg`), `last_seq` by the span of request positions they
 *    use, and a random nonce plus the old `last_seq` (`write_base`) are
 *    set. The mode (plaintext vs. E2E), the live-note limit, the byte quota
 *    and the daily budget are conditions of this statement (all or
 *    nothing),
 * 3. the INSERT … ON CONFLICT DO UPDATE of exactly those notes with seq
 *    `write_base + idx + 1` (idx = position in the request), only if step 2
 *    set this write's nonce; RETURNING the stored rows. The notes go in as
 *    a single JSON parameter read with `json_each`; the upsert's
 *    `WHERE excluded.updated_at > notes.updated_at` guards the update path
 *    again.
 *
 * No triggers: one written identity row per batch and one written note row
 * (+ its seq index entry, + the tombstone index entry for tombstones) per
 * written note. Only when needed, a second query reads the stored version
 * of keys that weren't written (older or tied), or — if nothing was written
 * — summarises the request to name the refusal precisely (retrying the
 * write if a concurrent change made the guards pass).
 *
 * Seqs are strictly increasing per identity and never handed out twice
 * (gaps where a note of the request wasn't written). A write that doesn't
 * grow the stored size (or the live count) passes the byte (or note) limit
 * even when over it (so deleting works); every written note, tombstones
 * included, counts against the daily budget.
 */
export async function writeNotes(
  db: D1Database,
  identityId: number,
  notes: NoteInput[],
  e2eMode: boolean,
  limits: WriteLimits,
  now: number = Date.now(),
): Promise<PutOutcome> {
  const { notesJson } = encodeNotes(notes);
  const today = Math.floor(now / DAY_MS);
  for (let attempt = 0; attempt < MAX_WRITE_ATTEMPTS; attempt++) {
    const nonce = newNonce();
    const [stateRes, updateRes, insertRes] = await db.batch([
      stateStatement(db, identityId),
      db
        .prepare(
          AGG +
            "UPDATE identities SET last_seq = last_seq + (SELECT span FROM agg), write_base = last_seq, " +
            "note_count = note_count + (SELECT live FROM agg), bytes = bytes + (SELECT delta FROM agg), " +
            `budget_used = ${USED_TODAY} + (SELECT writes FROM agg), budget_day = ?7, write_nonce = ?8 ` +
            "WHERE id = ?1 AND (SELECT writes FROM agg) > 0 " +
            "AND EXISTS (SELECT 1 FROM e2e_headers WHERE identity_id = ?1) = ?3 " +
            "AND (note_count + (SELECT live FROM agg) <= ?4 OR (SELECT live FROM agg) <= 0) " +
            "AND (bytes + (SELECT delta FROM agg) <= ?5 OR (SELECT delta FROM agg) <= 0) " +
            `AND ${USED_TODAY} + (SELECT writes FROM agg) <= ?6 ` +
            "RETURNING last_seq",
        )
        .bind(identityId, notesJson, e2eMode ? 1 : 0, limits.maxNotes, limits.maxBytes, limits.dailyWrites, today, nonce),
      db
        .prepare(
          GIVEN +
            "INSERT INTO notes (identity_id, key, exam, text, blob, updated_at, deleted, seq, stored_at) " +
            "SELECT ?1, c.key, c.exam, c.text, c.blob, c.updated_at, c.deleted, g.base + c.idx + 1, ?3 " +
            // g: one row only if step 2 set this write's nonce (else nothing is inserted).
            "FROM (SELECT write_base AS base FROM identities WHERE id = ?1 AND write_nonce = ?4) AS g " +
            "CROSS JOIN c LEFT JOIN notes AS n ON n.identity_id = ?1 AND n.key = c.key " +
            "WHERE (n.key IS NULL OR n.updated_at < c.updated_at) " +
            "ON CONFLICT (identity_id, key) DO UPDATE SET exam = excluded.exam, text = excluded.text, " +
            "blob = excluded.blob, updated_at = excluded.updated_at, deleted = excluded.deleted, " +
            "seq = excluded.seq, stored_at = excluded.stored_at WHERE excluded.updated_at > notes.updated_at " +
            `RETURNING ${NOTE_COLUMNS}`,
        )
        .bind(identityId, notesJson, now, nonce),
    ]);
    const before = readState(stateRes!);
    if (before === null) return { ok: false, reason: "identity_gone" };
    const updated = updateRes!.results[0] as { last_seq: number } | undefined;
    if (updated === undefined) {
      // Nothing written. Wrong mode is known from the same snapshot.
      if (before.e2e !== e2eMode) return { ok: false, reason: before.e2e ? "e2e_required" : "e2e_not_enabled" };
      const check = await refusal(db, identityId, notes, notesJson, limits, today);
      if (check === "retry") continue; // a concurrent change made the guards pass
      if (typeof check === "string") return { ok: false, reason: check };
      return { ok: true, result: { notes: check, latestSeq: before.latestSeq, e2e: before.e2e } };
    }
    const rows = new Map((insertRes!.results as unknown as NoteRow[]).map((r) => [r.key, r]));
    const unwritten = notes.filter((n) => !rows.has(n.key)).map((n) => n.key);
    if (unwritten.length > 0) {
      // Older/tied notes: their stored version (read after the batch; it
      // can only be at least as new as at the write).
      const back = await db.prepare(READ_BACK).bind(identityId, JSON.stringify(unwritten)).all();
      for (const r of back.results as unknown as NoteRow[]) rows.set(r.key, r);
    }
    return { ok: true, result: { notes: inOrder(notes, rows), latestSeq: updated.last_seq, e2e: before.e2e } };
  }
  throw new WriteContendedError();
}

function inOrder(notes: NoteInput[], rows: Map<string, NoteRow>): NoteRow[] {
  const out: NoteRow[] = [];
  for (const n of notes) {
    const r = rows.get(n.key);
    if (r !== undefined) out.push(r);
  }
  return out;
}

/**
 * A write that wrote nothing (mode was right): one batch with the request
 * summary and the stored rows. Returns the stored rows if nothing was newer
 * (fine), else the refusal, or "retry" if no guard fails any more.
 */
async function refusal(
  db: D1Database,
  identityId: number,
  notes: NoteInput[],
  notesJson: string,
  limits: WriteLimits,
  today: number,
): Promise<NoteRow[] | Refusal | "retry"> {
  const [plan, back] = await db.batch([
    db
      .prepare(
        AGG +
          `SELECT agg.writes, agg.live, agg.delta, i.note_count, i.bytes, ${USED_TODAY} AS used ` +
          "FROM agg, identities AS i WHERE i.id = ?1",
      )
      .bind(identityId, notesJson, null, null, null, null, today),
    db.prepare(READ_BACK).bind(identityId, JSON.stringify(notes.map((n) => n.key))),
  ]);
  const row = plan!.results[0] as
    | { writes: number; live: number; delta: number; note_count: number; bytes: number; used: number }
    | undefined;
  if (row === undefined) return "identity_gone";
  if (row.writes === 0) {
    return inOrder(notes, new Map((back!.results as unknown as NoteRow[]).map((r) => [r.key, r])));
  }
  if (row.used + row.writes > limits.dailyWrites) return "daily_limit";
  if (row.live > 0 && row.note_count + row.live > limits.maxNotes) return "too_many_notes";
  if (row.delta > 0 && row.bytes + row.delta > limits.maxBytes) return "storage_quota";
  return "retry";
}

/** Server-side age after which tombstones are purged (daily cron). */
export const TOMBSTONE_MAX_AGE_MS = 400 * 24 * 60 * 60 * 1000;

/**
 * Deletes up to [limit] tombstones whose row wasn't written since
 * [olderThan] (server time); returns how many. One batch: the affected
 * identities' `bytes` drop by the purged sizes (one aggregated UPDATE per
 * identity; tombstones don't count in `note_count`), then the same rows
 * (deterministic order over the partial index) are deleted. `last_seq`
 * stays (seqs never go back).
 */
export async function purgeTombstones(db: D1Database, olderThan: number, limit = 1000): Promise<number> {
  const victims =
    "SELECT identity_id, key FROM notes WHERE deleted = 1 AND stored_at < ?1 " +
    "ORDER BY stored_at, identity_id, key LIMIT ?2";
  const [, del] = await db.batch([
    db
      .prepare(
        `WITH v AS MATERIALIZED (${victims}), ` +
          `s AS (SELECT n.identity_id, sum(${size("n")}) AS sz FROM v ` +
          "JOIN notes AS n ON n.identity_id = v.identity_id AND n.key = v.key GROUP BY n.identity_id) " +
          "UPDATE identities SET bytes = bytes - s.sz FROM s WHERE identities.id = s.identity_id",
      )
      .bind(olderThan, limit),
    db.prepare(`DELETE FROM notes WHERE (identity_id, key) IN (${victims})`).bind(olderThan, limit),
  ]);
  return del!.meta.changes ?? 0;
}

/**
 * Deletes up to [limit] expired sessions; returns how many (daily cron).
 */
export async function purgeExpiredSessions(db: D1Database, now: number, limit = 1000): Promise<number> {
  const r = await db
    .prepare(
      "DELETE FROM sessions WHERE token_hash IN " +
        "(SELECT token_hash FROM sessions WHERE expires_at <= ?1 LIMIT ?2)",
    )
    .bind(now, limit)
    .run();
  return r.meta.changes ?? 0;
}

// --- e2e header -------------------------------------------------------------

/**
 * The identity's header JSON, null without one, or undefined if the
 * identity row doesn't exist (any more).
 */
export async function getE2eHeader(db: D1Database, identityId: number): Promise<string | null | undefined> {
  const row = await db
    .prepare(
      "SELECT h.header FROM identities AS i LEFT JOIN e2e_headers AS h ON h.identity_id = i.id WHERE i.id = ?1",
    )
    .bind(identityId)
    .first<{ header: string | null }>();
  return row === null ? undefined : row.header;
}

/**
 * Stores the header if the identity has none yet and, in the same batch,
 * deletes the identity's plaintext notes (they must not stay on the server
 * once E2E is on; seqs are kept, `last_seq` doesn't go back) and zeroes its
 * counters. Returns "created", "exists" (nothing changed) or "gone" (no
 * identity row).
 */
export async function createE2eHeader(
  db: D1Database,
  identityId: number,
  header: string,
  now: number,
): Promise<"created" | "exists" | "gone"> {
  const noHeader = "NOT EXISTS (SELECT 1 FROM e2e_headers WHERE identity_id = ?1)";
  const [counters, insert] = await db.batch([
    // Without a header only plaintext notes can exist (PUT /notes enforces
    // the mode atomically) and all of them are deleted below, so the
    // counters become 0. Runs before the insert, with the same condition.
    db
      .prepare(`UPDATE identities SET note_count = 0, bytes = 0 WHERE id = ?1 AND ${noHeader} RETURNING id`)
      .bind(identityId),
    db
      .prepare(
        "INSERT INTO e2e_headers (identity_id, header, created_at) " +
          "SELECT ?1, ?2, ?3 WHERE EXISTS (SELECT 1 FROM identities WHERE id = ?1) " +
          "ON CONFLICT (identity_id) DO NOTHING RETURNING identity_id",
      )
      .bind(identityId, header, now),
    // A no-op when a header already existed (then all notes are encrypted).
    db.prepare("DELETE FROM notes WHERE identity_id = ?1 AND blob IS NULL").bind(identityId),
  ]);
  if (insert!.results.length > 0) return "created";
  if (counters!.results.length === 0 && (await getE2eHeader(db, identityId)) === undefined) return "gone";
  return "exists";
}

/**
 * Replaces the identity's header only if its stored `authHash` is still
 * [authHash] (the caller verified the auth key against it; this guards a
 * concurrent reset + new header). Returns "replaced", "missing" or
 * "mismatch".
 */
export async function replaceE2eHeader(
  db: D1Database,
  identityId: number,
  header: string,
  authHash: string,
): Promise<"replaced" | "missing" | "mismatch"> {
  const updated = await db
    .prepare(
      "UPDATE e2e_headers SET header = ?2 " +
        "WHERE identity_id = ?1 AND json_extract(header, '$.authHash') = ?3 RETURNING identity_id",
    )
    .bind(identityId, header, authHash)
    .all();
  if (updated.results.length > 0) return "replaced";
  return (await getE2eHeader(db, identityId)) == null ? "missing" : "mismatch";
}

/**
 * Turns E2E off: deletes the identity's notes and header and zeroes its
 * counters in one batch, but only if the header's authHash is still
 * [authHash] (verified by the caller). Sessions and last_seq stay.
 */
export async function deleteE2e(
  db: D1Database,
  identityId: number,
  authHash: string,
): Promise<"deleted" | "missing" | "mismatch"> {
  const guard = "EXISTS (SELECT 1 FROM e2e_headers WHERE identity_id = ?1 AND json_extract(header, '$.authHash') = ?2)";
  const [, , header] = await db.batch([
    db.prepare(`UPDATE identities SET note_count = 0, bytes = 0 WHERE id = ?1 AND ${guard}`).bind(identityId, authHash),
    db.prepare(`DELETE FROM notes WHERE identity_id = ?1 AND ${guard}`).bind(identityId, authHash),
    db
      .prepare(
        "DELETE FROM e2e_headers WHERE identity_id = ?1 AND json_extract(header, '$.authHash') = ?2 " +
          "RETURNING identity_id",
      )
      .bind(identityId, authHash),
  ]);
  if (header!.results.length > 0) return "deleted";
  return (await getE2eHeader(db, identityId)) == null ? "missing" : "mismatch";
}
