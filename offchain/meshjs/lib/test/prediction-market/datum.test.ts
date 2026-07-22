import { describe, expect, it } from "vitest";
import {
  assetClassToData,
  credentialToData,
  mintActionToData,
  outcomeDatumToData,
  redemptionDatumToData,
  redemptionRedeemerToData,
  resolveRedeemer,
  tokenInfoToData,
} from "../../src/prediction-market/datum";
import type {
  AssetClass,
  OutcomeDatum,
  RedemptionDatum,
  TokenInfo,
} from "../../src/prediction-market/types";

const vkh = "ab".repeat(28);
const sh = "cd".repeat(28);

describe("credentialToData", () => {
  it("encodes a key credential as Constr 0 [hash]", () => {
    const d = credentialToData({ kind: "key", hash: vkh }) as {
      alternative: number;
      fields: string[];
    };
    expect(d.alternative).toBe(0);
    expect(d.fields).toEqual([vkh]);
  });

  it("encodes a script credential as Constr 1 [hash]", () => {
    const d = credentialToData({ kind: "script", hash: sh }) as {
      alternative: number;
      fields: string[];
    };
    expect(d.alternative).toBe(1);
    expect(d.fields).toEqual([sh]);
  });
});

describe("assetClassToData", () => {
  it("encodes an AssetClass as Constr 0 [policyId, assetName]", () => {
    const a: AssetClass = {
      policyId: "ff".repeat(28),
      assetName: "544f4b454e",
    };
    const d = assetClassToData(a) as {
      alternative: number;
      fields: string[];
    };
    expect(d.alternative).toBe(0);
    expect(d.fields).toEqual([a.policyId, a.assetName]);
  });
});

describe("tokenInfoToData", () => {
  it("encodes a TokenInfo as Constr 0 [AssetClass, amount]", () => {
    const t: TokenInfo = {
      asset: { policyId: "", assetName: "" },
      amount: 100n,
    };
    const d = tokenInfoToData(t) as {
      alternative: number;
      fields: unknown[];
    };
    expect(d.alternative).toBe(0);
    expect(d.fields).toHaveLength(2);
    const inner = d.fields[0] as { alternative: number; fields: string[] };
    expect(inner.alternative).toBe(0);
    expect(inner.fields).toEqual(["", ""]);
    expect(d.fields[1]).toBe(100n);
  });
});

describe("outcomeDatumToData", () => {
  it("encodes an OutcomeDatum as Constr 0 with 7 fields", () => {
    const datum: OutcomeDatum = {
      marketId: "aabb".repeat(14),
      cutoff: 1700000000000,
      winner: "None",
      outcomeCredential: { kind: "key", hash: vkh },
      resolutionTimeout: 1710000000000,
      claimDeadline: 1720000000000,
      collateral: {
        asset: { policyId: "", assetName: "" },
        amount: 50n,
      },
    };
    const d = outcomeDatumToData(datum) as {
      alternative: number;
      fields: unknown[];
    };
    expect(d.alternative).toBe(0);
    expect(d.fields).toHaveLength(7);
  });

  it("encodes a winner=Some(Yes) correctly in the option field", () => {
    const datum: OutcomeDatum = {
      marketId: "bb".repeat(28),
      cutoff: 1000,
      winner: { kind: "Some", value: "Yes" },
      outcomeCredential: { kind: "key", hash: vkh },
      resolutionTimeout: 2000,
      claimDeadline: 3000,
      collateral: {
        asset: { policyId: "cc".repeat(28), assetName: "" },
        amount: 10n,
      },
    };
    const d = outcomeDatumToData(datum) as {
      alternative: number;
      fields: unknown[];
    };
    const winnerField = d.fields[2] as {
      alternative: number;
      fields: unknown[];
    };
    expect(winnerField.alternative).toBe(1); // Some
    const winnerInner = winnerField.fields[0] as {
      alternative: number;
      fields: unknown[];
    };
    expect(winnerInner.alternative).toBe(0); // Yes
  });
});

describe("resolveRedeemer", () => {
  it("encodes Resolve(Yes) as Constr 0 [Constr 0 []]", () => {
    const r = resolveRedeemer("Yes") as {
      alternative: number;
      fields: unknown[];
    };
    expect(r.alternative).toBe(0);
    const inner = r.fields[0] as { alternative: number; fields: unknown[] };
    expect(inner.alternative).toBe(0);
    expect(inner.fields).toEqual([]);
  });

  it("encodes Resolve(No) as Constr 0 [Constr 1 []]", () => {
    const r = resolveRedeemer("No") as {
      alternative: number;
      fields: unknown[];
    };
    expect(r.alternative).toBe(0);
    const inner = r.fields[0] as { alternative: number; fields: unknown[] };
    expect(inner.alternative).toBe(1);
    expect(inner.fields).toEqual([]);
  });

  it("encodes Resolve(Draw) as Constr 0 [Constr 2 []]", () => {
    const r = resolveRedeemer("Draw") as {
      alternative: number;
      fields: unknown[];
    };
    expect(r.alternative).toBe(0);
    const inner = r.fields[0] as { alternative: number; fields: unknown[] };
    expect(inner.alternative).toBe(2);
    expect(inner.fields).toEqual([]);
  });
});

describe("redemptionDatumToData", () => {
  it("encodes a RedemptionDatum as Constr 0 [marketId, beaconPolicy]", () => {
    const d: RedemptionDatum = {
      marketId: "ee".repeat(28),
      beaconPolicy: "ff".repeat(28),
    };
    const result = redemptionDatumToData(d) as {
      alternative: number;
      fields: string[];
    };
    expect(result.alternative).toBe(0);
    expect(result.fields).toEqual([d.marketId, d.beaconPolicy]);
  });
});

describe("redemptionRedeemerToData", () => {
  it("encodes RedeemWinner as Constr 0 [outputIndex]", () => {
    const r = redemptionRedeemerToData({
      variant: "RedeemWinner",
      outputIndex: 0,
    }) as { alternative: number; fields: number[] };
    expect(r.alternative).toBe(0);
    expect(r.fields).toEqual([0]);
  });

  it("encodes BurnCompleteSet as Constr 1 [outputIndex]", () => {
    const r = redemptionRedeemerToData({
      variant: "BurnCompleteSet",
      outputIndex: 1,
    }) as { alternative: number; fields: number[] };
    expect(r.alternative).toBe(1);
    expect(r.fields).toEqual([1]);
  });

  it("encodes ClaimTimeout as Constr 2 [outputIndex]", () => {
    const r = redemptionRedeemerToData({
      variant: "ClaimTimeout",
      outputIndex: 2,
    }) as { alternative: number; fields: number[] };
    expect(r.alternative).toBe(2);
    expect(r.fields).toEqual([2]);
  });

  it("encodes ClaimDraw as Constr 3 [outputIndex]", () => {
    const r = redemptionRedeemerToData({
      variant: "ClaimDraw",
      outputIndex: 3,
    }) as { alternative: number; fields: number[] };
    expect(r.alternative).toBe(3);
    expect(r.fields).toEqual([3]);
  });

  it("encodes SweepResidual as Constr 4 [outputIndex]", () => {
    const r = redemptionRedeemerToData({
      variant: "SweepResidual",
      outputIndex: 4,
    }) as { alternative: number; fields: number[] };
    expect(r.alternative).toBe(4);
    expect(r.fields).toEqual([4]);
  });
});

describe("mintActionToData", () => {
  it("encodes MintSet as Constr 0 [marketId]", () => {
    const a = mintActionToData({
      variant: "MintSet",
      marketId: "aa".repeat(28),
    }) as { alternative: number; fields: string[] };
    expect(a.alternative).toBe(0);
    expect(a.fields).toEqual(["aa".repeat(28)]);
  });

  it("encodes BurnSet as Constr 1 [marketId]", () => {
    const a = mintActionToData({
      variant: "BurnSet",
      marketId: "bb".repeat(28),
    }) as { alternative: number; fields: string[] };
    expect(a.alternative).toBe(1);
    expect(a.fields).toEqual(["bb".repeat(28)]);
  });

  it("encodes BurnWinner as Constr 2 [marketId]", () => {
    const a = mintActionToData({
      variant: "BurnWinner",
      marketId: "cc".repeat(28),
    }) as { alternative: number; fields: string[] };
    expect(a.alternative).toBe(2);
    expect(a.fields).toEqual(["cc".repeat(28)]);
  });
});
