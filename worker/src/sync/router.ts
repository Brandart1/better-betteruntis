import type { Env } from "../env";

/** Notes sync API. Implemented in step 2 (see docs/SYNC-PLAN.md). */
export async function handleSync(_request: Request, _env: Env, _ctx: ExecutionContext): Promise<Response> {
  return new Response(JSON.stringify({ error: "not_implemented", message: "Sync is not implemented yet." }), {
    status: 501,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}
