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

export interface SessionInfo {
  identityId: number;
  identity: SyncIdentity;
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
 * Creates the identity if needed and a session for it, purges up to
 * [PURGE_BATCH] expired sessions and trims old sessions of the identity, in
 * one batch. Returns whether the identity has an E2E header.
 */
export async function createSession(
  db: D1Database,
  tokenHash: string,
  who: SyncIdentity,
  now: number,
  expiresAt: number,
): Promise<{ e2e: boolean }> {
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
        "INSERT INTO identities (host, school, user_id, created_at) VALUES (?1, ?2, ?3, ?4) " +
          "ON CONFLICT (host, school, user_id) DO NOTHING",
      )
      .bind(who.host, who.school, who.userId, now),
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
      .prepare(`SELECT EXISTS (SELECT 1 FROM e2e_headers WHERE identity_id = (${idOf})) AS e2e`)
      .bind(who.host, who.school, who.userId),
  ]);
  const row = results[4]!.results[0] as { e2e: number } | undefined;
  return { e2e: row?.e2e === 1 };
}

/** The unexpired session for [tokenHash], or null. */
export async function findSession(db: D1Database, tokenHash: string, now: number): Promise<SessionInfo | null> {
  const row = await db
    .prepare(
      "SELECT s.identity_id, s.expires_at, i.host, i.school, i.user_id " +
        "FROM sessions AS s JOIN identities AS i ON i.id = s.identity_id " +
        "WHERE s.token_hash = ?1 AND s.expires_at > ?2",
    )
    .bind(tokenHash, now)
    .first<{ identity_id: number; expires_at: number; host: string; school: string; user_id: string }>();
  if (row === null) return null;
  return {
    identityId: row.identity_id,
    identity: { host: row.host, school: row.school, userId: row.user_id },
    expiresAt: row.expires_at,
  };
}

export async function deleteSession(db: D1Database, tokenHash: string): Promise<void> {
  await db.prepare("DELETE FROM sessions WHERE token_hash = ?1").bind(tokenHash).run();
}

// --- account ----------------------------------------------------------------

/** Deletes the identity and everything belonging to it (one batch). */
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

/** Notes changed after [since] (ordered by seq, at most [limit]) plus the identity's state. */
export async function changes(
  db: D1Database,
  identityId: number,
  since: number,
  limit: number,
): Promise<{ notes: NoteRow[]; latestSeq: number; e2e: boolean }> {
  const [notes, state] = await db.batch([
    db
      .prepare(`SELECT ${NOTE_COLUMNS} FROM notes WHERE identity_id = ?1 AND seq > ?2 ORDER BY seq LIMIT ?3`)
      .bind(identityId, since, limit),
    stateStatement(db, identityId),
  ]);
  return { notes: notes!.results as unknown as NoteRow[], ...readState(state!) };
}

function stateStatement(db: D1Database, identityId: number): D1PreparedStatement {
  return db
    .prepare(
      "SELECT last_seq, EXISTS (SELECT 1 FROM e2e_headers WHERE identity_id = ?1) AS e2e, " +
        "(SELECT count(*) FROM notes WHERE identity_id = ?1) AS note_count " +
        "FROM identities WHERE id = ?1",
    )
    .bind(identityId);
}

function readState(r: D1Result): { latestSeq: number; e2e: boolean; noteCount: number } {
  const row = r.results[0] as { last_seq: number; e2e: number; note_count: number } | undefined;
  return { latestSeq: row?.last_seq ?? 0, e2e: row?.e2e === 1, noteCount: row?.note_count ?? 0 };
}

export interface PutResult {
  /** Stored version of every given key (in input order). */
  notes: NoteRow[];
  latestSeq: number;
  e2e: boolean;
}

export type PutOutcome =
  | { ok: true; result: PutResult }
  | { ok: false; reason: "too_many_notes" | "e2e_required" | "e2e_not_enabled" };

/** The notes as JSON parameters for `json_each` (data never enters SQL text). */
function encodeNotes(notes: NoteInput[]): { keysJson: string; notesJson: string } {
  return {
    keysJson: JSON.stringify(notes.map((n) => n.key)),
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

/**
 * Last-write-wins upsert of [notes] (distinct keys) for [identityId].
 *
 * The write is ONE statement (plus the seq bookkeeping in the same batch):
 * the notes go in as a single JSON parameter, read with `json_each`. Only
 * notes newer than the stored version are selected; they get the seqs
 * `last_seq + 1, + 2, ...` (row_number), the upsert's `WHERE
 * excluded.updated_at > notes.updated_at` guards the update path again, and
 * the next statement raises `identities.last_seq` to the highest seq in use.
 * The mode (plaintext vs. E2E) and the per-user note limit are conditions
 * of the same statement, so a concurrent request can't slip past them. All
 * of that runs in one `db.batch()` (one transaction; D1 runs one at a time
 * per database), so seqs are strictly increasing per identity and never
 * handed out twice.
 */
export async function putNotes(
  db: D1Database,
  identityId: number,
  notes: NoteInput[],
  e2eMode: boolean,
  maxNotes: number,
): Promise<PutOutcome> {
  const { keysJson } = encodeNotes(notes);

  // Pre-check (consistent snapshot) for precise errors; the write below
  // re-checks the same conditions atomically.
  const [state, known] = await db.batch([
    stateStatement(db, identityId),
    db
      .prepare("SELECT count(*) AS c FROM notes WHERE identity_id = ?1 AND key IN (SELECT value FROM json_each(?2))")
      .bind(identityId, keysJson),
  ]);
  const before = readState(state!);
  if (before.e2e !== e2eMode) return { ok: false, reason: before.e2e ? "e2e_required" : "e2e_not_enabled" };
  const knownCount = (known!.results[0] as { c: number }).c;
  if (before.noteCount + (notes.length - knownCount) > maxNotes) return { ok: false, reason: "too_many_notes" };
  return writeNotes(db, identityId, notes, e2eMode, maxNotes);
}

/**
 * The write half of [putNotes] without the pre-check (exported for tests:
 * the mode and quota guards inside the statement must hold on their own).
 */
export async function writeNotes(
  db: D1Database,
  identityId: number,
  notes: NoteInput[],
  e2eMode: boolean,
  maxNotes: number,
): Promise<PutOutcome> {
  const { keysJson, notesJson } = encodeNotes(notes);
  const results = await db.batch([
    db
      .prepare(
        "INSERT INTO notes (identity_id, key, exam, text, blob, updated_at, deleted, seq) " +
          "SELECT ?1, c.key, c.exam, c.text, c.blob, c.updated_at, c.deleted, " +
          "(SELECT last_seq FROM identities WHERE id = ?1) + row_number() OVER (ORDER BY c.idx) " +
          "FROM (SELECT CAST(j.key AS INTEGER) AS idx, " +
          "json_extract(j.value, '$.k') AS key, json_extract(j.value, '$.e') AS exam, " +
          "json_extract(j.value, '$.t') AS text, json_extract(j.value, '$.b') AS blob, " +
          "json_extract(j.value, '$.u') AS updated_at, json_extract(j.value, '$.d') AS deleted " +
          "FROM json_each(?2) AS j) AS c " +
          "WHERE NOT EXISTS (SELECT 1 FROM notes AS n " +
          "WHERE n.identity_id = ?1 AND n.key = c.key AND n.updated_at >= c.updated_at) " +
          "AND EXISTS (SELECT 1 FROM e2e_headers WHERE identity_id = ?1) = ?3 " +
          "AND (SELECT count(*) FROM notes WHERE identity_id = ?1) + " +
          "(SELECT count(*) FROM json_each(?2) AS f WHERE NOT EXISTS (SELECT 1 FROM notes AS m " +
          "WHERE m.identity_id = ?1 AND m.key = json_extract(f.value, '$.k'))) <= ?4 " +
          "ON CONFLICT (identity_id, key) DO UPDATE SET exam = excluded.exam, text = excluded.text, " +
          "blob = excluded.blob, updated_at = excluded.updated_at, deleted = excluded.deleted, " +
          "seq = excluded.seq WHERE excluded.updated_at > notes.updated_at " +
          "RETURNING key",
      )
      .bind(identityId, notesJson, e2eMode ? 1 : 0, maxNotes),
    db
      .prepare(
        "UPDATE identities SET last_seq = max(last_seq, " +
          "coalesce((SELECT max(seq) FROM notes WHERE identity_id = ?1), 0)) WHERE id = ?1",
      )
      .bind(identityId),
    db
      .prepare(`SELECT ${NOTE_COLUMNS} FROM notes WHERE identity_id = ?1 AND key IN (SELECT value FROM json_each(?2))`)
      .bind(identityId, keysJson),
    stateStatement(db, identityId),
  ]);
  const after = readState(results[3]!);
  const written = results[0]!.results.length;
  const rows = new Map((results[2]!.results as unknown as NoteRow[]).map((r) => [r.key, r]));
  if (written === 0) {
    // Nothing was written: either nothing was newer, or a concurrent
    // request changed the mode or filled the quota in between.
    if (after.e2e !== e2eMode) return { ok: false, reason: after.e2e ? "e2e_required" : "e2e_not_enabled" };
    const missing = notes.filter((n) => !rows.has(n.key)).length;
    if (missing > 0 && after.noteCount + missing > maxNotes) return { ok: false, reason: "too_many_notes" };
  }
  const stored: NoteRow[] = [];
  for (const n of notes) {
    const r = rows.get(n.key);
    if (r !== undefined) stored.push(r);
  }
  return { ok: true, result: { notes: stored, latestSeq: after.latestSeq, e2e: after.e2e } };
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

export async function getE2eHeader(db: D1Database, identityId: number): Promise<string | null> {
  const row = await db
    .prepare("SELECT header FROM e2e_headers WHERE identity_id = ?1")
    .bind(identityId)
    .first<{ header: string }>();
  return row?.header ?? null;
}

/**
 * Stores the header if the identity has none yet and, in the same batch,
 * deletes the identity's plaintext notes (they must not stay on the server
 * once E2E is on; seqs are kept, `last_seq` doesn't go back). Returns false
 * (nothing changed) if a header already exists.
 */
export async function createE2eHeader(
  db: D1Database,
  identityId: number,
  header: string,
  now: number,
): Promise<boolean> {
  const [insert] = await db.batch([
    db
      .prepare(
        "INSERT INTO e2e_headers (identity_id, header, created_at) VALUES (?1, ?2, ?3) " +
          "ON CONFLICT (identity_id) DO NOTHING RETURNING identity_id",
      )
      .bind(identityId, header, now),
    // Only plaintext notes can exist without a header (PUT /notes enforces
    // the mode atomically), so this is a no-op when the insert didn't happen.
    db.prepare("DELETE FROM notes WHERE identity_id = ?1 AND blob IS NULL").bind(identityId),
  ]);
  return insert!.results.length > 0;
}

/**
 * Replaces the identity's header only if it exists and its `check` equals
 * [check] (the new header must keep the same data key: passphrase change,
 * new recovery code). Returns "replaced", "missing" or "mismatch".
 */
export async function replaceE2eHeader(
  db: D1Database,
  identityId: number,
  header: string,
  check: string,
): Promise<"replaced" | "missing" | "mismatch"> {
  const updated = await db
    .prepare(
      "UPDATE e2e_headers SET header = ?2 " +
        "WHERE identity_id = ?1 AND json_extract(header, '$.check') = ?3 RETURNING identity_id",
    )
    .bind(identityId, header, check)
    .all();
  if (updated.results.length > 0) return "replaced";
  return (await getE2eHeader(db, identityId)) === null ? "missing" : "mismatch";
}
