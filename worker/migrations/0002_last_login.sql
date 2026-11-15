-- Inactive sync accounts are deleted after 12 months without a login
-- (privacy notice, retention). last_login = time of the newest session
-- creation (also silent re-logins); existing rows start at created_at.
ALTER TABLE identities ADD COLUMN last_login INTEGER NOT NULL DEFAULT 0;
UPDATE identities SET last_login = created_at;
CREATE INDEX identities_last_login ON identities (last_login);
