/**
 * BetterBetterUntis Worker entry point. Static assets (the web app) are
 * served by Cloudflare directly; the Worker only runs for /proxy/* (WebUntis
 * relay) and /api/* (optional notes sync). See ../docs/SYNC-PLAN.md.
 */
import type { Env } from "./env";
import { withSecurityHeaders } from "./http";
import { handleProxy } from "./proxy";
import { handleSync } from "./sync/router";

async function route(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const path = new URL(request.url).pathname;
  if (path === "/healthz") {
    return new Response("ok", {
      headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
    });
  }
  if (path === "/proxy" || path.startsWith("/proxy/")) {
    return handleProxy(request, env, ctx);
  }
  if (path === "/api/sync" || path.startsWith("/api/sync/")) {
    return handleSync(request, env, ctx);
  }
  // Asset responses get their headers from public/_headers.
  return env.ASSETS.fetch(request);
}

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const res = await route(request, env, ctx);
    // Worker-generated responses (/proxy, /api, /healthz) need the same
    // security headers as the assets; setting them again on assets is harmless.
    return withSecurityHeaders(res);
  },
} satisfies ExportedHandler<Env>;
