import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { LIMITS } from "../../src/sync/notes";
import { AUTH_HASH, AUTH_KEY, authHashOf, b64, blobNote, call, e2eHeader, freshUser, get, identityId, login, note, put, req } from "./helpers";

async function errorOf(res: Response): Promise<string> {
  return ((await res.json()) as { error: string }).error;
}

const putHeader = (token: string, body: unknown) => call(req("PUT", "/api/sync/e2e", { token, body }));
const getHeader = (token: string) => call(req("GET", "/api/sync/e2e", { token }));

describe("E2E header", () => {
  it("GET without header -> 404 e2e_not_enabled", async () => {
    const s = await login(freshUser());
    const res = await getHeader(s.token);
    expect([res.status, await errorOf(res)]).toEqual([404, "e2e_not_enabled"]);
  });

  it("PUT creates it once (201), GET returns it, second PUT -> 409 e2e_exists", async () => {
    const user = freshUser();
    const s = await login(user);
    const header = e2eHeader();
    const res = await putHeader(s.token, { ...header, extra: "dropped", kdf: { ...(header["kdf"] as object), junk: 1 } });
    expect(res.status).toBe(201);
    expect(await res.json()).toEqual(header);
    expect(await (await getHeader(s.token)).json()).toEqual(header);
    const again = await putHeader(s.token, e2eHeader({ wrappedDek: b64(72, 9) }));
    expect([again.status, await errorOf(again)]).toEqual([409, "e2e_exists"]);
    expect(await (await getHeader(s.token)).json()).toEqual(header);
    // A new login reports e2e: true.
    expect((await login(user)).body.e2e).toBe(true);
  });

  it("maximum KDF parameters are accepted", async () => {
    const s = await login(freshUser());
    const res = await putHeader(s.token, e2eHeader({ kdf: { alg: "argon2id", m: 262144, t: 16, p: 16, salt: b64(16) } }));
    expect(res.status).toBe(201);
  });

  it("wrappedDekRecovery is optional", async () => {
    const s = await login(freshUser());
    const header = e2eHeader();
    delete header["wrappedDekRecovery"];
    const res = await putHeader(s.token, header);
    expect(res.status).toBe(201);
    expect(await res.json()).not.toHaveProperty("wrappedDekRecovery");
  });

  it("concurrent creation: exactly one wins", async () => {
    const user = freshUser();
    const sessions = await Promise.all([login(user), login(user), login(user)]);
    const results = await Promise.all(sessions.map((s, i) => putHeader(s.token, e2eHeader({ check: b64(56, 10 + i) }))));
    expect(results.map((r) => r.status).sort()).toEqual([201, 409, 409]);
  });

  const bad: [string, Record<string, unknown>][] = [
    ["version 2", { version: 2 }],
    ["version string", { version: "1" }],
    ["alg", { kdf: { alg: "pbkdf2", m: 19456, t: 2, p: 1, salt: b64(16) } }],
    ["m too small", { kdf: { alg: "argon2id", m: 10, t: 2, p: 1, salt: b64(16) } }],
    ["t fraction", { kdf: { alg: "argon2id", m: 19456, t: 1.5, p: 1, salt: b64(16) } }],
    ["salt too short", { kdf: { alg: "argon2id", m: 19456, t: 2, p: 1, salt: b64(8) } }],
    ["salt not base64url", { kdf: { alg: "argon2id", m: 19456, t: 2, p: 1, salt: "a+b/c=dddddddddddddddddddddd" } }],
    ["kdf missing", { kdf: undefined }],
    ["wrappedDek missing", { wrappedDek: undefined }],
    ["wrappedDek too long", { wrappedDek: "A".repeat(600) }],
    ["wrappedDekRecovery number", { wrappedDekRecovery: 5 }],
    ["check missing", { check: undefined }],
    ["m below 19456", { kdf: { alg: "argon2id", m: 19455, t: 2, p: 1, salt: b64(16) } }],
    ["m above 262144", { kdf: { alg: "argon2id", m: 262145, t: 2, p: 1, salt: b64(16) } }],
    ["t 1", { kdf: { alg: "argon2id", m: 19456, t: 1, p: 1, salt: b64(16) } }],
    ["t 17", { kdf: { alg: "argon2id", m: 19456, t: 17, p: 1, salt: b64(16) } }],
    ["p 0", { kdf: { alg: "argon2id", m: 19456, t: 2, p: 0, salt: b64(16) } }],
    ["p 17", { kdf: { alg: "argon2id", m: 19456, t: 2, p: 17, salt: b64(16) } }],
    ["salt 15 bytes", { kdf: { alg: "argon2id", m: 19456, t: 2, p: 1, salt: b64(15) } }],
    ["salt 17 bytes", { kdf: { alg: "argon2id", m: 19456, t: 2, p: 1, salt: b64(17) } }],
    ["salt 32 bytes", { kdf: { alg: "argon2id", m: 19456, t: 2, p: 1, salt: b64(32) } }],
    ["authHash missing", { authHash: undefined }],
    ["authHash 42 chars", { authHash: AUTH_HASH.slice(0, 42) }],
    ["authHash 44 chars", { authHash: AUTH_HASH + "A" }],
    ["authHash not base64url", { authHash: "+" + AUTH_HASH.slice(1) }],
  ];
  for (const [name, overrides] of bad) {
    it(`invalid header (${name}) -> 400, nothing stored`, async () => {
      const s = await login(freshUser());
      const res = await putHeader(s.token, JSON.parse(JSON.stringify(e2eHeader(overrides))));
      expect([res.status, await errorOf(res)]).toEqual([400, "bad_request"]);
      expect((await getHeader(s.token)).status).toBe(404);
    });
  }

  it("too large body -> 413", async () => {
    const s = await login(freshUser());
    const res = await putHeader(s.token, e2eHeader({ pad: "x".repeat(5000) }));
    expect(res.status).toBe(413);
  });

  it("turning E2E on deletes the plaintext notes on the server; seq keeps increasing", async () => {
    const s = await login(freshUser());
    expect((await put(s.token, [note("a", 1, "secret"), note("b", 2)])).status).toBe(200);
    expect((await putHeader(s.token, e2eHeader())).status).toBe(201);
    const page = await get(s.token);
    expect(page.notes).toEqual([]);
    expect(page.e2e).toBe(true);
    expect(page.latestSeq).toBe(2);
    const res = await put(s.token, [blobNote(1, 5)]);
    expect(res.status).toBe(200);
    expect(((await res.json()) as { notes: { seq: number }[] }).notes[0]!.seq).toBe(3);
  });

  it("reset via DELETE /api/sync/account allows a new header", async () => {
    const user = freshUser();
    const s = await login(user);
    await putHeader(s.token, e2eHeader());
    await call(req("DELETE", "/api/sync/account", { token: s.token }));
    const s2 = await login(user);
    expect(s2.body.e2e).toBe(false);
    expect((await putHeader(s2.token, e2eHeader({ check: b64(56, 99) }))).status).toBe(201);
  });
});

describe("E2E notes", () => {
  it("without header, blob notes -> 409 e2e_not_enabled", async () => {
    const s = await login(freshUser());
    const res = await put(s.token, [blobNote(1, 1)]);
    expect([res.status, await errorOf(res)]).toEqual([409, "e2e_not_enabled"]);
    expect((await get(s.token)).notes).toEqual([]);
  });

  it("with header, plaintext notes -> 409 e2e_required", async () => {
    const s = await login(freshUser());
    await putHeader(s.token, e2eHeader());
    const res = await put(s.token, [note("a", 1)]);
    expect([res.status, await errorOf(res)]).toEqual([409, "e2e_required"]);
    expect((await get(s.token)).notes).toEqual([]);
  });

  it("blob notes: stored opaque, LWW by updatedAt, tombstones are encrypted records", async () => {
    const s = await login(freshUser());
    await putHeader(s.token, e2eHeader());
    const n1 = blobNote(1, 10);
    let res = await put(s.token, [n1, blobNote(2, 11)]);
    expect(res.status).toBe(200);
    const out = (await res.json()) as { notes: unknown[]; e2e: boolean };
    expect(out.e2e).toBe(true);
    expect(out.notes[0]).toEqual({ ...n1, seq: 1 });
    // Older loses, newer (tombstone) wins.
    await put(s.token, [{ ...n1, blob: b64(280, 50), updatedAt: 9 }]);
    res = await put(s.token, [{ ...n1, blob: b64(300, 51), updatedAt: 12, deleted: true }]);
    expect(((await res.json()) as { notes: unknown[] }).notes[0]).toEqual({ key: n1.key, blob: b64(300, 51), updatedAt: 12, deleted: true, seq: 3 });
    const page = await get(s.token);
    expect(page.notes.map((n) => Object.keys(n).sort())).toEqual([
      ["blob", "deleted", "key", "seq", "updatedAt"],
      ["blob", "deleted", "key", "seq", "updatedAt"],
    ]);
    const row = await env.DB.prepare("SELECT exam, text, blob FROM notes WHERE identity_id = ? AND key = ?")
      .bind(await identityId(s.body.identity.userId), n1.key)
      .first();
    expect(row).toEqual({ exam: null, text: null, blob: b64(300, 51) });
  });

  it("invalid encrypted notes -> 400", async () => {
    const s = await login(freshUser());
    await putHeader(s.token, e2eHeader());
    const cases: unknown[] = [
      { ...blobNote(1, 1), key: "short" },
      { ...blobNote(1, 1), key: "x".repeat(42) + "+" },
      { ...blobNote(1, 1), blob: "" },
      { ...blobNote(1, 1), blob: "not base64!" },
      { ...blobNote(1, 1), blob: "A".repeat(LIMITS.maxBlobChars + 1) },
      { ...blobNote(1, 1), exam: true },
      { ...blobNote(1, 1), text: "" },
    ];
    for (const c of cases) {
      const res = await put(s.token, [c]);
      expect(res.status, JSON.stringify(c).slice(0, 80)).toBe(400);
    }
    const mixed = await put(s.token, [blobNote(1, 1), note("a", 1)]);
    expect([mixed.status, await errorOf(mixed)]).toEqual([400, "bad_request"]);
    expect((await put(s.token, [{ ...blobNote(1, 1), blob: "A".repeat(LIMITS.maxBlobChars) }])).status).toBe(200);
  });

  it("race: plaintext PUTs while the header is created never leave plaintext behind", async () => {
    for (let round = 0; round < 3; round++) {
      const user = freshUser();
      const [a, b] = await Promise.all([login(user), login(user)]);
      const writes = Array.from({ length: 6 }, (_, i) => put(a.token, [note(`k${i}`, i + 1)]));
      const header = putHeader(b.token, e2eHeader());
      const statuses = await Promise.all([...writes, header].map(async (p) => (await p).status));
      expect(statuses[6]).toBe(201);
      for (const st of statuses.slice(0, 6)) expect([200, 409]).toContain(st);
      const left = await env.DB.prepare("SELECT count(*) AS c FROM notes WHERE identity_id = ? AND blob IS NULL")
        .bind(await identityId(user))
        .first<{ c: number }>();
      expect(left!.c).toBe(0);
    }
  });
});

describe("E2E header replace (PATCH)", () => {
  const patchHeader = (token: string, body: unknown) => call(req("PATCH", "/api/sync/e2e", { token, body }));

  it("replaces the header with the right authKey and the same authHash; check may change", async () => {
    const s = await login(freshUser());
    expect((await putHeader(s.token, e2eHeader())).status).toBe(201);
    const changed = e2eHeader({
      wrappedDek: b64(72, 9),
      check: b64(56, 8),
      kdf: { alg: "argon2id", m: 65536, t: 3, p: 1, salt: b64(16, 5) },
    });
    const res = await patchHeader(s.token, { header: changed, authKey: AUTH_KEY });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual(changed);
    expect(await (await getHeader(s.token)).json()).toEqual(changed);
  });

  it("wrong authKey -> 403 e2e_auth_failed, header unchanged", async () => {
    const s = await login(freshUser());
    const header = e2eHeader();
    await putHeader(s.token, header);
    const res = await patchHeader(s.token, { header: e2eHeader({ wrappedDek: b64(72, 9) }), authKey: b64(32, 43) });
    expect([res.status, await errorOf(res)]).toEqual([403, "e2e_auth_failed"]);
    expect(await (await getHeader(s.token)).json()).toEqual(header);
  });

  it("new header with another authHash -> 403 even with the right authKey", async () => {
    const s = await login(freshUser());
    const header = e2eHeader();
    await putHeader(s.token, header);
    const otherKey = b64(32, 77);
    const res = await patchHeader(s.token, { header: e2eHeader({ authHash: await authHashOf(otherKey) }), authKey: AUTH_KEY });
    expect([res.status, await errorOf(res)]).toEqual([403, "e2e_auth_failed"]);
    expect(await (await getHeader(s.token)).json()).toEqual(header);
  });

  it("the authHash itself is not accepted as authKey", async () => {
    const s = await login(freshUser());
    await putHeader(s.token, e2eHeader());
    const res = await patchHeader(s.token, { header: e2eHeader({ wrappedDek: b64(72, 9) }), authKey: AUTH_HASH });
    expect(res.status).toBe(403);
  });

  it("bad bodies -> 400 (old bare-header form, malformed authKey, invalid header)", async () => {
    const s = await login(freshUser());
    await putHeader(s.token, e2eHeader());
    for (const body of [
      e2eHeader(),
      { header: e2eHeader() },
      { header: e2eHeader(), authKey: "short" },
      { header: e2eHeader(), authKey: AUTH_KEY + "A" },
      { header: e2eHeader(), authKey: 5 },
      { header: e2eHeader({ authHash: undefined }), authKey: AUTH_KEY },
      { header: e2eHeader({ kdf: { alg: "argon2id", m: 1024, t: 2, p: 1, salt: b64(16) } }), authKey: AUTH_KEY },
    ]) {
      const res = await patchHeader(s.token, JSON.parse(JSON.stringify(body)));
      expect([res.status, await errorOf(res)], JSON.stringify(body).slice(0, 60)).toEqual([400, "bad_request"]);
    }
  });

  it("404 without a header; only touches the caller's identity", async () => {
    const a = await login(freshUser());
    const b = await login(freshUser());
    const header = e2eHeader();
    await putHeader(a.token, header);
    const res = await patchHeader(b.token, { header: e2eHeader({ wrappedDek: b64(72, 9) }), authKey: AUTH_KEY });
    expect([res.status, await errorOf(res)]).toEqual([404, "e2e_not_enabled"]);
    expect(await (await getHeader(a.token)).json()).toEqual(header);
  });
});

describe("E2E off (DELETE /api/sync/e2e)", () => {
  const deleteE2e = (token: string, body: unknown) => call(req("DELETE", "/api/sync/e2e", { token, body }));

  it("deletes header and all notes in one go, keeps sessions; other devices see e2e:false", async () => {
    const user = freshUser();
    const [a, b] = await Promise.all([login(user), login(user)]);
    await putHeader(a.token, e2eHeader());
    expect((await put(a.token, [blobNote(1, 1), blobNote(2, 2, { deleted: true })])).status).toBe(200);
    const id = await identityId(user);
    const res = await deleteE2e(a.token, { authKey: AUTH_KEY });
    expect(res.status).toBe(204);
    expect((await getHeader(b.token)).status).toBe(404);
    const page = await get(b.token);
    expect(page).toMatchObject({ notes: [], e2e: false, latestSeq: 2 });
    const c = await env.DB.prepare("SELECT note_count, bytes FROM identities WHERE id = ?").bind(id).first();
    expect(c).toEqual({ note_count: 0, bytes: 0 });
    // Plaintext works again with the same sessions; seqs continue.
    const out = await put(b.token, [note("a", 5)]);
    expect(out.status).toBe(200);
    expect(((await out.json()) as { notes: { seq: number }[]; e2e: boolean }).notes[0]!.seq).toBe(3);
  });

  it("wrong or missing authKey -> 403 / 400, nothing deleted", async () => {
    const s = await login(freshUser());
    await putHeader(s.token, e2eHeader());
    await put(s.token, [blobNote(1, 1)]);
    let res = await deleteE2e(s.token, { authKey: b64(32, 43) });
    expect([res.status, await errorOf(res)]).toEqual([403, "e2e_auth_failed"]);
    res = await deleteE2e(s.token, {});
    expect([res.status, await errorOf(res)]).toEqual([400, "bad_request"]);
    expect((await getHeader(s.token)).status).toBe(200);
    expect((await get(s.token)).notes).toHaveLength(1);
  });

  it("without a header -> 404 e2e_not_enabled, plaintext notes stay", async () => {
    const s = await login(freshUser());
    await put(s.token, [note("a", 1)]);
    const res = await deleteE2e(s.token, { authKey: AUTH_KEY });
    expect([res.status, await errorOf(res)]).toEqual([404, "e2e_not_enabled"]);
    expect((await get(s.token)).notes).toHaveLength(1);
  });
});

describe("scheduled session purge", () => {
  it("deletes expired sessions only", async () => {
    const { purgeExpiredSessions } = await import("../../src/sync/db");
    const s = await login(freshUser());
    const id = await identityId(s.body.identity.userId);
    await env.DB.prepare("INSERT INTO sessions (token_hash, identity_id, created_at, expires_at) VALUES (?1, ?2, 0, 1)")
      .bind("expired-test-hash", id)
      .run();
    const n = await purgeExpiredSessions(env.DB, Date.now());
    expect(n).toBeGreaterThanOrEqual(1);
    const left = await env.DB.prepare("SELECT token_hash FROM sessions WHERE token_hash = 'expired-test-hash'").first();
    expect(left).toBeNull();
    expect((await get(s.token)).latestSeq).toBe(0);
  });
});
