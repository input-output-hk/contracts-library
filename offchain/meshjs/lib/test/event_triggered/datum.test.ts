import { pubKeyAddress, serializeAddressObj } from "@meshsdk/core";
import { describe, expect, it } from "vitest";

import {
  addressToData,
  certificateDatumToData,
  couponName,
  decodeCouponName,
  mintingParamsToData,
  payoutToData,
  redeemRedeemer,
  stepName,
  stepOfName,
  vaultDatumToData,
} from "../../src/event_triggered/datum";

describe("asset names", () => {
  it("encodes the step as exactly one byte and round-trips", () => {
    expect(stepName(0)).toBe("00");
    expect(stepName(1)).toBe("01");
    expect(stepName(255)).toBe("ff");
    for (const k of [0, 1, 2, 100, 255]) {
      expect(stepOfName(stepName(k))).toBe(k);
    }
  });

  it("rejects names that are not one byte", () => {
    expect(stepOfName("")).toBeNull();
    expect(stepOfName("0001")).toBeNull();
    expect(stepOfName("524546")).toBeNull();
  });

  it("encodes the coupon amount as decimal bytes and round-trips", () => {
    expect(couponName(1040)).toBe("31303430");
    expect(decodeCouponName(couponName(1040))).toBe(1040);
    expect(decodeCouponName(couponName(1000))).toBe(1000);
  });
});

describe("datums", () => {
  it("encodes the certificate datum as [start, commit, cntPolicy]", () => {
    const none = certificateDatumToData({
      start: 123,
      commit: null,
      cntPolicy: "aa".repeat(28),
    }) as { alternative: number; fields: unknown[] };
    expect(none.alternative).toBe(0);
    expect(none.fields[0]).toBe(123);
    expect(none.fields[1]).toEqual({ alternative: 1, fields: [] });
    expect(none.fields[2]).toBe("aa".repeat(28));

    const some = certificateDatumToData({
      start: 1,
      commit: { kind: "key", hash: "bb".repeat(28) },
      cntPolicy: "aa".repeat(28),
    }) as { fields: unknown[] };
    expect(some.fields[1]).toEqual({
      alternative: 0,
      fields: [{ alternative: 0, fields: ["bb".repeat(28)] }],
    });
  });

  it("encodes the vault datum as [cntPolicy]", () => {
    expect(vaultDatumToData({ cntPolicy: "cc".repeat(28) })).toEqual({
      alternative: 0,
      fields: ["cc".repeat(28)],
    });
  });
});

describe("parameters", () => {
  it("encodes MintingParams as one 7-field record", () => {
    const params = mintingParamsToData({
      registryNodeCs: "dd".repeat(28),
      issuer: { kind: "key", hash: "ee".repeat(28) },
      transferLogic: "01".repeat(28),
      thirdPartyLogic: "02".repeat(28),
      vault: "03".repeat(28),
      vaultNftCs: "04".repeat(28),
      principal: 1000,
    });
    expect(params).toHaveLength(1);
    const record = params[0] as { alternative: number; fields: unknown[] };
    expect(record.alternative).toBe(0);
    expect(record.fields).toHaveLength(7);
    expect(record.fields[6]).toBe(1000);
  });
});

describe("addresses and payouts", () => {
  const address = serializeAddressObj(
    pubKeyAddress("ab".repeat(28), "cd".repeat(28)),
    0,
  );

  it("encodes a base address as [payment, Some(Inline(stake))]", () => {
    expect(addressToData(address)).toEqual({
      alternative: 0,
      fields: [
        { alternative: 0, fields: ["ab".repeat(28)] },
        {
          alternative: 0,
          fields: [
            {
              alternative: 0,
              fields: [{ alternative: 0, fields: ["cd".repeat(28)] }],
            },
          ],
        },
      ],
    });
  });

  it("encodes Redeem payouts and the redeem redeemer", () => {
    const payout = payoutToData({ address, amount: 1000n });
    expect((payout as { fields: unknown[] }).fields[1]).toBe(1000n);
    const redeemer = redeemRedeemer([{ address, amount: 1000n }]) as {
      alternative: number;
      fields: unknown[][];
    };
    expect(redeemer.alternative).toBe(1);
    expect(redeemer.fields[0]).toHaveLength(1);
  });
});
