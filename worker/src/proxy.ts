import type { Env } from "./env";

/** WebUntis relay. Implemented in step 1 (see docs/SYNC-PLAN.md). */
export async function handleProxy(_request: Request, _env: Env, _ctx: ExecutionContext): Promise<Response> {
  return new Response("not implemented", { status: 501 });
}
