/**
 * End-to-end tests for the event-triggered assets scaffold against a Yaci
 * DevKit devnet (CIP-113 substandard, docs/explorations/event-triggered-assets.md).
 *
 * Happy paths: issue → apply event → graduate / retire.
 * The on-chain predicates are permissive stubs pending triage (§7, TODO(#28)),
 * so instead of settings-style rejection paths this suite carries
 * "permissiveness controls": tests that assert the current permissive
 * behavior on-chain (and flip to rejections once the predicates are
 * hardened), plus builder-level guard tests for the off-chain checks.
 */

import {
  applyEventRedeemer,
  buildApplyEventTx,
  buildGraduateTx,
  buildIssueTx,
  buildRetireTx,
  eventTriggeredPolicyId,
  eventTriggeredScript,
  eventTriggeredScriptAddress,
  instrumentDatumToData,
  type EventAssetDatum,
} from "@contracts-library/meshjs";
import {
  mConStr0,
  unixTimeToEnclosingSlot,
  type PlutusScript,
  type SlotConfig,
  type UTxO,
} from "@meshsdk/core";
import { beforeAll, describe, expect, it } from "vitest";
import { ALWAYS_TRUE } from "../src/fixtures";
import {
  chainNowMs,
  collateralOf,
  devnetReachable,
  devnetSlotConfig,
  fundedAccount,
  makeProvider,
  NETWORK_ID,
  newTxBuilder,
  scriptOutputOf,
  signAndSubmit,
  STORE_URL,
  waitForTx,
  type Account,
} from "../src/devnet";

const reachable = await devnetReachable();
if (!reachable) {
  console.warn(
    `[e2e] Skipping all e2e tests: no Yaci devnet at ${STORE_URL}. ` +
      `Run \`npm run test:devnet\` (or start one and set INDEXER_URL / YACI_STORE_URL).`,
  );
}

const PROGRAMMATIC_ASSET_NAME = "6576656e74"; // hex-encoded "event"
const GRADUATED_ASSET_NAME = "677261647561746564"; // hex-encoded "graduated"

describe.skipIf(!reachable)("event_triggered e2e (Yaci devnet)", () => {
  let provider: ReturnType<typeof makeProvider>;
  let slotConfig: SlotConfig;
  let script: ReturnType<typeof eventTriggeredScript>;
  let scriptAddr: string;
  let policyId: string;
  let unit: string;

  beforeAll(async () => {
    provider = makeProvider();
    slotConfig = await devnetSlotConfig();
    script = eventTriggeredScript();
    scriptAddr = eventTriggeredScriptAddress(NETWORK_ID);
    policyId = eventTriggeredPolicyId();
    unit = policyId + PROGRAMMATIC_ASSET_NAME;
  });

  async function setup(): Promise<{
    ruleKeeper: Account;
    graduationKeeper: Account;
    datum: EventAssetDatum;
  }> {
    const ruleKeeper = await fundedAccount(provider);
    const graduationKeeper = await fundedAccount(provider);

    return {
      ruleKeeper,
      graduationKeeper,
      datum: {
        rule: { kind: "key", hash: ruleKeeper.keyHash },
        graduationAuth: { kind: "key", hash: graduationKeeper.keyHash },
        state: "Active",
      },
    };
  }

  /** A permissive Plutus policy for the graduated token. A Plutus policy
   * (not a native script) is required for an atomic graduate: see
   * `buildGraduateTx`. */
  function graduatedScriptOf(_ctx: Awaited<ReturnType<typeof setup>>): {
    script: PlutusScript;
    redeemer: ReturnType<typeof mConStr0>;
    unit: string;
  } {
    return {
      script: { code: ALWAYS_TRUE.cbor, version: "V3" },
      redeemer: mConStr0([]),
      unit: ALWAYS_TRUE.hash + GRADUATED_ASSET_NAME,
    };
  }

  /** Mint the programmable token into programmable custody (rule keeper signs). */
  async function issueInstrument(
    ctx: Awaited<ReturnType<typeof setup>>,
    quantity = 1n,
  ): Promise<UTxO> {
    const issueTx = await buildIssueTx({
      txBuilder: newTxBuilder(provider),
      datum: ctx.datum,
      assetName: PROGRAMMATIC_ASSET_NAME,
      quantity,
      utxos: await ctx.ruleKeeper.wallet.getUtxos(),
      changeAddress: ctx.ruleKeeper.address,
      collateralUtxo: await collateralOf(ctx.ruleKeeper),
      network: "preprod",
    });

    const issueHash = await signAndSubmit(ctx.ruleKeeper, issueTx);
    await waitForTx(provider, issueHash);
    return await scriptOutputOf(provider, issueHash, scriptAddr);
  }

  /** Apply an event: Active → Settled (rule keeper signs). */
  async function applySettleEvent(
    ctx: Awaited<ReturnType<typeof setup>>,
    instrumentUtxo: UTxO,
  ): Promise<UTxO> {
    const applyTx = await buildApplyEventTx({
      txBuilder: newTxBuilder(provider),
      instrumentUtxo,
      datum: ctx.datum,
      nextDatum: { ...ctx.datum, state: "Settled" },
      now: await chainNowMs(),
      utxos: await ctx.ruleKeeper.wallet.getUtxos(),
      changeAddress: ctx.ruleKeeper.address,
      collateralUtxo: await collateralOf(ctx.ruleKeeper),
      network: "preprod",
      customSlotConfig: slotConfig,
    });

    const applyHash = await signAndSubmit(ctx.ruleKeeper, applyTx);
    await waitForTx(provider, applyHash);
    return await scriptOutputOf(provider, applyHash, scriptAddr);
  }

  /**
   * A raw, possibly-malicious spend of an instrument UTxO with the ApplyEvent
   * redeemer (an attacker would not use our honest builder). Without a
   * `continuation` the UTxO is swept to the signer's wallet.
   */
  async function rawApply(p: {
    signer: Account;
    instrumentUtxo: UTxO;
    continuation?: EventAssetDatum;
    requiredSigner?: string;
  }): Promise<string> {
    const tb = newTxBuilder(provider);

    tb.spendingPlutusScriptV3()
      .txIn(
        p.instrumentUtxo.input.txHash,
        p.instrumentUtxo.input.outputIndex,
        p.instrumentUtxo.output.amount,
        p.instrumentUtxo.output.address,
      )
      .txInInlineDatumPresent()
      .txInRedeemerValue(applyEventRedeemer())
      .txInScript(script.code);

    if (p.continuation) {
      tb.txOut(
        scriptAddr,
        p.instrumentUtxo.output.amount,
      ).txOutInlineDatumValue(instrumentDatumToData(p.continuation));
    }

    if (p.requiredSigner) tb.requiredSignerHash(p.requiredSigner);

    const col = await collateralOf(p.signer);
    const unsigned = await tb
      .txInCollateral(
        col.input.txHash,
        col.input.outputIndex,
        col.output.amount,
        col.output.address,
      )
      .changeAddress(p.signer.address)
      .selectUtxosFrom(await p.signer.wallet.getUtxos())
      .complete();

    return provider.submitTx(await p.signer.wallet.signTx(unsigned, true));
  }

  /** Total quantity of `unit` across an account's wallet. */
  async function walletHolds(account: Account, unit: string): Promise<bigint> {
    const utxos = await account.wallet.getUtxos();
    return utxos.reduce((sum, u) => {
      const a = u.output.amount.find((x) => x.unit === unit);
      return sum + (a ? BigInt(a.quantity) : 0n);
    }, 0n);
  }

  /** Issue, then sweep the programmable token into the graduation keeper's
   * wallet (permissive stub permits it), so P3 can burn from there. */
  async function issueAndSweep(
    ctx: Awaited<ReturnType<typeof setup>>,
  ): Promise<void> {
    const instrumentUtxo = await issueInstrument(ctx);
    const sweepHash = await rawApply({
      signer: ctx.graduationKeeper,
      instrumentUtxo,
      requiredSigner: ctx.graduationKeeper.keyHash,
    });
    await waitForTx(provider, sweepHash);
  }

  // ----------------------------------------------------------- happy paths

  it("issues an instrument UTxO in programmable custody", async () => {
    const ctx = await setup();
    const instrumentUtxo = await issueInstrument(ctx);

    expect(instrumentUtxo.output.address).toBe(scriptAddr);
    const asset = instrumentUtxo.output.amount.find((a) => a.unit === unit);
    expect(asset).toBeDefined();
    expect(asset?.quantity).toBe("1");
  });

  it("issues, applies an event (Active → Settled), and continues", async () => {
    const ctx = await setup();
    const instrumentUtxo = await issueInstrument(ctx);

    const settledUtxo = await applySettleEvent(ctx, instrumentUtxo);

    expect(settledUtxo).toBeDefined();
    expect(settledUtxo.output.address).toBe(scriptAddr);
    const asset = settledUtxo.output.amount.find((a) => a.unit === unit);
    expect(asset?.quantity).toBe("1");
  });

  it("issues, applies an event, and graduates via burn + remint", async () => {
    const ctx = await setup();
    await issueAndSweep(ctx);

    const graduated = graduatedScriptOf(ctx);
    const graduateTx = await buildGraduateTx({
      txBuilder: newTxBuilder(provider),
      programmaticUnit: unit,
      programmaticQuantity: 1n,
      graduatedUnit: graduated.unit,
      graduatedQuantity: 1n,
      graduatedScript: graduated.script,
      graduatedRedeemer: graduated.redeemer,
      utxos: await ctx.graduationKeeper.wallet.getUtxos(),
      changeAddress: ctx.graduationKeeper.address,
      collateralUtxo: await collateralOf(ctx.graduationKeeper),
      graduationAuth: ctx.datum.graduationAuth,
      network: "preprod",
    });
    const graduateHash = await signAndSubmit(ctx.graduationKeeper, graduateTx);
    await waitForTx(provider, graduateHash);

    expect(await walletHolds(ctx.graduationKeeper, graduated.unit)).toBe(1n);
    expect(await walletHolds(ctx.graduationKeeper, unit)).toBe(0n);
  });

  it("issues, applies an event, and retires via burn only", async () => {
    const ctx = await setup();
    await issueAndSweep(ctx);

    const retireTx = await buildRetireTx({
      txBuilder: newTxBuilder(provider),
      programmaticUnit: unit,
      programmaticQuantity: 1n,
      utxos: await ctx.graduationKeeper.wallet.getUtxos(),
      changeAddress: ctx.graduationKeeper.address,
      collateralUtxo: await collateralOf(ctx.graduationKeeper),
      graduationAuth: ctx.datum.graduationAuth,
      network: "preprod",
    });
    const retireHash = await signAndSubmit(ctx.graduationKeeper, retireTx);
    await waitForTx(provider, retireHash);

    expect(await walletHolds(ctx.graduationKeeper, unit)).toBe(0n);
  });

  // ------------------------------------------------- permissiveness controls
  //
  // These document the CURRENT permissive on-chain behavior (§7 stubs,
  // TODO(#28)). Once the predicates are triaged into real checks, flip these
  // assertions to `rejects.toThrow()` — they mark exactly the hole that
  // triage closes.

  it("accepts a raw apply whose rule authority never signed (permissive stub)", async () => {
    const ctx = await setup();
    const instrumentUtxo = await issueInstrument(ctx);

    // No required signer for the rule credential, forged Settled continuation.
    const hash = await rawApply({
      signer: ctx.graduationKeeper,
      instrumentUtxo,
      continuation: { ...ctx.datum, state: "Settled" },
    });
    await waitForTx(provider, hash);
    expect(hash).toBeDefined();
  });

  it("accepts a raw apply that sweeps custody to a wallet (permissive stub)", async () => {
    const ctx = await setup();
    const instrumentUtxo = await issueInstrument(ctx);

    // CIP-113 forbids programmable tokens outside programmable custody; the
    // scaffold does not model the shared base validator, so this sweep flies.
    const hash = await rawApply({
      signer: ctx.graduationKeeper,
      instrumentUtxo,
      requiredSigner: ctx.graduationKeeper.keyHash,
    });
    await waitForTx(provider, hash);
    expect(await walletHolds(ctx.graduationKeeper, unit)).toBe(1n);
  });

  it("accepts a raw apply with a forged continuation datum (permissive stub)", async () => {
    const ctx = await setup();
    const instrumentUtxo = await issueInstrument(ctx);

    // Forged authorities: the continuation swaps the rule credential.
    const forged: EventAssetDatum = {
      rule: { kind: "key", hash: "00".repeat(28) },
      graduationAuth: { kind: "key", hash: "11".repeat(28) },
      state: "Settled",
    };
    const hash = await rawApply({
      signer: ctx.graduationKeeper,
      instrumentUtxo,
      continuation: forged,
      requiredSigner: ctx.graduationKeeper.keyHash,
    });
    await waitForTx(provider, hash);
    expect(hash).toBeDefined();
  });

  // ------------------------------------------------- off-chain guard checks
  //
  // The builders enforce more than the on-chain stubs do; these assert the
  // builder guards fire before any transaction is submitted.

  it("rejects graduation when the inputs do not hold the programmable token", async () => {
    const ctx = await setup();
    const graduated = graduatedScriptOf(ctx);

    await expect(
      buildGraduateTx({
        txBuilder: newTxBuilder(provider),
        programmaticUnit: unit,
        programmaticQuantity: 1n,
        graduatedUnit: graduated.unit,
        graduatedQuantity: 1n,
        graduatedScript: graduated.script,
        graduatedRedeemer: graduated.redeemer,
        utxos: await ctx.graduationKeeper.wallet.getUtxos(),
        changeAddress: ctx.graduationKeeper.address,
        collateralUtxo: await collateralOf(ctx.graduationKeeper),
        graduationAuth: ctx.datum.graduationAuth,
        network: "preprod",
      }),
    ).rejects.toThrow(/need 1 to burn/i);
  });

  it("rejects graduation into the event-triggered policy itself", async () => {
    const ctx = await setup();
    const graduated = graduatedScriptOf(ctx);

    await expect(
      buildGraduateTx({
        txBuilder: newTxBuilder(provider),
        programmaticUnit: unit,
        programmaticQuantity: 1n,
        graduatedUnit: policyId + GRADUATED_ASSET_NAME,
        graduatedQuantity: 1n,
        graduatedScript: graduated.script,
        graduatedRedeemer: graduated.redeemer,
        utxos: await ctx.graduationKeeper.wallet.getUtxos(),
        changeAddress: ctx.graduationKeeper.address,
        collateralUtxo: await collateralOf(ctx.graduationKeeper),
        graduationAuth: ctx.datum.graduationAuth,
        network: "preprod",
      }),
    ).rejects.toThrow(/distinct/i);
  });

  it("rejects retirement when the inputs do not hold the programmable token", async () => {
    const ctx = await setup();

    await expect(
      buildRetireTx({
        txBuilder: newTxBuilder(provider),
        programmaticUnit: unit,
        programmaticQuantity: 2n,
        utxos: await ctx.graduationKeeper.wallet.getUtxos(),
        changeAddress: ctx.graduationKeeper.address,
        collateralUtxo: await collateralOf(ctx.graduationKeeper),
        graduationAuth: ctx.datum.graduationAuth,
        network: "preprod",
      }),
    ).rejects.toThrow(/need 2 to burn/i);
  });

  // Sanity: the lower-bound slot conversion the builders use stays consistent
  // with the devnet slot config the suite fetched.
  it("validity lower bound converts time to a slot on this chain", async () => {
    const now = await chainNowMs();
    const slot = unixTimeToEnclosingSlot(now, slotConfig);
    expect(slot).toBeGreaterThan(0);
  });
});
