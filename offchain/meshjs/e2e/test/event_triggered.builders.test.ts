/**
 * Offline checks on the tokenized-bond MeshJS builders. No devnet: every
 * transaction is built against a mock fetcher over the vendored core scripts,
 * then inspected.
 *
 *   - Index-bearing redeemers (PLB `wdrl_idx` / `params_idx`, the node index)
 *     must point into the transaction's complete, ledger-ordered withdrawal
 *     and reference-input sets, including the entries a script authorizer
 *     adds.
 *   - Issuer-triggered continuations must keep the certificate UTxO's lovelace
 *     and unrelated assets (the core third-party rule).
 *   - `applyBond` must refuse configurations the on-chain rules cannot honor.
 */

import {
  applyBond,
  type Bond,
  type BondConfig,
  buildAuthorizeTx,
  buildBondDepositTx,
  buildClaimIssuerTx,
  buildClaimOwnerTx,
  buildCreateVaultTx,
  buildGraduateIssuerTx,
  buildGraduateOwnerTx,
  buildRedeemTx,
  buildRegisterTx,
  buildTransferTx,
  buildVaultTopUpTx,
  type CertificateDatum,
  type CoreConfig,
  type CoreDeployment,
  compareWithdrawalKeys,
  couponName,
  nodeAddress,
  type Payout,
  plbAddress,
  type RegistryNode,
  type ScriptAuthorizer,
  sortReferenceInputs,
  stepName,
  vaultAddress,
  type WithdrawalKey,
} from "@contracts-library/meshjs";
import {
  DEFAULT_V1_COST_MODEL_LIST,
  DEFAULT_V2_COST_MODEL_LIST,
  DEFAULT_V3_COST_MODEL_LIST,
  MeshTxBuilder,
  pubKeyAddress,
  serializeAddressObj,
  type UTxO,
} from "@meshsdk/core";
import { Cardano, deserializeTx } from "@meshsdk/core-cst";
import { describe, expect, it } from "vitest";

import { issuanceMintCompiledCode } from "../src/cip113/blueprint";
import { applyCoreScripts } from "../src/cip113/scripts";
import { ALWAYS_TRUE } from "../src/fixtures";

// --------------------------------------------------------------- fixtures

const NETWORK = 0 as const;
const tx = (b: string) => b.repeat(32);
const ISSUER_KEY = "a1".repeat(28);
const PAYER_KEY = "a2".repeat(28);
const HOLDER_KEY = "a3".repeat(28);
const PAYER = serializeAddressObj(pubKeyAddress(PAYER_KEY), NETWORK);
const STRAY_UNIT = `${"de".repeat(28)}7374726179`; // "stray"

const coreConfig: CoreConfig = {
  networkId: NETWORK,
  maxInlineDatumBytes: 1024,
  alwaysFailNonce: "ab".repeat(32),
  protocolParamsRef: { txHash: tx("c1"), outputIndex: 0 },
  registryRef: { txHash: tx("c2"), outputIndex: 0 },
  cborHexRef: { txHash: tx("c3"), outputIndex: 0 },
  upgradeConfigRef: { txHash: tx("c4"), outputIndex: 0 },
};

function utxo(
  txHash: string,
  address: string,
  amount: UTxO["output"]["amount"],
  extra: Partial<UTxO["output"]> = {},
): UTxO {
  return {
    input: { txHash, outputIndex: 0 },
    output: { address, amount, ...extra },
  };
}

const lovelace = (n: bigint | number) => ({
  unit: "lovelace",
  quantity: n.toString(),
});

// Reference UTxOs sit mid-range so an authorizer reference can sort on
// either side of them.
const core = applyCoreScripts(coreConfig);
const deployment: CoreDeployment = {
  config: coreConfig,
  core,
  refs: {
    protocolParams: utxo(tx("55"), PAYER, [lovelace(2_000_000)]),
    cborHex: utxo(tx("56"), PAYER, [lovelace(2_000_000)]),
    originNode: utxo(tx("57"), PAYER, [lovelace(2_000_000)]),
  },
  issuanceMintCode: issuanceMintCompiledCode,
};
const node = utxo(tx("66"), PAYER, [lovelace(2_000_000)]);

const config: BondConfig = {
  principal: 1000,
  interval: 10_000,
  amounts: [1040, 1081],
  issuer: { kind: "key", hash: ISSUER_KEY },
  vaultNftName: "5630",
};
const bond: Bond = applyBond(deployment, config);

const funding = utxo(tx("a0"), PAYER, [lovelace(500_000_000)]);
const collateral: UTxO = {
  input: { txHash: tx("a0"), outputIndex: 1 },
  output: { address: PAYER, amount: [lovelace(10_000_000)] },
};

function certificate(
  step: number,
  _datum: CertificateDatum,
  stakeHash: string,
  stakeIsScript: boolean,
  extra: UTxO["output"]["amount"] = [lovelace(2_000_000)],
): UTxO {
  return utxo(
    tx("77"),
    plbAddress(deployment, stakeHash, stakeIsScript),
    [...extra, { unit: bond.cipPolicy + stepName(step), quantity: "1" }],
    { plutusData: undefined },
  );
}

/** An authorizer whose script is read from a reference UTxO. */
function refAuthorizer(
  hash: string,
  refTx: string,
): {
  authorizer: ScriptAuthorizer;
  ref: UTxO;
} {
  const ref = utxo(refTx, PAYER, [lovelace(20_000_000)], {
    scriptRef: ALWAYS_TRUE.cbor,
    scriptHash: hash,
  });
  return { authorizer: { reference: ref, scriptHash: hash }, ref };
}

/** A tx builder whose fetcher resolves only the given UTxOs. */
function builder(known: UTxO[]): MeshTxBuilder {
  const fetcher = {
    fetchUTxOs: async (hash: string, index?: number) =>
      known.filter(
        (u) =>
          u.input.txHash === hash &&
          (index === undefined || u.input.outputIndex === index),
      ),
    fetchCostModels: async () => [
      DEFAULT_V1_COST_MODEL_LIST,
      DEFAULT_V2_COST_MODEL_LIST,
      DEFAULT_V3_COST_MODEL_LIST,
    ],
  };
  const tb = new MeshTxBuilder({ fetcher: fetcher as never });
  tb.setNetwork([
    DEFAULT_V1_COST_MODEL_LIST,
    DEFAULT_V2_COST_MODEL_LIST,
    DEFAULT_V3_COST_MODEL_LIST,
  ]);
  return tb;
}

function base(known: UTxO[]) {
  const all = [
    funding,
    collateral,
    deployment.refs.protocolParams,
    deployment.refs.cborHex,
    node,
    ...known,
  ];
  return {
    txBuilder: builder(all),
    deployment,
    funding: [funding],
    collateral,
    changeAddress: PAYER,
  };
}

// ------------------------------------------------------------- inspection

interface Built {
  /** Ledger-ordered withdrawal keys actually in the transaction. */
  withdrawals: WithdrawalKey[];
  /** Ledger-ordered reference inputs actually in the transaction. */
  references: string[];
  /** `[params_idx, wdrl_idx]` of the PLB spend of `cert`. */
  plbRedeemer: [number, number];
  outputs: { address: string; amount: { unit: string; quantity: string }[] }[];
}

function fieldsOf(data: unknown): number[] {
  const d = data as { fields: (number | bigint)[] };
  return d.fields.map((f) => Number(f));
}

function inspect(tb: MeshTxBuilder, hex: string, cert: UTxO): Built {
  const body = deserializeTx(hex).body();

  const withdrawals = [...(body.withdrawals()?.keys() ?? [])]
    .map((acct) => {
      const reward = Cardano.Address.fromBech32(acct).asReward();
      if (!reward) throw new Error(`not a reward address: ${acct}`);
      const cred = reward.getPaymentCredential();
      return {
        hash: cred.hash.toString(),
        isScript: cred.type === Cardano.CredentialType.ScriptHash,
      };
    })
    .sort(compareWithdrawalKeys);

  const references = sortReferenceInputs(
    (body.referenceInputs()?.values() ?? []).map((i) => ({
      input: {
        txHash: i.transactionId().toString(),
        outputIndex: Number(i.index()),
      },
      output: { address: "", amount: [] },
    })),
  ).map((u) => `${u.input.txHash}#${u.input.outputIndex}`);

  const spend = tb.meshTxBuilderBody.inputs.find(
    (i) =>
      i.txIn.txHash === cert.input.txHash &&
      i.txIn.txIndex === cert.input.outputIndex,
  ) as unknown as {
    scriptTxIn: { redeemer: { data: { content: unknown } } };
  };
  const [paramsIdx, wdrlIdx] = fieldsOf(spend.scriptTxIn.redeemer.data.content);

  return {
    withdrawals,
    references,
    plbRedeemer: [paramsIdx, wdrlIdx],
    outputs: tb.meshTxBuilderBody.outputs,
  };
}

function plgIndex(b: Built): number {
  return b.withdrawals.findIndex(
    (w) =>
      w.isScript &&
      w.hash === deployment.core.programmableLogicGlobalHash.toLowerCase(),
  );
}

function refIndex(b: Built, u: UTxO): number {
  return b.references.indexOf(`${u.input.txHash}#${u.input.outputIndex}`);
}

// ------------------------------------------------- item 4: index ordering

const SIDES = [
  { label: "sorting first", hash: "00".repeat(28), refTx: tx("00") },
  { label: "sorting last", hash: "ff".repeat(28), refTx: tx("ff") },
];

describe("builder indices include script-authorizer dependencies", () => {
  for (const side of SIDES) {
    it(`owner claim, script holder ${side.label}`, async () => {
      const { authorizer, ref } = refAuthorizer(side.hash, side.refTx);
      const datum: CertificateDatum = {
        start: 0,
        commit: null,
        cntPolicy: bond.cntPolicy,
      };
      const cert = certificate(0, datum, side.hash, true);
      const p = {
        ...base([cert, ref]),
        bond,
        node,
        certificate: cert,
        step: 1,
        datum,
        couponAddress: PAYER,
        holderStakeHash: side.hash,
        holderIsScript: true,
        authorizer,
        validFromSlot: 0,
      };
      const hex = await buildClaimOwnerTx(p);
      const b = inspect(p.txBuilder, hex, cert);

      expect(b.withdrawals.some((w) => w.hash === side.hash)).toBe(true);
      expect.soft(b.plbRedeemer[1]).toBe(plgIndex(b));
      expect
        .soft(b.plbRedeemer[0])
        .toBe(refIndex(b, deployment.refs.protocolParams));
    });

    it(`transfer, script holder ${side.label}`, async () => {
      const { authorizer, ref } = refAuthorizer(side.hash, side.refTx);
      const datum: CertificateDatum = {
        start: 0,
        commit: null,
        cntPolicy: bond.cntPolicy,
      };
      const cert = certificate(0, datum, side.hash, true);
      const p = {
        ...base([cert, ref]),
        bond,
        node,
        certificate: cert,
        recipientAddress: plbAddress(deployment, HOLDER_KEY),
        outputDatum: datum,
        holderStakeHash: side.hash,
        holderIsScript: true,
        authorizer,
      };
      const hex = await buildTransferTx(p);
      const b = inspect(p.txBuilder, hex, cert);

      expect.soft(b.plbRedeemer[1]).toBe(plgIndex(b));
      expect
        .soft(b.plbRedeemer[0])
        .toBe(refIndex(b, deployment.refs.protocolParams));
    });
  }

  for (const side of SIDES) {
    it(`issuer claim, script issuer ${side.label}`, async () => {
      const scriptIssuerBond = applyBond(deployment, {
        ...config,
        issuer: { kind: "script", hash: side.hash },
      });
      const { authorizer, ref } = refAuthorizer(side.hash, side.refTx);
      const datum: CertificateDatum = {
        start: 0,
        commit: { kind: "key" as const, hash: PAYER_KEY },
        cntPolicy: scriptIssuerBond.cntPolicy,
      };
      const cert = utxo(tx("77"), plbAddress(deployment, HOLDER_KEY), [
        lovelace(2_000_000),
        { unit: scriptIssuerBond.cipPolicy + stepName(0), quantity: "1" },
      ]);
      const p = {
        ...base([cert, ref]),
        bond: scriptIssuerBond,
        node,
        certificate: cert,
        step: 1,
        datum,
        payoutAddress: PAYER,
        authorizer,
        validFromSlot: 0,
      };
      const hex = await buildClaimIssuerTx(p);
      const b = inspect(p.txBuilder, hex, cert);

      expect.soft(b.plbRedeemer[1]).toBe(plgIndex(b));
      expect
        .soft(b.plbRedeemer[0])
        .toBe(refIndex(b, deployment.refs.protocolParams));
    });
  }
});

// ------------------------------------- item 5: issuer continuation value

describe("issuer-triggered continuations preserve the certificate value", () => {
  const datum: CertificateDatum = {
    start: 0,
    commit: { kind: "key", hash: PAYER_KEY },
    cntPolicy: bond.cntPolicy,
  };
  const rich = (step: number) =>
    utxo(tx("77"), plbAddress(deployment, HOLDER_KEY), [
      lovelace(5_000_000),
      { unit: STRAY_UNIT, quantity: "3" },
      { unit: bond.cipPolicy + stepName(step), quantity: "1" },
    ]);

  function continuation(b: Built, cert: UTxO) {
    // The paired output is the first output (thirdPartyRedeemer(_, 0)).
    const out = b.outputs[0];
    if (!out) throw new Error("expected the paired continuation output");
    expect(out.address).toBe(cert.output.address);
    const qty = (unit: string) =>
      BigInt(out.amount.find((a) => a.unit === unit)?.quantity ?? "0");
    return { lovelace: qty("lovelace"), stray: qty(STRAY_UNIT) };
  }

  it("issuer claim keeps lovelace and unrelated assets", async () => {
    const cert = rich(0);
    const p = {
      ...base([cert]),
      bond,
      node,
      certificate: cert,
      step: 1,
      datum,
      payoutAddress: PAYER,
      validFromSlot: 0,
    };
    const hex = await buildClaimIssuerTx(p);
    const c = continuation(inspect(p.txBuilder, hex, cert), cert);
    expect(c.lovelace).toBeGreaterThanOrEqual(5_000_000n);
    expect(c.stray).toBe(3n);
  });

  it("issuer graduation keeps lovelace and unrelated assets", async () => {
    const cert = rich(config.amounts.length);
    const p = {
      ...base([cert]),
      bond,
      node,
      certificate: cert,
      step: config.amounts.length,
      datum,
      payoutAddress: PAYER,
      validFromSlot: 0,
    };
    const hex = await buildGraduateIssuerTx(p);
    const c = continuation(inspect(p.txBuilder, hex, cert), cert);
    expect(c.lovelace).toBeGreaterThanOrEqual(5_000_000n);
    expect(c.stray).toBe(3n);
  });
});

// ------------------------------------------- vault top-up (escrow funding)

describe("vault top-up", () => {
  it("gains the topped-up amount and preserves the vault", async () => {
    const vault = utxo(tx("88"), vaultAddress(bond), [
      lovelace(5_000_000),
      { unit: bond.vaultNftCs + config.vaultNftName, quantity: "1" },
    ]);
    const p = {
      ...base([vault]),
      bond,
      vault,
      amount: 3_000_000n,
    };
    const hex = await buildVaultTopUpTx(p);
    const out = p.txBuilder.meshTxBuilderBody.outputs[0];
    if (!out) throw new Error("expected the top-up output");

    expect(out.address).toBe(vaultAddress(bond));
    const qty = (unit: string) =>
      BigInt(out.amount.find((a) => a.unit === unit)?.quantity ?? "0");
    expect(qty("lovelace")).toBe(8_000_000n);
    expect(qty(bond.vaultNftCs + config.vaultNftName)).toBe(1n);
    expect(deserializeTx(hex).body()).toBeDefined();
  });

  it("refuses a non-positive top-up", async () => {
    const vault = utxo(tx("88"), vaultAddress(bond), [
      lovelace(5_000_000),
      { unit: bond.vaultNftCs + config.vaultNftName, quantity: "1" },
    ]);
    const p = {
      ...base([vault]),
      bond,
      vault,
      amount: 0n,
    };
    await expect(buildVaultTopUpTx(p)).rejects.toThrow();
  });
});

// --------------------------------------- item 6: deployment parameters
describe("applyBond refuses configurations the validators cannot honor", () => {
  it("accepts the reference configuration", () => {
    expect(() => applyBond(deployment, config)).not.toThrow();
  });

  const bad: [string, Partial<BondConfig>][] = [
    ["zero principal", { principal: 0 }],
    ["negative principal", { principal: -1 }],
    ["fractional principal", { principal: 1.5 }],
    ["zero interval", { interval: 0 }],
    ["negative interval", { interval: -10 }],
    ["empty schedule", { amounts: [] }],
    ["schedule longer than 255 steps", { amounts: Array(256).fill(1) }],
    ["non-positive coupon amount", { amounts: [1040, 0] }],
    ["fractional coupon amount", { amounts: [10.5] }],
    // Coupon names are decimal bytes; asset names are at most 32 bytes.
    ["coupon name longer than 32 bytes", { amounts: [10 ** 32] }],
    ["vault NFT name longer than 32 bytes", { vaultNftName: "00".repeat(33) }],
  ];
  for (const [label, patch] of bad) {
    it(`rejects ${label}`, () => {
      expect(() => applyBond(deployment, { ...config, ...patch })).toThrow();
    });
  }
});

// ------------------------------------------------ remaining builders offline

/** A withdrawal-key-free claimant: a plain key credential. */
const holderDatum: CertificateDatum = {
  start: 0,
  commit: null,
  cntPolicy: bond.cntPolicy,
};

function certUtxo(step: number, extra = [lovelace(2_000_000)]): UTxO {
  return utxo(tx("77"), plbAddress(deployment, HOLDER_KEY), [
    ...extra,
    { unit: bond.cipPolicy + stepName(step), quantity: "1" },
  ]);
}

/** The PLB spend of `cert` exists (0 or 1 per builder); `inspect` needs it. */
function inspectMintOnly(p: { txBuilder: MeshTxBuilder }, hex: string): Built {
  const body = deserializeTx(hex).body();
  return {
    withdrawals: [...(body.withdrawals()?.keys() ?? [])].map((acct) => {
      const reward = Cardano.Address.fromBech32(acct).asReward();
      if (!reward) throw new Error(`not a reward address: ${acct}`);
      const cred = reward.getPaymentCredential();
      return {
        hash: cred.hash.toString(),
        isScript: cred.type === Cardano.CredentialType.ScriptHash,
      };
    }),
    references: [],
    plbRedeemer: [-1, -1],
    outputs: p.txBuilder.meshTxBuilderBody.outputs,
  };
}

function couponUtxo(step: number, quantity: number): UTxO {
  const amount = config.amounts[step - 1];
  if (amount === undefined) {
    throw new Error(`no coupon amount configured for step ${step}`);
  }
  return utxo(tx("99"), PAYER, [
    lovelace(2_000_000),
    {
      unit: bond.cntPolicy + couponName(amount),
      quantity: quantity.toString(),
    },
  ]);
}

function outputAt(b: Built, index: number) {
  const out = b.outputs[index];
  if (!out) throw new Error(`expected an output at index ${index}`);
  const qty = (unit: string) =>
    BigInt(out.amount.find((a) => a.unit === unit)?.quantity ?? "0");
  return { out, qty };
}

describe("create vault mints the NFT into a funded vault UTxO", () => {
  it("mints the vault NFT and puts it at the vault address", async () => {
    const p = { ...base([]), bond, vaultAda: 5_000_000n };
    const hex = await buildCreateVaultTx(p);
    const { out, qty } = outputAt(inspectMintOnly(p, hex), 0);

    expect(out.address).toBe(vaultAddress(bond));
    expect(qty("lovelace")).toBe(5_000_000n);
    expect(qty(bond.vaultNftCs + config.vaultNftName)).toBe(1n);
    expect(deserializeTx(hex).body()).toBeDefined();
  });
});

describe("register inserts the bond node", () => {
  it("re-emits the covering node and adds the bond node", async () => {
    const coveringNode: RegistryNode = {
      key: "aa".repeat(28),
      next: "bb".repeat(28),
      mintingLogic: { kind: "script", hash: "cc".repeat(28) },
      transferLogic: { kind: "script", hash: "dd".repeat(28) },
      thirdPartyLogic: { kind: "script", hash: "ee".repeat(28) },
      unfrackingLogic: { kind: "key", hash: "" },
      globalStateCs: "",
    };
    const covering = utxo(tx("d3"), nodeAddress(deployment), [
      lovelace(2_000_000),
      {
        unit: deployment.core.registryNodeCs + coveringNode.key,
        quantity: "1",
      },
    ]);
    const p = {
      ...base([covering]),
      bond,
      covering,
      coveringNode,
    };
    const hex = await buildRegisterTx(p);
    const b = inspectMintOnly(p, hex);
    const nodeAddr = nodeAddress(deployment);

    // Continuation of the covering node first, then the new bond node.
    const continued = b.outputs[0];
    if (!continued) throw new Error("expected the continuation node output");
    expect(continued.address).toBe(nodeAddr);
    const created = b.outputs[1];
    if (!created) throw new Error("expected the new bond node output");
    expect(created.address).toBe(nodeAddr);
    expect(
      created.amount.find(
        (a) => a.unit === deployment.core.registryNodeCs + bond.cipPolicy,
      ),
    ).toBeDefined();
    expect(deserializeTx(hex).body()).toBeDefined();
  });
});

describe("bond deposit mints certificate step 0 into the vault", () => {
  it("vault gains the principal and the certificate is minted", async () => {
    const vault = utxo(tx("d1"), vaultAddress(bond), [
      lovelace(5_000_000),
      { unit: bond.vaultNftCs + config.vaultNftName, quantity: "1" },
    ]);
    const p = {
      ...base([vault]),
      bond,
      vault,
      node,
      depositorStakeHash: HOLDER_KEY,
      depositorIsScript: false,
      start: 1_000,
      validHereafterSlot: 10,
    };
    const hex = await buildBondDepositTx(p);
    const b = inspectMintOnly(p, hex);

    const vaultOut = b.outputs.find((o) => o.address === vaultAddress(bond));
    if (!vaultOut) throw new Error("expected the vault output");
    const vaultAda = vaultOut.amount.find((a) => a.unit === "lovelace");
    if (!vaultAda) throw new Error("expected lovelace in the vault output");
    expect(BigInt(vaultAda.quantity)).toBe(
      5_000_000n + BigInt(config.principal),
    );
    // The certificate lands at the depositor's PLB address.
    expect(
      b.outputs.some((o) =>
        o.amount.some(
          (a) => a.unit === bond.cipPolicy + stepName(0) && a.quantity === "1",
        ),
      ),
    ).toBe(true);
    expect(deserializeTx(hex).body()).toBeDefined();
  });
});

describe("authorize delegates to transfer with the commit written", () => {
  it("keeps the same holder address and writes the commit", async () => {
    const cert = certUtxo(0);
    const p = {
      ...base([cert]),
      bond,
      node,
      certificate: cert,
      commit: { kind: "key" as const, hash: PAYER_KEY },
      datum: holderDatum,
      holderStakeHash: HOLDER_KEY,
      holderIsScript: false,
    };
    const hex = await buildAuthorizeTx(p);
    expect(deserializeTx(hex).body()).toBeDefined();
    // Same recipient as the spent certificate (self-transfer).
    const out = p.txBuilder.meshTxBuilderBody.outputs[0];
    if (!out) throw new Error("expected the certificate transfer output");
    expect(out.address).toBe(cert.output.address);
  });
});

describe("redeem burns coupons and pays the payouts", () => {
  it("pays the payout addresses and drains the vault by the coupon value", async () => {
    const vault = utxo(tx("d2"), vaultAddress(bond), [
      lovelace(50_000_000),
      { unit: bond.vaultNftCs + config.vaultNftName, quantity: "1" },
    ]);
    const payout: Payout = {
      address: PAYER,
      amount: 1040n,
    };
    const p = {
      ...base([vault, couponUtxo(1, 1)]),
      bond,
      vault,
      coupons: [couponUtxo(1, 1)],
      payouts: [payout],
    };
    const hex = await buildRedeemTx(p);
    const b = inspectMintOnly(p, hex);

    const payer = b.outputs.find((o) => o.address === PAYER);
    if (!payer)
      throw new Error("expected a change output at the payer's address");
    const payerAda = payer.amount.find((a) => a.unit === "lovelace");
    if (!payerAda) throw new Error("expected lovelace in the payer output");
    expect(BigInt(payerAda.quantity)).toBeGreaterThanOrEqual(2_000_000n);
    const vaultOut = b.outputs.find((o) => o.address === vaultAddress(bond));
    if (!vaultOut) throw new Error("expected the vault output");
    const vaultAda = vaultOut.amount.find((a) => a.unit === "lovelace");
    if (!vaultAda) throw new Error("expected lovelace in the vault output");
    const couponValue = config.amounts[0];
    if (couponValue === undefined) {
      throw new Error("no coupon amount configured for step 1");
    }
    expect(BigInt(vaultAda.quantity)).toBe(50_000_000n - BigInt(couponValue));
    expect(deserializeTx(hex).body()).toBeDefined();
  });
});

describe("owner graduation burns the final name and mints the principal coupon", () => {
  it("sends the principal coupon to the coupon address", async () => {
    const cert = certUtxo(config.amounts.length);
    const p = {
      ...base([cert]),
      bond,
      node,
      certificate: cert,
      step: config.amounts.length,
      couponAddress: PAYER,
      holderStakeHash: HOLDER_KEY,
      holderIsScript: false,
      validFromSlot: 0,
    };
    const hex = await buildGraduateOwnerTx(p);
    const b = inspect(p.txBuilder, hex, cert);

    const couponOut = b.outputs.find((o) => o.address === PAYER);
    if (!couponOut) throw new Error("expected the coupon output at the payer");
    expect(
      couponOut.amount.find(
        (a) => a.unit === bond.cntPolicy + couponName(config.principal),
      )?.quantity,
    ).toBe("1");
    expect(deserializeTx(hex).body()).toBeDefined();
  });
});
