/**
 * End-to-end tests for the settings contract against a Yaci DevKit devnet.
 *
 * Happy paths: mint → propose → apply → close.
 * Attack paths verify the builder's validation (early-apply rejection, etc.)
 * while the on-chain validators for propose/apply are still WIP.
 */

import {
  applyRedeemer,
  buildLaunchTx,
  buildProposeTx,
  buildApplyTx,
  buildCloseTx,
  SETTINGS_TOKEN_NAME,
  settingsDatumToData,
  settingsScript,
  settingsScriptAddress,
  type SettingsDatum,
  type SettingsParams,
} from "@contracts-library/meshjs";
import {
  mConStr0,
  type Data,
  type SlotConfig,
  type UTxO,
  unixTimeToEnclosingSlot,
} from "@meshsdk/core";
import { beforeAll, describe, expect, it } from "vitest";
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
  waitUntilChainTimeMs,
  type Account,
} from "../src/devnet";

const reachable = await devnetReachable();
if (!reachable) {
  console.warn(
    `[e2e] Skipping all e2e tests: no Yaci devnet at ${STORE_URL}. ` +
      `Run \`npm run test:devnet\` (or start one and set INDEXER_URL / YACI_STORE_URL).`,
  );
}

const VALUE_A: Data = mConStr0([1n]);
const VALUE_B: Data = mConStr0([2n]);

describe.skipIf(!reachable)("settings e2e (Yaci devnet)", () => {
  let provider: ReturnType<typeof makeProvider>;
  let slotConfig: SlotConfig;

  beforeAll(async () => {
    provider = makeProvider();
    slotConfig = await devnetSlotConfig();
  });

  async function setup(): Promise<{
    proposer: Account;
    applier: Account;
    seedUtxo: { transactionId: string; outputIndex: number };
    script: ReturnType<typeof settingsScript>;
    scriptAddr: string;
    applyDelay: number;
  }> {
    const proposer = await fundedAccount(provider);
    const applier = await fundedAccount(provider);

    const seedUtxos = await applier.wallet.getUtxos();
    const seed = seedUtxos[0];

    const params: SettingsParams = {
      seedUtxo: {
        transactionId: seed.input.txHash,
        outputIndex: seed.input.outputIndex,
      },
      proposeAuth: { kind: "key", hash: proposer.keyHash },
      applyAuth: { kind: "key", hash: applier.keyHash },
      applyDelay: 4_000,
      settingsTokenName: SETTINGS_TOKEN_NAME,
    };

    const script = settingsScript(params);
    const scriptAddr = settingsScriptAddress(script, NETWORK_ID);

    return {
      proposer,
      applier,
      seedUtxo: {
        transactionId: seed.input.txHash,
        outputIndex: seed.input.outputIndex,
      },
      script,
      scriptAddr,
      applyDelay: params.applyDelay,
    };
  }

  /** A raw, possibly-malicious spend of a settings UTxO (apply redeemer). */
  async function rawApply(p: {
    signer: Account;
    script: ReturnType<typeof settingsScript>;
    scriptAddr: string;
    settingsUtxo: UTxO;
    datum: SettingsDatum;
    validityNow: number;
    outputIndex: number;
    requiredSigner?: string;
  }): Promise<string> {
    const tb = newTxBuilder(provider);

    tb.spendingPlutusScriptV3()
      .txIn(
        p.settingsUtxo.input.txHash,
        p.settingsUtxo.input.outputIndex,
        p.settingsUtxo.output.amount,
        p.settingsUtxo.output.address,
      )
      .txInInlineDatumPresent()
      .txInRedeemerValue(applyRedeemer(p.outputIndex))
      .txInScript(p.script.code);

    tb.txOut(p.scriptAddr, p.settingsUtxo.output.amount).txOutInlineDatumValue(
      settingsDatumToData(p.datum),
    );

    tb.invalidBefore(unixTimeToEnclosingSlot(p.validityNow, slotConfig));
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

  // ----------------------------------------------------------- happy paths

  it("mints a settings UTxO", async () => {
    const ctx = await setup();

    const datum: SettingsDatum = {
      current: VALUE_A,
      next: null,
      nextApply: null,
    };

    const mintTx = await buildLaunchTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      seedUtxo: (await ctx.applier.wallet.getUtxos()).find(
        (u) =>
          u.input.txHash === ctx.seedUtxo.transactionId &&
          u.input.outputIndex === ctx.seedUtxo.outputIndex,
      )!,
      datum,
      outputIndex: 0,
      utxos: await ctx.applier.wallet.getUtxos(),
      changeAddress: ctx.applier.address,
      collateralUtxo: await collateralOf(ctx.applier),
      applyAuth: { kind: "key", hash: ctx.applier.keyHash },
    });

    const hash = await signAndSubmit(ctx.applier, mintTx);
    await waitForTx(provider, hash);

    const settingsUtxo = await scriptOutputOf(provider, hash, ctx.scriptAddr);
    expect(settingsUtxo).toBeDefined();
  });

  it("mints, proposes, applies, and closes", async () => {
    const ctx = await setup();

    // 1. Mint
    const datum: SettingsDatum = {
      current: VALUE_A,
      next: null,
      nextApply: null,
    };

    const seedUtxo = (await ctx.applier.wallet.getUtxos()).find(
      (u) =>
        u.input.txHash === ctx.seedUtxo.transactionId &&
        u.input.outputIndex === ctx.seedUtxo.outputIndex,
    )!;

    const mintTx = await buildLaunchTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      seedUtxo,
      datum,
      outputIndex: 0,
      utxos: await ctx.applier.wallet.getUtxos(),
      changeAddress: ctx.applier.address,
      collateralUtxo: await collateralOf(ctx.applier),
      applyAuth: { kind: "key", hash: ctx.applier.keyHash },
    });
    const mintHash = await signAndSubmit(ctx.applier, mintTx);
    await waitForTx(provider, mintHash);
    const settingsUtxo = await scriptOutputOf(
      provider,
      mintHash,
      ctx.scriptAddr,
    );

    // 2. Propose
    const proposeNow = await chainNowMs();
    const proposeTx = await buildProposeTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      settingsUtxo,
      datum,
      newValue: VALUE_B,
      now: proposeNow,
      outputIndex: 0,
      utxos: await ctx.proposer.wallet.getUtxos(),
      changeAddress: ctx.proposer.address,
      collateralUtxo: await collateralOf(ctx.proposer),
      proposeAuth: { kind: "key", hash: ctx.proposer.keyHash },
      applyDelay: ctx.applyDelay,
      customSlotConfig: slotConfig,
    });
    const proposeHash = await signAndSubmit(ctx.proposer, proposeTx);
    await waitForTx(provider, proposeHash);
    const proposedUtxo = await scriptOutputOf(
      provider,
      proposeHash,
      ctx.scriptAddr,
    );

    // 3. Wait and Apply
    const proposedDatum: SettingsDatum = {
      current: VALUE_A,
      next: VALUE_B,
      nextApply: proposeNow + ctx.applyDelay,
    };
    await waitUntilChainTimeMs(proposedDatum.nextApply! + 2_000);
    const applyNow = await chainNowMs();

    const applyTx = await buildApplyTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      settingsUtxo: proposedUtxo,
      datum: proposedDatum,
      now: applyNow,
      outputIndex: 0,
      utxos: await ctx.applier.wallet.getUtxos(),
      changeAddress: ctx.applier.address,
      collateralUtxo: await collateralOf(ctx.applier),
      applyAuth: { kind: "key", hash: ctx.applier.keyHash },
      customSlotConfig: slotConfig,
    });
    const applyHash = await signAndSubmit(ctx.applier, applyTx);
    await waitForTx(provider, applyHash);
    const appliedUtxo = await scriptOutputOf(
      provider,
      applyHash,
      ctx.scriptAddr,
    );
    expect(appliedUtxo).toBeDefined();

    // 4. Close
    const closeTx = await buildCloseTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      settingsUtxo: appliedUtxo,
      utxos: await ctx.applier.wallet.getUtxos(),
      changeAddress: ctx.applier.address,
      collateralUtxo: await collateralOf(ctx.applier),
      applyAuth: { kind: "key", hash: ctx.applier.keyHash },
    });
    const closeHash = await signAndSubmit(ctx.applier, closeTx);
    await waitForTx(provider, closeHash);

    const outs = await provider.fetchUTxOs(closeHash);
    expect(outs.some((u) => u.output.address === ctx.scriptAddr)).toBe(false);
  });

  // ----------------------------------------------------------- attack paths

  it("rejects raw apply before next_apply", async () => {
    const ctx = await setup();

    const datum: SettingsDatum = {
      current: VALUE_A,
      next: null,
      nextApply: null,
    };

    const seedUtxo = (await ctx.applier.wallet.getUtxos()).find(
      (u) =>
        u.input.txHash === ctx.seedUtxo.transactionId &&
        u.input.outputIndex === ctx.seedUtxo.outputIndex,
    )!;

    const mintTx = await buildLaunchTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      seedUtxo,
      datum,
      outputIndex: 0,
      utxos: await ctx.applier.wallet.getUtxos(),
      changeAddress: ctx.applier.address,
      collateralUtxo: await collateralOf(ctx.applier),
      applyAuth: { kind: "key", hash: ctx.applier.keyHash },
    });
    const mintHash = await signAndSubmit(ctx.applier, mintTx);
    await waitForTx(provider, mintHash);
    const settingsUtxo = await scriptOutputOf(
      provider,
      mintHash,
      ctx.scriptAddr,
    );

    const proposeNow = await chainNowMs();
    const proposeTx = await buildProposeTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      settingsUtxo,
      datum,
      newValue: VALUE_B,
      now: proposeNow,
      outputIndex: 0,
      utxos: await ctx.proposer.wallet.getUtxos(),
      changeAddress: ctx.proposer.address,
      collateralUtxo: await collateralOf(ctx.proposer),
      proposeAuth: { kind: "key", hash: ctx.proposer.keyHash },
      applyDelay: ctx.applyDelay,
      customSlotConfig: slotConfig,
    });
    const proposeHash = await signAndSubmit(ctx.proposer, proposeTx);
    await waitForTx(provider, proposeHash);
    const proposedUtxo = await scriptOutputOf(
      provider,
      proposeHash,
      ctx.scriptAddr,
    );

    const proposedDatum: SettingsDatum = {
      current: VALUE_A,
      next: VALUE_B,
      nextApply: proposeNow + ctx.applyDelay,
    };

    await expect(
      rawApply({
        signer: ctx.applier,
        script: ctx.script,
        scriptAddr: ctx.scriptAddr,
        settingsUtxo: proposedUtxo,
        datum: proposedDatum,
        validityNow: proposeNow + 1_000,
        outputIndex: 0,
        requiredSigner: ctx.applier.keyHash,
      }),
    ).rejects.toThrow();
  });

  it("rejects raw apply with no pending proposal", async () => {
    const ctx = await setup();

    const datum: SettingsDatum = {
      current: VALUE_A,
      next: null,
      nextApply: null,
    };

    const seedUtxo = (await ctx.applier.wallet.getUtxos()).find(
      (u) =>
        u.input.txHash === ctx.seedUtxo.transactionId &&
        u.input.outputIndex === ctx.seedUtxo.outputIndex,
    )!;

    const mintTx = await buildLaunchTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      seedUtxo,
      datum,
      outputIndex: 0,
      utxos: await ctx.applier.wallet.getUtxos(),
      changeAddress: ctx.applier.address,
      collateralUtxo: await collateralOf(ctx.applier),
      applyAuth: { kind: "key", hash: ctx.applier.keyHash },
    });
    const mintHash = await signAndSubmit(ctx.applier, mintTx);
    await waitForTx(provider, mintHash);
    const settingsUtxo = await scriptOutputOf(
      provider,
      mintHash,
      ctx.scriptAddr,
    );

    await expect(
      rawApply({
        signer: ctx.applier,
        script: ctx.script,
        scriptAddr: ctx.scriptAddr,
        settingsUtxo,
        datum,
        validityNow: await chainNowMs(),
        outputIndex: 0,
        requiredSigner: ctx.applier.keyHash,
      }),
    ).rejects.toThrow();
  });

  it("rejects propose with same value as current", async () => {
    const ctx = await setup();

    const datum: SettingsDatum = {
      current: VALUE_A,
      next: null,
      nextApply: null,
    };

    await expect(
      buildProposeTx({
        txBuilder: newTxBuilder(provider),
        script: ctx.script,
        settingsUtxo: (await ctx.proposer.wallet.getUtxos())[0],
        datum,
        newValue: VALUE_A,
        now: await chainNowMs(),
        outputIndex: 0,
        utxos: await ctx.proposer.wallet.getUtxos(),
        changeAddress: ctx.proposer.address,
        collateralUtxo: await collateralOf(ctx.proposer),
        proposeAuth: { kind: "key", hash: ctx.proposer.keyHash },
        applyDelay: ctx.applyDelay,
        customSlotConfig: slotConfig,
      }),
    ).rejects.toThrow();
  });
});
