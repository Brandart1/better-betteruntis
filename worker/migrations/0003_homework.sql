-- The user's own homework of a lesson (plaintext accounts; next to exam and
-- text). Additive: old app versions don't send it and get it ignored, rows
-- written before this migration have none. E2E rows keep '' (their content,
-- homework included, is inside the blob). Counts in identities.bytes like
-- text.
ALTER TABLE notes ADD COLUMN homework TEXT NOT NULL DEFAULT '';
