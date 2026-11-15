import { describe, expect, it } from "vitest";
import { rateLimitIpKey } from "../src/ip";

describe("rateLimitIpKey", () => {
  const cases: [string | null, string][] = [
    ["203.0.113.7", "203.0.113.7"],
    [" 10.0.0.1 ", "10.0.0.1"],
    ["2001:db8:1:2:3:4:5:6", "2001:db8:1:2::/64"],
    ["2001:DB8:1:2::abcd", "2001:db8:1:2::/64"],
    ["2001:0db8:0001:0002:ffff::", "2001:db8:1:2::/64"],
    ["2001:db8::1", "2001:db8:0:0::/64"],
    ["::1", "0:0:0:0::/64"],
    ["fe80::1%eth0", "fe80:0:0:0::/64"],
    ["::ffff:192.0.2.1", "192.0.2.1"],
    ["64:ff9b::192.0.2.1", "64:ff9b:0:0::/64"],
    [null, "unknown"],
    ["", "unknown"],
    ["not-an-ip", "not-an-ip"],
    ["1:2:3:4:5:6:7:8:9", "1:2:3:4:5:6:7:8:9"],
    ["1::2::3", "1::2::3"],
    ["999.1.1.1", "999.1.1.1"],
    ["x".repeat(100), "x".repeat(64)],
  ];
  for (const [ip, key] of cases) {
    it(`${ip} -> ${key.slice(0, 20)}`, () => expect(rateLimitIpKey(ip)).toBe(key));
  }

  it("all addresses of one /64 share a key, neighbouring /64s don't", () => {
    expect(rateLimitIpKey("2001:db8:a:b:1::")).toBe(rateLimitIpKey("2001:db8:a:b:ffff:ffff:ffff:ffff"));
    expect(rateLimitIpKey("2001:db8:a:b::1")).not.toBe(rateLimitIpKey("2001:db8:a:c::1"));
  });
});
