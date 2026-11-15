import { SELF } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { expect, it } from "vitest";

it("answers /healthz", async () => {
  const res = await SELF.fetch("https://bbu.test/healthz");
  expect(res.status).toBe(200);
  expect(await res.text()).toBe("ok");
});

it("has the D1 binding with migrations applied", async () => {
  const row = await env.DB.prepare("SELECT name FROM sqlite_master WHERE name = 'meta'").first();
  expect(row).not.toBeNull();
});

it("has the rate limit bindings", async () => {
  const r = await env.RL_SESSION.limit({ key: "smoke" });
  expect(r.success).toBe(true);
});
