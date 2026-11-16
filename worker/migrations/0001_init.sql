-- Notes sync schema (docs/SYNC-PLAN.md, step 2). D1 enforces foreign keys,
-- so deleting an identity cascades to its notes, sessions and E2E header
-- (the account deletion also deletes them explicitly).
--
-- IMPORTANT: this file may only be edited in place until the first deploy.
-- After that, every schema change must be a NEW migration file
-- (0002_....sql), additive, and work with the version that is live.

-- One WebUntis user of one school, as verified with WebUntis itself.
CREATE TABLE identities (
  -- AUTOINCREMENT: ids of deleted identities are never handed out again.
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  host TEXT NOT NULL,
  school TEXT NOT NULL,
  user_id TEXT NOT NULL,
  -- Random tag of this incarnation of the identity (16 random bytes,
  -- base64url, 22 chars), set once on insert and never updated. A deleted
  -- and re-created identity gets a new epoch, so clients can tell "same
  -- account" from "deleted and created again" (the id isn't exposed: it
  -- would leak user counts). A Time Travel restore keeps it.
  epoch TEXT NOT NULL CHECK (length(epoch) = 22),
  -- Highest seq ever handed out for this identity (never decreases, also
  -- not when notes are deleted), so seqs stay strictly increasing.
  last_seq INTEGER NOT NULL DEFAULT 0,
  -- Number of live (non-deleted) notes and the size in bytes of all stored
  -- notes incl. tombstones (UTF-8 key + text/blob). Maintained by explicit,
  -- aggregated UPDATEs in the same batch as every change of notes (no
  -- per-row triggers: D1 bills every row written), so the quota checks
  -- never scan the notes.
  note_count INTEGER NOT NULL DEFAULT 0,
  bytes INTEGER NOT NULL DEFAULT 0,
  -- Daily write budget: UTC day number (ms / 86 400 000) of budget_used,
  -- the number of note writes accepted on that day.
  budget_day INTEGER NOT NULL DEFAULT 0,
  budget_used INTEGER NOT NULL DEFAULT 0,
  -- Set by the guarded counter UPDATE of a notes write: a random
  -- per-request marker and last_seq before the write; the INSERT of the
  -- same batch only runs if the marker matches and numbers its notes from
  -- write_base (src/sync/db.ts writeNotes).
  write_nonce TEXT,
  write_base INTEGER,
  created_at INTEGER NOT NULL,
  UNIQUE (host, school, user_id)
) STRICT;

-- The user's lesson notes. Plaintext accounts: exam + text, blob NULL
-- (tombstones are stored blanked: text '', exam 0). E2E accounts: blob
-- (base64url ciphertext), exam/text NULL, key = HMAC.
CREATE TABLE notes (
  identity_id INTEGER NOT NULL REFERENCES identities (id) ON DELETE CASCADE,
  key TEXT NOT NULL,
  exam INTEGER,
  text TEXT,
  blob TEXT,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL CHECK (deleted IN (0, 1)),
  seq INTEGER NOT NULL,
  -- Server time (ms) of the last write of this row; the daily cron purges
  -- tombstones not written for 400 days (updated_at is the client's clock).
  stored_at INTEGER NOT NULL,
  PRIMARY KEY (identity_id, key),
  CHECK (
    (blob IS NULL AND exam IN (0, 1) AND text IS NOT NULL)
    OR (blob IS NOT NULL AND exam IS NULL AND text IS NULL)
  )
) STRICT, WITHOUT ROWID;
-- Pulls (seq > since ORDER BY seq). Costs one extra written row per note
-- write, but keeps every pull at ~1 row read per returned note.
CREATE UNIQUE INDEX notes_identity_seq ON notes (identity_id, seq);
-- Only tombstones, for the purge (deterministic order: stored_at, then PK).
CREATE INDEX notes_tombstones ON notes (stored_at, identity_id, key) WHERE deleted = 1;

-- Sessions: only the SHA-256 (hex) of the token is stored.
CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  identity_id INTEGER NOT NULL REFERENCES identities (id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
) STRICT, WITHOUT ROWID;
CREATE INDEX sessions_identity ON sessions (identity_id, created_at);
CREATE INDEX sessions_expires ON sessions (expires_at);

-- End-to-end encryption header (salt, KDF params, wrapped keys), one per
-- identity; the JSON is validated and re-serialized by the Worker.
CREATE TABLE e2e_headers (
  identity_id INTEGER PRIMARY KEY REFERENCES identities (id) ON DELETE CASCADE,
  header TEXT NOT NULL,
  created_at INTEGER NOT NULL
) STRICT;
