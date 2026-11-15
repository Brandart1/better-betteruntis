/** JSON responses, errors and body reading for the sync API (sync-specific; shared helpers are in ../http.ts). */
import { jsonError as sharedJsonError, readLimited, TooLargeError } from "../http";

export const JSON_HEADERS: Record<string, string> = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...JSON_HEADERS, ...headers } });
}

/** A JSON error `{"error": code, "message": message}`. Messages never contain user data. */
export function jsonError(
  status: number,
  code: string,
  message: string,
  headers: Record<string, string> = {},
): Response {
  return sharedJsonError(status, code, message, headers);
}

export function noContent(headers: Record<string, string> = {}): Response {
  return new Response(null, { status: 204, headers: { "cache-control": "no-store", ...headers } });
}

export function methodNotAllowed(allow: string): Response {
  return jsonError(405, "method_not_allowed", "Method not allowed.", { allow });
}

/** Thrown by handlers to answer with a JSON error. */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly headers: Record<string, string> = {},
  ) {
    super(message);
  }

  toResponse(): Response {
    return jsonError(this.status, this.code, this.message, this.headers);
  }
}

/** True if the request's content-type is application/json (any parameters). */
export function isJsonContentType(request: Request): boolean {
  const ct = request.headers.get("content-type");
  if (ct === null) return false;
  return ct.split(";")[0]!.trim().toLowerCase() === "application/json";
}

/** Strict UTF-8 decoding; null for invalid UTF-8. */
export function utf8Decode(bytes: Uint8Array): string | null {
  try {
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
  } catch {
    return null;
  }
}

/**
 * Reads and parses a JSON body of at most [limit] bytes (declared or
 * streamed). Throws [HttpError] 413 `body_too_large` or 400 `bad_request`
 * (invalid UTF-8 or JSON).
 */
export async function readJsonBody(request: Request, limit: number): Promise<unknown> {
  const declared = request.headers.get("content-length");
  if (declared !== null && /^\d+$/.test(declared) && Number(declared) > limit) {
    throw tooLarge(limit);
  }
  let bytes: Uint8Array;
  try {
    bytes = await readLimited(request.body, limit);
  } catch (e) {
    if (e instanceof TooLargeError) throw tooLarge(limit);
    throw new HttpError(400, "bad_request", "Could not read the request body.");
  }
  const text = utf8Decode(bytes);
  if (text === null) throw new HttpError(400, "bad_request", "Body is not valid UTF-8.");
  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new HttpError(400, "bad_request", "Body is not valid JSON.");
  }
}

function tooLarge(limit: number): HttpError {
  return new HttpError(413, "body_too_large", `Request body larger than ${limit} bytes.`);
}

export function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** True if [s] contains a lone UTF-16 surrogate (not representable in UTF-8) or NUL. */
export function hasBadChars(s: string): boolean {
  return /[\u0000]|[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/.test(s);
}

const BASE64URL = /^[A-Za-z0-9_-]*$/;

/** True if [s] is unpadded base64url of [min]..[max] characters. */
export function isBase64Url(s: unknown, min: number, max: number): s is string {
  return typeof s === "string" && s.length >= min && s.length <= max && BASE64URL.test(s) && s.length % 4 !== 1;
}

export function base64UrlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
