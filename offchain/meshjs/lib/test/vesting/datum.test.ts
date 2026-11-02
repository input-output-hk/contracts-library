import { describe, expect, it } from "vitest";
import {
  assertValidBundle,
  requiredRemainder,
  sortVestingBundle,
  vestedQuantity,
} from "../../src/vesting/datum";
import type { VestingDatum } from "../../src/vesting/types";

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

describe("vesting bundle well-formedness (mirrors onchain bundle_well_formed)", () => {
  const policyA = "cd".repeat(28);
  const policyB = "ef".repeat(28);
  const ada = { policyId: "", assetName: "", total: 100n };

  it("accepts a strictly ascending bundle, ada first", () => {
    expect(() =>
      assertValidBundle([
        ada,
        { policyId: policyA, assetName: "41", total: 1n },
        { policyId: policyA, assetName: "42", total: 0n },
        { policyId: policyB, assetName: "", total: 5n },
      ]),
    ).not.toThrow();
    expect(() => assertValidBundle([])).not.toThrow();
  });

  it("rejects duplicates", () => {
    const t = { policyId: policyA, assetName: "41", total: 1n };
    expect(() => assertValidBundle([t, t])).toThrow(/strictly ascending/);
  });

  it("rejects duplicates that differ only in hex case", () => {
    expect(() =>
      assertValidBundle([
        { policyId: policyA, assetName: "4a", total: 1n },
        { policyId: policyA, assetName: "4A", total: 1n },
      ]),
    ).toThrow(/strictly ascending/);
  });

  it("rejects unsorted entries", () => {
    expect(() =>
      assertValidBundle([
        { policyId: policyB, assetName: "", total: 1n },
        { policyId: policyA, assetName: "", total: 1n },
      ]),
    ).toThrow(/strictly ascending/);
  });

  it("rejects negative totals", () => {
    expect(() => assertValidBundle([{ ...ada, total: -1n }])).toThrow(
      /negative total/,
    );
  });

  it("sortVestingBundle puts entries in validator order", () => {
    const sorted = sortVestingBundle([
      { policyId: policyB, assetName: "", total: 1n },
      { policyId: policyA, assetName: "42", total: 1n },
      ada,
      { policyId: policyA, assetName: "41", total: 1n },
    ]);
    expect(sorted.map((a) => a.policyId + a.assetName)).toEqual([
      "",
      `${policyA}41`,
      `${policyA}42`,
      policyB,
    ]);
    expect(() => assertValidBundle(sorted)).not.toThrow();
  });
});
