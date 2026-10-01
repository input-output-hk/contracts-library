/**
 * End-to-end tests for the smart wallet's delegated withdrawal scripts
 * (`spending_limit`, `spending_window`) against a Yaci DevKit devnet.
 *
 * Covers the CIP-69 `publish` lifecycle: register on mint, invoke (withdraw-0)
 * on spend, deregister on update/close.
 */

import {
  buildWalletMintTx,
  buildWalletDepositTx,
  buildWalletSpendTx,
  buildWalletCloseTx,
  smartWalletScript,
  smartWalletScriptAddress,
  spendingLimitScript,
  spendingWindowScript,
  spendingWindowStateToData,
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
  type SpendingWindowState,
} from "@contracts-library/meshjs";
import {
  resolveScriptHash,
  unixTimeToEnclosingSlot,
  type Asset,
  type SlotConfig,
  type UTxO,
} from "@meshsdk/core";
import { beforeAll, describe, expect, it } from "vitest";
import {
  chainNowMs,
  collateralOf,
  devnetReachable,
  devnetSlotConfig,
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
const ADA = 1_000_000n;

function minusLovelace(amount: Asset[], ada: bigint): Asset[] {
  return amount.map((a) =>
    a.unit === "lovelace"
      ? { unit: "lovelace", quantity: (BigInt(a.quantity) - ada).toString() }
      : a,
  );
}

describe.skipIf(!reachable)("smart wallet withdrawal scripts e2e", () => {
  let provider: ReturnType<typeof makeProvider>;
  let slotConfig: SlotConfig;

  beforeAll(async () => {
    provider = makeProvider();
    slotConfig = await devnetSlotConfig();
  });

  async function setup(): Promise<{
    admin: Account;
    member: Account;
    walletScript: ReturnType<typeof smartWalletScript>;
    scriptAddr: string;
    walletHash: string;
    settingsUtxo: UTxO;
    walletSeed: UTxO;
  }> {
    const admin = await fundedAccount(provider);
    const member = await fundedAccount(provider);

    // Launch a settings instance holding the M-of-N config.
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

    const walletSeed = (await admin.wallet.getUtxos())[0];
    const walletParams: WalletParams = {
      seedUtxo: walletSeed.input,
      settingsPolicy: resolveScriptHash(settings.code, settings.version),
      settingsTokenName: SETTINGS_TOKEN_NAME,
      walletTokenName: WALLET_TOKEN_NAME,
      admin: { kind: "key", hash: admin.keyHash },
    };
    const walletScript = smartWalletScript(walletParams);
    const scriptAddr = smartWalletScriptAddress(walletScript, NETWORK_ID);
    const walletHash = resolveScriptHash(
      walletScript.code,
      walletScript.version,
    );

    return {
      admin,
      member,
      walletScript,
      scriptAddr,
      walletHash,
      settingsUtxo,
      walletSeed,
    };
  }

  it("spending_limit: register on mint, spend under bound, reject over bound, close", async () => {
    const ctx = await setup();

    const limit = spendingLimitScript({
      wallet: { kind: "script", hash: ctx.walletHash },
      bound: 5_000_000,
    });
    const limitHash = resolveScriptHash(limit.code, limit.version);
    const datum: WalletDatum = {
      withdrawals: [{ scriptHash: limitHash, data: 0 }],
      depositor: { kind: "key", hash: ctx.admin.keyHash },
    };

    // 1. Mint (registers the script's stake credential).
    const mintTx = await buildWalletMintTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.walletScript,
      walletTokenName: WALLET_TOKEN_NAME,
      seedUtxo: ctx.walletSeed,
      datum,
      outputIndex: 0,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
      admin: { kind: "key", hash: ctx.admin.keyHash },
      registerScripts: [limit],
    });
    const mintHash = await signAndSubmit(ctx.admin, mintTx);
    await waitForTx(provider, mintHash);
    const minted = await scriptOutputOf(provider, mintHash, ctx.scriptAddr);

    // 2. Deposit so there is enough to test a large payout.
    const depositTx = await buildWalletDepositTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.walletScript,
      walletUtxo: minted,
      datum,
      deposit: [{ unit: "lovelace", quantity: (10n * ADA).toString() }],
      outputIndex: 0,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
      depositor: { kind: "key", hash: ctx.admin.keyHash },
    });
    const depositHash = await signAndSubmit(ctx.admin, depositTx);
    await waitForTx(provider, depositHash);
    const deposited = await scriptOutputOf(
      provider,
      depositHash,
      ctx.scriptAddr,
    );

    // 3. Spend under the bound (outflow 3 ADA < 5 ADA).
    const underPayout = 3_000_000n;
    const underChange = minusLovelace(deposited.output.amount, underPayout);
    const underTx = await buildWalletSpendTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.walletScript,
      walletUtxo: deposited,
      settingsUtxo: ctx.settingsUtxo,
      datum,
      payoutAddress: ctx.member.address,
      payoutAmount: [{ unit: "lovelace", quantity: underPayout.toString() }],
      changeAmount: underChange,
      outputIndex: 0,
      utxos: await ctx.member.wallet.getUtxos(),
      changeAddress: ctx.member.address,
      collateralUtxo: await collateralOf(ctx.member),
      signers: [ctx.member.keyHash],
      withdrawalScripts: [limit],
    });
    const underHash = await signAndSubmit(ctx.member, underTx);
    await waitForTx(provider, underHash);
    const spentUnder = await scriptOutputOf(
      provider,
      underHash,
      ctx.scriptAddr,
    );
    expect(lovelaceOf(spentUnder)).toBe(lovelaceOf(deposited) - underPayout);

    // 4. Spend over the bound (outflow 6 ADA >= 5 ADA) must be rejected.
    const overPayout = 6_000_000n;
    const overChange = minusLovelace(spentUnder.output.amount, overPayout);
    await expect(
      buildWalletSpendTx({
        txBuilder: newTxBuilder(provider),
        script: ctx.walletScript,
        walletUtxo: spentUnder,
        settingsUtxo: ctx.settingsUtxo,
        datum,
        payoutAddress: ctx.member.address,
        payoutAmount: [{ unit: "lovelace", quantity: overPayout.toString() }],
        changeAmount: overChange,
        outputIndex: 0,
        utxos: await ctx.member.wallet.getUtxos(),
        changeAddress: ctx.member.address,
        collateralUtxo: await collateralOf(ctx.member),
        signers: [ctx.member.keyHash],
        withdrawalScripts: [limit],
      }),
    ).rejects.toThrow();

    // 5. Close (deregisters the script's stake credential).
    const closeTx = await buildWalletCloseTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.walletScript,
      walletTokenName: WALLET_TOKEN_NAME,
      walletUtxo: spentUnder,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
      admin: { kind: "key", hash: ctx.admin.keyHash },
      deregisterScripts: [limit],
    });
    const closeHash = await signAndSubmit(ctx.admin, closeTx);
    await waitForTx(provider, closeHash);
    const outs = await provider.fetchUTxOs(closeHash);
    expect(outs.some((u) => u.output.address === ctx.scriptAddr)).toBe(false);
  });

  it("spending_window: first spend allowed, second spend within the window rejected", async () => {
    const ctx = await setup();

    const window = spendingWindowScript({
      wallet: { kind: "script", hash: ctx.walletHash },
      window: 3_600_000,
    });
    const windowHash = resolveScriptHash(window.code, window.version);

    function datumWith(state: SpendingWindowState): WalletDatum {
      return {
        withdrawals: [
          { scriptHash: windowHash, data: spendingWindowStateToData(state) },
        ],
        depositor: { kind: "key", hash: ctx.admin.keyHash },
      };
    }

    const startMs = (slot: number) =>
      slotConfig.zeroTime +
      (slot - slotConfig.zeroSlot) * slotConfig.slotLength;

    // 1. Mint with initial state `lastSpend = 0`.
    const initialDatum = datumWith({ lastSpend: 0 });
    const mintTx = await buildWalletMintTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.walletScript,
      walletTokenName: WALLET_TOKEN_NAME,
      seedUtxo: ctx.walletSeed,
      datum: initialDatum,
      outputIndex: 0,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
      admin: { kind: "key", hash: ctx.admin.keyHash },
      registerScripts: [window],
    });
    const mintHash = await signAndSubmit(ctx.admin, mintTx);
    await waitForTx(provider, mintHash);
    const minted = await scriptOutputOf(provider, mintHash, ctx.scriptAddr);

    // 2. Deposit so the wallet holds enough lovelace for a >= min-ADA payout.
    const depositTx = await buildWalletDepositTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.walletScript,
      walletUtxo: minted,
      datum: initialDatum,
      deposit: [{ unit: "lovelace", quantity: (5n * ADA).toString() }],
      outputIndex: 0,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
      depositor: { kind: "key", hash: ctx.admin.keyHash },
    });
    const depositHash = await signAndSubmit(ctx.admin, depositTx);
    await waitForTx(provider, depositHash);
    const deposited = await scriptOutputOf(
      provider,
      depositHash,
      ctx.scriptAddr,
    );

    // 3. First spend: advances the state to `now`.
    const now1Ms = await chainNowMs();
    const slot1 = unixTimeToEnclosingSlot(now1Ms, slotConfig);
    const nextDatum = datumWith({ lastSpend: startMs(slot1) });
    const firstTx = await buildWalletSpendTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.walletScript,
      walletUtxo: deposited,
      settingsUtxo: ctx.settingsUtxo,
      datum: nextDatum,
      payoutAddress: ctx.member.address,
      payoutAmount: [{ unit: "lovelace", quantity: ADA.toString() }],
      changeAmount: minusLovelace(deposited.output.amount, ADA),
      outputIndex: 0,
      utxos: await ctx.member.wallet.getUtxos(),
      changeAddress: ctx.member.address,
      collateralUtxo: await collateralOf(ctx.member),
      signers: [ctx.member.keyHash],
      withdrawalScripts: [window],
      invalidBeforeSlot: slot1,
    });
    const firstHash = await signAndSubmit(ctx.member, firstTx);
    await waitForTx(provider, firstHash);
    const spentOnce = await scriptOutputOf(provider, firstHash, ctx.scriptAddr);

    // 4. Second spend within the window must be rejected.
    const now2Ms = await chainNowMs();
    const slot2 = unixTimeToEnclosingSlot(now2Ms, slotConfig);
    const againDatum = datumWith({ lastSpend: startMs(slot2) });
    await expect(
      buildWalletSpendTx({
        txBuilder: newTxBuilder(provider),
        script: ctx.walletScript,
        walletUtxo: spentOnce,
        settingsUtxo: ctx.settingsUtxo,
        datum: againDatum,
        payoutAddress: ctx.member.address,
        payoutAmount: [{ unit: "lovelace", quantity: ADA.toString() }],
        changeAmount: minusLovelace(spentOnce.output.amount, ADA),
        outputIndex: 0,
        utxos: await ctx.member.wallet.getUtxos(),
        changeAddress: ctx.member.address,
        collateralUtxo: await collateralOf(ctx.member),
        signers: [ctx.member.keyHash],
        withdrawalScripts: [window],
        invalidBeforeSlot: slot2,
      }),
    ).rejects.toThrow();
  });
});
