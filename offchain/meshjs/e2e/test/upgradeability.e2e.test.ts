/**
 * End-to-end tests for the upgradeability building block against a Yaci devnet.
 *
 * The registry lives in a settings UTxO; a forced tick forwards to the
 * registered logic script via a withdraw-0, and the opt-in migration moves a
 * V1 UTxO to V2 under the owner's consent. Happy paths plus attack paths that
 * exercise both off-chain guards and on-chain validator checks:
 *
 *   - forced tick → registered logic runs, funds never move;
 *   - opt-in tick → native, the registry is not consulted;
 *   - propose/apply → registry change with the timelock, entries carried forward;
 *   - migration → V1 `Upgrade` + owner signature → V2 state preserved;
 *   - no consent → rejected;
 *   - malicious migrations → tampered state, wrong target, underpayment,
 *     missing continuation, or a non-`Upgrade` action → rejected;
 *   - batched forwards → every registered input is validated, so a benign
 *     input cannot shield a stale one;
 *   - forced repoint → delegation actually switches (a tick routed to the
 *     migration script is rejected on-chain), and back;
 *   - forged registry → a look-alike without the settings NFT is ignored;
 *   - malformed registry → consumers brick (guarded off-chain) until restored.
 */

import {
  SETTINGS_TOKEN_NAME,
  buildLaunchTx,
  buildProposeTx,
  counterDatumFromUtxo,
  counterDatumToData,
  counterForwarderScript,
  counterLogicScript,
  counterMigrationScript,
  counterScriptAddress,
  counterScriptHash,
  counterV1Script,
  counterV2Script,
  enclosingSlotBound,
  opaqueRedeemer,
  readRegistry,
  registryToData,
  settingsDatumToData,
  settingsScript as makeSettingsScript,
  settingsScriptAddress,
  tickRedeemer,
  upgradeRedeemer,
  buildCounterTickTx,
  buildForwardTx,
  buildRegistryApplyTx,
  buildRegistryProposeTx,
  buildUpgradeTx,
  type CounterDatum,
  type Registry,
  type SettingsDatum,
  type SettingsRefParams,
} from "@contracts-library/meshjs";
import {
  resolveScriptHash,
  serializeRewardAddress,
  type Asset,
  type Data,
  type PlutusScript,
  type UTxO,
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
  registerStakeCredential,
  scriptOutputOf,
  signAndSubmit,
  waitForTx,
  waitUntilChainTimeMs,
  type Account,
} from "../src/devnet";

const reachable = await devnetReachable();
if (!reachable) {
  console.warn(
    "[e2e] Skipping all e2e tests: no Yaci devnet. " +
      "Run `npm run test:devnet` (or start one and set INDEXER_URL / YACI_STORE_URL).",
  );
}

describe.skipIf(!reachable)("upgradeability e2e (Yaci devnet)", () => {
  let provider: ReturnType<typeof makeProvider>;
  let slotConfig: Awaited<ReturnType<typeof devnetSlotConfig>>;

  const APPLY_DELAY = 4_000;
  const TIME_SLACK = 1_100;
  const SETTINGS_LOVELACE = 5_000_000n;
  const COUNTER_LOVELACE: Asset[] = [{ unit: "lovelace", quantity: "3000000" }];

  let governor: Account; // settings proposer + applier; pays stake registrations
  let alice: Account; // owns the counter UTxOs and consents to migrations
  let bob: Account; // the unconsenting owner for the negative test

  let settingsScript: PlutusScript;
  let settingsAddr: string;
  let counterParams: SettingsRefParams;

  let forwarderScript: ReturnType<typeof counterForwarderScript>;
  let logicScript: ReturnType<typeof counterLogicScript>;
  let v1Script: ReturnType<typeof counterV1Script>;
  let v2Script: ReturnType<typeof counterV2Script>;
  let migrationScript: ReturnType<typeof counterMigrationScript>;

  let forwarderAddr: string;
  let v1Addr: string;
  let v2Addr: string;

  let forwarderHash: string;
  let logicHash: string;
  let v1Hash: string;
  let migrationHash: string;

  let settingsUtxo: UTxO;
  let settingsDatum: SettingsDatum;
  let forwarderUtxo: UTxO;
  let v1Utxo: UTxO;
  let v2Utxo: UTxO;
  let seedRef: { txHash: string; outputIndex: number };

  const aliceOwner = (): CounterDatum["owner"] => ({
    kind: "key",
    hash: alice.keyHash,
  });

  beforeAll(async () => {
    provider = makeProvider();
    slotConfig = await devnetSlotConfig();

    governor = await fundedAccount(provider, [10_000, 10_000, 10_000]);
    alice = await fundedAccount(provider);
    bob = await fundedAccount(provider);

    // The settings script must be parameterized with its own seed, so the seed
    // is picked before anything else spends it.
    const seed = (await governor.wallet.getUtxos())[0];
    seedRef = seed.input;
    settingsScript = makeSettingsScript({
      seedUtxo: seed.input,
      proposeAuth: { kind: "key", hash: governor.keyHash },
      applyAuth: { kind: "key", hash: governor.keyHash },
      applyDelay: APPLY_DELAY,
      settingsTokenName: SETTINGS_TOKEN_NAME,
    });
    settingsAddr = settingsScriptAddress(settingsScript, NETWORK_ID);
    const settingsHash = resolveScriptHash(settingsScript.code, "V3");
    counterParams = {
      settingsPolicy: settingsHash,
      settingsTokenName: SETTINGS_TOKEN_NAME,
    };

    forwarderScript = counterForwarderScript(counterParams);
    logicScript = counterLogicScript(counterParams);
    v1Script = counterV1Script(counterParams);
    v2Script = counterV2Script();
    migrationScript = counterMigrationScript({
      ...counterParams,
      v2Address: counterScriptAddress(v2Script, NETWORK_ID),
    });

    forwarderAddr = counterScriptAddress(forwarderScript, NETWORK_ID);
    v1Addr = counterScriptAddress(v1Script, NETWORK_ID);
    v2Addr = counterScriptAddress(v2Script, NETWORK_ID);

    forwarderHash = counterScriptHash(forwarderScript);
    logicHash = counterScriptHash(logicScript);
    v1Hash = counterScriptHash(v1Script);
    migrationHash = counterScriptHash(migrationScript);

    // Launch the settings instance with the forwarder already registered.
    settingsUtxo = await launchSettings(new Map([[forwarderHash, logicHash]]));
    settingsDatum = {
      current: registryToData(new Map([[forwarderHash, logicHash]])),
      next: null,
      nextApply: null,
    };

    // The logic and migration scripts run as withdraw-0s: their reward
    // accounts must exist on the ledger.
    await registerStakeCredential(provider, governor, logicHash);
    await registerStakeCredential(provider, governor, migrationHash);

    forwarderUtxo = await lockCounter(
      forwarderAddr,
      { count: 1, owner: aliceOwner() },
      alice,
    );
    v1Utxo = await lockCounter(
      v1Addr,
      { count: 5, owner: aliceOwner() },
      alice,
    );
  });

  // ------------------------------------------------------------ helpers

  /** Mint the settings NFT and lock the registry at the settings address. */
  async function launchSettings(registry: Registry): Promise<UTxO> {
    const seedUtxo = (await governor.wallet.getUtxos()).find(
      (u) =>
        u.input.txHash === seedRef.txHash &&
        u.input.outputIndex === seedRef.outputIndex,
    )!;
    const mintTx = await buildLaunchTx({
      txBuilder: newTxBuilder(provider),
      script: settingsScript,
      seedUtxo,
      datum: {
        current: registryToData(registry),
        next: null,
        nextApply: null,
      },
      outputIndex: 0,
      utxos: await governor.wallet.getUtxos(),
      changeAddress: governor.address,
      collateralUtxo: await collateralOf(governor),
      applyAuth: { kind: "key", hash: governor.keyHash },
      minUtxoLovelace: SETTINGS_LOVELACE,
    });
    const mintHash = await signAndSubmit(governor, mintTx);
    await waitForTx(provider, mintHash);
    return await scriptOutputOf(provider, mintHash, settingsAddr);
  }

  /**
   * Governed, timelocked registry change: `Propose` the whole map (carrying
   * forward every entry), wait out `apply_delay`, then `Apply`.
   */
  async function changeRegistry(next: Registry): Promise<void> {
    const proposeNow = await chainNowMs();
    const proposeTx = await buildRegistryProposeTx({
      txBuilder: newTxBuilder(provider),
      script: settingsScript,
      settingsUtxo: settingsUtxo!,
      datum: settingsDatum,
      now: proposeNow,
      outputIndex: 0,
      utxos: await governor.wallet.getUtxos(),
      changeAddress: governor.address,
      collateralUtxo: await collateralOf(governor),
      proposeAuth: { kind: "key", hash: governor.keyHash },
      applyDelay: APPLY_DELAY,
      customSlotConfig: slotConfig,
      registry: next,
    });
    const proposeHash = await signAndSubmit(governor, proposeTx);
    await waitForTx(provider, proposeHash);
    const proposedUtxo = await scriptOutputOf(
      provider,
      proposeHash,
      settingsAddr,
    );

    // The builder bakes next_apply = slot_start(propose_now) + apply_delay.
    const { startMs } = enclosingSlotBound(proposeNow, slotConfig);
    const proposedDatum: SettingsDatum = {
      current: settingsDatum.current,
      next: registryToData(next),
      nextApply: startMs + APPLY_DELAY,
    };
    await waitUntilChainTimeMs(proposedDatum.nextApply! + TIME_SLACK);

    const applyTx = await buildRegistryApplyTx({
      txBuilder: newTxBuilder(provider),
      script: settingsScript,
      settingsUtxo: proposedUtxo,
      datum: proposedDatum,
      now: await chainNowMs(),
      outputIndex: 0,
      utxos: await governor.wallet.getUtxos(),
      changeAddress: governor.address,
      collateralUtxo: await collateralOf(governor),
      applyAuth: { kind: "key", hash: governor.keyHash },
      customSlotConfig: slotConfig,
    });
    const applyHash = await signAndSubmit(governor, applyTx);
    await waitForTx(provider, applyHash);
    settingsUtxo = await scriptOutputOf(provider, applyHash, settingsAddr);
    settingsDatum = {
      current: registryToData(next),
      next: null,
      nextApply: null,
    };
  }

  /** Lock a UTxO with a raw inline datum (plain lovelace) at a script address. */
  async function lockDatum(
    addr: string,
    datumData: Data,
    owner: Account,
    lovelace = 3_000_000n,
  ): Promise<UTxO> {
    const tx = await newTxBuilder(provider)
      .txOut(addr, [{ unit: "lovelace", quantity: lovelace.toString() }])
      .txOutInlineDatumValue(datumData)
      .changeAddress(owner.address)
      .selectUtxosFrom(await owner.wallet.getUtxos())
      .complete();
    const hash = await signAndSubmit(owner, tx);
    await waitForTx(provider, hash);
    return await scriptOutputOf(provider, hash, addr);
  }

  /** Lock a counter UTxO (plain lovelace + inline datum) at a script address. */
  async function lockCounter(
    addr: string,
    datum: CounterDatum,
    owner: Account,
  ): Promise<UTxO> {
    return await lockDatum(addr, counterDatumToData(datum), owner);
  }

  /**
   * A raw, possibly-malicious V1 upgrade: spends `inputs` with `redeemer`,
   * optionally runs the migration script as a withdraw-0, and emits arbitrary
   * continuation outputs. An attacker chooses the shape; the validators decide.
   */
  async function rawUpgradeTx(p: {
    inputs: UTxO[];
    redeemer: Data;
    outputs: { address: string; amount: Asset[]; datum: CounterDatum }[];
    withdrawMigration: boolean;
    requiredSigner?: string;
    settings?: UTxO;
  }): Promise<string> {
    const tb = newTxBuilder(provider);
    for (const utxo of p.inputs) {
      tb.spendingPlutusScriptV3()
        .txIn(
          utxo.input.txHash,
          utxo.input.outputIndex,
          utxo.output.amount,
          utxo.output.address,
        )
        .txInInlineDatumPresent()
        .txInRedeemerValue(p.redeemer)
        .txInScript(v1Script.code);
    }
    if (p.withdrawMigration) {
      const rewardAddress = serializeRewardAddress(
        migrationHash,
        true,
        NETWORK_ID,
      );
      tb.withdrawalPlutusScriptV3()
        .withdrawal(rewardAddress, "0")
        .withdrawalScript(migrationScript.code)
        .withdrawalRedeemerValue(opaqueRedeemer());
    }
    const settings = p.settings ?? settingsUtxo!;
    tb.readOnlyTxInReference(settings.input.txHash, settings.input.outputIndex);
    for (const out of p.outputs) {
      tb.txOut(out.address, out.amount).txOutInlineDatumValue(
        counterDatumToData(out.datum),
      );
    }
    if (p.requiredSigner) tb.requiredSignerHash(p.requiredSigner);
    const col = await collateralOf(alice);
    const unsigned = await tb
      .txInCollateral(
        col.input.txHash,
        col.input.outputIndex,
        col.output.amount,
        col.output.address,
      )
      .changeAddress(alice.address)
      .selectUtxosFrom(await alice.wallet.getUtxos())
      .complete();
    return await signAndSubmit(alice, unsigned);
  }

  /**
   * A raw forced tick spending several forwarder UTxOs at once, invoking the
   * registered logic as a withdraw-0 and emitting arbitrary continuations.
   */
  async function rawForwardTick(p: {
    inputs: UTxO[];
    outputs: { address: string; amount: Asset[]; datum: CounterDatum }[];
  }): Promise<string> {
    const tb = newTxBuilder(provider);
    for (const utxo of p.inputs) {
      tb.spendingPlutusScriptV3()
        .txIn(
          utxo.input.txHash,
          utxo.input.outputIndex,
          utxo.output.amount,
          utxo.output.address,
        )
        .txInInlineDatumPresent()
        .txInRedeemerValue(opaqueRedeemer())
        .txInScript(forwarderScript.code);
    }
    const rewardAddress = serializeRewardAddress(logicHash, true, NETWORK_ID);
    tb.withdrawalPlutusScriptV3()
      .withdrawal(rewardAddress, "0")
      .withdrawalScript(logicScript.code)
      .withdrawalRedeemerValue(opaqueRedeemer());
    tb.readOnlyTxInReference(
      settingsUtxo!.input.txHash,
      settingsUtxo!.input.outputIndex,
    );
    for (const out of p.outputs) {
      tb.txOut(out.address, out.amount).txOutInlineDatumValue(
        counterDatumToData(out.datum),
      );
    }
    const col = await collateralOf(alice);
    const unsigned = await tb
      .txInCollateral(
        col.input.txHash,
        col.input.outputIndex,
        col.output.amount,
        col.output.address,
      )
      .changeAddress(alice.address)
      .selectUtxosFrom(await alice.wallet.getUtxos())
      .complete();
    return await signAndSubmit(alice, unsigned);
  }

  /** Tick the forwarder: build + submit, and return the continuation UTxO. */
  async function forwardTick(logicAuthorizerCbor: string): Promise<UTxO> {
    const tx = await buildForwardTx({
      txBuilder: newTxBuilder(provider),
      forwarderScript,
      logicAuthorizer: { scriptCbor: logicAuthorizerCbor },
      forwarderUtxo: forwarderUtxo!,
      settingsUtxo: settingsUtxo!,
      utxos: await alice.wallet.getUtxos(),
      changeAddress: alice.address,
      collateralUtxo: await collateralOf(alice),
    });
    const hash = await signAndSubmit(alice, tx);
    await waitForTx(provider, hash);
    return await scriptOutputOf(provider, hash, forwarderAddr);
  }

  // ------------------------------------------------------------ tests

  it("launches the settings instance with the forwarder registered", () => {
    expect(readRegistry(settingsUtxo!).get(forwarderHash)).toBe(logicHash);
  });

  it("locks the forwarder and V1 state UTxOs", () => {
    expect(counterDatumFromUtxo(forwarderUtxo!)).toEqual({
      count: 1,
      owner: aliceOwner(),
    });
    expect(counterDatumFromUtxo(v1Utxo!)).toEqual({
      count: 5,
      owner: aliceOwner(),
    });
  });

  it("ticks the forwarder through the registered logic (forced)", async () => {
    const continuation = await forwardTick(logicScript.code);
    expect(counterDatumFromUtxo(continuation)).toEqual({
      count: 2,
      owner: aliceOwner(),
    });
    forwarderUtxo = continuation;
  });

  it("ticks V1 natively without consulting the registry", async () => {
    const tx = await buildCounterTickTx({
      txBuilder: newTxBuilder(provider),
      script: v1Script,
      counterUtxo: v1Utxo!,
      utxos: await alice.wallet.getUtxos(),
      changeAddress: alice.address,
      collateralUtxo: await collateralOf(alice),
    });
    const hash = await signAndSubmit(alice, tx);
    await waitForTx(provider, hash);
    const continuation = await scriptOutputOf(provider, hash, v1Addr);
    expect(counterDatumFromUtxo(continuation)).toEqual({
      count: 6,
      owner: aliceOwner(),
    });
    v1Utxo = continuation;
  });

  it("adds the V1 migration entry via propose + apply, carrying the forwarder entry", async () => {
    await changeRegistry(
      new Map([
        [forwarderHash, logicHash],
        [v1Hash, migrationHash],
      ]),
    );
    const registry = readRegistry(settingsUtxo!);
    expect(registry.get(forwarderHash)).toBe(logicHash);
    expect(registry.get(v1Hash)).toBe(migrationHash);
  });

  it("rejects a migration that tampers with the count", async () => {
    const v1 = await lockCounter(
      v1Addr,
      { count: 1, owner: aliceOwner() },
      alice,
    );
    await expect(
      rawUpgradeTx({
        inputs: [v1],
        redeemer: upgradeRedeemer(),
        outputs: [
          {
            address: v2Addr,
            amount: COUNTER_LOVELACE,
            datum: { count: 2, owner: aliceOwner() },
          },
        ],
        withdrawMigration: true,
        requiredSigner: alice.keyHash,
      }),
    ).rejects.toThrow();
  });

  it("rejects a migration that swaps the state's owner", async () => {
    const v1 = await lockCounter(
      v1Addr,
      { count: 1, owner: aliceOwner() },
      alice,
    );
    await expect(
      rawUpgradeTx({
        inputs: [v1],
        redeemer: upgradeRedeemer(),
        outputs: [
          {
            address: v2Addr,
            amount: COUNTER_LOVELACE,
            datum: { count: 1, owner: { kind: "key", hash: bob.keyHash } },
          },
        ],
        withdrawMigration: true,
        requiredSigner: alice.keyHash,
      }),
    ).rejects.toThrow();
  });

  it("rejects a migration whose continuation stays at the V1 address", async () => {
    const v1 = await lockCounter(
      v1Addr,
      { count: 1, owner: aliceOwner() },
      alice,
    );
    await expect(
      rawUpgradeTx({
        inputs: [v1],
        redeemer: upgradeRedeemer(),
        outputs: [
          {
            address: v1Addr,
            amount: COUNTER_LOVELACE,
            datum: { count: 1, owner: aliceOwner() },
          },
        ],
        withdrawMigration: true,
        requiredSigner: alice.keyHash,
      }),
    ).rejects.toThrow();
  });

  it("rejects a migration that underpays the continuation", async () => {
    const v1 = await lockCounter(
      v1Addr,
      { count: 1, owner: aliceOwner() },
      alice,
    );
    await expect(
      rawUpgradeTx({
        inputs: [v1],
        redeemer: upgradeRedeemer(),
        outputs: [
          {
            address: v2Addr,
            amount: [{ unit: "lovelace", quantity: "2000000" }],
            datum: { count: 1, owner: aliceOwner() },
          },
        ],
        withdrawMigration: true,
        requiredSigner: alice.keyHash,
      }),
    ).rejects.toThrow();
  });

  it("rejects a migration with no V2 continuation", async () => {
    const v1 = await lockCounter(
      v1Addr,
      { count: 1, owner: aliceOwner() },
      alice,
    );
    await expect(
      rawUpgradeTx({
        inputs: [v1],
        redeemer: upgradeRedeemer(),
        outputs: [],
        withdrawMigration: true,
        requiredSigner: alice.keyHash,
      }),
    ).rejects.toThrow();
  });

  it("rejects a V1 spent with Tick while the migration script runs", async () => {
    const v1 = await lockCounter(
      v1Addr,
      { count: 1, owner: aliceOwner() },
      alice,
    );
    await expect(
      rawUpgradeTx({
        inputs: [v1],
        redeemer: tickRedeemer(),
        outputs: [
          {
            address: v1Addr,
            amount: COUNTER_LOVELACE,
            datum: { count: 2, owner: aliceOwner() },
          },
        ],
        withdrawMigration: true,
        requiredSigner: alice.keyHash,
      }),
    ).rejects.toThrow();
  });

  it("rejects a batch migration when one forwarded input is not preserved", async () => {
    const matching = await lockCounter(
      v1Addr,
      { count: 2, owner: aliceOwner() },
      alice,
    );
    const stale = await lockCounter(
      v1Addr,
      { count: 5, owner: aliceOwner() },
      alice,
    );
    await expect(
      rawUpgradeTx({
        inputs: [matching, stale],
        redeemer: upgradeRedeemer(),
        outputs: [
          {
            address: v2Addr,
            amount: [{ unit: "lovelace", quantity: "6000000" }],
            datum: { count: 2, owner: aliceOwner() },
          },
        ],
        withdrawMigration: true,
        requiredSigner: alice.keyHash,
      }),
    ).rejects.toThrow();
  });

  it("migrates a V1 UTxO to V2 with the owner's consent", async () => {
    const upgradeTx = await buildUpgradeTx({
      txBuilder: newTxBuilder(provider),
      v1Script,
      migrationAuthorizer: { scriptCbor: migrationScript.code },
      v1Utxo: v1Utxo!,
      settingsUtxo: settingsUtxo!,
      v2Address: v2Addr,
      utxos: await alice.wallet.getUtxos(),
      changeAddress: alice.address,
      collateralUtxo: await collateralOf(alice),
    });
    const hash = await signAndSubmit(alice, upgradeTx);
    await waitForTx(provider, hash);
    v2Utxo = await scriptOutputOf(provider, hash, v2Addr);
    expect(counterDatumFromUtxo(v2Utxo)).toEqual({
      count: 6,
      owner: aliceOwner(),
    });
  });

  it("ticks V2 natively under the new script", async () => {
    const tx = await buildCounterTickTx({
      txBuilder: newTxBuilder(provider),
      script: v2Script,
      counterUtxo: v2Utxo!,
      utxos: await alice.wallet.getUtxos(),
      changeAddress: alice.address,
      collateralUtxo: await collateralOf(alice),
    });
    const hash = await signAndSubmit(alice, tx);
    await waitForTx(provider, hash);
    const continuation = await scriptOutputOf(provider, hash, v2Addr);
    expect(counterDatumFromUtxo(continuation).count).toBe(7);
    v2Utxo = continuation;
  });

  it("rejects an upgrade whose owner did not consent", async () => {
    // A V1 UTxO owned by bob: the builder requires bob's signature, but alice
    // signs, so the required vkey witness is missing.
    const bobUtxo = await lockCounter(
      v1Addr,
      { count: 0, owner: { kind: "key", hash: bob.keyHash } },
      alice,
    );
    await expect(
      (async () => {
        const tx = await buildUpgradeTx({
          txBuilder: newTxBuilder(provider),
          v1Script,
          migrationAuthorizer: { scriptCbor: migrationScript.code },
          v1Utxo: bobUtxo,
          settingsUtxo: settingsUtxo!,
          v2Address: v2Addr,
          utxos: await alice.wallet.getUtxos(),
          changeAddress: alice.address,
          collateralUtxo: await collateralOf(alice),
        });
        await signAndSubmit(alice, tx);
      })(),
    ).rejects.toThrow();
  });

  it("a forced repoint delegates to the new logic, and a tick routed to the migration script is rejected on-chain", async () => {
    await changeRegistry(
      new Map([
        [forwarderHash, migrationHash],
        [v1Hash, migrationHash],
      ]),
    );
    // The builder accepts (the registry now names the migration script), but
    // the migration script demands the Upgrade action and a V2 continuation,
    // so the tick fails phase-2.
    await expect(
      (async () => {
        const tx = await buildForwardTx({
          txBuilder: newTxBuilder(provider),
          forwarderScript,
          logicAuthorizer: { scriptCbor: migrationScript.code },
          forwarderUtxo: forwarderUtxo!,
          settingsUtxo: settingsUtxo!,
          utxos: await alice.wallet.getUtxos(),
          changeAddress: alice.address,
          collateralUtxo: await collateralOf(alice),
        });
        await signAndSubmit(alice, tx);
      })(),
    ).rejects.toThrow();

    // Repoint back to the logic script; the tick works again.
    await changeRegistry(
      new Map([
        [forwarderHash, logicHash],
        [v1Hash, migrationHash],
      ]),
    );
    const continuation = await forwardTick(logicScript.code);
    expect(counterDatumFromUtxo(continuation).count).toBe(3);
    forwarderUtxo = continuation;
  });

  it("rejects a batch tick when one forwarded input is not preserved", async () => {
    const matching = await lockCounter(
      forwarderAddr,
      { count: 1, owner: aliceOwner() },
      alice,
    );
    const stale = await lockCounter(
      forwarderAddr,
      { count: 5, owner: aliceOwner() },
      alice,
    );
    await expect(
      rawForwardTick({
        inputs: [matching, stale],
        outputs: [
          {
            address: forwarderAddr,
            amount: [{ unit: "lovelace", quantity: "6000000" }],
            datum: { count: 2, owner: aliceOwner() },
          },
        ],
      }),
    ).rejects.toThrow();
  });

  it("ignores a forged registry without the settings NFT", async () => {
    const forged = await lockDatum(
      settingsAddr,
      settingsDatumToData({
        current: registryToData(new Map([[forwarderHash, logicHash]])),
        next: null,
        nextApply: null,
      }),
      alice,
    );
    await expect(
      (async () => {
        const tx = await buildForwardTx({
          txBuilder: newTxBuilder(provider),
          forwarderScript,
          logicAuthorizer: { scriptCbor: logicScript.code },
          forwarderUtxo: forwarderUtxo!,
          settingsUtxo: forged,
          utxos: await alice.wallet.getUtxos(),
          changeAddress: alice.address,
          collateralUtxo: await collateralOf(alice),
        });
        await signAndSubmit(alice, tx);
      })(),
    ).rejects.toThrow();
  });

  it("a malformed registry bricks consumers until governance restores it", async () => {
    // The reference settings validator accepts any value: governance can write
    // a non-map registry, which every consumer then rejects.
    const proposeNow = await chainNowMs();
    const proposeTx = await buildProposeTx({
      txBuilder: newTxBuilder(provider),
      script: settingsScript,
      settingsUtxo: settingsUtxo!,
      datum: settingsDatum,
      newValue: 5,
      now: proposeNow,
      outputIndex: 0,
      utxos: await governor.wallet.getUtxos(),
      changeAddress: governor.address,
      collateralUtxo: await collateralOf(governor),
      proposeAuth: { kind: "key", hash: governor.keyHash },
      applyDelay: APPLY_DELAY,
      customSlotConfig: slotConfig,
    });
    const proposeHash = await signAndSubmit(governor, proposeTx);
    await waitForTx(provider, proposeHash);
    const proposedUtxo = await scriptOutputOf(
      provider,
      proposeHash,
      settingsAddr,
    );
    const { startMs } = enclosingSlotBound(proposeNow, slotConfig);
    const proposedDatum: SettingsDatum = {
      current: settingsDatum.current,
      next: 5,
      nextApply: startMs + APPLY_DELAY,
    };
    await waitUntilChainTimeMs(proposedDatum.nextApply! + TIME_SLACK);
    const applyTx = await buildRegistryApplyTx({
      txBuilder: newTxBuilder(provider),
      script: settingsScript,
      settingsUtxo: proposedUtxo,
      datum: proposedDatum,
      now: await chainNowMs(),
      outputIndex: 0,
      utxos: await governor.wallet.getUtxos(),
      changeAddress: governor.address,
      collateralUtxo: await collateralOf(governor),
      applyAuth: { kind: "key", hash: governor.keyHash },
      customSlotConfig: slotConfig,
    });
    const applyHash = await signAndSubmit(governor, applyTx);
    await waitForTx(provider, applyHash);
    settingsUtxo = await scriptOutputOf(provider, applyHash, settingsAddr);
    settingsDatum = { current: 5, next: null, nextApply: null };

    // Consumers brick — guarded off-chain by the registry decode.
    await expect(
      buildForwardTx({
        txBuilder: newTxBuilder(provider),
        forwarderScript,
        logicAuthorizer: { scriptCbor: logicScript.code },
        forwarderUtxo: forwarderUtxo!,
        settingsUtxo: settingsUtxo!,
        utxos: await alice.wallet.getUtxos(),
        changeAddress: alice.address,
        collateralUtxo: await collateralOf(alice),
      }),
    ).rejects.toThrow(/not a map/i);

    // Governance restores a well-formed registry; the forwarder works again.
    await changeRegistry(
      new Map([
        [forwarderHash, logicHash],
        [v1Hash, migrationHash],
      ]),
    );
    const continuation = await forwardTick(logicScript.code);
    expect(counterDatumFromUtxo(continuation).count).toBe(4);
    forwarderUtxo = continuation;
  });
});
