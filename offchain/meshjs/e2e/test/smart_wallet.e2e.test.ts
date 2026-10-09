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

    // 1. Mint with initial state `lastSpend = 0`.
    const initialDatum = datumWith({ lastSpend: 0 });
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

    // 3. First spend: advances the state to `now`.
    const now1Ms = await chainNowMs();
    const slot1 = unixTimeToEnclosingSlot(now1Ms, slotConfig);
    const nextDatum = datumWith({ lastSpend: startMs(slot1) });
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
      }),
    ).rejects.toThrow();
  });
});
