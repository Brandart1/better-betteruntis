import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import * as db from "../../src/sync/db";
import { mergeDuplicates } from "../../src/sync/notes";
import { freshUser, HOST } from "./helpers";

const L = (maxNotes: number, maxBytes = Number.MAX_SAFE_INTEGER, dailyWrites = 1_000_000): db.WriteLimits => ({
  maxNotes,
  maxBytes,
  dailyWrites,
});

/** Counters on the identity row vs. what the notes actually are. */
async function countersOf(id: number) {
  return env.DB.prepare("SELECT note_count, bytes FROM identities WHERE id = ?").bind(id).first<{ note_count: number; bytes: number }>();
}
async function actualOf(id: number) {
  return env.DB.prepare(
    "SELECT coalesce(sum(deleted = 0), 0) AS note_count, coalesce(sum(length(CAST(key AS BLOB)) + " +
      "coalesce(length(CAST(text AS BLOB)), 0) + coalesce(length(CAST(blob AS BLOB)), 0)), 0) AS bytes " +
      "FROM notes WHERE identity_id = ?",
  )
    .bind(id)
    .first<{ note_count: number; bytes: number }>();
}
async function expectConsistent(id: number) {
  expect(await countersOf(id)).toEqual(await actualOf(id));
}

/** Store semantics directly on D1 (no HTTP), incl. the guards inside the write statement. */

async function newIdentity(): Promise<number> {
  const user = freshUser();
  await db.createSession(env.DB, `hash-${user}`, { host: HOST, school: "s", userId: user }, Date.now(), Date.now() + 1000, "e".repeat(22));
  const row = await env.DB.prepare("SELECT id FROM identities WHERE user_id = ?").bind(user).first<{ id: number }>();
  return row!.id;
}

const plain = (key: string, updatedAt: number, text = "t"): db.NoteInput => ({
  key,
  exam: false,
  text,
  blob: null,
  updatedAt,
  deleted: false,
});
const enc = (key: string, updatedAt: number): db.NoteInput => ({
  key,
  exam: null,
  text: null,
  blob: "QUJD",
  updatedAt,
  deleted: false,
});

describe("write statement guards (without the pre-check)", () => {
  it("plaintext write is a no-op once a header exists", async () => {
    const id = await newIdentity();
    await db.createE2eHeader(env.DB, id, "{}", 1);
    const out = await db.writeNotes(env.DB, id, [plain("a", 1)], false, L(100));
    expect(out).toEqual({ ok: false, reason: "e2e_required" });
    expect((await db.changes(env.DB, id, 0, 10))!.notes).toEqual([]);
  });

  it("encrypted write is a no-op without a header", async () => {
    const id = await newIdentity();
    const out = await db.writeNotes(env.DB, id, [enc("a", 1)], true, L(100));
    expect(out).toEqual({ ok: false, reason: "e2e_not_enabled" });
    expect((await db.changes(env.DB, id, 0, 10))!.notes).toEqual([]);
  });

  it("quota is enforced inside the statement, all or nothing", async () => {
    const id = await newIdentity();
    expect((await db.writeNotes(env.DB, id, [plain("a", 1), plain("b", 1)], false, L(3))).ok).toBe(true);
    const out = await db.writeNotes(env.DB, id, [plain("a", 2, "upd"), plain("c", 1), plain("d", 1)], false, L(3));
    expect(out).toEqual({ ok: false, reason: "too_many_notes" });
    const page = (await db.changes(env.DB, id, 0, 10))!;
    expect(page.notes.map((n) => [n.key, n.text])).toEqual([
      ["a", "t"],
      ["b", "t"],
    ]);
    expect(page.latestSeq).toBe(2);
    // Exactly at the limit is fine.
    expect((await db.writeNotes(env.DB, id, [plain("c", 1)], false, L(3))).ok).toBe(true);
    // Tombstones don't count as notes: delete one, then a new one fits.
    expect((await db.writeNotes(env.DB, id, [{ ...plain("a", 5, ""), deleted: true }], false, L(3))).ok).toBe(true);
    expect((await db.writeNotes(env.DB, id, [plain("d", 1)], false, L(3))).ok).toBe(true);
    // Reviving the tombstone would make 4 live notes.
    expect(await db.writeNotes(env.DB, id, [plain("a", 6)], false, L(3))).toEqual({ ok: false, reason: "too_many_notes" });
    // Over the limit, a write that doesn't grow the live count still passes.
    expect((await db.writeNotes(env.DB, id, [{ ...plain("b", 9, ""), deleted: true }, plain("e", 1)], false, L(2))).ok).toBe(true);
    await expectConsistent(id);
  });

  it("only newer versions get a seq (base + request position: gaps for skipped notes); last_seq never goes back", async () => {
    const id = await newIdentity();
    await db.writeNotes(env.DB, id, [plain("a", 10), plain("b", 10)], false, L(100));
    const out = await db.writeNotes(env.DB, id, [plain("a", 5), plain("c", 1), plain("b", 11)], false, L(100));
    expect(out.ok && out.result.notes.map((n) => [n.key, n.seq])).toEqual([
      ["a", 1],
      ["c", 4],
      ["b", 5],
    ]);
    expect(out.ok && out.result.latestSeq).toBe(5);
    // Skipped notes at the end don't reserve seqs.
    const tail = await db.writeNotes(env.DB, id, [plain("d", 1), plain("a", 1)], false, L(100));
    expect(tail.ok && [tail.result.notes.map((n) => n.seq), tail.result.latestSeq]).toEqual([[6, 1], 6]);
    // Deleting notes (e.g. E2E turned on) doesn't lower last_seq.
    await env.DB.prepare("DELETE FROM notes WHERE identity_id = ?").bind(id).run();
    const after = await db.writeNotes(env.DB, id, [plain("z", 1)], false, L(100));
    expect(after.ok && after.result.notes[0]!.seq).toBe(7);
  });

  it("byte quota inside the statement, built by real writes; shrinking writes pass over it", async () => {
    const id = await newIdentity();
    // "a" + 9 = 10 bytes, "b" + 9 = 10 bytes.
    expect((await db.writeNotes(env.DB, id, [plain("a", 1, "x".repeat(9)), plain("b", 1, "x".repeat(9))], false, L(100, 25))).ok).toBe(true);
    expect(await db.writeNotes(env.DB, id, [plain("c", 1, "x".repeat(5))], false, L(100, 25))).toEqual({ ok: false, reason: "storage_quota" });
    expect((await db.writeNotes(env.DB, id, [plain("c", 1, "x".repeat(4))], false, L(100, 25))).ok).toBe(true); // exactly 25
    // With a lower quota (now over it): growing refused, shrinking and equal-size allowed.
    expect(await db.writeNotes(env.DB, id, [plain("a", 2, "x".repeat(10))], false, L(100, 20))).toEqual({ ok: false, reason: "storage_quota" });
    expect((await db.writeNotes(env.DB, id, [plain("a", 3, "y".repeat(9))], false, L(100, 20))).ok).toBe(true);
    expect((await db.writeNotes(env.DB, id, [{ ...plain("b", 3, ""), deleted: true }], false, L(100, 20))).ok).toBe(true);
    await expectConsistent(id);
    expect(await countersOf(id)).toEqual({ note_count: 2, bytes: 10 + 1 + 5 });
  });

  it("daily write budget: all or nothing, counts inserts, overwrites and tombstones, not skipped notes; resets per UTC day", async () => {
    const id = await newIdentity();
    const day = Date.UTC(2026, 10, 16, 10);
    const lim = L(100, Number.MAX_SAFE_INTEGER, 3);
    expect((await db.writeNotes(env.DB, id, [plain("a", 1), plain("b", 1)], false, lim, day)).ok).toBe(true);
    // a is older (not written, doesn't count), c new, b overwrite -> 2 more = 4 > 3.
    expect(await db.writeNotes(env.DB, id, [plain("a", 1), plain("c", 1), plain("b", 2)], false, lim, day)).toEqual({
      ok: false,
      reason: "daily_limit",
    });
    expect((await db.changes(env.DB, id, 0, 10))!.notes.map((n) => n.key)).toEqual(["a", "b"]);
    // Only skipped + one tombstone: 3 exactly.
    expect((await db.writeNotes(env.DB, id, [plain("a", 1), { ...plain("b", 2, ""), deleted: true }], false, lim, day)).ok).toBe(true);
    expect(await db.writeNotes(env.DB, id, [plain("z", 1)], false, lim, day + 1000)).toEqual({ ok: false, reason: "daily_limit" });
    // A write with nothing newer is fine at the limit.
    expect((await db.writeNotes(env.DB, id, [plain("a", 1)], false, lim, day)).ok).toBe(true);
    // Next UTC day: budget is back.
    const next = Date.UTC(2026, 10, 17, 0, 0, 0, 1);
    expect((await db.writeNotes(env.DB, id, [plain("z", 1), plain("y", 1), plain("x", 1)], false, lim, next)).ok).toBe(true);
    const row = await env.DB.prepare("SELECT budget_day, budget_used FROM identities WHERE id = ?").bind(id).first();
    expect(row).toEqual({ budget_day: Math.floor(next / db.DAY_MS), budget_used: 3 });
  });

  it("identity gone at write/read time -> identity_gone / null", async () => {
    const id = await newIdentity();
    await db.deleteIdentity(env.DB, id);
    expect(await db.writeNotes(env.DB, id, [plain("a", 1)], false, L(10))).toEqual({ ok: false, reason: "identity_gone" });
    expect(await db.writeNotes(env.DB, id, [], false, L(10))).toEqual({ ok: false, reason: "identity_gone" });
    expect(await db.changes(env.DB, id, 0, 10)).toBeNull();
    expect(await db.getE2eHeader(env.DB, id)).toBeUndefined();
    expect(await db.createE2eHeader(env.DB, id, "{}", 1)).toBe("gone");
    expect(await env.DB.prepare("SELECT count(*) AS c FROM notes WHERE identity_id = ?").bind(id).first()).toEqual({ c: 0 });
  });

  it("CHECK constraint rejects mixed rows", async () => {
    const id = await newIdentity();
    await expect(
      env.DB.prepare("INSERT INTO notes VALUES (?, 'k', 1, 'x', 'blob', 1, 0, 1, 1)").bind(id).run(),
    ).rejects.toThrow();
  });
});

describe("identities", () => {
  it("ids of deleted identities are never reused (AUTOINCREMENT)", async () => {
    const id = await newIdentity();
    await db.deleteIdentity(env.DB, id);
    const next = await newIdentity();
    expect(next).toBeGreaterThan(id);
    const max = await env.DB.prepare("SELECT max(id) AS m FROM identities").first<{ m: number }>();
    await db.deleteIdentity(env.DB, max!.m);
    expect(await newIdentity()).toBeGreaterThan(max!.m);
  });
});

describe("sessions", () => {
  it("findSession: valid before, null at/after expiresAt; delete", async () => {
    const user = freshUser();
    const who = { host: HOST, school: "s", userId: user };
    await db.createSession(env.DB, `h-${user}`, who, 1000, 5000, "f".repeat(22));
    expect((await db.findSession(env.DB, `h-${user}`, 4999))?.identity).toEqual({ ...who, epoch: "f".repeat(22) });
    expect(await db.findSession(env.DB, `h-${user}`, 5000)).toBeNull();
    expect(await db.deleteSession(env.DB, `h-${user}`)).toBe(true);
    expect(await db.deleteSession(env.DB, `h-${user}`)).toBe(false);
    expect(await db.findSession(env.DB, `h-${user}`, 1000)).toBeNull();
  });

  it("sessions don't touch notes", async () => {
    const id = await newIdentity();
    await db.writeNotes(env.DB, id, [plain("a", 1)], false, L(10));
    await env.DB.prepare("DELETE FROM sessions WHERE identity_id = ?").bind(id).run();
    expect((await db.changes(env.DB, id, 0, 10))!.notes).toHaveLength(1);
  });
});

describe("mergeDuplicates", () => {
  it("highest updatedAt wins, ties keep the first, first-occurrence order", () => {
    const out = mergeDuplicates([plain("a", 1, "1"), plain("b", 1), plain("a", 3, "2"), plain("a", 3, "3"), plain("a", 2, "4")]);
    expect(out.map((n) => [n.key, n.text])).toEqual([
      ["a", "2"],
      ["b", "t"],
    ]);
  });
});

describe("counters without triggers (explicit aggregated updates)", () => {
  it("createE2eHeader deletes plaintext and zeroes counters; a second header changes nothing", async () => {
    const id = await newIdentity();
    await db.writeNotes(env.DB, id, [plain("a", 1, "xyz"), { ...plain("b", 1, ""), deleted: true }], false, L(10));
    expect(await countersOf(id)).toEqual({ note_count: 1, bytes: 4 + 1 });
    expect(await db.createE2eHeader(env.DB, id, "{}", 1)).toBe("created");
    await expectConsistent(id);
    expect(await countersOf(id)).toEqual({ note_count: 0, bytes: 0 });
    expect((await db.writeNotes(env.DB, id, [enc("k1", 1), { ...enc("k2", 1), deleted: true }], true, L(10))).ok).toBe(true);
    expect(await countersOf(id)).toEqual({ note_count: 1, bytes: 2 * (2 + 4) });
    expect(await db.createE2eHeader(env.DB, id, "{}", 2)).toBe("exists");
    await expectConsistent(id);
    expect((await db.changes(env.DB, id, 0, 10))!.notes).toHaveLength(2);
  });

  it("deleteE2e zeroes counters only with the right authHash", async () => {
    const id = await newIdentity();
    await db.createE2eHeader(env.DB, id, JSON.stringify({ authHash: "good" }), 1);
    await db.writeNotes(env.DB, id, [enc("k1", 1), enc("k2", 1)], true, L(10));
    expect(await db.deleteE2e(env.DB, id, "bad")).toBe("mismatch");
    expect(await countersOf(id)).toEqual({ note_count: 2, bytes: 12 });
    await expectConsistent(id);
    expect(await db.deleteE2e(env.DB, id, "good")).toBe("deleted");
    expect(await countersOf(id)).toEqual({ note_count: 0, bytes: 0 });
    await expectConsistent(id);
    expect(await db.deleteE2e(env.DB, id, "good")).toBe("missing");
  });

  it("purge: per-identity bytes drop by the purged tombstones (plaintext and E2E), rewritten tombstones stay", async () => {
    const a = await newIdentity();
    const b = await newIdentity();
    await db.createE2eHeader(env.DB, b, "{}", 1);
    const t0 = 1_000_000;
    const tomb = (n: db.NoteInput) => ({ ...n, deleted: true, ...(n.blob === null ? { text: "" } : {}) });
    await db.writeNotes(env.DB, a, [tomb(plain("old1", 1)), tomb(plain("old2", 1)), tomb(plain("rewritten", 1)), plain("live", 1, "x")], false, L(10), t0);
    await db.writeNotes(env.DB, b, [tomb(enc("e-old", 1)), enc("e-live", 1)], true, L(10), t0);
    // "rewritten" is written again later (a newer tombstone): stored_at moves.
    await db.writeNotes(env.DB, a, [tomb(plain("rewritten", 2))], false, L(10), t0 + 500);
    const purged = await db.purgeTombstones(env.DB, t0 + 100);
    expect(purged).toBeGreaterThanOrEqual(3);
    expect((await db.changes(env.DB, a, 0, 10))!.notes.map((n) => n.key).sort()).toEqual(["live", "rewritten"]);
    expect((await db.changes(env.DB, b, 0, 10))!.notes.map((n) => n.key)).toEqual(["e-live"]);
    await expectConsistent(a);
    await expectConsistent(b);
    expect(await countersOf(a)).toEqual({ note_count: 1, bytes: 5 + "rewritten".length });
    expect(await countersOf(b)).toEqual({ note_count: 1, bytes: 6 + 4 });
    // last_seq stays.
    expect((await db.changes(env.DB, a, 0, 10))!.latestSeq).toBe(5);
  });

  it("purge limit: deterministic subset, counters match", async () => {
    const id = await newIdentity();
    const notes = Array.from({ length: 7 }, (_, i) => ({ ...plain(`t${i}`, 1, ""), deleted: true }));
    await db.writeNotes(env.DB, id, notes, false, L(10), 10);
    // Other identities' old tombstones may exist in the shared store; purge
    // in small steps until ours are gone, checking consistency each time.
    for (let i = 0; i < 1000; i++) {
      const n = await db.purgeTombstones(env.DB, 11, 3);
      await expectConsistent(id);
      if (n < 3) break;
    }
    expect((await db.changes(env.DB, id, 0, 10))!.notes).toEqual([]);
    expect(await countersOf(id)).toEqual({ note_count: 0, bytes: 0 });
  });

  it("deleting an identity cascades to notes, sessions and header (no counter work needed)", async () => {
    const id = await newIdentity();
    await db.createE2eHeader(env.DB, id, "{}", 1);
    await db.writeNotes(env.DB, id, [enc("k1", 1)], true, L(10));
    await env.DB.prepare("DELETE FROM identities WHERE id = ?").bind(id).run();
    const left = await env.DB.prepare(
      "SELECT (SELECT count(*) FROM notes WHERE identity_id = ?1) + (SELECT count(*) FROM sessions WHERE identity_id = ?1) " +
        "+ (SELECT count(*) FROM e2e_headers WHERE identity_id = ?1) AS c",
    )
      .bind(id)
      .first<{ c: number }>();
    expect(left!.c).toBe(0);
  });

  it("no triggers left in the schema", async () => {
    const t = await env.DB.prepare("SELECT name FROM sqlite_master WHERE type = 'trigger'").all();
    expect(t.results).toEqual([]);
  });
});
