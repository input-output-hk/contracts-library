/**
 * End-to-end tests for the smart wallet contract against a Yaci DevKit devnet.
 *
 * Core lifecycle (no delegated withdrawal scripts): the wallet reads its base
 * M-of-N config from a settings UTxO (reference input) and carries an empty
 * `withdrawals` map, so `Spend` only needs the M-of-N floor.
 */

import {
  buildWalletMintTx,
  buildWalletDepositTx,
  buildWalletSpendTx,
  buildWalletUpdateConfigTx,
  buildWalletCloseTx,
  smartWalletScript,
  smartWalletScriptAddress,
  walletConfigToData,
  SETTINGS_TOKEN_NAME,
  settingsScript,
  settingsScriptAddress,
  buildLaunchTx,
  type SettingsDatum,
  type SettingsParams,
  type WalletConfig,
  type WalletDatum,
  type WalletParams,
} from "@contracts-library/meshjs";
import {
  resolveScriptHash,
  type Asset,
  type TxInput,
  type UTxO,
} from "@meshsdk/core";
import { beforeAll, describe, expect, it } from "vitest";
import {
  collateralOf,
  devnetReachable,
  fundedAccount,
  lovelaceOf,
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

const WALLET_TOKEN_NAME = "57414c4c4554"; // hex "WALLET"

const LOVELACE: Asset = { unit: "lovelace", quantity: "1000000" };

/** Subtract `lovelace` from an asset list (used to compute the Spend change). */
function minusLovelace(amount: Asset[], ada: bigint): Asset[] {
  return amount.map((a) =>
    a.unit === "lovelace"
      ? { unit: "lovelace", quantity: (BigInt(a.quantity) - ada).toString() }
      : a,
  );
}

describe.skipIf(!reachable)("smart wallet e2e (Yaci devnet)", () => {
  let provider: ReturnType<typeof makeProvider>;

  beforeAll(async () => {
    provider = makeProvider();
  });

  async function setup(): Promise<{
    admin: Account;
    depositor: Account;
    member: Account;
    walletTokenName: string;
    script: ReturnType<typeof smartWalletScript>;
    scriptAddr: string;
    walletConfig: WalletConfig;
    settingsUtxo: UTxO;
    walletSeed: UTxO;
  }> {
    const admin = await fundedAccount(provider);
    const depositor = await fundedAccount(provider);
    const member = await fundedAccount(provider);

    // Launch a settings instance whose `current` is the wallet's M-of-N config.
    const settingsSeed = (await admin.wallet.getUtxos())[0];
    const settingsParams: SettingsParams = {
      seedUtxo: settingsSeed.input,
      proposeAuth: { kind: "key", hash: admin.keyHash },
      applyAuth: { kind: "key", hash: admin.keyHash },
      applyDelay: 4_000,
      settingsTokenName: SETTINGS_TOKEN_NAME,
    };
    const settings = settingsScript(settingsParams);
    const settingsAddr = settingsScriptAddress(settings, NETWORK_ID);

    const walletConfig: WalletConfig = {
      members: [member.keyHash],
      threshold: 1,
    };
    const settingsDatum: SettingsDatum = {
      current: walletConfigToData(walletConfig),
      next: null,
      nextApply: null,
    };

    const settingsLaunchTx = await buildLaunchTx({
      txBuilder: newTxBuilder(provider),
      script: settings,
      seedUtxo: settingsSeed,
      datum: settingsDatum,
      outputIndex: 0,
      utxos: await admin.wallet.getUtxos(),
      changeAddress: admin.address,
      collateralUtxo: await collateralOf(admin),
      applyAuth: { kind: "key", hash: admin.keyHash },
    });
    const settingsHash = await signAndSubmit(admin, settingsLaunchTx);
    await waitForTx(provider, settingsHash);
    const settingsUtxo = await scriptOutputOf(
      provider,
      settingsHash,
      settingsAddr,
    );

    // A fresh UTxO (post-launch) serves as the wallet's one-shot seed.
    const walletSeed = (await admin.wallet.getUtxos())[0];

    const params: WalletParams = {
      seedUtxo: walletSeed.input,
      settingsPolicy: resolveScriptHash(settings.code, settings.version),
      settingsTokenName: SETTINGS_TOKEN_NAME,
      walletTokenName: WALLET_TOKEN_NAME,
      admin: { kind: "key", hash: admin.keyHash },
    };
    const script = smartWalletScript(params);
    const scriptAddr = smartWalletScriptAddress(script, NETWORK_ID);

    return {
      admin,
      depositor,
      member,
      walletTokenName: WALLET_TOKEN_NAME,
      script,
      scriptAddr,
      walletConfig,
      settingsUtxo,
      walletSeed,
    };
  }

  function emptyDatum(depositor: string): WalletDatum {
    return { withdrawals: [], depositor: { kind: "key", hash: depositor } };
  }

  async function mintWallet(
    ctx: Awaited<ReturnType<typeof setup>>,
    depositorKeyHash: string,
  ): Promise<UTxO> {
    const datum = emptyDatum(depositorKeyHash);

    const mintTx = await buildWalletMintTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletTokenName: ctx.walletTokenName,
      seedUtxo: ctx.walletSeed,
      datum,
      outputIndex: 0,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
      admin: { kind: "key", hash: ctx.admin.keyHash },
    });
    const hash = await signAndSubmit(ctx.admin, mintTx);
    await waitForTx(provider, hash);
    return await scriptOutputOf(provider, hash, ctx.scriptAddr);
  }

  it("mints, deposits, spends, updates config, and closes", async () => {
    const ctx = await setup();

    // 1. Mint
    const minted = await mintWallet(ctx, ctx.depositor.keyHash);
    const policyId = resolveScriptHash(ctx.script.code, ctx.script.version);
    expect(
      minted.output.amount.some(
        (a) => a.unit === policyId + ctx.walletTokenName && a.quantity === "1",
      ),
    ).toBe(true);

    // 2. Deposit
    const depositTx = await buildWalletDepositTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletUtxo: minted,
      datum: emptyDatum(ctx.depositor.keyHash),
      deposit: [LOVELACE],
      outputIndex: 0,
      utxos: await ctx.depositor.wallet.getUtxos(),
      changeAddress: ctx.depositor.address,
      collateralUtxo: await collateralOf(ctx.depositor),
      depositor: { kind: "key", hash: ctx.depositor.keyHash },
    });
    const depositHash = await signAndSubmit(ctx.depositor, depositTx);
    await waitForTx(provider, depositHash);
    const deposited = await scriptOutputOf(
      provider,
      depositHash,
      ctx.scriptAddr,
    );
    expect(lovelaceOf(deposited)).toBeGreaterThan(lovelaceOf(minted));

    // 3. Spend (M-of-N: the single member signs)
    const payoutAda = 1_000_000n;
    const change = minusLovelace(deposited.output.amount, payoutAda);
    const spendTx = await buildWalletSpendTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletUtxo: deposited,
      settingsUtxo: ctx.settingsUtxo,
      datum: emptyDatum(ctx.depositor.keyHash),
      payoutAddress: ctx.member.address,
      payoutAmount: [{ unit: "lovelace", quantity: payoutAda.toString() }],
      changeAmount: change,
      outputIndex: 0,
      utxos: await ctx.member.wallet.getUtxos(),
      changeAddress: ctx.member.address,
      collateralUtxo: await collateralOf(ctx.member),
      signers: [ctx.member.keyHash],
    });
    const spendHash = await signAndSubmit(ctx.member, spendTx);
    await waitForTx(provider, spendHash);
    const spent = await scriptOutputOf(provider, spendHash, ctx.scriptAddr);
    expect(lovelaceOf(spent)).toBe(lovelaceOf(deposited) - payoutAda);

    // 4. UpdateConfig (change depositor to the admin)
    const updated = await buildWalletUpdateConfigTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletUtxo: spent,
      newDatum: emptyDatum(ctx.admin.keyHash),
      outputIndex: 0,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
      admin: { kind: "key", hash: ctx.admin.keyHash },
    });
    const updatedHash = await signAndSubmit(ctx.admin, updated);
    await waitForTx(provider, updatedHash);
    const updatedUtxo = await scriptOutputOf(
      provider,
      updatedHash,
      ctx.scriptAddr,
    );

    // 5. Close (burn the NFT)
    const closeTx = await buildWalletCloseTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletTokenName: ctx.walletTokenName,
      walletUtxo: updatedUtxo,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
      admin: { kind: "key", hash: ctx.admin.keyHash },
    });
    const closeHash = await signAndSubmit(ctx.admin, closeTx);
    await waitForTx(provider, closeHash);
    const outs = await provider.fetchUTxOs(closeHash);
    expect(outs.some((u) => u.output.address === ctx.scriptAddr)).toBe(false);
  });
});
