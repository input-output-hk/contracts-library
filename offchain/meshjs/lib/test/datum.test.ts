import { describe, expect, it } from "vitest";
import { requiredRemainder, vestedQuantity } from "../src/datum";
import type { VestingDatum } from "../src/types";

describe("vestedQuantity (mirrors onchain lib/vesting/linear.ak)", () => {
  it("is zero at or before start", () => {
    expect(vestedQuantity(100n, 1000, 2000, 1000)).toBe(0n);
    expect(vestedQuantity(100n, 1000, 2000, 500)).toBe(0n);
  });

  it("is the full total at or after end", () => {
    expect(vestedQuantity(100n, 1000, 2000, 2000)).toBe(100n);
    expect(vestedQuantity(100n, 1000, 2000, 9999)).toBe(100n);
  });

  it("is linear and floored in the middle", () => {
    expect(vestedQuantity(100n, 1000, 2000, 1500)).toBe(50n);
    expect(vestedQuantity(100n, 1000, 2000, 1250)).toBe(25n);
    // floor: 100 * 333 / 1000 = 33.3 -> 33
    expect(vestedQuantity(100n, 1000, 2000, 1333)).toBe(33n);
  });

  it("never exceeds the total and is non-decreasing", () => {
    let prev = -1n;
    for (let now = 900; now <= 2100; now += 7) {
      const v = vestedQuantity(1_000_000n, 1000, 2000, now);
      expect(v).toBeGreaterThanOrEqual(0n);
      expect(v).toBeLessThanOrEqual(1_000_000n);
      expect(v).toBeGreaterThanOrEqual(prev);
      prev = v;
    }
  });
});

describe("requiredRemainder", () => {
  const datum: VestingDatum = {
    beneficiary: { kind: "key", hash: "ab".repeat(28) },
    locker: { kind: "key", hash: "ef".repeat(28) },
    vesting: [
      { policyId: "", assetName: "", total: 100n },
      { policyId: "cd".repeat(28), assetName: "544f4b454e", total: 10n },
    ],
    startTime: 1000,
    endTime: 2000,
    recoveryTime: 3000,
  };

  it("keeps total - vested per asset mid-schedule", () => {
    const r = requiredRemainder(datum, 1500);
    expect(r).toEqual([
      { policyId: "", assetName: "", total: 50n },
      { policyId: "cd".repeat(28), assetName: "544f4b454e", total: 5n },
    ]);
  });

  it("is empty once fully vested (no continuing output needed)", () => {
    expect(requiredRemainder(datum, 2000)).toEqual([]);
  });

  it("requires the whole bundle before start", () => {
    const r = requiredRemainder(datum, 1000);
    expect(r.map((a) => a.total)).toEqual([100n, 10n]);
  });
});
