/**
 * Notes sync API (`/api/sync/*`, docs/SYNC-PLAN.md). Unknown paths get a
 * JSON 404, known paths with a wrong method a JSON 405 (before any auth).
 *
 * Privacy: nothing here logs bodies, tokens, note keys, texts or blobs;
 * unexpected errors are logged with the error name and a short identity
 * hash only.
 */
import type { Env } from "../env";
import {
  authenticate,
  CLEAR_COOKIE,
  createSessionHandler,
  deleteSessionHandler,
  identityLogTag,
  type AuthedRequest,
  type AuthOptions,
  type SyncDeps,
} from "./auth";
import * as db from "./db";
import { deleteE2e, getE2e, patchE2e, putE2e } from "./e2e";
import { HttpError, jsonError, methodNotAllowed, noContent } from "./http";
import { getNotes, putNotes } from "./notes";

type Handler = (request: Request, env: Env, deps: SyncDeps) => Promise<Response>;
type AuthedHandler = (request: Request, env: Env, auth: AuthedRequest, deps: SyncDeps) => Promise<Response>;

function errorName(e: unknown): string {
  return e instanceof Error ? e.name : "error";
}

/** Wraps [fn] with session authentication (and its rate limits). */
function authed(fn: AuthedHandler, options: AuthOptions = {}): Handler {
  return async (request, env, deps) => {
    const auth = await authenticate(request, env, deps, options);
    try {
      return await fn(request, env, auth, deps);
    } catch (e) {
      if (!(e instanceof HttpError)) {
        const tag = await identityLogTag(auth.identity);
        console.error(`sync ${request.method} ${new URL(request.url).pathname} id=${tag} failed: ${errorName(e)}`);
        throw new HttpError(500, "internal_error", "Something went wrong on the server.");
      }
      throw e;
    }
  };
}

const WRITE: AuthOptions = { write: true };

const ROUTES: Record<string, Record<string, Handler>> = {
  "/api/sync/session": {
    POST: (r, env, deps) => createSessionHandler(r, env, deps),
    DELETE: (r, env) => deleteSessionHandler(r, env),
  },
  "/api/sync/notes": {
    GET: authed((r, env, auth) => getNotes(r, env, auth)),
    PUT: authed((r, env, auth, deps) => putNotes(r, env, auth, deps), WRITE),
  },
  "/api/sync/e2e": {
    GET: authed((_r, env, auth) => getE2e(env, auth)),
    PUT: authed((r, env, auth, deps) => putE2e(r, env, auth, deps), WRITE),
    PATCH: authed((r, env, auth) => patchE2e(r, env, auth), WRITE),
    DELETE: authed((r, env, auth) => deleteE2e(r, env, auth), WRITE),
  },
  "/api/sync/account": {
    DELETE: authed(async (_r, env, auth) => {
      await db.deleteIdentity(env.DB, auth.identityId);
      return noContent({ "set-cookie": CLEAR_COOKIE });
    }),
  },
};

/**
 * Entry point (called from index.ts). [deps] lets tests inject the
 * upstream fetch and the clock; production uses the defaults.
 */
export async function handleSync(
  request: Request,
  env: Env,
  _ctx: ExecutionContext,
  deps: SyncDeps = {},
): Promise<Response> {
  const path = new URL(request.url).pathname;
  const methods = ROUTES[path];
  if (methods === undefined) return jsonError(404, "not_found", "Unknown sync endpoint.");
  const handler = methods[request.method];
  if (handler === undefined) return methodNotAllowed(Object.keys(methods).join(", "));
  try {
    return await handler(request, env, deps);
  } catch (e) {
    if (e instanceof HttpError) return e.toResponse();
    console.error(`sync ${request.method} ${path} failed: ${errorName(e)}`);
    return jsonError(500, "internal_error", "Something went wrong on the server.");
  }
}
