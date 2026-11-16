import { SELF } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { expect, it } from "vitest";

it("answers /healthz", async () => {
  const res = await SELF.fetch("https://bbu.test/healthz");
  expect(res.status).toBe(200);
  expect(await res.text()).toBe("ok");
});

it("has the D1 binding with migrations applied", async () => {
  const row = await env.DB.prepare("SELECT name FROM sqlite_master WHERE name = 'notes'").first();
  expect(row).not.toBeNull();
});

it("has the rate limit bindings", async () => {
  for (const rl of [env.RL_SESSION, env.RL_PROXY, env.RL_SYNC, env.RL_WRITE, env.RL_AUTH]) {
    expect((await rl.limit({ key: "smoke" })).success).toBe(true);
  }
});

it("answers sync_disabled without a database (web-only deployment)", async () => {
  const worker = (await import("../src/index")).default;
  const ctx = { waitUntil() {}, passThroughOnException() {} } as unknown as ExecutionContext;
  const res = await worker.fetch(
    new Request("https://bbu.test/api/sync/session", { method: "POST" }),
    { ...env, DB: undefined } as unknown as typeof env,
    ctx,
  );
  expect(res.status).toBe(404);
  expect(await res.json()).toEqual({ error: "sync_disabled" });
});
