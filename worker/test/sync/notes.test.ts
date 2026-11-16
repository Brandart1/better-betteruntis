import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { LIMITS } from "../../src/sync/notes";
import { call, freshUser, get, identityId, login, note, put, req, type WireNote } from "./helpers";

async function errorOf(res: Response): Promise<string> {
  return ((await res.json()) as { error: string }).error;
}

interface PutBody {
  notes: WireNote[];
  latestSeq: number;
  e2e: boolean;
  identity: { host: string; school: string; userId: string; epoch: string };
}

async function putOk(token: string, notes: unknown[]): Promise<PutBody> {
  const res = await put(token, notes);
  if (res.status !== 200) throw new Error(`put failed: ${res.status} ${await res.text()}`);
  return (await res.json()) as PutBody;
}

/**
 * Inserts [n] plaintext notes for the identity directly (fast seeding) and
 * sets the identity's counters to exactly what is stored (so later real
 * writes see consistent counters).
 */
async function seed(id: number, n: number): Promise<void> {
  await env.DB.batch([
    env.DB.prepare(
      "WITH RECURSIVE c(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM c WHERE i < ?2) " +
        "INSERT INTO notes (identity_id, key, exam, text, blob, updated_at, deleted, seq, stored_at) " +
        "SELECT ?1, 'seed-' || i, 0, '', NULL, 1, 0, i, 1 FROM c",
    ).bind(id, n),
    env.DB.prepare(
      "UPDATE identities SET last_seq = ?2, " +
        "note_count = (SELECT count(*) FROM notes WHERE identity_id = ?1 AND deleted = 0), " +
        "bytes = (SELECT coalesce(sum(length(CAST(key AS BLOB)) + length(CAST(text AS BLOB))), 0) FROM notes WHERE identity_id = ?1) " +
        "WHERE id = ?1",
    ).bind(id, n),
  ]);
}

const counters = async (id: number) =>
  (await env.DB.prepare("SELECT note_count, bytes FROM identities WHERE id = ?").bind(id).first<{ note_count: number; bytes: number }>())!;
/** What the counters should be: live notes, bytes of all rows. */
const actual = async (id: number) =>
  (await env.DB.prepare(
    "SELECT coalesce(sum(deleted = 0), 0) AS note_count, coalesce(sum(length(CAST(key AS BLOB)) + coalesce(length(CAST(text AS BLOB)), 0) + " +
      "coalesce(length(CAST(blob AS BLOB)), 0)), 0) AS bytes FROM notes WHERE identity_id = ?",
  ).bind(id).first<{ note_count: number; bytes: number }>())!;

describe("auth", () => {
  for (const [method, path] of [
    ["GET", "/api/sync/notes"],
    ["PUT", "/api/sync/notes"],
    ["GET", "/api/sync/e2e"],
    ["PUT", "/api/sync/e2e"],
    ["DELETE", "/api/sync/account"],
  ] as const) {
    it(`${method} ${path} without session -> 401`, async () => {
      const res = await call(req(method, path, method === "GET" ? {} : { body: { notes: [] } }));
      expect(res.status).toBe(401);
      expect(res.headers.get("cache-control")).toBe("no-store");
      expect(await errorOf(res)).toBe("unauthorized");
    });
  }
});

describe("GET /api/sync/notes", () => {
  it("empty", async () => {
    const s = await login(freshUser());
    expect(await get(s.token)).toEqual({ notes: [], latestSeq: 0, more: false, e2e: false, identity: s.body.identity });
  });

  it("returns changes after since, with all fields", async () => {
    const s = await login(freshUser());
    await putOk(s.token, [note("a", 10, "A", { exam: true }), note("b", 11, "B")]);
    await putOk(s.token, [note("c", 12, "C", { deleted: true })]);
    const all = await get(s.token);
    expect(all.notes).toEqual([
      { key: "a", exam: true, text: "A", updatedAt: 10, deleted: false, seq: 1 },
      { key: "b", exam: false, text: "B", updatedAt: 11, deleted: false, seq: 2 },
      // Plaintext tombstones are stored and returned blanked.
      { key: "c", exam: false, text: "", updatedAt: 12, deleted: true, seq: 3 },
    ]);
    expect(all.latestSeq).toBe(3);
    expect((await get(s.token, 2)).notes.map((n) => n.key)).toEqual(["c"]);
    expect((await get(s.token, 3)).notes).toEqual([]);
    expect((await get(s.token, 3)).latestSeq).toBe(3);
  });

  it("pages with more (1000 per page); exactly a full page -> more false", async () => {
    const s = await login(freshUser());
    const id = await identityId(s.body.identity.userId);
    await seed(id, 1000);
    let page = await get(s.token);
    expect(page.notes).toHaveLength(LIMITS.pageSize);
    expect(page.more).toBe(false);
    await putOk(s.token, [note("x", 5)]);
    page = await get(s.token);
    expect(page.notes).toHaveLength(1000);
    expect(page.more).toBe(true);
    const next = await get(s.token, page.notes[999]!.seq);
    expect(next.notes.map((n) => n.key)).toEqual(["x"]);
    expect(next.more).toBe(false);
  });

  it("bad since -> 400", async () => {
    const s = await login(freshUser());
    for (const q of ["since=-1", "since=abc", "since=1.5", "since=", "since=1e3", "since=9999999999999999", "since=1&since=2", "since=1%20OR%201=1"]) {
      const res = await call(req("GET", `/api/sync/notes?${q}`, { token: s.token }));
      expect(res.status, q).toBe(400);
      expect(await errorOf(res)).toBe("bad_request");
    }
  });
});

describe("PUT /api/sync/notes", () => {
  it("stores and returns the stored versions (with seq)", async () => {
    const s = await login(freshUser());
    const out = await putOk(s.token, [note("a", 1, "x"), note("b", 2, "y")]);
    expect(out.notes).toEqual([
      { key: "a", exam: false, text: "x", updatedAt: 1, deleted: false, seq: 1 },
      { key: "b", exam: false, text: "y", updatedAt: 2, deleted: false, seq: 2 },
    ]);
    expect(out.latestSeq).toBe(2);
    expect(out.e2e).toBe(false);
  });

  it("last write wins; older write and ties return the stored version", async () => {
    const s = await login(freshUser());
    await putOk(s.token, [note("a", 100, "first")]);
    let out = await putOk(s.token, [note("a", 50, "older")]);
    expect(out.notes[0]).toMatchObject({ text: "first", updatedAt: 100, seq: 1 });
    out = await putOk(s.token, [note("a", 100, "tie")]);
    expect(out.notes[0]).toMatchObject({ text: "first", seq: 1 });
    expect(out.latestSeq).toBe(1);
    out = await putOk(s.token, [note("a", 101, "newer")]);
    expect(out.notes[0]).toMatchObject({ text: "newer", updatedAt: 101, seq: 2 });
    expect((await get(s.token)).notes).toHaveLength(1);
  });

  it("duplicate keys in one request: merged like in order, one result", async () => {
    const s = await login(freshUser());
    const out = await putOk(s.token, [note("a", 5, "x"), note("b", 1), note("a", 9, "y"), note("a", 9, "z"), note("a", 7, "w")]);
    expect(out.notes.map((n) => [n.key, n.text])).toEqual([
      ["a", "y"],
      ["b", "t"],
    ]);
  });

  it("plaintext tombstones are stored blanked (text '', exam false), also in the DB", async () => {
    const s = await login(freshUser());
    await putOk(s.token, [note("a", 1, "secret", { exam: true })]);
    const out = await putOk(s.token, [note("a", 2, "still secret", { exam: true, deleted: true })]);
    expect(out.notes[0]).toEqual({ key: "a", exam: false, text: "", updatedAt: 2, deleted: true, seq: 2 });
    const row = await env.DB.prepare("SELECT exam, text FROM notes WHERE identity_id = ? AND key = 'a'")
      .bind(await identityId(s.body.identity.userId))
      .first();
    expect(row).toEqual({ exam: 0, text: "" });
    const id = await identityId(s.body.identity.userId);
    expect(await counters(id)).toEqual({ note_count: 0, bytes: 1 });
  });

  it("tombstones are stored, returned and can be revived", async () => {
    const s = await login(freshUser());
    await putOk(s.token, [note("a", 1, "x")]);
    let out = await putOk(s.token, [note("a", 2, "", { deleted: true })]);
    expect(out.notes[0]).toMatchObject({ deleted: true, seq: 2 });
    expect((await get(s.token, 1)).notes[0]).toMatchObject({ key: "a", deleted: true });
    out = await putOk(s.token, [note("a", 3, "back")]);
    expect(out.notes[0]).toMatchObject({ deleted: false, text: "back", seq: 3 });
  });

  it("seq strictly increasing and per identity", async () => {
    const a = await login(freshUser());
    const b = await login(freshUser());
    const seqs: number[] = [];
    for (let i = 0; i < 5; i++) {
      const out = await putOk(a.token, [note(`k${i}`, i + 1), note("same", i + 1)]);
      seqs.push(...out.notes.map((n) => n.seq!));
      await putOk(b.token, [note(`k${i}`, i + 1)]);
    }
    for (let i = 1; i < seqs.length; i++) expect(seqs[i]!).toBeGreaterThan(seqs[i - 1]!);
    expect((await get(b.token)).latestSeq).toBe(5);
    expect((await get(a.token)).latestSeq).toBe(10);
  });

  it("concurrent PUTs of one identity: all seqs unique and increasing, last_seq = max", async () => {
    const user = freshUser();
    const sessions = await Promise.all([login(user), login(user), login(user), login(user)]);
    const results = await Promise.all(
      sessions.flatMap((s, d) =>
        Array.from({ length: 5 }, (_, r) =>
          putOk(s.token, Array.from({ length: 20 }, (_, i) => note(`d${d}-r${r}-${i % 15}`, 1000 + i, `v${i}`)).concat(note("shared", 10 + d * 10 + r))),
        ),
      ),
    );
    const page = await get(sessions[0]!.token);
    const seqs = page.notes.map((n) => n.seq!);
    expect(new Set(seqs).size).toBe(seqs.length);
    expect([...seqs].sort((x, y) => x - y)).toEqual(seqs);
    expect(page.latestSeq).toBe(Math.max(...seqs));
    expect(page.notes).toHaveLength(4 * 5 * 15 + 1);
    // The shared key ends with the highest updatedAt of all writers.
    expect(page.notes.find((n) => n.key === "shared")!.updatedAt).toBe(10 + 3 * 10 + 4);
    // Every response's latestSeq is a real seq at that point.
    for (const r of results) expect(r.latestSeq).toBeGreaterThan(0);
  });

  it("empty list is fine", async () => {
    const s = await login(freshUser());
    expect(await putOk(s.token, [])).toEqual({ notes: [], latestSeq: 0, e2e: false, identity: s.body.identity });
  });

  const badNotes: [string, unknown][] = [
    ["not an object", 5],
    ["missing key", { exam: false, text: "", updatedAt: 1, deleted: false }],
    ["key not a string", { key: 1, exam: false, text: "", updatedAt: 1, deleted: false }],
    ["empty key", note("", 1)],
    ["key too long", note("k".repeat(LIMITS.maxKeyLength + 1), 1)],
    ["text too long", note("k", 1, "x".repeat(LIMITS.maxTextLength + 1))],
    ["exam not bool", { ...note("k", 1), exam: 1 }],
    ["text missing", { key: "k", exam: false, updatedAt: 1, deleted: false }],
    ["deleted missing", { key: "k", exam: false, text: "", updatedAt: 1 }],
    ["updatedAt negative", note("k", -1)],
    ["updatedAt fraction", note("k", 1.5)],
    ["updatedAt string", { ...note("k", 1), updatedAt: "1" }],
    ["updatedAt huge", note("k", 2 ** 60)],
    ["NUL in key", note("a\u0000b", 1)],
    ["lone surrogate in text", note("k", 1, "x\ud800y")],
    ["blob and text", { ...note("k", 1), blob: "AAAA" }],
  ];
  for (const [name, bad] of badNotes) {
    it(`${name} -> 400, nothing stored`, async () => {
      const s = await login(freshUser());
      const res = await put(s.token, [note("ok", 1), bad]);
      expect(res.status).toBe(400);
      expect(await errorOf(res)).toBe("bad_request");
      expect((await get(s.token)).notes).toEqual([]);
    });
  }

  it("bad bodies -> 400", async () => {
    const s = await login(freshUser());
    for (const body of ["nope", "[]", "{}", '{"notes": {}}', '{"notes": null}']) {
      const res = await call(req("PUT", "/api/sync/notes", { token: s.token, body }));
      expect(res.status, body).toBe(400);
    }
    const invalidUtf8 = new Request("https://bbu.test/api/sync/notes", {
      method: "PUT",
      headers: { authorization: `Bearer ${s.token}`, "content-type": "application/json" },
      body: new Uint8Array([0x7b, 0xff, 0x7d]),
    });
    expect((await call(invalidUtf8)).status).toBe(400);
  });

  it("maximum lengths and unicode round-trip", async () => {
    const s = await login(freshUser());
    const key = "k".repeat(LIMITS.maxKeyLength);
    const text = "Mathe 😀 Schularbeit äöü ß\n\t" + "x".repeat(LIMITS.maxTextLength - 30);
    const out = await putOk(s.token, [note(key, 1, text)]);
    expect(out.notes[0]!.text).toBe(text);
    expect((await get(s.token)).notes[0]).toMatchObject({ key, text });
  });

  it("updatedAt more than 5 minutes in the future -> 400 clock_skew; within is fine", async () => {
    const s = await login(freshUser());
    const t0 = Date.now();
    let res = await call(req("PUT", "/api/sync/notes", { token: s.token, body: { notes: [note("a", t0 + 6 * 60_000)] } }), { now: () => t0 });
    expect(res.status).toBe(400);
    const err = (await res.json()) as { error: string; serverTime: number };
    expect(err.error).toBe("clock_skew");
    expect(err.serverTime).toBe(t0);
    res = await call(req("PUT", "/api/sync/notes", { token: s.token, body: { notes: [note("a", t0 + 4 * 60_000)] } }), { now: () => t0 });
    expect(res.status).toBe(200);
  });

  it("more than 500 notes -> 413; 500 are fine", async () => {
    const s = await login(freshUser());
    const many = (n: number) => Array.from({ length: n }, (_, i) => note(`k${i}`, 1));
    const res = await put(s.token, many(501));
    expect([res.status, await errorOf(res)]).toEqual([413, "batch_too_large"]);
    const out = await putOk(s.token, many(500));
    expect(out.notes).toHaveLength(500);
    expect(out.latestSeq).toBe(500);
  });

  it("body over 1 MiB -> 413 (declared or streamed)", async () => {
    const s = await login(freshUser());
    const big = JSON.stringify({ notes: [note("a", 1, "x".repeat(10))], pad: "p".repeat(LIMITS.maxBodyBytes) });
    let res = await call(req("PUT", "/api/sync/notes", { token: s.token, body: big }));
    expect([res.status, await errorOf(res)]).toEqual([413, "body_too_large"]);
    const stream = new ReadableStream({
      start(c) {
        c.enqueue(new TextEncoder().encode(big));
        c.close();
      },
    });
    res = await call(
      new Request("https://bbu.test/api/sync/notes", {
        method: "PUT",
        headers: { authorization: `Bearer ${s.token}`, "content-type": "application/json" },
        body: stream,
      }),
    );
    expect(res.status).toBe(413);
    expect((await get(s.token)).notes).toEqual([]);
  });

  it("per-user limit 5 000 live notes (tombstones don't count) -> 413 too_many_notes, all or nothing", async () => {
    const s = await login(freshUser());
    const id = await identityId(s.body.identity.userId);
    expect(LIMITS.maxNotesPerUser).toBe(5000);
    await seed(id, LIMITS.maxNotesPerUser - 2);
    let res = await put(s.token, [note("new1", 5), note("new2", 5), note("new3", 5)]);
    expect([res.status, await errorOf(res)]).toEqual([413, "too_many_notes"]);
    const count = async () =>
      (await env.DB.prepare("SELECT count(*) AS c FROM notes WHERE identity_id = ?").bind(id).first<{ c: number }>())!.c;
    expect(await count()).toBe(LIMITS.maxNotesPerUser - 2);
    // Updates of existing keys and duplicates don't count.
    const out = await putOk(s.token, [note("new1", 5), note("new2", 5), note("new1", 6), note("seed-1", 9, "edited")]);
    expect(out.notes).toHaveLength(3);
    expect(await counters(id)).toMatchObject({ note_count: LIMITS.maxNotesPerUser });
    res = await put(s.token, [note("one-more", 5)]);
    expect([res.status, await errorOf(res)]).toEqual([413, "too_many_notes"]);
    // A tombstone frees a slot (tombstones count only in bytes).
    expect((await put(s.token, [note("seed-2", 9, "", { deleted: true })])).status).toBe(200);
    expect((await put(s.token, [note("one-more", 5)])).status).toBe(200);
    expect(await count()).toBe(LIMITS.maxNotesPerUser + 1);
    expect(await counters(id)).toEqual(await actual(id));
    // Another user is not affected.
    const other = await login(freshUser());
    expect((await put(other.token, [note("one-more", 5)])).status).toBe(200);
  });
});

describe("counters and byte quota", () => {

  it("note_count (live) and bytes follow inserts, overwrites (UTF-8 bytes), tombstones and revivals", async () => {
    const s = await login(freshUser());
    const id = await identityId(s.body.identity.userId);
    await putOk(s.token, [note("a", 1, "xyz"), note("bb", 1, "ä")]);
    expect(await counters(id)).toEqual({ note_count: 2, bytes: 1 + 3 + 2 + 2 });
    await putOk(s.token, [note("a", 2, "😀😀")]); // 8 bytes
    expect(await counters(id)).toEqual({ note_count: 2, bytes: 1 + 8 + 2 + 2 });
    await putOk(s.token, [note("bb", 3, "ignored", { deleted: true })]);
    expect(await counters(id)).toEqual({ note_count: 1, bytes: 1 + 8 + 2 });
    await putOk(s.token, [note("bb", 4, "back")]);
    expect(await counters(id)).toEqual({ note_count: 2, bytes: 1 + 8 + 2 + 4 });
    expect(await counters(id)).toEqual(await actual(id));
  });

  it("counters stay exact under concurrent writes", async () => {
    const user = freshUser();
    const sessions = await Promise.all([login(user), login(user), login(user)]);
    await Promise.all(
      sessions.flatMap((s, d) =>
        Array.from({ length: 4 }, (_, r) => put(s.token, Array.from({ length: 10 }, (_, i) => note(`k${(d + r + i) % 17}`, 10 * r + d + i, "v".repeat(d + r + i))))),
      ),
    );
    const id = await identityId(user);
    expect(await counters(id)).toEqual(await actual(id));
  });

  it("byte quota (5 MiB) via real writes -> 413 storage_quota, all or nothing; shrinking writes still pass", async () => {
    const s = await login(freshUser());
    const id = await identityId(s.body.identity.userId);
    // Fill to just under the quota with real PUTs (4 000-char notes).
    const big = (i: number) => note(`big-${String(i).padStart(4, "0")}`, 1, "x".repeat(LIMITS.maxTextLength));
    const perNote = "big-0000".length + LIMITS.maxTextLength;
    const fill = Math.floor(LIMITS.maxBytesPerUser / perNote);
    for (let i = 0; i < fill; i += 240) {
      await putOk(s.token, Array.from({ length: Math.min(240, fill - i) }, (_, j) => big(i + j)));
    }
    expect(await counters(id)).toEqual(await actual(id));
    const free = LIMITS.maxBytesPerUser - (await counters(id)).bytes;
    expect(free).toBeGreaterThan(10);
    expect(free).toBeLessThan(perNote);
    // Too big by one byte: refused, nothing of the request stored.
    // "small"+"y" = 6 bytes, "c" + (free - 6) chars = free - 5 -> one byte over.
    let res = await put(s.token, [note("small", 1, "y"), note("c", 1, "z".repeat(free - 6))]);
    expect([res.status, await errorOf(res)]).toEqual([413, "storage_quota"]);
    expect((await get(s.token, fill)).notes).toEqual([]);
    // Exactly full.
    expect((await put(s.token, [note("small", 1, "y"), note("c", 1, "z".repeat(free - 7))])).status).toBe(200);
    expect((await counters(id)).bytes).toBe(LIMITS.maxBytesPerUser);
    res = await put(s.token, [note("d", 1)]);
    expect([res.status, await errorOf(res)]).toEqual([413, "storage_quota"]);
    // A shrinking write (tombstone) passes at the quota.
    expect((await put(s.token, [note("big-0000", 2, "", { deleted: true })])).status).toBe(200);
    expect((await put(s.token, [note("d", 1)])).status).toBe(200);
    expect(await counters(id)).toEqual(await actual(id));
  });

  it("tie: equal updatedAt keeps the stored version and returns it", async () => {
    const s = await login(freshUser());
    await putOk(s.token, [note("a", 100, "stored", { exam: true })]);
    const out = await putOk(s.token, [note("a", 100, "other", { exam: false })]);
    expect(out.notes).toEqual([{ key: "a", exam: true, text: "stored", updatedAt: 100, deleted: false, seq: 1 }]);
    expect(out.latestSeq).toBe(1);
  });

  it("GET and PUT answers carry the session's identity", async () => {
    const s = await login(freshUser(), "school-x");
    expect((await get(s.token)).identity).toEqual({
      host: s.body.identity.host,
      school: "school-x",
      userId: s.body.identity.userId,
      epoch: s.body.identity.epoch,
    });
    expect(s.body.identity.epoch).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect((await putOk(s.token, [note("a", 1)])).identity).toEqual(s.body.identity);
  });
});

describe("tombstone purge (cron)", () => {
  it("deletes only tombstones not written for 400 days, adjusts counters, keeps last_seq", async () => {
    const { dailyCleanup } = await import("../../src/index");
    const { TOMBSTONE_MAX_AGE_MS } = await import("../../src/sync/db");
    const s = await login(freshUser());
    const id = await identityId(s.body.identity.userId);
    await putOk(s.token, [note("old-tomb", 1, "", { deleted: true }), note("old-live", 2, "x"), note("new-tomb", 3, "", { deleted: true })]);
    const now = Date.now();
    await env.DB.prepare("UPDATE notes SET stored_at = ? WHERE identity_id = ? AND key IN ('old-tomb', 'old-live')")
      .bind(now - TOMBSTONE_MAX_AGE_MS - 1, id)
      .run();
    await dailyCleanup(env.DB, now);
    const page = await get(s.token);
    expect(page.notes.map((n) => n.key).sort()).toEqual(["new-tomb", "old-live"]);
    expect(page.latestSeq).toBe(3);
    expect(await counters(id)).toEqual({ note_count: 1, bytes: "old-live".length + 1 + "new-tomb".length });
    expect(await counters(id)).toEqual(await actual(id));
  });
});

describe("inactive account purge (cron)", () => {
  it("deletes accounts without a login for 12 months and no session; keeps active ones", async () => {
    const { dailyCleanup } = await import("../../src/index");
    const { INACTIVE_IDENTITY_MS } = await import("../../src/sync/db");
    const now = Date.now();
    const old = await login(freshUser());
    const oldId = await identityId(old.body.identity.userId);
    await putOk(old.token, [note("x", 1, "old note")]);
    const active = await login(freshUser());
    const activeId = await identityId(active.body.identity.userId);
    const withSession = await login(freshUser());
    const withSessionId = await identityId(withSession.body.identity.userId);
    // Old: last login 12 months + 1 ms ago, session gone.
    await env.DB.prepare("UPDATE identities SET last_login = ? WHERE id IN (?, ?)")
      .bind(now - INACTIVE_IDENTITY_MS - 1, oldId, withSessionId)
      .run();
    await env.DB.prepare("DELETE FROM sessions WHERE identity_id = ?").bind(oldId).run();
    await dailyCleanup(env.DB, now);
    const ids = (await env.DB.prepare("SELECT id FROM identities WHERE id IN (?, ?, ?)")
      .bind(oldId, activeId, withSessionId)
      .all<{ id: number }>()).results.map((r) => r.id);
    expect(ids.sort()).toEqual([activeId, withSessionId].sort());
    const notesLeft = await env.DB.prepare("SELECT count(*) AS n FROM notes WHERE identity_id = ?").bind(oldId).first<{ n: number }>();
    expect(notesLeft!.n).toBe(0);
  });

  it("a login updates last_login", async () => {
    const user = freshUser();
    const s = await login(user);
    const id = await identityId(s.body.identity.userId);
    await env.DB.prepare("UPDATE identities SET last_login = 1 WHERE id = ?").bind(id).run();
    await login(user);
    const row = await env.DB.prepare("SELECT last_login FROM identities WHERE id = ?").bind(id).first<{ last_login: number }>();
    expect(row!.last_login).toBeGreaterThan(1);
  });
});

describe("isolation and injection", () => {
  it("user B can't read, overwrite or delete A's notes, even with A's keys", async () => {
    const a = await login(freshUser());
    const b = await login(freshUser());
    await putOk(a.token, [note("2026-11-16|lesson-42", 100, "A's secret", { exam: true })]);
    // B sees nothing of A.
    expect((await get(b.token)).notes).toEqual([]);
    // B writes the same key (newer), and a tombstone for it.
    await putOk(b.token, [note("2026-11-16|lesson-42", 200, "B was here")]);
    await putOk(b.token, [note("2026-11-16|lesson-42", 300, "", { deleted: true })]);
    const pageA = await get(a.token);
    expect(pageA.notes).toEqual([{ key: "2026-11-16|lesson-42", exam: true, text: "A's secret", updatedAt: 100, deleted: false, seq: 1 }]);
    expect(pageA.latestSeq).toBe(1);
    // B deletes its account: A's data stays.
    expect((await call(req("DELETE", "/api/sync/account", { token: b.token }))).status).toBe(204);
    expect((await get(a.token)).notes).toHaveLength(1);
  });

  it("same user id at another school or host is another identity", async () => {
    const user = freshUser();
    const a = await login(user, "school-a");
    const b = await login(user, "school-b");
    await putOk(a.token, [note("k", 1, "a")]);
    expect((await get(b.token)).notes).toEqual([]);
  });

  it("SQL-injection-looking keys and texts are stored verbatim and harmless", async () => {
    const a = await login(freshUser());
    const victim = await login(freshUser());
    await putOk(victim.token, [note("v", 1, "victim")]);
    const evil = [
      "'; DROP TABLE notes; --",
      "\" OR 1=1 --",
      "x') ON CONFLICT DO NOTHING; DELETE FROM notes; --",
      "$.k",
      "?1",
      "'), (1, 'k', 0, 't', NULL, 1, 0, 1); --",
      '{"k":"other"}',
      "%_*",
    ];
    const notes = evil.map((k, i) => note(k, 10 + i, `${k} || (SELECT text FROM notes)`));
    const out = await putOk(a.token, notes);
    expect(out.notes.map((n) => n.key)).toEqual(evil);
    const page = await get(a.token);
    expect(page.notes.map((n) => [n.key, n.text])).toEqual(evil.map((k) => [k, `${k} || (SELECT text FROM notes)`]));
    // Tables and other users untouched.
    expect((await get(victim.token)).notes).toEqual([{ key: "v", exam: false, text: "victim", updatedAt: 1, deleted: false, seq: 1 }]);
    const tables = await env.DB.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('notes','identities','sessions','e2e_headers')").all();
    expect(tables.results).toHaveLength(4);
  });
});

describe("DELETE /api/sync/account", () => {
  it("deletes everything of the user (notes, tombstones, sessions, e2e header), clears the cookie", async () => {
    const user = freshUser();
    const s1 = await login(user);
    const s2 = await login(user);
    await putOk(s1.token, [note("a", 1), note("b", 2, "", { deleted: true })]);
    const id = await identityId(user);
    const other = await login(freshUser());
    await putOk(other.token, [note("a", 1)]);

    const res = await call(req("DELETE", "/api/sync/account", { token: s1.token }));
    expect(res.status).toBe(204);
    expect(res.headers.get("set-cookie")).toBe("__Host-bbu_sync=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0");
    for (const t of [s1.token, s2.token]) expect((await call(req("GET", "/api/sync/notes", { token: t }))).status).toBe(401);
    for (const table of ["notes", "sessions", "e2e_headers"]) {
      const n = await env.DB.prepare(`SELECT count(*) AS c FROM ${table} WHERE identity_id = ?`).bind(id).first<{ c: number }>();
      expect(n!.c, table).toBe(0);
    }
    expect(await env.DB.prepare("SELECT 1 FROM identities WHERE id = ?").bind(id).first()).toBeNull();
    // Others untouched; the user can start over (seq from 1 again).
    expect((await get(other.token)).notes).toHaveLength(1);
    const again = await login(user);
    expect((await putOk(again.token, [note("a", 1)])).notes[0]!.seq).toBe(1);
  });

  it("foreign keys cascade when an identity row is deleted", async () => {
    const user = freshUser();
    const s = await login(user);
    await putOk(s.token, [note("a", 1)]);
    const id = await identityId(user);
    await env.DB.prepare("DELETE FROM identities WHERE id = ?").bind(id).run();
    const n = await env.DB.prepare("SELECT (SELECT count(*) FROM notes WHERE identity_id = ?1) + (SELECT count(*) FROM sessions WHERE identity_id = ?1) AS c").bind(id).first<{ c: number }>();
    expect(n!.c).toBe(0);
  });
});
