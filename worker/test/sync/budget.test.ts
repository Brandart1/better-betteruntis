import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import * as db from "../../src/sync/db";
import { LIMITS, secondsToNextUtcDay } from "../../src/sync/notes";
import { call, e2eHeader, freshUser, HOST, identityId, login, note, put, req, AUTH_KEY } from "./helpers";

async function errorOf(res: Response): Promise<string> {
  return ((await res.json()) as { error: string }).error;
}

describe("daily write budget (HTTP)", () => {
  it("5 000 note writes per UTC day -> 429 daily_limit with retry-after to midnight; next day works", async () => {
    const s = await login(freshUser());
    const t = Date.UTC(2026, 10, 16, 23, 59, 0, 500);
    const clock = { now: () => t };
    expect(LIMITS.maxWritesPerDay).toBe(5000);
    for (let b = 0; b < LIMITS.maxWritesPerDay / 500; b++) {
      const res = await put(s.token, Array.from({ length: 500 }, (_, i) => note(`b${b}-${i}`, 1)), clock);
      expect(res.status).toBe(200);
    }
    // Re-sending stored versions (nothing newer) costs nothing and still works.
    expect((await put(s.token, [note("b0-0", 1)], clock)).status).toBe(200);
    const res = await put(s.token, [note("b0-0", 2, "overwrite")], clock);
    expect([res.status, res.headers.get("retry-after")]).toEqual([429, "60"]);
    expect(await errorOf(res)).toBe("daily_limit");
    // Tombstones count too.
    expect((await put(s.token, [note("b0-1", 2, "", { deleted: true })], clock)).status).toBe(429);
    const nextDay = { now: () => t + 60_000 };
    expect((await put(s.token, [note("b0-0", 2, "overwrite")], nextDay)).status).toBe(200);
  });

  it("the budget is per identity", async () => {
    const id = await identityId((await login(freshUser())).body.identity.userId);
    await env.DB.prepare("UPDATE identities SET budget_day = ?2, budget_used = ?3 WHERE id = ?1")
      .bind(id, Math.floor(Date.now() / db.DAY_MS), LIMITS.maxWritesPerDay)
      .run();
    const other = await login(freshUser());
    expect((await put(other.token, [note("k", 1)])).status).toBe(200);
  });

  it("secondsToNextUtcDay", () => {
    expect(secondsToNextUtcDay(Date.UTC(2026, 0, 1))).toBe(86400);
    expect(secondsToNextUtcDay(Date.UTC(2026, 0, 1, 23, 59, 59, 999))).toBe(1);
    expect(secondsToNextUtcDay(Date.UTC(2026, 0, 1, 12))).toBe(43200);
  });
});

/** An env whose DB deletes [identityId] right after the session lookup returned. */
function deletingEnv(id: number): typeof env {
  const real = env.DB;
  const DB = new Proxy(real, {
    get(target, prop) {
      if (prop === "prepare") {
        return (sql: string) => {
          const stmt = target.prepare(sql);
          if (!sql.startsWith("SELECT s.identity_id")) return stmt;
          return {
            bind: (...args: unknown[]) => {
              const bound = stmt.bind(...args);
              return {
                first: async () => {
                  const row = await bound.first();
                  await db.deleteIdentity(real, id);
                  return row;
                },
              };
            },
          };
        };
      }
      const v = Reflect.get(target, prop);
      return typeof v === "function" ? v.bind(target) : v;
    },
  });
  return { ...env, DB };
}

describe("identity deleted between session lookup and statement (L1) -> 401", () => {
  const cases: [string, string, (token: string) => Request][] = [
    ["GET notes", "GET", (t) => req("GET", "/api/sync/notes", { token: t })],
    ["PUT notes", "PUT", (t) => req("PUT", "/api/sync/notes", { token: t, body: { notes: [note("a", 1)] } })],
    ["PUT empty notes", "PUT", (t) => req("PUT", "/api/sync/notes", { token: t, body: { notes: [] } })],
    ["GET e2e", "GET", (t) => req("GET", "/api/sync/e2e", { token: t })],
    ["PUT e2e", "PUT", (t) => req("PUT", "/api/sync/e2e", { token: t, body: e2eHeader() })],
    ["PATCH e2e", "PATCH", (t) => req("PATCH", "/api/sync/e2e", { token: t, body: { header: e2eHeader(), authKey: AUTH_KEY } })],
    ["DELETE e2e", "DELETE", (t) => req("DELETE", "/api/sync/e2e", { token: t, body: { authKey: AUTH_KEY } })],
  ];
  for (const [name, , mk] of cases) {
    it(name, async () => {
      const user = freshUser();
      const s = await login(user);
      const id = await identityId(user);
      const res = await call(mk(s.token), {}, deletingEnv(id));
      expect([res.status, await errorOf(res)]).toEqual([401, "unauthorized"]);
      expect(await env.DB.prepare("SELECT 1 FROM identities WHERE id = ?").bind(id).first()).toBeNull();
      expect(await env.DB.prepare("SELECT count(*) AS c FROM notes WHERE identity_id = ?").bind(id).first()).toEqual({ c: 0 });
    });
  }
});

/** D1 rows read/written by every batch / statement through a wrapped DB. */
function metered(d: D1Database) {
  const m = { read: 0, written: 0 };
  const add = (r: D1Result) => {
    m.read += r.meta.rows_read ?? 0;
    m.written += r.meta.rows_written ?? 0;
  };
  const wrapStmt = (s: D1PreparedStatement): D1PreparedStatement =>
    new Proxy(s, {
      get(t, p) {
        if (p === "bind") return (...a: unknown[]) => wrapStmt(t.bind(...a));
        if (p === "all" || p === "run") return async () => { const r = await (t as any)[p](); add(r); return r; };
        if (p === "first") return async () => { const r = await t.all(); add(r); return r.results[0] ?? null; };
        const v = Reflect.get(t, p);
        return typeof v === "function" ? v.bind(t) : v;
      },
    });
  const wrapped = new Proxy(d, {
    get(t, p) {
      if (p === "prepare") return (sql: string) => wrapStmt(t.prepare(sql));
      if (p === "batch") return async (s: D1PreparedStatement[]) => { const r = await t.batch(s); r.forEach(add); return r; };
      const v = Reflect.get(t, p);
      return typeof v === "function" ? v.bind(t) : v;
    },
  });
  return { db: wrapped, m };
}

describe("D1 row cost of a 500-note PUT (regression guard; D1 bills rows)", () => {
  it("insert / overwrite / no-op / tombstones", async () => {
    const user = freshUser();
    await db.createSession(env.DB, `rows-${user}`, { host: HOST, school: "s", userId: user }, Date.now(), Date.now() + 1e6, "r".repeat(22));
    const id = await identityId(user, "s");
    const limits = { maxNotes: LIMITS.maxNotesPerUser, maxBytes: LIMITS.maxBytesPerUser, dailyWrites: LIMITS.maxWritesPerDay };
    const batch = (u: number, deleted = false): db.NoteInput[] =>
      Array.from({ length: 500 }, (_, i) => ({
        key: `2026-11-${String(i).padStart(3, "0")}|lesson-${i}`,
        exam: false,
        text: deleted ? "" : "x".repeat(50),
        blob: null,
        updatedAt: u,
        deleted,
      }));
    const cost = async (notes: db.NoteInput[]) => {
      const { db: w, m } = metered(env.DB);
      const out = await db.writeNotes(w, id, notes, false, limits);
      expect(out.ok).toBe(true);
      return m;
    };
    // Measured: 2514 / 1001 (was 7010 / 1501 with triggers + plan statement).
    const insert = await cost(batch(1));
    expect(insert.written).toBeLessThanOrEqual(1001); // 500 notes + 500 seq index entries + 1 identity row
    expect(insert.read).toBeLessThanOrEqual(2600);
    // Measured: 3014 / 1001 (was 8510 / 1501).
    const overwrite = await cost(batch(2));
    expect(overwrite.written).toBeLessThanOrEqual(1001);
    expect(overwrite.read).toBeLessThanOrEqual(3100);
    // Nothing newer: nothing written. Measured: 3010 reads (was 5512).
    const noop = await cost(batch(2));
    expect(noop.written).toBe(0);
    expect(noop.read).toBeLessThanOrEqual(3100);
    // Tombstones also enter the partial purge index. Measured: 3014 / 1501.
    const tomb = await cost(batch(3, true));
    expect(tomb.written).toBeLessThanOrEqual(1501);
  });
});
