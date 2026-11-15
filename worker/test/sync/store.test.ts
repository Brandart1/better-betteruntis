import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import * as db from "../../src/sync/db";
import { mergeDuplicates } from "../../src/sync/notes";
import { freshUser, HOST } from "./helpers";

/** Store semantics directly on D1 (no HTTP), incl. the guards inside the write statement. */

async function newIdentity(): Promise<number> {
  const user = freshUser();
  await db.createSession(env.DB, `hash-${user}`, { host: HOST, school: "s", userId: user }, Date.now(), Date.now() + 1000);
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
    const out = await db.writeNotes(env.DB, id, [plain("a", 1)], false, 100);
    expect(out).toEqual({ ok: false, reason: "e2e_required" });
    expect((await db.changes(env.DB, id, 0, 10)).notes).toEqual([]);
  });

  it("encrypted write is a no-op without a header", async () => {
    const id = await newIdentity();
    const out = await db.writeNotes(env.DB, id, [enc("a", 1)], true, 100);
    expect(out).toEqual({ ok: false, reason: "e2e_not_enabled" });
    expect((await db.changes(env.DB, id, 0, 10)).notes).toEqual([]);
  });

  it("quota is enforced inside the statement, all or nothing", async () => {
    const id = await newIdentity();
    expect((await db.writeNotes(env.DB, id, [plain("a", 1), plain("b", 1)], false, 3)).ok).toBe(true);
    const out = await db.writeNotes(env.DB, id, [plain("a", 2, "upd"), plain("c", 1), plain("d", 1)], false, 3);
    expect(out).toEqual({ ok: false, reason: "too_many_notes" });
    const page = await db.changes(env.DB, id, 0, 10);
    expect(page.notes.map((n) => [n.key, n.text])).toEqual([
      ["a", "t"],
      ["b", "t"],
    ]);
    expect(page.latestSeq).toBe(2);
    // Exactly at the limit is fine.
    expect((await db.writeNotes(env.DB, id, [plain("c", 1)], false, 3)).ok).toBe(true);
  });

  it("only newer versions get a seq; seqs are dense per write and last_seq never goes back", async () => {
    const id = await newIdentity();
    await db.writeNotes(env.DB, id, [plain("a", 10), plain("b", 10)], false, 100);
    const out = await db.writeNotes(env.DB, id, [plain("a", 5), plain("c", 1), plain("b", 11)], false, 100);
    expect(out.ok && out.result.notes.map((n) => [n.key, n.seq])).toEqual([
      ["a", 1],
      ["c", 3],
      ["b", 4],
    ]);
    // Deleting notes (e.g. E2E turned on) doesn't lower last_seq.
    await env.DB.prepare("DELETE FROM notes WHERE identity_id = ?").bind(id).run();
    const after = await db.writeNotes(env.DB, id, [plain("z", 1)], false, 100);
    expect(after.ok && after.result.notes[0]!.seq).toBe(5);
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
    await db.createSession(env.DB, `h-${user}`, who, 1000, 5000);
    expect((await db.findSession(env.DB, `h-${user}`, 4999))?.identity).toEqual(who);
    expect(await db.findSession(env.DB, `h-${user}`, 5000)).toBeNull();
    await db.deleteSession(env.DB, `h-${user}`);
    expect(await db.findSession(env.DB, `h-${user}`, 1000)).toBeNull();
  });

  it("sessions don't touch notes", async () => {
    const id = await newIdentity();
    await db.writeNotes(env.DB, id, [plain("a", 1)], false, 10);
    await env.DB.prepare("DELETE FROM sessions WHERE identity_id = ?").bind(id).run();
    expect((await db.changes(env.DB, id, 0, 10)).notes).toHaveLength(1);
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
