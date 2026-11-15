import { describe, expect, it } from "vitest";
import { HostAllowlist, isValidHostname } from "../src/allowlist";

describe("host allowlist", () => {
  const allow = HostAllowlist.parse("webuntis.com,*.webuntis.com");

  it("accepts exact and wildcard hosts", () => {
    for (const h of ["webuntis.com", "mese.webuntis.com", "a.b.webuntis.com", "schoolsearch.webuntis.com"]) {
      expect(allow.allows(h), h).toBe(true);
    }
  });

  it("rejects look-alikes", () => {
    for (const h of [
      "evil.com",
      "webuntis.com.evil.com",
      "evilwebuntis.com",
      "xwebuntis.com",
      ".webuntis.com",
      "a..webuntis.com",
      "a.webuntis.com.",
      "-a.webuntis.com",
      "user@x.webuntis.com",
      "x.webuntis.com:444",
      "WEBUNTIS.COM", // allows() expects pre-lowercased input
      "127.0.0.1",
      "[::1]",
      "x%2ewebuntis.com",
      "schüle.webuntis.com", // IDNs only as punycode
      "",
    ]) {
      expect(allow.allows(h), h).toBe(false);
    }
  });

  it("accepts punycode labels", () => {
    expect(allow.allows("xn--schle-kva.webuntis.com")).toBe(true);
  });

  it("wildcard without exact does not match bare suffix", () => {
    const a = HostAllowlist.parse("*.example.org");
    expect(a.allows("example.org")).toBe(false);
    expect(a.allows("x.example.org")).toBe(true);
  });

  it("parses case-insensitively and ignores blanks", () => {
    const a = HostAllowlist.parse(" Untis.Example.ORG , ,*.WebUntis.com");
    expect(a.allows("untis.example.org")).toBe(true);
    expect(a.allows("x.webuntis.com")).toBe(true);
    expect(a.toString()).toBe("untis.example.org,*.webuntis.com");
  });

  it("rejects invalid allowlist entries", () => {
    for (const spec of ["", " , ", "*.", "a.com:80", "*", "localhost", "1.2.3.4", "*.*.com", "a b.com"]) {
      expect(() => HostAllowlist.parse(spec), spec).toThrow();
    }
  });

  it("validates hostname shape", () => {
    expect(isValidHostname("a".repeat(63) + ".com")).toBe(true);
    expect(isValidHostname("a".repeat(64) + ".com")).toBe(false);
    expect(isValidHostname(`${"a.".repeat(126)}com`)).toBe(false); // > 253 chars
    expect(isValidHostname("a-.com")).toBe(false);
    expect(isValidHostname("a.123")).toBe(false);
  });
});
