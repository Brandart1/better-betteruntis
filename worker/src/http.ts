/** Small response helpers shared by the Worker's own endpoints. */

/** Security headers for every response (the static assets get them via public/_headers). */
export const SECURITY_HEADERS: Readonly<Record<string, string>> = {
  "cross-origin-opener-policy": "same-origin",
  "cross-origin-embedder-policy": "credentialless",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
};

/** Copy of `res` with the security headers set (headers of fetched responses are immutable). */
export function withSecurityHeaders(res: Response): Response {
  // WebSocket upgrades can't be re-wrapped; the Worker doesn't produce any.
  if (res.webSocket) return res;
  const out = new Response(res.body, res);
  for (const [k, v] of Object.entries(SECURITY_HEADERS)) out.headers.set(k, v);
  return out;
}

/** Plain-text error, like the Dart server's proxy errors. */
export function textError(status: number, message: string, extra?: Record<string, string>): Response {
  return new Response(message, {
    status,
    headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store", ...extra },
  });
}

/** JSON error `{"error": code, "message"?}` (sync API format). */
export function jsonError(status: number, error: string, message?: string, extra?: Record<string, string>): Response {
  return new Response(JSON.stringify(message === undefined ? { error } : { error, message }), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...extra },
  });
}

export class TooLargeError extends Error {
  constructor() {
    super("body too large");
  }
}

/**
 * Reads a body stream into one buffer, throwing TooLargeError as soon as it
 * exceeds `limit` bytes (the stream is cancelled).
 */
export async function readLimited(body: ReadableStream<Uint8Array> | null, limit: number): Promise<Uint8Array> {
  if (body === null) return new Uint8Array(0);
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > limit) {
        await reader.cancel().catch(() => {});
        throw new TooLargeError();
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  if (chunks.length === 1) return chunks[0]!;
  const out = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) {
    out.set(c, off);
    off += c.byteLength;
  }
  return out;
}
