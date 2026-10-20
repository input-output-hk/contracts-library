import { deserializeAddress, serializePlutusScript } from "@meshsdk/core";
import { describe, expect, it } from "vitest";
import { spendingLimitCode } from "../../src/smart_wallet/blueprint";
import {
  addressToData,
  assetAllowListParamsToData,
  assetDenyListParamsToData,
  assetListToData,
  fullRecipientAllowListParamsToData,
  fullRecipientDenyListParamsToData,
  paymentStakingAllowListParamsToData,
  paymentStakingDenyListParamsToData,
  spendingPeriodLimitParamsToData,
  spendingPeriodStateToData,
} from "../../src/smart_wallet/datum";
import type { AssetList, Credential } from "../../src/smart_wallet/types";
import {
  assetDepositDenyListScript,
  fullRecipientAllowListScript,
  spendingPeriodLimitScript,
  withdrawalScriptAddress,
} from "../../src/smart_wallet/withdrawal_scripts";

/** MeshJS `Data` constructor variant, for structural assertions. */
interface Constr {
  alternative: number;
  fields: unknown[];
}

function asConstr(d: unknown): Constr {
  return d as Constr;
}

/** A base (key payment + inline key stake) testnet address. */
const BASE_ADDRESS =
  "addr_test1qz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3n0d3vllmyqwsx5wktcd8cc3sq835lu7drv2xwl2wywfgs68faae";

/** An enterprise (script payment, no stake) address. */
function scriptAddress(): string {
  return serializePlutusScript(
    { code: spendingLimitCode, version: "V3" },
    undefined,
    0,
  ).address;
}

describe("addressToData", () => {
  it("encodes a base address as Constr0 [key payment, Some(Inline(key stake))]", () => {
    const { pubKeyHash, stakeCredentialHash } =
      deserializeAddress(BASE_ADDRESS);
    const d = asConstr(addressToData(BASE_ADDRESS));

    expect(d.alternative).toBe(0);
    expect(d.fields).toHaveLength(2);

    // payment credential: key = Constr0 [hash]
    expect(asConstr(d.fields[0])).toEqual({
      alternative: 0,
      fields: [pubKeyHash],
    });

    // stake: Some(Inline(key credential)) = Constr0 [Constr0 [Constr0 [hash]]]
    const stake = asConstr(d.fields[1]);
    expect(stake.alternative).toBe(0);
    const inline = asConstr(stake.fields[0]);
    expect(inline.alternative).toBe(0);
    expect(asConstr(inline.fields[0])).toEqual({
      alternative: 0,
      fields: [stakeCredentialHash],
    });
  });

  it("encodes a script address as Constr0 [script payment, None]", () => {
    const address = scriptAddress();
    const { scriptHash } = deserializeAddress(address);
    const d = asConstr(addressToData(address));

    // payment credential: script = Constr1 [hash]
    expect(asConstr(d.fields[0])).toEqual({
      alternative: 1,
      fields: [scriptHash],
    });
    // no stake: None = Constr1 []
    expect(asConstr(d.fields[1])).toEqual({ alternative: 1, fields: [] });
  });
});

describe("assetListToData", () => {
  it("encodes an AssetList as a Plutus association map", () => {
    const list: AssetList = [
      ["aa".repeat(28), ["4e4654", "544f4b454e"]],
      ["bb".repeat(28), []],
    ];
    const d = assetListToData(list);
    expect(d).toBeInstanceOf(Map);
    expect([...(d as Map<string, string[]>).entries()]).toEqual(list);
  });
});

describe("recipient / asset param encoders", () => {
  const wallet: Credential = { kind: "script", hash: "cc".repeat(28) };
  const paymentKey: Credential = { kind: "key", hash: "11".repeat(28) };
  const stakeKey: Credential = { kind: "key", hash: "22".repeat(28) };

  it("full_recipient_allow_list: [wallet, [address]]", () => {
    const data = fullRecipientAllowListParamsToData({
      wallet,
      allowed: [BASE_ADDRESS],
    });
    expect(data).toHaveLength(2);
    expect(asConstr(data[0])).toEqual({
      alternative: 1,
      fields: [wallet.hash],
    });
    expect(data[1]).toEqual([addressToData(BASE_ADDRESS)]);
  });

  it("full_recipient_deny_list: [wallet, [address]]", () => {
    const data = fullRecipientDenyListParamsToData({
      wallet,
      denied: [BASE_ADDRESS],
    });
    expect(data).toHaveLength(2);
    expect(data[1]).toEqual([addressToData(BASE_ADDRESS)]);
  });

  it("payment_staking_allow_list: [wallet, payments, stakings]", () => {
    const data = paymentStakingAllowListParamsToData({
      wallet,
      allowedPayments: [paymentKey],
      allowedStakings: [stakeKey],
    });
    expect(data).toHaveLength(3);
    expect(data[1]).toEqual([{ alternative: 0, fields: [paymentKey.hash] }]);
    expect(data[2]).toEqual([{ alternative: 0, fields: [stakeKey.hash] }]);
  });

  it("payment_staking_deny_list: [wallet, payments, stakings]", () => {
    const data = paymentStakingDenyListParamsToData({
      wallet,
      deniedPayments: [paymentKey],
      deniedStakings: [stakeKey],
    });
    expect(data).toHaveLength(3);
    expect(data[1]).toEqual([{ alternative: 0, fields: [paymentKey.hash] }]);
    expect(data[2]).toEqual([{ alternative: 0, fields: [stakeKey.hash] }]);
  });

  it("asset_allow_list / asset_deny_list: [wallet, map]", () => {
    const list: AssetList = [["dd".repeat(28), ["41"]]];
    const allowed = assetAllowListParamsToData({ wallet, allowed: list });
    const denied = assetDenyListParamsToData({ wallet, denied: list });
    expect(allowed).toHaveLength(2);
    expect(denied).toHaveLength(2);
    expect(allowed[1]).toBeInstanceOf(Map);
    expect(denied[1]).toBeInstanceOf(Map);
  });
});

describe("withdrawal script constructors", () => {
  it("parameterize the raw script", () => {
    const script = fullRecipientAllowListScript({
      wallet: { kind: "script", hash: "cc".repeat(28) },
      allowed: [BASE_ADDRESS],
    });
    expect(script.version).toBe("V3");
    expect(typeof script.code).toBe("string");
    expect(script.code.length).toBeGreaterThan(0);
  });

  it("depositor asset scripts reuse the asset param encoding", () => {
    const script = assetDepositDenyListScript({
      wallet: { kind: "script", hash: "cc".repeat(28) },
      denied: [["dd".repeat(28), []]],
    });
    expect(script.version).toBe("V3");
    expect(script.code.length).toBeGreaterThan(0);
  });
});

describe("withdrawalScriptAddress", () => {
  const script = { code: spendingLimitCode, version: "V3" as const };

  it("returns the script's reward (stake) address", () => {
    expect(withdrawalScriptAddress(script, 0)).toMatch(/^stake_test1/);
    expect(withdrawalScriptAddress(script, 1)).toMatch(/^stake1/);
  });
});

describe("spending_period_limit encoders", () => {
  const wallet: Credential = { kind: "script", hash: "cc".repeat(28) };
  const interval = 604_800_000; // one week
  const maxSpend = 100_000_000;

  it("spendingPeriodStateToData: Constr0 [period, accSpend]", () => {
    expect(
      asConstr(
        spendingPeriodStateToData({ period: interval, accSpend: 5_000_000 }),
      ),
    ).toEqual({ alternative: 0, fields: [interval, 5_000_000] });
  });

  it("spendingPeriodLimitParamsToData: [wallet, interval, maxSpend]", () => {
    expect(
      spendingPeriodLimitParamsToData({ wallet, interval, maxSpend }),
    ).toEqual([{ alternative: 1, fields: [wallet.hash] }, interval, maxSpend]);
  });

  it("spendingPeriodLimitScript parameterizes the raw script", () => {
    const script = spendingPeriodLimitScript({ wallet, interval, maxSpend });
    expect(script.version).toBe("V3");
    expect(script.code.length).toBeGreaterThan(0);
  });
});
