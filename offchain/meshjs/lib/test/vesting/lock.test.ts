import type { Asset, MeshTxBuilder } from "@meshsdk/core";
import { describe, expect, it, vi } from "vitest";
import type { VestingDatum } from "../../src/vesting/types";
import {
  assertLockValue,
  buildLockTx,
  type LockValueOptions,
} from "../../src/vesting/vesting";

const ADA = 1_000_000n;
const TOKEN = `${"cd".repeat(28)}544f4b454e`;

const datum: VestingDatum = {
  beneficiary: { kind: "key", hash: "ab".repeat(28) },
  locker: { kind: "key", hash: "ef".repeat(28) },
  vesting: [
    { policyId: "", assetName: "", total: 100n * ADA },
    { policyId: TOKEN.slice(0, 56), assetName: TOKEN.slice(56), total: 10n },
  ],
  startTime: 1_000,
  endTime: 2_000,
  recoveryTime: 3_000,
};

const minLovelace = 2n * ADA;

function assets(...entries: Array<[unit: string, quantity: bigint]>): Asset[] {
  return entries.map(([unit, quantity]) => ({
    unit,
    quantity: quantity.toString(),
  }));
}

function options(overrides: Partial<LockValueOptions> = {}): LockValueOptions {
  return { minLovelace, ...overrides };
}

const completeBundle = assets(["lovelace", 100n * ADA], [TOKEN, 10n]);

describe("assertLockValue", () => {
  it("accepts a value that exactly covers the datum totals", () => {
    expect(() =>
      assertLockValue(datum, completeBundle, options()),
    ).not.toThrow();
  });

  it("accepts min-ada when the bundle has less ada than the floor", () => {
    const lowAda: VestingDatum = {
      ...datum,
      vesting: [
        { policyId: "", assetName: "", total: 1n * ADA },
        {
          policyId: TOKEN.slice(0, 56),
          assetName: TOKEN.slice(56),
          total: 10n,
        },
      ],
    };
    expect(() =>
      assertLockValue(
        lowAda,
        assets(["lovelace", minLovelace], [TOKEN, 10n]),
        options(),
      ),
    ).not.toThrow();
  });

  it("accepts min-ada for an empty bundle but rejects anything above it", () => {
    const empty: VestingDatum = { ...datum, vesting: [] };
    expect(() =>
      assertLockValue(empty, assets(["lovelace", minLovelace]), options()),
    ).not.toThrow();
    expect(() =>
      assertLockValue(empty, assets(["lovelace", minLovelace + 1n]), options()),
    ).toThrow(/exceeds the datum totals/);
  });

  it("rejects an underfunded listed asset", () => {
    expect(() =>
      assertLockValue(
        datum,
        assets(["lovelace", 100n * ADA], [TOKEN, 9n]),
        options(),
      ),
    ).toThrow(/short of the datum totals.*1 of cd/);
  });

  it("rejects an output below the min-ada floor", () => {
    const empty: VestingDatum = { ...datum, vesting: [] };
    expect(() =>
      assertLockValue(empty, assets(["lovelace", 1n * ADA]), options()),
    ).toThrow(/min-ada floor/);
  });

  it("rejects surplus of a listed asset", () => {
    expect(() =>
      assertLockValue(
        datum,
        assets(["lovelace", 101n * ADA], [TOKEN, 10n]),
        options(),
      ),
    ).toThrow(/1000000 of ada exceeds the datum totals/);
  });

  it("rejects an unlisted token", () => {
    expect(() =>
      assertLockValue(
        datum,
        assets(
          ["lovelace", 100n * ADA],
          [TOKEN, 10n],
          [`${"ef".repeat(28)}01`, 1n],
        ),
        options(),
      ),
    ).toThrow(/1 of ef[0-9a-f]+01 exceeds the datum totals/);
  });

  it("rejects unlisted ada above min-ada", () => {
    const noAda: VestingDatum = {
      ...datum,
      vesting: [
        {
          policyId: TOKEN.slice(0, 56),
          assetName: TOKEN.slice(56),
          total: 10n,
        },
      ],
    };
    expect(() =>
      assertLockValue(
        noAda,
        assets(["lovelace", minLovelace + 1n], [TOKEN, 10n]),
        options(),
      ),
    ).toThrow(/1 of ada exceeds the datum totals/);
  });

  it("warns instead of rejecting when unprotected value is allowed", () => {
    const warn = vi.fn();
    expect(() =>
      assertLockValue(
        datum,
        assets(["lovelace", 101n * ADA], [TOKEN, 11n]),
        options({ allowUnprotectedValue: true, logger: { warn } }),
      ),
    ).not.toThrow();
    expect(warn).toHaveBeenCalledOnce();
    expect(warn.mock.calls[0][0]).toMatch(/not schedule-protected/);
  });

  it("rejects invalid asset quantities and units", () => {
    expect(() =>
      assertLockValue(datum, [{ unit: "lovelace", quantity: "-1" }], options()),
    ).toThrow(/not a non-negative integer/);
    expect(() =>
      assertLockValue(datum, [{ unit: "lovelace", quantity: "1" }], {
        minLovelace: -1n,
      }),
    ).toThrow(/minUtxoLovelace/);
  });
});

describe("buildLockTx lock checks", () => {
  const params = (overrides: Partial<Parameters<typeof buildLockTx>[0]>) => ({
    txBuilder: {} as MeshTxBuilder,
    datum,
    utxos: [],
    changeAddress: "addr_test1...",
    ...overrides,
  });

  it("rejects a degenerate schedule before building", async () => {
    await expect(
      buildLockTx(params({ datum: { ...datum, endTime: datum.startTime } })),
    ).rejects.toThrow(/startTime < endTime < recoveryTime/);
    await expect(
      buildLockTx(
        params({
          datum: { ...datum, recoveryTime: datum.endTime },
        }),
      ),
    ).rejects.toThrow(/startTime < endTime < recoveryTime/);
  });

  it("rejects a lock value that does not cover the datum", async () => {
    await expect(
      buildLockTx(
        params({
          lockAssets: assets(["lovelace", 5n * ADA], [TOKEN, 10n]),
        }),
      ),
    ).rejects.toThrow(/short of the datum totals/);
  });

  it("rejects unprotected value by default", async () => {
    await expect(
      buildLockTx(
        params({
          lockAssets: assets(["lovelace", 101n * ADA], [TOKEN, 10n]),
        }),
      ),
    ).rejects.toThrow(/exceeds the datum totals/);
  });
});
