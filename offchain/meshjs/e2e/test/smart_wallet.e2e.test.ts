/**
 * End-to-end tests for the smart wallet contract against a Yaci DevKit devnet.
 *
 * Two groups share this file:
 *   - the core lifecycle (no delegated scripts): the wallet reads its base
 *     M-of-N config from a settings UTxO (reference input), carries empty
 *     `spenders` / `depositors` maps (deposits are open), and exercises adding
 *     and invoking a depositor script through `UpdatePermissions`;
 *   - the delegated spender scripts (`spending_limit`, `spending_window`),
 *     which exercise the CIP-69 `publish` lifecycle: register on mint, invoke
 *     (withdraw-0) on spend, deregister on close.
 */

import {
  buildWalletMintTx,
  buildWalletDepositTx,
  buildWalletSpendTx,
  buildWalletUpdatePermissionsTx,
  buildWalletCloseTx,
  smartWalletScript,
  smartWalletScriptAddress,
  spendingLimitScript,
  spendingWindowScript,
  spendingWindowStateToData,
  spendingPeriodLimitScript,
  spendingPeriodStateToData,
  fullRecipientAllowListScript,
  fullRecipientDenyListScript,
  paymentStakingAllowListScript,
  paymentStakingDenyListScript,
  assetAllowListScript,
  assetDenyListScript,
  assetDepositAllowListScript,
  assetDepositDenyListScript,
  walletConfigToData,
  SETTINGS_TOKEN_NAME,
  settingsScript,
  settingsScriptAddress,
  buildLaunchTx,
  type Credential,
  type SettingsDatum,
  type SettingsParams,
  type WalletConfig,
  type WalletDatum,
  type WalletParams,
  type SpendingWindowState,
} from "@contracts-library/meshjs";
import {
  deserializeAddress,
  mConStr0,
  resolveScriptHash,
  unixTimeToEnclosingSlot,
  type Asset,
  type PlutusScript,
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
import { ALWAYS_TRUE, REJECT_WITHDRAW } from "../src/fixtures";

const reachable = await devnetReachable();
if (!reachable) {
  console.warn(
    `[e2e] Skipping all e2e tests: no Yaci devnet at ${STORE_URL}. ` +
      `Run \`npm run test:devnet\` (or start one and set INDEXER_URL / YACI_STORE_URL).`,
  );
}

const WALLET_TOKEN_NAME = "57414c4c4554"; // hex "WALLET"
const ADA = 1_000_000n;

/** The always-approving fixture as a parameterless withdraw-0 script. */
const GUARD_SCRIPT: PlutusScript = { code: ALWAYS_TRUE.cbor, version: "V3" };
/** The reject-withdraw fixture, as a script that refuses deposit approvals. */
const REJECT_SCRIPT: PlutusScript = {
  code: REJECT_WITHDRAW.cbor,
  version: "V3",
};

/** An initial/continuation datum with no delegated scripts. */
function emptyDatum(): WalletDatum {
  return { spenders: [], depositors: [] };
}

/** Subtract `lovelace` from an asset list (used to compute the Spend change). */
function minusLovelace(amount: Asset[], ada: bigint): Asset[] {
  return amount.map((a) =>
    a.unit === "lovelace"
      ? { unit: "lovelace", quantity: (BigInt(a.quantity) - ada).toString() }
      : a,
  );
}

/**
 * Launch a settings instance and a smart wallet on it, returning the context
 * both test groups need. `admin` owns the wallet; `depositor` funds it in the
 * core lifecycle (the spender-script group reuses `admin` as funder).
 */
async function setup(provider: ReturnType<typeof makeProvider>): Promise<{
  admin: Account;
  depositor: Account;
  member: Account;
  script: ReturnType<typeof smartWalletScript>;
  scriptAddr: string;
  walletHash: string;
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
  const walletHash = resolveScriptHash(script.code, script.version);

  return {
    admin,
    depositor,
    member,
    script,
    scriptAddr,
    walletHash,
    walletConfig,
    settingsUtxo,
    walletSeed,
  };
}

describe.skipIf(!reachable)("smart wallet e2e (Yaci devnet)", () => {
  let provider: ReturnType<typeof makeProvider>;

  beforeAll(async () => {
    provider = makeProvider();
  });

  async function mintWallet(
    ctx: Awaited<ReturnType<typeof setup>>,
  ): Promise<UTxO> {
    const mintTx = await buildWalletMintTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletTokenName: WALLET_TOKEN_NAME,
      seedUtxo: ctx.walletSeed,
      datum: emptyDatum(),
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

  it("mints, deposits, spends, updates permissions, and closes", async () => {
    const ctx = await setup(provider);

    // 1. Mint
    const minted = await mintWallet(ctx);
    const policyId = resolveScriptHash(ctx.script.code, ctx.script.version);
    expect(
      minted.output.amount.some(
        (a) => a.unit === policyId + WALLET_TOKEN_NAME && a.quantity === "1",
      ),
    ).toBe(true);

    // 2. Deposit (open: the `depositors` map is empty, so no scripts run)
    const depositTx = await buildWalletDepositTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletUtxo: minted,
      datum: emptyDatum(),
      deposit: [{ unit: "lovelace", quantity: ADA.toString() }],
      outputIndex: 0,
      utxos: await ctx.depositor.wallet.getUtxos(),
      changeAddress: ctx.depositor.address,
      collateralUtxo: await collateralOf(ctx.depositor),
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
      datum: emptyDatum(),
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

    // 4. UpdatePermissions: add the always-approving guard as a depositor
    const guardDatum: WalletDatum = {
      spenders: [],
      depositors: [{ scriptHash: ALWAYS_TRUE.hash, data: 0 }],
    };
    const updated = await buildWalletUpdatePermissionsTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletUtxo: spent,
      newDatum: guardDatum,
      outputIndex: 0,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
      admin: { kind: "key", hash: ctx.admin.keyHash },
      registerScripts: [GUARD_SCRIPT],
    });
    const updatedHash = await signAndSubmit(ctx.admin, updated);
    await waitForTx(provider, updatedHash);
    const updatedUtxo = await scriptOutputOf(
      provider,
      updatedHash,
      ctx.scriptAddr,
    );

    // 5. Deposit through the guard (the depositor script must be invoked)
    const guardedDeposit = await buildWalletDepositTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletUtxo: updatedUtxo,
      datum: guardDatum,
      deposit: [{ unit: "lovelace", quantity: ADA.toString() }],
      outputIndex: 0,
      utxos: await ctx.depositor.wallet.getUtxos(),
      changeAddress: ctx.depositor.address,
      collateralUtxo: await collateralOf(ctx.depositor),
      depositorScripts: [GUARD_SCRIPT],
    });
    const guardedHash = await signAndSubmit(ctx.depositor, guardedDeposit);
    await waitForTx(provider, guardedHash);
    const guardedUtxo = await scriptOutputOf(
      provider,
      guardedHash,
      ctx.scriptAddr,
    );

    // 6. Close (deregisters the depositor script)
    const closeTx = await buildWalletCloseTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletTokenName: WALLET_TOKEN_NAME,
      walletUtxo: guardedUtxo,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
      admin: { kind: "key", hash: ctx.admin.keyHash },
      deregisterScripts: [GUARD_SCRIPT],
    });
    const closeHash = await signAndSubmit(ctx.admin, closeTx);
    await waitForTx(provider, closeHash);
    const outs = await provider.fetchUTxOs(closeHash);
    expect(outs.some((u) => u.output.address === ctx.scriptAddr)).toBe(false);
  });

  it("rejects a deposit whose depositor script refuses", async () => {
    const ctx = await setup(provider);

    const datum: WalletDatum = {
      spenders: [],
      depositors: [{ scriptHash: REJECT_WITHDRAW.hash, data: 0 }],
    };
    const mintTx = await buildWalletMintTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletTokenName: WALLET_TOKEN_NAME,
      seedUtxo: ctx.walletSeed,
      datum,
      outputIndex: 0,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
      admin: { kind: "key", hash: ctx.admin.keyHash },
      registerScripts: [REJECT_SCRIPT],
    });
    const mintHash = await signAndSubmit(ctx.admin, mintTx);
    await waitForTx(provider, mintHash);
    const minted = await scriptOutputOf(provider, mintHash, ctx.scriptAddr);

    await expect(
      buildWalletDepositTx({
        txBuilder: newTxBuilder(provider),
        script: ctx.script,
        walletUtxo: minted,
        datum,
        deposit: [{ unit: "lovelace", quantity: ADA.toString() }],
        outputIndex: 0,
        utxos: await ctx.depositor.wallet.getUtxos(),
        changeAddress: ctx.depositor.address,
        collateralUtxo: await collateralOf(ctx.depositor),
        depositorScripts: [REJECT_SCRIPT],
      }),
    ).rejects.toThrow();
  });
});

describe.skipIf(!reachable)("smart wallet spender scripts e2e", () => {
  let provider: ReturnType<typeof makeProvider>;
  let slotConfig: SlotConfig;

  beforeAll(async () => {
    provider = makeProvider();
    slotConfig = await devnetSlotConfig();
  });

  it("spending_limit: register on mint, spend under bound, reject over bound, close", async () => {
    const ctx = await setup(provider);

    const limit = spendingLimitScript({
      wallet: { kind: "script", hash: ctx.walletHash },
      walletTokenName: WALLET_TOKEN_NAME,
      bound: 5_000_000,
    });
    const limitHash = resolveScriptHash(limit.code, limit.version);
    const datum: WalletDatum = {
      spenders: [{ scriptHash: limitHash, data: 0 }],
      depositors: [],
    };

    // 1. Mint (registers the script's stake credential).
    const mintTx = await buildWalletMintTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
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
      script: ctx.script,
      walletUtxo: minted,
      datum,
      deposit: [{ unit: "lovelace", quantity: (10n * ADA).toString() }],
      outputIndex: 0,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
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
      script: ctx.script,
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
      spenderScripts: [limit],
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
        script: ctx.script,
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
        spenderScripts: [limit],
      }),
    ).rejects.toThrow();

    // 5. Close (deregisters the script's stake credential).
    const closeTx = await buildWalletCloseTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
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
    const ctx = await setup(provider);

    const window = spendingWindowScript({
      wallet: { kind: "script", hash: ctx.walletHash },
      walletTokenName: WALLET_TOKEN_NAME,
      window: 3_600_000,
    });
    const windowHash = resolveScriptHash(window.code, window.version);

    function datumWith(state: SpendingWindowState): WalletDatum {
      return {
        spenders: [
          { scriptHash: windowHash, data: spendingWindowStateToData(state) },
        ],
        depositors: [],
      };
    }

    const startMs = (slot: number) =>
      slotConfig.zeroTime +
      (slot - slotConfig.zeroSlot) * slotConfig.slotLength;
    const upperSlot = (slot: number) => slot + 1_000;

    // 1. Mint with initial state `lastUpper = 0`.
    const initialDatum = datumWith({ lastUpper: 0 });
    const mintTx = await buildWalletMintTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
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
      script: ctx.script,
      walletUtxo: minted,
      datum: initialDatum,
      deposit: [{ unit: "lovelace", quantity: (5n * ADA).toString() }],
      outputIndex: 0,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
    });
    const depositHash = await signAndSubmit(ctx.admin, depositTx);
    await waitForTx(provider, depositHash);
    const deposited = await scriptOutputOf(
      provider,
      depositHash,
      ctx.scriptAddr,
    );

    // 3. First spend: records the finite validity upper bound.
    const now1Ms = await chainNowMs();
    const slot1 = unixTimeToEnclosingSlot(now1Ms, slotConfig);
    const slot1Upper = upperSlot(slot1);
    const nextDatum = datumWith({ lastUpper: startMs(slot1Upper) });
    const firstTx = await buildWalletSpendTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
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
      spenderScripts: [window],
      invalidBeforeSlot: slot1,
      invalidHereafterSlot: slot1Upper,
    });
    const firstHash = await signAndSubmit(ctx.member, firstTx);
    await waitForTx(provider, firstHash);
    const spentOnce = await scriptOutputOf(provider, firstHash, ctx.scriptAddr);

    // 4. Second spend within the window must be rejected.
    const now2Ms = await chainNowMs();
    const slot2 = unixTimeToEnclosingSlot(now2Ms, slotConfig);
    const slot2Upper = upperSlot(slot2);
    const againDatum = datumWith({ lastUpper: startMs(slot2Upper) });
    await expect(
      buildWalletSpendTx({
        txBuilder: newTxBuilder(provider),
        script: ctx.script,
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
        spenderScripts: [window],
        invalidBeforeSlot: slot2,
        invalidHereafterSlot: slot2Upper,
      }),
    ).rejects.toThrow();
  });

  it("spending_period_limit: under the cap ok, over the cap rejected in-period", async () => {
    const ctx = await setup(provider);

    const interval = 604_800_000; // one week, fixed grid
    const maxSpend = 1_500_000n; // 1.5 ADA per period
    const script = spendingPeriodLimitScript({
      wallet: { kind: "script", hash: ctx.walletHash },
      walletTokenName: WALLET_TOKEN_NAME,
      interval,
      maxSpend: Number(maxSpend),
    });
    const scriptHash = resolveScriptHash(script.code, script.version);

    function datumWith(state: {
      period: number;
      accSpend: number;
    }): WalletDatum {
      return {
        spenders: [{ scriptHash, data: spendingPeriodStateToData(state) }],
        depositors: [],
      };
    }

    const startMs = (slot: number) =>
      slotConfig.zeroTime +
      (slot - slotConfig.zeroSlot) * slotConfig.slotLength;

    // 1. Mint with the initial state (no period, nothing spent).
    const initialDatum = datumWith({ period: 0, accSpend: 0 });
    const mintTx = await buildWalletMintTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletTokenName: WALLET_TOKEN_NAME,
      seedUtxo: ctx.walletSeed,
      datum: initialDatum,
      outputIndex: 0,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
      admin: { kind: "key", hash: ctx.admin.keyHash },
      registerScripts: [script],
    });
    const mintHash = await signAndSubmit(ctx.admin, mintTx);
    await waitForTx(provider, mintHash);
    const minted = await scriptOutputOf(provider, mintHash, ctx.scriptAddr);

    // 2. Deposit so the wallet holds enough for a payout.
    const depositTx = await buildWalletDepositTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletUtxo: minted,
      datum: initialDatum,
      deposit: [{ unit: "lovelace", quantity: (5n * ADA).toString() }],
      outputIndex: 0,
      utxos: await ctx.admin.wallet.getUtxos(),
      changeAddress: ctx.admin.address,
      collateralUtxo: await collateralOf(ctx.admin),
    });
    const depositHash = await signAndSubmit(ctx.admin, depositTx);
    await waitForTx(provider, depositHash);
    const deposited = await scriptOutputOf(
      provider,
      depositHash,
      ctx.scriptAddr,
    );

    // 3. First spend (1 ADA) rolls the period over to the next fixed boundary.
    const now1Ms = await chainNowMs();
    const slot1 = unixTimeToEnclosingSlot(now1Ms, slotConfig);
    const period1 = (Math.floor(startMs(slot1) / interval) + 1) * interval;
    const firstTx = await buildWalletSpendTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.script,
      walletUtxo: deposited,
      settingsUtxo: ctx.settingsUtxo,
      datum: datumWith({ period: period1, accSpend: Number(ADA) }),
      payoutAddress: ctx.member.address,
      payoutAmount: [{ unit: "lovelace", quantity: ADA.toString() }],
      changeAmount: minusLovelace(deposited.output.amount, ADA),
      outputIndex: 0,
      utxos: await ctx.member.wallet.getUtxos(),
      changeAddress: ctx.member.address,
      collateralUtxo: await collateralOf(ctx.member),
      signers: [ctx.member.keyHash],
      spenderScripts: [script],
      invalidBeforeSlot: slot1,
    });
    const firstHash = await signAndSubmit(ctx.member, firstTx);
    await waitForTx(provider, firstHash);
    const spentOnce = await scriptOutputOf(provider, firstHash, ctx.scriptAddr);

    // 4. A second 1 ADA spend in the same period would exceed the 1.5 ADA cap.
    const now2Ms = await chainNowMs();
    const slot2 = unixTimeToEnclosingSlot(now2Ms, slotConfig);
    await expect(
      buildWalletSpendTx({
        txBuilder: newTxBuilder(provider),
        script: ctx.script,
        walletUtxo: spentOnce,
        settingsUtxo: ctx.settingsUtxo,
        datum: datumWith({ period: period1, accSpend: Number(ADA) }),
        payoutAddress: ctx.member.address,
        payoutAmount: [{ unit: "lovelace", quantity: ADA.toString() }],
        changeAmount: minusLovelace(spentOnce.output.amount, ADA),
        outputIndex: 0,
        utxos: await ctx.member.wallet.getUtxos(),
        changeAddress: ctx.member.address,
        collateralUtxo: await collateralOf(ctx.member),
        signers: [ctx.member.keyHash],
        spenderScripts: [script],
        invalidBeforeSlot: slot2,
      }),
    ).rejects.toThrow();
  });
});

describe.skipIf(!reachable)(
  "smart wallet recipient & asset scripts e2e",
  () => {
    let provider: ReturnType<typeof makeProvider>;

    beforeAll(async () => {
      provider = makeProvider();
    });

    type Ctx = Awaited<ReturnType<typeof setup>>;

    /** A test token minted under the always-true policy. */
    const TOKEN_NAME = "544f4b"; // hex("TOK")
    const TOKEN_QTY = 100n;
    const tokenPolicy = resolveScriptHash(ALWAYS_TRUE.cbor, "V3");
    const tokenUnit = tokenPolicy + TOKEN_NAME;
    const OTHER_POLICY = "ff".repeat(28);

    async function mintToken(account: Account): Promise<void> {
      const col = (await account.wallet.getCollateral())[0];
      const mintTx = await newTxBuilder(provider)
        .mintPlutusScriptV3()
        .mint(TOKEN_QTY.toString(), tokenPolicy, TOKEN_NAME)
        .mintRedeemerValue(mConStr0([]))
        .mintingScript(ALWAYS_TRUE.cbor)
        .txInCollateral(
          col.input.txHash,
          col.input.outputIndex,
          col.output.amount,
          col.output.address,
        )
        .changeAddress(account.address)
        .selectUtxosFrom(await account.wallet.getUtxos())
        .complete();
      await waitForTx(provider, await signAndSubmit(account, mintTx));
    }

    function statelessSpender(scriptHash: string): WalletDatum {
      return { spenders: [{ scriptHash, data: 0 }], depositors: [] };
    }

    function statelessDepositor(scriptHash: string): WalletDatum {
      return { spenders: [], depositors: [{ scriptHash, data: 0 }] };
    }

    async function mintWallet(
      ctx: Ctx,
      datum: WalletDatum,
      registerScripts: PlutusScript[],
    ): Promise<UTxO> {
      const mintTx = await buildWalletMintTx({
        txBuilder: newTxBuilder(provider),
        script: ctx.script,
        walletTokenName: WALLET_TOKEN_NAME,
        seedUtxo: ctx.walletSeed,
        datum,
        outputIndex: 0,
        utxos: await ctx.admin.wallet.getUtxos(),
        changeAddress: ctx.admin.address,
        collateralUtxo: await collateralOf(ctx.admin),
        admin: { kind: "key", hash: ctx.admin.keyHash },
        registerScripts,
      });
      const hash = await signAndSubmit(ctx.admin, mintTx);
      await waitForTx(provider, hash);
      return await scriptOutputOf(provider, hash, ctx.scriptAddr);
    }

    async function buildDeposit(
      ctx: Ctx,
      walletUtxo: UTxO,
      datum: WalletDatum,
      deposit: Asset[],
      depositorScripts?: PlutusScript[],
    ): Promise<string> {
      return buildWalletDepositTx({
        txBuilder: newTxBuilder(provider),
        script: ctx.script,
        walletUtxo,
        datum,
        deposit,
        outputIndex: 0,
        utxos: await ctx.depositor.wallet.getUtxos(),
        changeAddress: ctx.depositor.address,
        collateralUtxo: await collateralOf(ctx.depositor),
        depositorScripts,
      });
    }

    async function okDeposit(
      ctx: Ctx,
      walletUtxo: UTxO,
      datum: WalletDatum,
      deposit: Asset[],
      depositorScripts?: PlutusScript[],
    ): Promise<UTxO> {
      const tx = await buildDeposit(
        ctx,
        walletUtxo,
        datum,
        deposit,
        depositorScripts,
      );
      const hash = await signAndSubmit(ctx.depositor, tx);
      await waitForTx(provider, hash);
      return await scriptOutputOf(provider, hash, ctx.scriptAddr);
    }

    async function buildSpendAsync(
      ctx: Ctx,
      walletUtxo: UTxO,
      datum: WalletDatum,
      payoutAddress: string,
      payoutAmount: Asset[],
      changeAmount: Asset[],
      spenderScripts: PlutusScript[],
    ): Promise<string> {
      return buildWalletSpendTx({
        txBuilder: newTxBuilder(provider),
        script: ctx.script,
        walletUtxo,
        settingsUtxo: ctx.settingsUtxo,
        datum,
        payoutAddress,
        payoutAmount,
        changeAmount,
        outputIndex: 0,
        utxos: await ctx.member.wallet.getUtxos(),
        changeAddress: ctx.member.address,
        collateralUtxo: await collateralOf(ctx.member),
        signers: [ctx.member.keyHash],
        spenderScripts,
      });
    }

    async function okSpend(
      ctx: Ctx,
      walletUtxo: UTxO,
      datum: WalletDatum,
      payoutAddress: string,
      payoutAmount: Asset[],
      changeAmount: Asset[],
      spenderScripts: PlutusScript[],
    ): Promise<UTxO> {
      const tx = await buildSpendAsync(
        ctx,
        walletUtxo,
        datum,
        payoutAddress,
        payoutAmount,
        changeAmount,
        spenderScripts,
      );
      const hash = await signAndSubmit(ctx.member, tx);
      await waitForTx(provider, hash);
      return await scriptOutputOf(provider, hash, ctx.scriptAddr);
    }

    /** Remove `removed` from `amount`, dropping non-positive entries. */
    function moveOut(amount: Asset[], removed: Asset[]): Asset[] {
      const out = amount.map((a) => ({ ...a }));
      for (const r of removed) {
        const e = out.find((a) => a.unit === r.unit);
        if (e)
          e.quantity = (BigInt(e.quantity) - BigInt(r.quantity)).toString();
      }
      return out.filter((a) => BigInt(a.quantity) > 0n);
    }

    /**
     * The address(es) a member-funded spend emits outputs to: the member's
     * change/collateral-return address, the addresses its funding UTxOs live on,
     * and `@cardano-sdk/input-selection`'s fixed change placeholder
     * (`stubMaxSizeAddress`).
     *
     * MeshJS's `MeshTxBuilder.complete()` runs input selection, and the CSDK
     * selector builds a provisional change output at that placeholder and
     * evaluates the scripts against that skeleton — the change address is only
     * rewritten to the real one *after* fee estimation
     * (`RoundRobinRandomImprove/index.js`). A strict recipient allow-list
     * therefore has to authorise the placeholder, even though the final
     * transaction uses the real change address. It is not a real recipient.
     */
    const FEE_ESTIMATION_CHANGE_ADDRESS =
      "addr_test1qqydn46r6mhge0kfpqmt36m6q43knzsd9ga32n96m89px3nuzcjqw982pcftgx53fu5527z2cj2tkx2h8ux2vxsg475qypp3m9";

    async function memberSpendAddresses(ctx: Ctx): Promise<string[]> {
      const utxos = await ctx.member.wallet.getUtxos();
      return [
        ...new Set([
          ctx.member.address,
          ...utxos.map((u) => u.output.address),
          FEE_ESTIMATION_CHANGE_ADDRESS,
        ]),
      ];
    }

    function paymentCredential(addr: string): Credential {
      const d = deserializeAddress(addr);
      return d.scriptHash
        ? { kind: "script", hash: d.scriptHash }
        : { kind: "key", hash: d.pubKeyHash };
    }

    function stakingCredential(addr: string): Credential | undefined {
      const d = deserializeAddress(addr);
      if (d.stakeCredentialHash)
        return { kind: "key", hash: d.stakeCredentialHash };
      if (d.stakeScriptCredentialHash)
        return { kind: "script", hash: d.stakeScriptCredentialHash };
      return undefined;
    }

    const payoutAda = 2n * ADA;

    // ------------------------------------------------- recipient scripts

    it("full_recipient_allow_list: listed recipient ok, unlisted rejected", async () => {
      const ctx = await setup(provider);
      const script = fullRecipientAllowListScript({
        wallet: { kind: "script", hash: ctx.walletHash },
        walletTokenName: WALLET_TOKEN_NAME,
        allowed: await memberSpendAddresses(ctx),
      });
      const datum = statelessSpender(
        resolveScriptHash(script.code, script.version),
      );

      let w = await mintWallet(ctx, datum, [script]);
      w = await okDeposit(ctx, w, datum, [
        { unit: "lovelace", quantity: (10n * ADA).toString() },
      ]);

      const payout = [{ unit: "lovelace", quantity: payoutAda.toString() }];
      w = await okSpend(
        ctx,
        w,
        datum,
        ctx.member.address,
        payout,
        minusLovelace(w.output.amount, payoutAda),
        [script],
      );

      await expect(
        buildSpendAsync(
          ctx,
          w,
          datum,
          ctx.depositor.address,
          payout,
          minusLovelace(w.output.amount, payoutAda),
          [script],
        ),
      ).rejects.toThrow();
    });

    it("full_recipient_deny_list: denied recipient rejected, other ok", async () => {
      const ctx = await setup(provider);
      const script = fullRecipientDenyListScript({
        wallet: { kind: "script", hash: ctx.walletHash },
        walletTokenName: WALLET_TOKEN_NAME,
        denied: [ctx.depositor.address],
      });
      const datum = statelessSpender(
        resolveScriptHash(script.code, script.version),
      );

      let w = await mintWallet(ctx, datum, [script]);
      w = await okDeposit(ctx, w, datum, [
        { unit: "lovelace", quantity: (10n * ADA).toString() },
      ]);
      const payout = [{ unit: "lovelace", quantity: payoutAda.toString() }];

      await expect(
        buildSpendAsync(
          ctx,
          w,
          datum,
          ctx.depositor.address,
          payout,
          minusLovelace(w.output.amount, payoutAda),
          [script],
        ),
      ).rejects.toThrow();

      await okSpend(
        ctx,
        w,
        datum,
        ctx.member.address,
        payout,
        minusLovelace(w.output.amount, payoutAda),
        [script],
      );
    });

    it("payment_staking_allow_list: listed payment+stake ok, unlisted rejected", async () => {
      const ctx = await setup(provider);
      const addrs = await memberSpendAddresses(ctx);
      const script = paymentStakingAllowListScript({
        wallet: { kind: "script", hash: ctx.walletHash },
        walletTokenName: WALLET_TOKEN_NAME,
        allowedPayments: addrs.map(paymentCredential),
        allowedStakings: addrs
          .map(stakingCredential)
          .filter((c): c is Credential => c !== undefined),
      });
      const datum = statelessSpender(
        resolveScriptHash(script.code, script.version),
      );

      let w = await mintWallet(ctx, datum, [script]);
      w = await okDeposit(ctx, w, datum, [
        { unit: "lovelace", quantity: (10n * ADA).toString() },
      ]);
      const payout = [{ unit: "lovelace", quantity: payoutAda.toString() }];

      w = await okSpend(
        ctx,
        w,
        datum,
        ctx.member.address,
        payout,
        minusLovelace(w.output.amount, payoutAda),
        [script],
      );

      await expect(
        buildSpendAsync(
          ctx,
          w,
          datum,
          ctx.depositor.address,
          payout,
          minusLovelace(w.output.amount, payoutAda),
          [script],
        ),
      ).rejects.toThrow();
    });

    it("payment_staking_deny_list: denied payment/staking rejected", async () => {
      const ctx = await setup(provider);
      const d = deserializeAddress(ctx.depositor.address);
      const script = paymentStakingDenyListScript({
        wallet: { kind: "script", hash: ctx.walletHash },
        walletTokenName: WALLET_TOKEN_NAME,
        deniedPayments: [{ kind: "key", hash: d.pubKeyHash }],
        deniedStakings: [],
      });
      const datum = statelessSpender(
        resolveScriptHash(script.code, script.version),
      );

      let w = await mintWallet(ctx, datum, [script]);
      w = await okDeposit(ctx, w, datum, [
        { unit: "lovelace", quantity: (10n * ADA).toString() },
      ]);
      const payout = [{ unit: "lovelace", quantity: payoutAda.toString() }];

      await expect(
        buildSpendAsync(
          ctx,
          w,
          datum,
          ctx.depositor.address,
          payout,
          minusLovelace(w.output.amount, payoutAda),
          [script],
        ),
      ).rejects.toThrow();

      await okSpend(
        ctx,
        w,
        datum,
        ctx.member.address,
        payout,
        minusLovelace(w.output.amount, payoutAda),
        [script],
      );
    });

    it("payment_staking_deny_list: denied staking rejected", async () => {
      const ctx = await setup(provider);
      const d = deserializeAddress(ctx.depositor.address);
      const script = paymentStakingDenyListScript({
        wallet: { kind: "script", hash: ctx.walletHash },
        walletTokenName: WALLET_TOKEN_NAME,
        deniedPayments: [],
        deniedStakings: [{ kind: "key", hash: d.stakeCredentialHash }],
      });
      const datum = statelessSpender(
        resolveScriptHash(script.code, script.version),
      );

      let w = await mintWallet(ctx, datum, [script]);
      w = await okDeposit(ctx, w, datum, [
        { unit: "lovelace", quantity: (10n * ADA).toString() },
      ]);
      const payout = [{ unit: "lovelace", quantity: payoutAda.toString() }];

      // The depositor's staking credential is denied: a payout to it is rejected.
      await expect(
        buildSpendAsync(
          ctx,
          w,
          datum,
          ctx.depositor.address,
          payout,
          minusLovelace(w.output.amount, payoutAda),
          [script],
        ),
      ).rejects.toThrow();

      // A payout to the member (staking not denied) is allowed.
      await okSpend(
        ctx,
        w,
        datum,
        ctx.member.address,
        payout,
        minusLovelace(w.output.amount, payoutAda),
        [script],
      );
    });

    // ------------------------------------------------- asset scripts

    async function walletWithToken(
      ctx: Ctx,
      script: PlutusScript,
      datum: WalletDatum,
      registerScripts: PlutusScript[],
    ): Promise<UTxO> {
      let w = await mintWallet(ctx, datum, registerScripts);
      w = await okDeposit(ctx, w, datum, [
        { unit: "lovelace", quantity: (5n * ADA).toString() },
        { unit: tokenUnit, quantity: TOKEN_QTY.toString() },
      ]);
      return w;
    }

    it("asset_allow_list: listed policy moves out, unlisted rejected", async () => {
      const ctx = await setup(provider);
      await mintToken(ctx.depositor);

      const allowed = assetAllowListScript({
        wallet: { kind: "script", hash: ctx.walletHash },
        walletTokenName: WALLET_TOKEN_NAME,
        allowed: [[tokenPolicy, []]],
      });
      const allowedDatum = statelessSpender(
        resolveScriptHash(allowed.code, allowed.version),
      );
      let w = await walletWithToken(ctx, allowed, allowedDatum, [allowed]);

      const moved = [
        { unit: tokenUnit, quantity: TOKEN_QTY.toString() },
        { unit: "lovelace", quantity: payoutAda.toString() },
      ];
      await okSpend(
        ctx,
        w,
        allowedDatum,
        ctx.member.address,
        moved,
        moveOut(w.output.amount, moved),
        [allowed],
      );

      // A wallet whose allow list omits the token's policy rejects the move.
      const ctx2 = await setup(provider);
      await mintToken(ctx2.depositor);
      const disallowed = assetAllowListScript({
        wallet: { kind: "script", hash: ctx2.walletHash },
        walletTokenName: WALLET_TOKEN_NAME,
        allowed: [[OTHER_POLICY, []]],
      });
      const disallowedDatum = statelessSpender(
        resolveScriptHash(disallowed.code, disallowed.version),
      );
      const w2 = await walletWithToken(ctx2, disallowed, disallowedDatum, [
        disallowed,
      ]);
      await expect(
        buildSpendAsync(
          ctx2,
          w2,
          disallowedDatum,
          ctx2.member.address,
          moved,
          moveOut(w2.output.amount, moved),
          [disallowed],
        ),
      ).rejects.toThrow();
    });

    it("asset_deny_list: denied policy rejected, lovelace-only ok", async () => {
      const ctx = await setup(provider);
      await mintToken(ctx.depositor);
      const script = assetDenyListScript({
        wallet: { kind: "script", hash: ctx.walletHash },
        walletTokenName: WALLET_TOKEN_NAME,
        denied: [[tokenPolicy, []]],
      });
      const datum = statelessSpender(
        resolveScriptHash(script.code, script.version),
      );
      const w = await walletWithToken(ctx, script, datum, [script]);

      const moved = [
        { unit: tokenUnit, quantity: TOKEN_QTY.toString() },
        { unit: "lovelace", quantity: payoutAda.toString() },
      ];
      await expect(
        buildSpendAsync(
          ctx,
          w,
          datum,
          ctx.member.address,
          moved,
          moveOut(w.output.amount, moved),
          [script],
        ),
      ).rejects.toThrow();

      // Moving only lovelace (the token stays put) is allowed.
      await okSpend(
        ctx,
        w,
        datum,
        ctx.member.address,
        [{ unit: "lovelace", quantity: payoutAda.toString() }],
        minusLovelace(w.output.amount, payoutAda),
        [script],
      );
    });

    it("asset_deposit_allow_list: listed deposit ok, unlisted rejected", async () => {
      const ctx = await setup(provider);
      await mintToken(ctx.depositor);
      const script = assetDepositAllowListScript({
        wallet: { kind: "script", hash: ctx.walletHash },
        walletTokenName: WALLET_TOKEN_NAME,
        allowed: [[tokenPolicy, []]],
      });
      const datum = statelessDepositor(
        resolveScriptHash(script.code, script.version),
      );
      const w = await mintWallet(ctx, datum, [script]);

      const withToken = [
        { unit: "lovelace", quantity: ADA.toString() },
        { unit: tokenUnit, quantity: TOKEN_QTY.toString() },
      ];
      await okDeposit(ctx, w, datum, withToken, [script]);

      // A wallet whose allow list omits the token's policy rejects the deposit.
      const ctx2 = await setup(provider);
      await mintToken(ctx2.depositor);
      const disallowed = assetDepositAllowListScript({
        wallet: { kind: "script", hash: ctx2.walletHash },
        walletTokenName: WALLET_TOKEN_NAME,
        allowed: [[OTHER_POLICY, []]],
      });
      const disallowedDatum = statelessDepositor(
        resolveScriptHash(disallowed.code, disallowed.version),
      );
      const w2 = await mintWallet(ctx2, disallowedDatum, [disallowed]);
      await expect(
        okDeposit(ctx2, w2, disallowedDatum, withToken, [disallowed]),
      ).rejects.toThrow();

      // A lovelace-only deposit is unaffected by the asset list.
      await okDeposit(
        ctx2,
        w2,
        disallowedDatum,
        [{ unit: "lovelace", quantity: ADA.toString() }],
        [disallowed],
      );
    });

    it("asset_deposit_deny_list: denied deposit rejected, lovelace-only ok", async () => {
      const ctx = await setup(provider);
      await mintToken(ctx.depositor);
      const script = assetDepositDenyListScript({
        wallet: { kind: "script", hash: ctx.walletHash },
        walletTokenName: WALLET_TOKEN_NAME,
        denied: [[tokenPolicy, []]],
      });
      const datum = statelessDepositor(
        resolveScriptHash(script.code, script.version),
      );
      const w = await mintWallet(ctx, datum, [script]);

      const withToken = [
        { unit: "lovelace", quantity: ADA.toString() },
        { unit: tokenUnit, quantity: TOKEN_QTY.toString() },
      ];
      await expect(
        okDeposit(ctx, w, datum, withToken, [script]),
      ).rejects.toThrow();

      await okDeposit(
        ctx,
        w,
        datum,
        [{ unit: "lovelace", quantity: ADA.toString() }],
        [script],
      );
    });
  },
);
