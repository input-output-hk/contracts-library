import { describe, expect, it } from "vitest";
import {
  walletBurnRedeemer,
  walletCloseRedeemer,
  walletDepositRedeemer,
  walletDatumToData,
  walletMintRedeemer,
  walletSpendRedeemer,
  walletUpdatePermissionsRedeemer,
} from "../../src/smart_wallet/datum";
import type { WalletDatum } from "../../src/smart_wallet/types";

/** MeshJS `Data` constructor variant, for structural assertions. */
interface Constr {
  alternative: number;
  fields: unknown[];
}

function asConstr(d: unknown): Constr {
  return d as Constr;
}

describe("walletDatumToData", () => {
  const spenders = [
    { scriptHash: "aa".repeat(28), data: 0 },
    { scriptHash: "bb".repeat(28), data: "00" },
  ];
  const depositors = [{ scriptHash: "cc".repeat(28), data: 1 }];
  const datum: WalletDatum = { spenders, depositors };

  it("encodes Constr 0 with spenders and depositors as association maps", () => {
    const d = asConstr(walletDatumToData(datum));
    expect(d.alternative).toBe(0);
    expect(d.fields).toHaveLength(2);

    const [s, dep] = d.fields as unknown as [
      Map<unknown, unknown>,
      Map<unknown, unknown>,
    ];
    expect(s).toBeInstanceOf(Map);
    expect(dep).toBeInstanceOf(Map);
    expect([...s.entries()]).toEqual([
      [spenders[0].scriptHash, spenders[0].data],
      [spenders[1].scriptHash, spenders[1].data],
    ]);
    expect([...dep.entries()]).toEqual([
      [depositors[0].scriptHash, depositors[0].data],
    ]);
  });

  it("encodes empty maps", () => {
    const d = asConstr(walletDatumToData({ spenders: [], depositors: [] }));
    expect((d.fields[0] as Map<unknown, unknown>).size).toBe(0);
    expect((d.fields[1] as Map<unknown, unknown>).size).toBe(0);
  });
});

describe("redeemer constructor indices", () => {
  it("match the Aiken SpendRedeemer / MintRedeemer order", () => {
    expect(asConstr(walletSpendRedeemer())).toEqual({
      alternative: 0,
      fields: [],
    });
    expect(asConstr(walletUpdatePermissionsRedeemer(1))).toEqual({
      alternative: 1,
      fields: [1],
    });
    expect(asConstr(walletDepositRedeemer(2))).toEqual({
      alternative: 2,
      fields: [2],
    });
    expect(asConstr(walletCloseRedeemer())).toEqual({
      alternative: 3,
      fields: [],
    });
    expect(asConstr(walletMintRedeemer(0))).toEqual({
      alternative: 0,
      fields: [0],
    });
    expect(asConstr(walletBurnRedeemer())).toEqual({
      alternative: 1,
      fields: [],
    });
  });
});
