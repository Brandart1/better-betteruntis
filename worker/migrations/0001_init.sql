-- Notes sync schema (docs/SYNC-PLAN.md, step 2). D1 enforces foreign keys,
-- so deleting an identity cascades to its notes, sessions and E2E header
-- (the account deletion also deletes them explicitly).

-- One WebUntis user of one school, as verified with WebUntis itself.
CREATE TABLE identities (
  -- AUTOINCREMENT: ids of deleted identities are never handed out again.
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  host TEXT NOT NULL,
  school TEXT NOT NULL,
  user_id TEXT NOT NULL,
  -- Highest seq ever handed out for this identity (never decreases, also
  -- not when notes are deleted), so seqs stay strictly increasing.
  last_seq INTEGER NOT NULL DEFAULT 0,
  -- Number of stored notes (incl. tombstones) and their size in bytes
  -- (UTF-8 key + text/blob), kept up to date by the triggers below so the
  -- quota checks never scan the notes (D1 bills rows read).
  note_count INTEGER NOT NULL DEFAULT 0,
  bytes INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  UNIQUE (host, school, user_id)
) STRICT;

-- The user's lesson notes. Plaintext accounts: exam + text, blob NULL.
-- E2E accounts: blob (base64url ciphertext), exam/text NULL, key = HMAC.
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
CREATE UNIQUE INDEX notes_identity_seq ON notes (identity_id, seq);
-- Only tombstones, for the purge.
CREATE INDEX notes_tombstones ON notes (stored_at) WHERE deleted = 1;

-- identities.note_count / bytes follow every change of notes, in the same
-- statement (so also in the same batch/transaction as the write). A
-- cascade from a deleted identity updates nothing (the row is gone).
CREATE TRIGGER notes_counters_insert AFTER INSERT ON notes
BEGIN
  UPDATE identities SET note_count = note_count + 1,
    bytes = bytes + length(CAST(NEW.key AS BLOB))
      + coalesce(length(CAST(NEW.text AS BLOB)), 0) + coalesce(length(CAST(NEW.blob AS BLOB)), 0)
  WHERE id = NEW.identity_id;
END;

CREATE TRIGGER notes_counters_update AFTER UPDATE OF key, text, blob ON notes
BEGIN
  UPDATE identities SET
    bytes = bytes
      + length(CAST(NEW.key AS BLOB)) + coalesce(length(CAST(NEW.text AS BLOB)), 0) + coalesce(length(CAST(NEW.blob AS BLOB)), 0)
      - length(CAST(OLD.key AS BLOB)) - coalesce(length(CAST(OLD.text AS BLOB)), 0) - coalesce(length(CAST(OLD.blob AS BLOB)), 0)
  WHERE id = NEW.identity_id;
END;

CREATE TRIGGER notes_counters_delete AFTER DELETE ON notes
BEGIN
  UPDATE identities SET note_count = note_count - 1,
    bytes = bytes - length(CAST(OLD.key AS BLOB))
      - coalesce(length(CAST(OLD.text AS BLOB)), 0) - coalesce(length(CAST(OLD.blob AS BLOB)), 0)
  WHERE id = OLD.identity_id;
END;

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
